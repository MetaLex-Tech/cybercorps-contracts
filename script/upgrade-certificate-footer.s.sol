// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Install the issuer-name footer without upgrading the URI implementation.
/// @dev Configure RPC, sender and signing through Forge's normal options. No script-specific env vars.
///      Forge links/deploys CertificateImageContentBuilder using the configured wallet.
contract UpgradeCertificateFooterScript is DeploymentScript {
    function run() external {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        runWithArgs(block.chainid, core.uriBuilder, core.metalexSafe, batchPath(block.chainid, core.uriBuilder));
    }

    function batchPath(uint256 chainId, address proxy) public pure returns (string memory) {
        return string.concat("script/res/gnosis-batch-certificate-footer-", vm.toString(chainId),
            "-", vm.toString(proxy), ".unverified.json");
    }

    /// @notice Optional wrapper entrypoint; expected chain and output path are ordinary Forge --sig arguments.
    function runForChain(uint256 expectedChain, string memory path) external {
        if (expectedChain != block.chainid) revert ChainIdMismatch(expectedChain, block.chainid);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        runWithArgs(expectedChain, core.uriBuilder, core.metalexSafe, path);
    }

    /// @notice Explicit targets for local rehearsals or separately inventoried custom proxies.
    function runWithArgs(uint256 chainId, address proxy, address ownerSafe, string memory path)
        public
        returns (GnosisTransaction[] memory)
    {
        if (chainId != block.chainid) revert ChainIdMismatch(chainId, block.chainid);
        safe = ownerSafe;
        delete safeTxs;
        require(proxy.code.length > 0, "URI_BUILDER has no code");
        address implementation = implementationOf(proxy);
        require(implementation.code.length > 0, "URI_BUILDER is not an implementation proxy");
        CertificateUriBuilder builder = CertificateUriBuilder(proxy);
        address auth = address(builder.AUTH());
        require(ownerSafe != address(0) && DeploymentUtils.hasOwnerRole(auth, ownerSafe),
            "Safe does not own URI_BUILDER");
        console2.log("URI proxy:", proxy);
        console2.log("Preserved URI implementation:", implementation);
        console2.log("Previous image builder:", builder.imageBuilder());
        // This renderer has no immutables. Compare linked runtime code in simulation before broadcasting.
        address image = builder.imageBuilder();
        address candidate = address(new CertificateImageBuilderContract());
        bool changed = image.codehash != candidate.codehash;
        if (changed) {
            vm.broadcast(msg.sender); // Forge's --sender; the matching wallet signs outside this script.
            image = address(new CertificateImageBuilderContract());
            // Always require multisig execution, even when the deployment key is also an owner.
            safeTxs.push(GnosisTransaction({to: proxy, value: 0,
                data: abi.encodeCall(CertificateUriBuilder.setImageBuilder, (image))}));
        }
        finish("[footer Safe batch]", path);
        require(implementationOf(proxy) == implementation, "URI implementation changed");
        require(address(builder.AUTH()) == auth, "AUTH changed");
        require(builder.imageBuilder() == image, "Image builder update failed");
        if (safeTxs.length == 0) vm.writeFile(path, DeploymentUtils.formatSafeTxJson(safeTxs, chainId));
        console2.log("Verified image builder (simulation):", image);
        console2.log("Batch output (verify deployment receipts before Safe import):", path);
        return safeTxs;
    }
}
