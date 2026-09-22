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
import {SafeUtils} from "./libs/SafeUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys or upgrades the extension proxies that render the whole certificate.
/// @dev A recorded proxy keeps its address and takes the new code; a zero field gets a new proxy.
///      Do not upgrade a V1 or V2 proxy to these implementations. A v4 printer on that proxy
///      then reverts in `tokenURI`. Forge deploys and links ShareCertDataLayerLib for ShareExtensionV3.
///      The two salts are separate. Bump the implementation salt to re-run on a chain that already
///      holds these proxies, because the same code under the same salt gives an occupied address.
///      A new proxy address depends on the implementation address, so a chain that deploys later
///      matches the recorded addresses only under the original implementation salt and the same code.
///      The deployer only deploys. The upgrades of recorded proxies need the owner role, so
///      `runWithArgs` returns them as gated calls and does not send them.
contract DeployExtensionsV3Script is Script {
    using SafeUtils for GnosisTransaction[];

    GnosisTransaction[] internal gatedCalls;

    function run() public returns (DeploymentConstants.ExtensionDeployment memory deployed) {
        return runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV3", // proxySaltStr
//            "CyberCorpV5-ExtensionsV3-impl0", // implSaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV3", // proxySaltStr
            "CyberCorpV5-ExtensionsV3-impl0", // implSaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then sends the gated calls or hands them off to the MetaLeX Safe.
    function runAndExecute(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.ExtensionDeployment memory deployed) {
        GnosisTransaction[] memory calls;
        (deployed, calls) = runWithArgs(chainId, proxySaltStr, implSaltStr, deployerPrivateKey);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        bool direct = DeploymentConstants.isTestnet(chainId)
            && SafeUtils.hasOwnerRole(core.auth, vm.addr(deployerPrivateKey));
        SafeUtils.executeOrHandOff(
            calls,
            chainId,
            deployerPrivateKey,
            core.metalexSafe,
            direct,
            string.concat("script/res/gnosis-batch-deploy-extensions-v3-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.ExtensionDeployment memory deployed, GnosisTransaction[] memory calls) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 implSalt = keccak256(bytes(implSaltStr));
        bytes32 proxySalt = keccak256(bytes(proxySaltStr));

        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants.coreV2(chainId);
        DeploymentConstants.ExtensionDeployment memory recorded = DeploymentConstants.extensions(chainId);

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("proxy salt string: %s", proxySaltStr);
        console2.log("implementation salt string: %s", implSaltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("AUTH:", deployment.auth);
        console2.log("");

        bytes memory initCall = abi.encodeWithSignature("initialize(address)", deployment.auth);
        vm.startBroadcast(deployerPrivateKey);
        deployed.aceSafeExtensionV3 = gatedCalls.deployOrUpgrade("ACESAFEExtensionV3", 
            recorded.aceSafeExtensionV3, address(new ACESAFEExtensionV3{salt: implSalt}()), initCall, proxySalt
        );
        deployed.safeExtensionV3 = gatedCalls.deployOrUpgrade("SAFEExtensionV3", 
            recorded.safeExtensionV3, address(new SAFEExtensionV3{salt: implSalt}()), initCall, proxySalt
        );
        deployed.saftExtensionV3 = gatedCalls.deployOrUpgrade("SAFTExtensionV3", 
            recorded.saftExtensionV3, address(new SAFTExtensionV3{salt: implSalt}()), initCall, proxySalt
        );
        deployed.safteExtensionV3 = gatedCalls.deployOrUpgrade("SAFTEExtensionV3", 
            recorded.safteExtensionV3, address(new SAFTEExtensionV3{salt: implSalt}()), initCall, proxySalt
        );
        deployed.tokenWarrantExtensionV3 = gatedCalls.deployOrUpgrade("TokenWarrantExtensionV3", 
            recorded.tokenWarrantExtensionV3,
            address(new TokenWarrantExtensionV3{salt: implSalt}()),
            initCall,
            proxySalt
        );
        deployed.shareExtensionV3 = gatedCalls.deployOrUpgrade("ShareExtensionV3", 
            recorded.shareExtensionV3, address(new ShareExtensionV3{salt: implSalt}()), initCall, proxySalt
        );
        deployed.fundInterestExtensionV3 = gatedCalls.deployOrUpgrade("FundInterestExtensionV3", 
            recorded.fundInterestExtensionV3,
            address(new FundInterestExtensionV3{salt: implSalt}()),
            initCall,
            proxySalt
        );
        vm.stopBroadcast();

        console2.log("");
        calls = gatedCalls;
    }
}
