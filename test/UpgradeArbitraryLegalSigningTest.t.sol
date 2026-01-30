// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistryTest} from "./CyberAgreementRegistryTest.t.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {UpgradeArbitraryLegalSigningScript} from "../script/upgrade-arbitrary-legal-signing.s.sol";

contract UpgradeArbitraryLegalSigningTest is CyberAgreementRegistryTest {

    // Assume Ethereum mainnet @ 24347623 (pre upgrade-arbitrary-legal-signing)
    function test_setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        (chad, chadPrivateKey) = makeAddrAndKey("chad");

        address coreDeployer = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
        coreAuth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);

        // Simulate granting test deployer core AUTH
        vm.prank(coreDeployer);
        coreAuth.updateRole(deployer, 99);

        // Simulate running upgrade scripts
        (coreAuth, registry) = (new UpgradeArbitraryLegalSigningScript()).runWithArgs(
            coreSalt,
            deployerPrivateKey
        );

        // Simulate revoke test deployer core AUTH
        vm.prank(coreDeployer);
        coreAuth.updateRole(deployer, 0);
    }

    // Will run all CyberAgreementRegistryTest tests to verify this upgrade
}
