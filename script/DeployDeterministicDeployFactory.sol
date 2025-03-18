// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DeterministicDeployFactory} from "../src/DeterministicDeployFactory.sol";

contract DeployDeterministicDeployFactory is Script {
    function run() public {
        vm.startBroadcast();

        DeterministicDeployFactory factory = new DeterministicDeployFactory();
        console.log("Factory deployed at", address(factory));

        vm.stopBroadcast();
    }
}
