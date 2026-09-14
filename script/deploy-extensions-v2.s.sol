// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ACESAFEExtension} from "../src/storage/extensions/ACESAFEExtension.sol";
import {SAFEExtension} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFTEExtensionV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTExtensionV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {TokenWarrantExtensionV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Upgrades the live V1 and V2 certificate extension proxies to new implementations.
/// @dev The proxies keep their addresses. The new code escapes string fields in the JSON it renders.
contract DeployExtensionsV2Script is Script {
    function run() public {
        runWithArgs(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV2.0.1",
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV2.0.1",
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 salt = keccak256(bytes(saltStr));

        DeploymentConstants.ExtensionDeployment memory extensions = DeploymentConstants.extensions(chainId);

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        address safeImplementation = address(new SAFEExtension{salt: salt}());
        SAFEExtension(extensions.safeExtension).upgradeToAndCall(safeImplementation, "");

        address saftV2Implementation = address(new SAFTExtensionV2{salt: salt}());
        SAFTExtensionV2(extensions.saftExtensionV2).upgradeToAndCall(saftV2Implementation, "");

        address safteV2Implementation = address(new SAFTEExtensionV2{salt: salt}());
        SAFTEExtensionV2(extensions.safteExtensionV2).upgradeToAndCall(safteV2Implementation, "");

        address tokenWarrantV2Implementation = address(new TokenWarrantExtensionV2{salt: salt}());
        TokenWarrantExtensionV2(extensions.tokenWarrantExtensionV2).upgradeToAndCall(tokenWarrantV2Implementation, "");

        // ACESAFEExtension exists on Base mainnet only.
        address aceSafeImplementation;
        if (chainId == DeploymentConstants.BASE) {
            aceSafeImplementation = address(new ACESAFEExtension{salt: salt}());
            ACESAFEExtension(extensions.aceSafeExtension).upgradeToAndCall(aceSafeImplementation, "");
        }
        vm.stopBroadcast();

        console2.log("==== Upgraded ====");
        console2.log("SAFEExtension: %s -> %s", extensions.safeExtension, safeImplementation);
        console2.log("SAFTExtensionV2: %s -> %s", extensions.saftExtensionV2, saftV2Implementation);
        console2.log("SAFTEExtensionV2: %s -> %s", extensions.safteExtensionV2, safteV2Implementation);
        console2.log(
            "TokenWarrantExtensionV2: %s -> %s", extensions.tokenWarrantExtensionV2, tokenWarrantV2Implementation
        );
        if (chainId == DeploymentConstants.BASE) {
            console2.log("ACESAFEExtension: %s -> %s", extensions.aceSafeExtension, aceSafeImplementation);
        }
        console2.log("");
    }
}
