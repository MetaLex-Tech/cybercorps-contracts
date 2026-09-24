// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistryTest} from "./CyberAgreementRegistryTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {RegistryBeforeExpiryBound} from "./fixtures/RegistryBeforeExpiryBound.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IExpiryBoundStandalone {
    function createStandaloneContractAndSignExpiryBoundFor(
        string memory title, string memory uri, string[] memory globalFields,
        string[] memory partyFields, uint256 salt, string[] memory globalValues,
        address[] memory parties, string[][] memory partyValues, uint256 expiry,
        address signer, bytes calldata signature
    ) external returns (bytes32);
}

contract StandaloneExpiryBoundTest is CyberAgreementRegistryTest {
    bytes32 constant ID_DOMAIN = keccak256("CyberAgreementRegistry.StandaloneExpiryBound.v1");

    function boundId(uint256 expiry) internal view returns (bytes32) {
        return keccak256(abi.encode(ID_DOMAIN, expectedStandaloneTemplateId, uint256(42),
            testGlobalValues, testParties, testPartyValues, expiry));
    }

    function signatureFor(bytes32 id) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), id, testLegalContractUri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[0], alicePrivateKey);
    }

    function createBound(uint256 expiry, bytes memory signature) internal returns (bytes32) {
        return IExpiryBoundStandalone(address(registry)).createStandaloneContractAndSignExpiryBoundFor(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields, 42,
            testGlobalValues, testParties, testPartyValues, expiry, alice, signature);
    }

    function test_boundCreationSurvivesLegacyExpirySquat() public {
        registry.createTemplate(expectedStandaloneTemplateId, testTitle, testLegalContractUri,
            testGlobalFields, testPartyFields);
        vm.prank(chad);
        bytes32 poisoned = registry.createContract(expectedStandaloneTemplateId, 42,
            testGlobalValues, testParties, testPartyValues, bytes32(0), address(0), 1);
        bytes32 expected = boundId(0);
        assertNotEq(poisoned, expected);
        bytes memory sig = signatureFor(expected);
        vm.prank(chad); // Relaying the exact signed terms is permitted.
        assertEq(createBound(0, sig), expected);
        assertTrue(registry.hasSigned(expected, alice));
        bytes memory bobSig = CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), expected, testLegalContractUri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[1], bobPrivateKey);
        registry.signContractFor(bob, expected, testPartyValues[1], bobSig, false, "");
        assertTrue(registry.isFinalized(expected));
    }

    function test_boundRejectsChangedExpiryAndRollsBack() public {
        bytes32 intended = boundId(0);
        bytes memory sig = signatureFor(intended);
        bytes32 altered = boundId(block.timestamp + 1000);
        vm.expectRevert();
        createBound(block.timestamp + 1000, sig);
        assertEq(registry.getParties(altered).length, 0);
        assertEq(createBound(0, sig), intended);
    }

    function test_boundRejectsChangedUnsignedPartyRow() public {
        bytes32 intended = boundId(0);
        bytes memory sig = signatureFor(intended);
        testPartyValues[1][0] = "Hostile replacement";
        vm.expectRevert();
        createBound(0, sig);
        testPartyValues[1][0] = "Bob";
        assertEq(createBound(0, sig), intended);
    }

    function test_boundRequiresFirstPartySignature() public {
        vm.expectRevert();
        createBound(0, hex"00");
        assertEq(registry.getParties(boundId(0)).length, 0);
        assertEq(createBound(0, signatureFor(boundId(0))), boundId(0));
    }

    function test_boundIgnoresHostileLegacyTemplate() public {
        registry.createTemplate(expectedStandaloneTemplateId, "Hostile", "ipfs://hostile",
            testGlobalFields, testPartyFields);
        bytes32 id = createBound(0, signatureFor(boundId(0)));
        (, string memory uri,,,,,,,,) = registry.getContractDetails(id);
        assertEq(uri, testLegalContractUri);
        assertTrue(vm.contains(registry.getContractJson(id), testLegalContractUri));
        (string memory legacyUri,,,) = registry.getTemplateDetails(expectedStandaloneTemplateId);
        assertEq(legacyUri, "ipfs://hostile");
        bytes memory sig = CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), id, testLegalContractUri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[1], bobPrivateKey);
        registry.signContractFor(bob, id, testPartyValues[1], sig, false, "");
        assertTrue(registry.isFinalized(id));
        bytes memory firstSig = signatureFor(id);
        vm.expectRevert();
        createBound(0, firstSig);
        assertTrue(registry.hasSigned(id, bob));
    }

    function test_boundRejectsValidLaterSignerAsCreator() public {
        bytes32 id = boundId(0);
        bytes memory sig = CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), id, testLegalContractUri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[0], bobPrivateKey);
        vm.expectRevert();
        IExpiryBoundStandalone(address(registry)).createStandaloneContractAndSignExpiryBoundFor(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields, 42,
            testGlobalValues, testParties, testPartyValues, 0, bob, sig);
        assertEq(registry.getParties(id).length, 0);
    }

    function test_boundRejectsInvalidPartiesAndRows() public {
        bytes memory sig = signatureFor(boundId(0));
        testParties[1] = alice;
        vm.expectRevert();
        createBound(0, sig);
        testParties[1] = address(0);
        vm.expectRevert();
        createBound(0, sig);
        testParties[1] = bob;
        testPartyValues.pop();
        vm.expectRevert();
        createBound(0, sig);
        delete testParties;
        vm.expectRevert();
        createBound(0, sig);
    }

    function test_boundExpiryBoundaryAndDelegation() public {
        vm.warp(100);
        bytes memory expiredSig = signatureFor(boundId(99));
        vm.expectRevert();
        createBound(99, expiredSig);
        assertEq(registry.getParties(boundId(99)).length, 0);
        bytes32 atBoundary = createBound(100, signatureFor(boundId(100)));
        assertTrue(registry.hasSigned(atBoundary, alice));
        vm.prank(alice);
        registry.setDelegation(chad, 200);
        bytes32 future = boundId(150);
        bytes memory delegated = CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), future, testLegalContractUri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[0], alice, chadPrivateKey);
        assertEq(createBound(150, delegated), future);
        assertTrue(registry.hasSigned(future, alice));
    }

    function test_populatedUpgradePreservesLegacyStorageAndJson() public {
        RegistryBeforeExpiryBound old = RegistryBeforeExpiryBound(address(new ERC1967Proxy(
            address(new RegistryBeforeExpiryBound()), abi.encodeCall(RegistryBeforeExpiryBound.initialize, (address(coreAuth))))));
        // Include escaping and an unsigned row in exact JSON parity.
        string memory uri = 'ipfs://old\\"document';
        old.createTemplate(testTemplateId, 'Title "quoted"', uri, testGlobalFields, testPartyFields);
        bytes32 id = old.createContract(testTemplateId, 7, testGlobalValues, testParties,
            testPartyValues, bytes32(0), address(0), 0);
        bytes memory sig = CyberAgreementUtils.signAgreementTypedData(vm, old.DOMAIN_SEPARATOR(),
            old.SIGNATUREDATA_TYPEHASH(), id, uri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[0], alicePrivateKey);
        old.signContractFor(alice, id, testPartyValues[0], sig, false, "");
        vm.prank(alice);
        old.setDelegation(chad, block.timestamp + 1000);
        string memory beforeJson = old.getContractJson(id);
        bytes32 beforeDomain = old.DOMAIN_SEPARATOR();
        address next = address(new CyberAgreementRegistry());
        vm.prank(deployer);
        old.upgradeToAndCall(next, "");
        registry = CyberAgreementRegistry(address(old));
        assertEq(registry.getContractJson(id), beforeJson);
        assertEq(registry.DOMAIN_SEPARATOR(), beforeDomain);
        assertTrue(registry.hasSigned(id, alice));
        assertTrue(registry.isValidDelegate(alice, chad));
        bytes memory bobSig = CyberAgreementUtils.signAgreementTypedData(vm, registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(), id, uri, testGlobalFields,
            testPartyFields, testGlobalValues, testPartyValues[1], bobPrivateKey);
        registry.signContractFor(bob, id, testPartyValues[1], bobSig, false, "");
        assertTrue(registry.isFinalized(id));
        assertEq(createBound(0, signatureFor(boundId(0))), boundId(0));
        assertTrue(registry.hasSigned(id, alice));
    }
}
