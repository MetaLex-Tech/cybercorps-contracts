// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ACESAFEExtension} from "../src/storage/extensions/ACESAFEExtension.sol";
import {SAFEExtension} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFTEExtensionV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTExtensionV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {TokenWarrantExtensionV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {SafeUtils} from "./libs/SafeUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys or upgrades the live V1 and V2 certificate extension proxies.
/// @dev A recorded proxy keeps its address and takes the new code; a zero field gets a new proxy.
///      The new code escapes string fields in the JSON it renders.
///      The two salts are separate. Bump the implementation salt to re-run on a chain that already
///      holds these implementations, because the same code under the same salt gives an occupied address.
///      The deployer only deploys. The upgrades of recorded proxies need the owner role, so
///      `runWithArgs` returns them as gated calls and does not send them.
contract DeployExtensionsV2Script is Script {
    GnosisTransaction[] internal gatedCalls;

    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV2.0.1", // proxySaltStr
//            "CyberCorpV5-ExtensionsV2.0.1-impl0", // implSaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV2.0.1", // proxySaltStr
            "CyberCorpV5-ExtensionsV2.0.1-impl0", // implSaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then sends the gated calls or hands them off to the MetaLeX Safe.
    function runAndExecute(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public {
        GnosisTransaction[] memory calls = runWithArgs(chainId, proxySaltStr, implSaltStr, deployerPrivateKey);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        bool direct = DeploymentConstants.isTestnet(chainId)
            && SafeUtils.hasOwnerRole(core.auth, vm.addr(deployerPrivateKey));
        SafeUtils.executeOrHandOff(
            calls,
            chainId,
            deployerPrivateKey,
            core.metalexSafe,
            direct,
            string.concat("script/res/gnosis-batch-deploy-extensions-v2-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public returns (GnosisTransaction[] memory) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 implSalt = keccak256(bytes(implSaltStr));
        bytes32 proxySalt = keccak256(bytes(proxySaltStr));

        address auth = DeploymentConstants.coreV2(chainId).auth;
        DeploymentConstants.ExtensionDeployment memory recorded = DeploymentConstants.extensions(chainId);

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("proxy salt string: %s", proxySaltStr);
        console2.log("implementation salt string: %s", implSaltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("AUTH:", auth);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        address safeExtension = _deployOrUpgrade(
            recorded.safeExtension, address(new SAFEExtension{salt: implSalt}()), auth, proxySalt
        );
        address saftExtensionV2 = _deployOrUpgrade(
            recorded.saftExtensionV2, address(new SAFTExtensionV2{salt: implSalt}()), auth, proxySalt
        );
        address safteExtensionV2 = _deployOrUpgrade(
            recorded.safteExtensionV2, address(new SAFTEExtensionV2{salt: implSalt}()), auth, proxySalt
        );
        address tokenWarrantExtensionV2 = _deployOrUpgrade(
            recorded.tokenWarrantExtensionV2, address(new TokenWarrantExtensionV2{salt: implSalt}()), auth, proxySalt
        );

        // ACESAFEExtension exists on Base mainnet only.
        address aceSafeExtension;
        if (chainId == DeploymentConstants.BASE) {
            aceSafeExtension = _deployOrUpgrade(
                recorded.aceSafeExtension, address(new ACESAFEExtension{salt: implSalt}()), auth, proxySalt
            );
        }
        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log("SAFEExtension:", safeExtension);
        console2.log("SAFTExtensionV2:", saftExtensionV2);
        console2.log("SAFTEExtensionV2:", safteExtensionV2);
        console2.log("TokenWarrantExtensionV2:", tokenWarrantExtensionV2);
        if (chainId == DeploymentConstants.BASE) {
            console2.log("ACESAFEExtension:", aceSafeExtension);
        }
        console2.log("");
        return gatedCalls;
    }

    /// @dev A recorded proxy takes the new code at its own address. A zero one gets a new proxy.
    ///      The upgrade needs the owner role, so it goes to the gated calls.
    function _deployOrUpgrade(
        address recorded,
        address implementation,
        address auth,
        bytes32 proxySalt
    ) internal returns (address) {
        if (recorded != address(0)) {
            gatedCalls.push(
                GnosisTransaction({
                    to: recorded,
                    value: 0,
                    data: abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, ""))
                })
            );
            return recorded;
        }
        return address(
            new ERC1967Proxy{salt: proxySalt}(implementation, abi.encodeWithSignature("initialize(address)", auth))
        );
    }
}
