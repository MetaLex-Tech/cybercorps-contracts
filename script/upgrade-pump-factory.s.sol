// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";

contract DeployPumpCorpFactoryScript is Script {
    function run() public returns (PumpCorpFactory implementation) {
        return runWithArgs("PumpCorp.V1.0.1", vm.envUint("PRIVATE_KEY_MAIN"));
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (PumpCorpFactory implementation) {
        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        console2.log("==== Configs ====");
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        implementation = new PumpCorpFactory{salt: salt}();
        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log("PumpCorpFactory implementation:", address(implementation));
        console2.log("");
    }
}
