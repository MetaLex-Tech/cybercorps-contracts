// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {OrCondition} from "../src/libs/conditions/OrCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNonUsZkPassportConditionScript is Script {
    function run() public returns (BorgAuth zkpassportAuth, NonUSNationalityCondition zkpassportCondition) {
        return runWithArgs(
            // Production
            "MetaLexCyberCorp.NonUSNationalityZkpassport.V1.2.0",
            vm.envUint("PRIVATE_KEY_MAIN"),
            "ace.metalex.tech",
            "non-us-non-sanctioned",
            2592000, // 3600 * 24 * 30 days
            DeploymentConstants.BASE,
            false // ownedByDeployer

//            // Staging (localhost)
//            "MetaLexCyberCorp.NonUSNationalityZkpassport.V1.2.0.staging.dev0-localhost",
//            vm.envUint("PRIVATE_KEY_MAIN"),
//            "localhost",
//            "non-us-non-sanctioned",
//            2592000, // 3600 * 24 * 30 days
//            DeploymentConstants.BASE,
//            true // ownedByDeployer

//            // Staging (staging.ace.metalex.tech)
//            "MetaLexCyberCorp.NonUSNationalityZkpassport.V1.2.0.staging.dev0-staging.ace.metalex.tech",
//            vm.envUint("PRIVATE_KEY_MAIN"),
//            "staging.ace.metalex.tech",
//            "non-us-non-sanctioned",
//            2592000, // 3600 * 24 * 30 days
//            DeploymentConstants.BASE,
//            true // ownedByDeployer
        );
    }

    function runWithArgs(
        string memory saltStr,
        uint256 deployerPrivateKey,
        string memory expectedDomain,
        string memory expectedScope,
        uint256 maxValidityPeriod,
        uint256 chainId,
        bool ownedByDeployer // for test because our staging env is Base mainnet
    ) public returns (BorgAuth zkpassportAuth, NonUSNationalityCondition zkpassportCondition) {

        bytes32 salt = keccak256(bytes(saltStr));

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

        NonUSNationalityCondition impl = new NonUSNationalityCondition{salt: salt}();
        zkpassportCondition = NonUSNationalityCondition(
            address(new ERC1967Proxy{salt: salt}(
                address(impl),
                abi.encodeCall(NonUSNationalityCondition.initialize, (
                    address(zkpassportAuth),
                    expectedDomain,
                    expectedScope,
                    address(0), // verifier (use default)
                    maxValidityPeriod,
                    outCountries
                ))
            ))
        );

        // Deploy OrCondition (zkPassport || LexChex)
        address[] memory orAddrs = new address[](2);
        orAddrs[0] = address(zkpassportCondition);
        orAddrs[1] = deployment.lexchexCondition;
        OrCondition orCondition = new OrCondition(orAddrs);

        if (!ownedByDeployer) {
            // Assign ownership to MetaLeX multisig
            zkpassportAuth.updateRole(deployment.metalexSafe, zkpassportAuth.OWNER_ROLE());

            // Deployer to self-revoke ownership
            zkpassportAuth.zeroOwner();
            console2.log("Transferred ownership to %s:", deployment.metalexSafe);
        }

        vm.stopBroadcast();

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
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
