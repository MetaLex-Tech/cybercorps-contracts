// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeployZKPassportFinalizerScript} from "../../script/deploy-zkpassport-finalizer.s.sol";
import {DeploymentConstants} from "../../script/libs/DeploymentConstants.sol";
import {DeploymentUtils} from "../../script/libs/DeploymentUtils.sol";
import {GnosisTransaction} from "../../script/libs/safe.sol";
import {ZKPassportFinalizer} from "../../src/ZKPassportFinalizer.sol";
import {ICyberAgreementRegistry} from "../../src/interfaces/ICyberAgreementRegistry.sol";
import "forge-std/Test.sol";

/// @notice `DeployZKPassportFinalizerScript` deploys a configured proxy that creates agreements on the live registry.
/// @dev The fork is pinned. The constants have no ZKPassportFinalizer yet, so the run deploys a new proxy.
contract DeployZKPassportFinalizerScriptForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 52_661_651;
    uint256 internal constant BASE_SEPOLIA_PINNED_BLOCK = 48_172_194;
    uint256 internal constant SEPOLIA_PINNED_BLOCK = 11_924_106;
    string internal constant SALT = "CyberCorpV5-ZKPassportFinalizerV1.0.0";
    string internal constant DOMAIN = "app.metalex.tech";
    string internal constant SCOPE = "cyberagreement-passport";
    uint256 internal deployerKey = 0xA11CE;
    address internal deployer = vm.addr(0xA11CE);
    DeploymentConstants.CoreDeployment internal core;

    function setUp() public {
        vm.createSelectFork("base", PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        core = DeploymentConstants.coreV2(block.chainid);
    }

    function test_DeploysConfiguredProxyThatCreatesGatedAgreements() public {
        GnosisTransaction[] memory safeTxs =
            (new DeployZKPassportFinalizerScript()).runWithArgs(block.chainid, SALT, DOMAIN, SCOPE, deployerKey);
        assertEq(safeTxs.length, 0);

        ZKPassportFinalizer finalizer = _finalizer();
        assertEq(address(finalizer.registry()), core.cyberAgreementRegistry);
        assertEq(address(finalizer.verifier()), core.zkpassportVerifier);
        assertEq(finalizer.expectedDomain(), DOMAIN);
        assertEq(finalizer.expectedScope(), SCOPE);
        assertFalse(finalizer.devMode());
        assertEq(address(finalizer.AUTH()), core.auth);

        bytes32 contractId = _createGatedAgreement(finalizer);
        assertTrue(finalizer.isRegistered(contractId));
        assertEq(ICyberAgreementRegistry(core.cyberAgreementRegistry).getParties(contractId).length, 2);
    }

    function test_TestnetDeploysInDevMode() public {
        vm.createSelectFork("sepolia", SEPOLIA_PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        (new DeployZKPassportFinalizerScript()).runWithArgs(block.chainid, SALT, DOMAIN, SCOPE, deployerKey);

        assertTrue(_finalizer().devMode());
    }

    function test_RevertIf_ChainHasNoVerifier() public {
        vm.createSelectFork("base_sepolia", BASE_SEPOLIA_PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        DeployZKPassportFinalizerScript script = new DeployZKPassportFinalizerScript();

        // `initialize` reverts with InvalidVerifier. CreateX reports only that the proxy creation failed.
        // ZKPassportFinalizerTest checks the InvalidVerifier cause.
        vm.expectRevert(abi.encodeWithSignature("FailedContractCreation(address)", DeploymentUtils.CREATEX));
        script.runWithArgs(block.chainid, SALT, DOMAIN, SCOPE, deployerKey);
    }

    function _finalizer() internal view returns (ZKPassportFinalizer) {
        return ZKPassportFinalizer(
            DeploymentUtils.computeCreate3Address(
                deployer, DeploymentUtils.create3Salt(deployer, string.concat(SALT, "/ZKPassportFinalizer"))
            )
        );
    }

    function _createGatedAgreement(ZKPassportFinalizer finalizer) internal returns (bytes32) {
        string[] memory fields = new string[](1);
        fields[0] = "Name";
        bytes32 templateId = keccak256("zkpassport-finalizer-fork-template");
        ICyberAgreementRegistry(core.cyberAgreementRegistry)
            .createTemplate(templateId, "Passport Agreement", "https://example.com/agreement", fields, fields);

        address[] memory parties = new address[](2);
        parties[0] = makeAddr("alice");
        parties[1] = makeAddr("bob");
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Alice";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Bob";
        bytes32[] memory pins = new bytes32[](2);
        pins[1] = keccak256("passport-b");

        return finalizer.createContract(templateId, 1, fields, parties, partyValues, block.timestamp + 1 days, pins);
    }
}
