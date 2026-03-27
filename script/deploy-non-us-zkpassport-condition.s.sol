// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {OrCondition} from "../src/libs/conditions/OrCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

contract DeployNonUsZkPassportConditionScript is Script {
    function run() public returns (BorgAuth zkpassportAuth, NonUSNationalityCondition zkpassportCondition) {
        return runWithArgs(
            "zkpassport.v1.dev1",
            vm.envUint("PRIVATE_KEY_MAIN"),
            vm.envString("ZKPASSPORT_DOMAIN"),
            vm.envString("ZKPASSPORT_SCOPE"),
            vm.envUint("ZKPASSPORT_MAX_VALIDITY_PERIOD"),
            DeploymentConstants.BASE
        );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey,
        string memory expectedDomain,
        string memory expectedScope,
        uint256 maxValidityPeriod,
        uint256 chainId
    ) public returns (BorgAuth zkpassportAuth, NonUSNationalityCondition zkpassportCondition) {

        bytes32 salt = keccak256(abi.encodePacked("zkpassport.v1.0.1-dev2"));

        address deployerAddress = vm.addr(deployerPrivateKey);

        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(chainId);

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

        zkpassportAuth = new BorgAuth{salt: salt}(deployerAddress);

        zkpassportCondition = new NonUSNationalityCondition{salt: salt}(
            address(zkpassportAuth),
            expectedDomain,
            expectedScope,
            address(0), // verifier (use default)
            maxValidityPeriod,
            outCountries
        );

        // Deploy OrCondition (zkPassport || LexChex)
        address[] memory orAddrs = new address[](2);
        orAddrs[0] = address(zkpassportCondition);
        orAddrs[1] = deployment.lexchexCondition;
        OrCondition orCondition = new OrCondition(orAddrs);

        vm.stopBroadcast();

        console2.log("==== Configs ====");
        console2.log("LexChexCondition:", address(deployment.lexchexCondition));
        console2.log("Expected domain:", expectedDomain);
        console2.log("Expected scope:", expectedScope);
        console2.log("");

        console2.log("==== Deployed ====");
        console2.log("zkpassportAuth:", address(zkpassportAuth));
        console2.log("NonUSNationalityCondition:", address(zkpassportCondition));
        console2.log("OrCondition(zkPassport || lexchex):", address(orCondition));
        console2.log("");
    }
}
