// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";

contract BaseScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        string memory expectedDomain = vm.envString("ZKPASSPORT_DOMAIN");
        string memory expectedScope = vm.envString("ZKPASSPORT_SCOPE");
        address verifier = vm.envOr("ZKPASSPORT_VERIFIER", address(0));

        vm.startBroadcast(deployerPrivateKey);

        NonUSNationalityCondition condition = new NonUSNationalityCondition(
            expectedDomain,
            expectedScope,
            verifier
        );

        vm.stopBroadcast();

        console2.log("NonUSNationalityCondition:", address(condition));
        console2.log("Expected domain:", expectedDomain);
        console2.log("Expected scope:", expectedScope);
    }
}
