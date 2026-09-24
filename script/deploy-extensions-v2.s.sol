// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ACESAFEExtension} from "../src/storage/extensions/ACESAFEExtension.sol";
import {SAFEExtension} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFTEExtensionV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTExtensionV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {TokenWarrantExtensionV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Deploys or upgrades the live V1 and V2 certificate extension proxies.
/// @dev An existing proxy keeps its address and takes the new code. A zero field gets a new proxy.
///      The new code escapes string fields in the JSON it renders.
///      The proxy salt applies only to a zero field. A field with an address ignores the salt.
///      See `DeploymentScript` for the checks and for who sends each call.
contract DeployExtensionsV2Script is DeploymentScript {
    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV2.0.1", // proxySaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV2.0.1", // proxySaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey) public {
        runWithArgs(chainId, proxySaltStr, deployerPrivateKey);
        finish(
            "[Safe batch]",
            string.concat("script/res/gnosis-batch-deploy-extensions-v2-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey)
        public
        returns (GnosisTransaction[] memory)
    {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        address auth = core.auth;
        DeploymentConstants.ExtensionDeployment memory existing = DeploymentConstants.extensions(chainId);

        console2.log("==== DeployExtensionsV2Script Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] proxy salt string: %s", proxySaltStr);
        console2.log("[config] AUTH:", auth);
        console2.log("");

        bytes memory initCall = abi.encodeWithSignature("initialize(address)", auth);
        upgradeOrDeployProxyIfDiffImpl(
            auth, proxySaltStr, "SAFEExtension", existing.safeExtension, type(SAFEExtension).creationCode, initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            auth,
            proxySaltStr,
            "SAFTExtensionV2",
            existing.saftExtensionV2,
            type(SAFTExtensionV2).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            auth,
            proxySaltStr,
            "SAFTEExtensionV2",
            existing.safteExtensionV2,
            type(SAFTEExtensionV2).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            auth,
            proxySaltStr,
            "TokenWarrantExtensionV2",
            existing.tokenWarrantExtensionV2,
            type(TokenWarrantExtensionV2).creationCode,
            initCall
        );

        // ACESAFEExtension exists on Base mainnet only.
        if (chainId == DeploymentConstants.BASE) {
            upgradeOrDeployProxyIfDiffImpl(
                auth,
                proxySaltStr,
                "ACESAFEExtension",
                existing.aceSafeExtension,
                type(ACESAFEExtension).creationCode,
                initCall
            );
        }

        console2.log(" ");
        return safeTxs;
    }
}
