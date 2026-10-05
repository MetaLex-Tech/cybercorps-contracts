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

/// @notice Refresh both certificate renderers, executing as the deployer or preparing a Safe batch.
/// @dev Uses PRIVATE_KEY_MAIN; URI_BUILDER and METALEX_SAFE optionally override chain defaults.
///      Dry run: forge script script/upgrade-certificate-rendering.s.sol:UpgradeCertificateRenderingScript --rpc-url <RPC_URL>
///      --broadcast deploys changed renderers and any deployer-owned updates. Safe-owned updates
///      are only simulated and written to script/res/gnosis-batch-certificate-rendering-<chain>-<proxy>.json.
///      Import that batch only after the deployments have been broadcast successfully.
///      Forge deploys/links CertificateImageContentBuilder, which the image renderer depends on.
///      Set --sender to the address of PRIVATE_KEY_MAIN so linked-library deployments use the same signer.
contract UpgradeCertificateRenderingScript is DeploymentScript {
    function run() external {
        address proxy = vm.envOr("URI_BUILDER", address(0));
        address ownerSafe = vm.envOr("METALEX_SAFE", address(0));
        if (proxy == address(0) || ownerSafe == address(0)) {
            DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
            if (proxy == address(0)) proxy = core.uriBuilder;
            if (ownerSafe == address(0)) ownerSafe = core.metalexSafe;
        }
        runWithArgs(
            block.chainid,
            vm.envUint("PRIVATE_KEY_MAIN"),
            proxy,
            ownerSafe,
            string.concat(
                "script/res/gnosis-batch-certificate-rendering-",
                vm.toString(block.chainid),
                "-",
                vm.toString(proxy),
                ".json"
            )
        );
    }

    /// @notice Explicit arguments for rehearsals and custom URI proxies. Runs Safe calls in simulation only.
    function runWithArgs(uint256 chainId, uint256 privateKey, address proxy, address ownerSafe, string memory jsonPath)
        public
        returns (GnosisTransaction[] memory)
    {
        initDeployment("[certificate rendering]", chainId, privateKey, ownerSafe);
        require(proxy.code.length > 0, "URI_BUILDER has no code");
        address oldImplementation = implementationOf(proxy);
        require(oldImplementation.code.length > 0, "URI_BUILDER is not an implementation proxy");
        CertificateUriBuilder builder = CertificateUriBuilder(proxy);
        address auth = address(builder.AUTH());
        require(
            DeploymentUtils.hasOwnerRole(auth, deployer)
                || (ownerSafe != address(0) && DeploymentUtils.hasOwnerRole(auth, ownerSafe)),
            "Neither deployer nor Safe owns URI_BUILDER"
        );
        address oldImage = builder.imageBuilder();
        console2.log("URI proxy:", proxy);
        console2.log("Old URI implementation:", oldImplementation);
        console2.log("Old image builder:", oldImage);

        (address image,) = deployIfDifferent(
            "[image renderer]",
            "CertificateImageBuilderContract",
            type(CertificateImageBuilderContract).creationCode,
            oldImage
        );
        (address implementation,) = deployIfDifferent(
            "[URI renderer]", "CertificateUriBuilder", type(CertificateUriBuilder).creationCode, oldImplementation
        );
        bytes memory imageCall = abi.encodeCall(CertificateUriBuilder.setImageBuilder, (image));
        if (implementation != oldImplementation) {
            // One owner call switches both components, with no intermediate mixed rendering path.
            execute(
                "[rendering upgrade]",
                auth,
                proxy,
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, imageCall)),
                "upgrade URI implementation and set image builder atomically"
            );
        } else if (image != oldImage) {
            execute("[rendering upgrade]", auth, proxy, imageCall, "set current image builder");
        }

        finish("[rendering Safe batch]", jsonPath);
        require(implementationOf(proxy) == implementation, "URI implementation update failed");
        require(builder.imageBuilder() == image, "Image builder update failed");
        require(address(builder.AUTH()) == auth, "AUTH changed unexpectedly");
        // finish writes only nonempty batches. Clear any prior actionable batch on a direct/no-op run.
        if (safeTxs.length == 0) {
            vm.writeFile(jsonPath, DeploymentUtils.formatSafeTxJson(safeTxs, chainId));
        }
        console2.log("Verified URI implementation (simulation):", implementation);
        console2.log("Verified image builder (simulation):", image);
        return safeTxs;
    }
}
