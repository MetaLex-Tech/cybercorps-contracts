// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

/// @notice Deploys a new CyberAgreementRegistry implementation via CREATE2.
/// @dev Upgrade the existing proxy separately on each chain after deployment.
contract DeployCyberAgreementRegistryScript is Script {
    string internal constant DEFAULT_SALT_STRING =
        "MetaLex.CyberAgreementRegistry.UpgradeV3.2.0";

    function run() public returns (CyberAgreementRegistry implementation) {
        return
            runWithArgs(
                DEFAULT_SALT_STRING,
                vm.envUint("PRIVATE_KEY_MAIN")
            );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (CyberAgreementRegistry implementation) {
        bytes32 salt = keccak256(bytes(saltStr));
        address deployer = vm.addr(deployerPrivateKey);

        DeploymentConstants.CoreDeployment memory deployment =
            DeploymentConstants.coreV2(block.chainid);

        console2.log("==== Configs ====");
        console2.log("chainId:", block.chainid);
        console2.log("deployer:", deployer);
        console2.log("salt string:", saltStr);
        console2.logBytes32(salt);
        console2.log("AUTH:", deployment.auth);
        console2.log(
            "Existing CyberAgreementRegistry proxy:",
            deployment.cyberAgreementRegistry
        );
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        implementation = new CyberAgreementRegistry{salt: salt}();

        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log(
            "CyberAgreementRegistry implementation:",
            address(implementation)
        );
        console2.log("");
    }
}
