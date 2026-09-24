// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ACESAFEExtensionV3} from "../src/storage/extensions/ACESAFEExtensionV3.sol";
import {FundInterestExtensionV3} from "../src/storage/extensions/FundInterestExtensionV3.sol";
import {SAFEExtensionV3} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {SAFTEExtensionV3} from "../src/storage/extensions/SAFTEExtensionV3.sol";
import {SAFTExtensionV3} from "../src/storage/extensions/SAFTExtensionV3.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {TokenWarrantExtensionV3} from "../src/storage/extensions/TokenWarrantExtensionV3.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Deploys or upgrades the extension proxies that render the whole certificate.
/// @dev An existing proxy keeps its address and takes the new code. A zero field gets a new proxy.
///      Do not upgrade a V1 or V2 proxy to these implementations. A v4 printer on that proxy
///      then reverts in `tokenURI`. Forge deploys and links ShareCertDataLayerLib for ShareExtensionV3.
///      The proxy salt applies only to a zero field. A field with an address ignores the salt.
///      See `DeploymentScript` for the checks and for who sends each call.
contract DeployExtensionsV3Script is DeploymentScript {
    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV3", // proxySaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV3", // proxySaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey) public {
        runWithArgs(chainId, proxySaltStr, deployerPrivateKey);
        finish(
            "[Safe batch]",
            string.concat("script/res/gnosis-batch-deploy-extensions-v3-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey)
        public
        returns (GnosisTransaction[] memory)
    {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        DeploymentConstants.ExtensionDeployment memory existing = DeploymentConstants.extensions(chainId);

        console2.log("==== DeployExtensionsV3Script Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] proxy salt string: %s", proxySaltStr);
        console2.log("[config] AUTH:", core.auth);
        console2.log("");

        bytes memory initCall = abi.encodeWithSignature("initialize(address)", core.auth);
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "ACESAFEExtensionV3",
            existing.aceSafeExtensionV3,
            type(ACESAFEExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "SAFEExtensionV3",
            existing.safeExtensionV3,
            type(SAFEExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "SAFTExtensionV3",
            existing.saftExtensionV3,
            type(SAFTExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "SAFTEExtensionV3",
            existing.safteExtensionV3,
            type(SAFTEExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "TokenWarrantExtensionV3",
            existing.tokenWarrantExtensionV3,
            type(TokenWarrantExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "ShareExtensionV3",
            existing.shareExtensionV3,
            type(ShareExtensionV3).creationCode,
            initCall
        );
        upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "FundInterestExtensionV3",
            existing.fundInterestExtensionV3,
            type(FundInterestExtensionV3).creationCode,
            initCall
        );

        console2.log(" ");
        return safeTxs;
    }
}
