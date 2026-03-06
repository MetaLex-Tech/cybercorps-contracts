// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract BaseScript is Script {
    function run() public {
        bytes32 salt = keccak256(abi.encodePacked("zkpassport.v1"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        string memory expectedDomain = vm.envString("ZKPASSPORT_DOMAIN");
        string memory expectedScope = vm.envString("ZKPASSPORT_SCOPE");
        address verifier = vm.envOr("ZKPASSPORT_VERIFIER", address(0));
        uint256 maxValidityPeriod = vm.envUint("ZKPASSPORT_MAX_VALIDITY_PERIOD");
        BorgAuth coreAuth = BorgAuth(vm.envAddress("CORE_AUTH_ADDRESS"));

        string[] memory outCountries = new string[](9);
        outCountries[0] = "IRN";
        outCountries[1] = "IRQ";
        outCountries[2] = "LBY";
        outCountries[3] = "PRK";
        outCountries[4] = "SDN";
        outCountries[5] = "SOM";
        outCountries[6] = "SYR";
        outCountries[7] = "USA";
        outCountries[8] = "YEM";

        vm.startBroadcast(deployerPrivateKey);

        NonUSNationalityCondition condition = new NonUSNationalityCondition{salt: salt}(
//            address(coreAuth), // TODO WIP TBD
            expectedDomain,
            expectedScope,
            verifier,
            maxValidityPeriod,
            outCountries
        );

        vm.stopBroadcast();

        console2.log("NonUSNationalityCondition:", address(condition));
        console2.log("Expected domain:", expectedDomain);
        console2.log("Expected scope:", expectedScope);
    }
}
