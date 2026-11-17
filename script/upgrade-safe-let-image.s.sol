// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice Installs the SAFE Consideration display based on unitsRepresented.
/// @dev Follows the certificate-footer deployment flow, without unrelated extension upgrades.
///      Forge links/deploys CertificateImageContentBuilder. Only deployments are broadcast;
///      all owner actions are exported for the Safe, including when the deployer is an owner.
///      Deployment signing uses PRIVATE_KEY_MAIN, like the other upgrade scripts.
///      Set Forge --sender to that key's address for linked-library deployment.
contract UpgradeSafeLetImageScript is DeploymentScript {
    function run() external {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        runWithArgs(block.chainid, core.uriBuilder, core.metalexSafe, batchPath(block.chainid));
    }

    function batchPath(uint256 chainId) public pure returns (string memory) {
        return string.concat("script/res/gnosis-batch-safe-let-image-", vm.toString(chainId), ".unverified.json");
    }

    /// @notice Runner entrypoint: refuses an RPC on the wrong chain before deploying.
    function runForChain(uint256 expectedChain, string memory path) external {
        if (expectedChain != block.chainid) revert ChainIdMismatch(expectedChain, block.chainid);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        runWithArgs(expectedChain, core.uriBuilder, core.metalexSafe, path);
    }

    /// @notice Explicit targets for local rehearsals or separately verified custom URI proxies.
    function runWithArgs(uint256 chainId, address proxy, address ownerSafe, string memory path)
        public
        returns (GnosisTransaction[] memory)
    {
        if (chainId != block.chainid) revert ChainIdMismatch(chainId, block.chainid);
        require(proxy.code.length > 0, "URI_BUILDER has no code");
        address oldImplementation = implementationOf(proxy);
        require(oldImplementation.code.length > 0, "URI_BUILDER is not an implementation proxy");
        CertificateUriBuilder builder = CertificateUriBuilder(proxy);
        address auth = address(builder.AUTH());
        require(ownerSafe != address(0) && DeploymentUtils.hasOwnerRole(auth, ownerSafe),
            "Safe does not own URI_BUILDER");
        address oldImage = _currentImageBuilder(proxy);
        initDeployment("[SAFE LET image]", chainId, vm.envUint("PRIVATE_KEY_MAIN"), ownerSafe);
        console2.log("Chain:", chainId);
        console2.log("URI proxy:", proxy);
        console2.log("AUTH (preserved):", auth);
        console2.log("Safe:", ownerSafe);
        // Preserve these addresses with the release evidence for an atomic rollback.
        console2.log("Previous URI implementation:", oldImplementation);
        console2.log("Previous image builder:", oldImage);

        address image = _deployIfChanged(oldImage, type(CertificateImageBuilderContract).creationCode, "image builder");
        address implementation =
            _deployIfChanged(oldImplementation, type(CertificateUriBuilder).creationCode, "URI implementation");
        bytes memory imageCall = abi.encodeCall(CertificateUriBuilder.setImageBuilder, (image));
        if (implementation != oldImplementation) {
            // The current URI/image ABI must go live together on chains with older renderers.
            safeTxs.push(GnosisTransaction(proxy, 0,
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, imageCall))));
        } else if (image != oldImage) {
            safeTxs.push(GnosisTransaction(proxy, 0, imageCall));
        }

        finish("[SAFE LET image batch]", path); // Owner calls run in simulation only.
        require(implementationOf(proxy) == implementation, "URI implementation update failed");
        require(address(builder.AUTH()) == auth, "AUTH changed");
        require(builder.imageBuilder() == image, "Image builder update failed");
        // finish() skips empty batches. Overwrite an earlier file so a no-op cannot retain stale calls.
        if (safeTxs.length == 0) vm.writeFile(path, DeploymentUtils.formatSafeTxJson(safeTxs, chainId));
        console2.log("Verified URI implementation (simulation):", implementation);
        console2.log("Verified image builder (simulation):", image);
        console2.log("Batch (verify deployment receipts before Safe import):", path);
        return safeTxs;
    }

    function _currentImageBuilder(address proxy) private view returns (address) {
        (bool ok, bytes memory result) = proxy.staticcall(abi.encodeWithSignature("imageBuilder()"));
        // Older URI implementations may render inline and have no imageBuilder getter.
        if (!ok || result.length == 0) return address(0);
        return abi.decode(result, (address));
    }

    function _deployIfChanged(address current, bytes memory creationCode, string memory name)
        private
        returns (address)
    {
        (address deployed,) = deployIfDifferent("[SAFE LET image]", name, creationCode, current);
        return deployed;
    }
}
