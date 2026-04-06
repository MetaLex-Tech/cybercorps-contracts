// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";

contract BaseScript is Script {
    string internal constant DEFAULT_SALT_STRING =
        "MetaLexCyberCorp.RoundManagerFactory.Implementation.V2";

    function run() public returns (RoundManagerFactory implementation) {
        return
            runWithArgs(
                DEFAULT_SALT_STRING,
                vm.envUint("PRIVATE_KEY_MAIN")
            );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (RoundManagerFactory implementation) {
        address deployer = vm.addr(deployerPrivateKey);
        bytes32 salt = keccak256(bytes(saltStr));

        console2.log("==== Configs ====");
        console2.log("chainId:", block.chainid);
        console2.log("deployer:", deployer);
        console2.log("salt string:", saltStr);
        console2.logBytes32(salt);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        implementation = new RoundManagerFactory{salt: salt}();
        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log(
            "RoundManagerFactory implementation:",
            address(implementation)
        );
        console2.log("");
    }
}
