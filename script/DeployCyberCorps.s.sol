// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CyberCorps} from "../src/CyberCorps.sol";
import {DeterministicDeployFactory} from "../src/DeterministicDeployFactory.sol";

contract DeployCyberCorpsScript is Script {
    error MissingFactoryAddress();
    error MissingSalt();

    function run() public {
        // Load and validate factory address
        address factoryAddress;
        try vm.envAddress("FACTORY_ADDRESS") returns (address addr) {
            factoryAddress = addr;
        } catch {
            revert MissingFactoryAddress();
        }

        // Load and validate salt
        bytes32 salt;
        try vm.envUint("SALT") returns (uint256 value) {
            salt = bytes32(value);
        } catch {
            revert MissingSalt();
        }

        // Get deployment params
        string memory name = "CyberCorps";
        string memory symbol = "CyCos";

        // Get creation bytecode with constructor args
        bytes memory creationCode = abi.encodePacked(type(CyberCorps).creationCode, abi.encode(name, symbol));

        // Get factory instance
        DeterministicDeployFactory factory = DeterministicDeployFactory(factoryAddress);

        vm.broadcast();
        address cyberCorps = factory.deploy(salt, creationCode);
        console.log("CyberCorps deployed to:", cyberCorps);
    }
}
