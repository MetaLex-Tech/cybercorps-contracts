// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Installs the current certificate renderers on the shared URI builder proxy: the URI implementation
///         and the image builder.
/// @dev The URI builder calls the image builder through one entry point. A release can change that entry point.
///      Then a new URI builder with an old image builder, or the reverse, gives a blank image. So when both parts
///      change, one call switches both. Each part deploys only when its runtime code changed.
///
///      | Case | URI implementation | Image builder | Call                                                        |
///      |------|--------------------|---------------|-------------------------------------------------------------|
///      | 1    | same               | same          | none                                                        |
///      | 2    | same               | changed       | `setImageBuilder(newImageBuilder)`                          |
///      | 3    | changed            | same          | `upgradeToAndCall(newUriImplementation, "")`                |
///      | 4    | changed            | changed       | `upgradeToAndCall(newUriImplementation, setImageBuilder(newImageBuilder))` |
///
///      A part with the same code already uses the current entry point, so it works with the new other part.
///      See `DeploymentScript` for the checks and for who sends each call.
contract DeployBuildersScript is DeploymentScript {
    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Upgrades, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(uint256 chainId, uint256 deployerPrivateKey) public {
        runWithArgs(chainId, deployerPrivateKey);
        finish(
            "[Safe batch]", string.concat("script/res/gnosis-batch-deploy-builders-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(uint256 chainId, uint256 deployerPrivateKey) public returns (GnosisTransaction[] memory) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);

        console2.log("==== DeployBuildersScript Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] URI builder:", core.uriBuilder);
        console2.log("");

        CertificateUriBuilder uriBuilder = CertificateUriBuilder(core.uriBuilder);
        (address uriImplementation, bool uriImplementationChanged) = deployIfDifferent(
            "[deploy implementation]",
            "CertificateUriBuilder",
            type(CertificateUriBuilder).creationCode,
            implementationOf(core.uriBuilder)
        );
        if (!uriImplementationChanged) {
            // Cases 1 and 2: the current URI implementation calls the current image builder entry point.
            // `upgradeIfDifferent` sets a changed image builder alone, or does nothing.
            upgradeIfDifferent(
                core.auth,
                core.uriBuilder,
                uriBuilder.imageBuilder.selector,
                uriBuilder.setImageBuilder.selector,
                "CertificateImageBuilderContract",
                type(CertificateImageBuilderContract).creationCode
            );
            return safeTxs;
        }
        (address imageBuilder, bool imageBuilderChanged) = deployIfDifferent(
            "[deploy contract]",
            "CertificateImageBuilderContract",
            type(CertificateImageBuilderContract).creationCode,
            uriBuilder.imageBuilder()
        );
        // Case 4: the new image builder goes live in the same call as the new URI implementation.
        // Case 3: the current image builder stays, so the upgrade has no setter call.
        bytes memory data = imageBuilderChanged
            ? abi.encodeCall(CertificateUriBuilder.setImageBuilder, (imageBuilder))
            : bytes("");
        upgradeProxy("[upgrade proxy]", core.auth, core.uriBuilder, "CertificateUriBuilder", uriImplementation, data);
        return safeTxs;
    }
}
