// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

contract CyberAgreementRegistryTest is Test {
    address deployer;
    uint256 deployerPrivateKey;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    bytes32 coreSalt = keccak256("CyberAgreementRegistryTest");
    
    BorgAuth coreAuth;
    CyberAgreementRegistry registry;

    string testTitle = "Test agreement";
    string testLegalContractUri = "ipfs://template";
    string[] testGlobalFields;
    string[] testPartyFields;
    string[] testGlobalValues;
    address[] testParties;
    string[][] testPartyValues;

    bytes32 expectedStandaloneTemplateId;

    bytes32 testTemplateId = keccak256("test-template-id");

    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vm.startPrank(deployer);

        coreAuth = new BorgAuth{salt: coreSalt}(deployer);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: coreSalt}(
                    address(new CyberAgreementRegistry{salt: coreSalt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(coreAuth)
                    )
                )
            )
        );

        testGlobalFields = new string[](1);
        testGlobalFields[0] = "Global Field";
        testPartyFields = new string[](2);
        testPartyFields[0] = "Officer Name";
        testPartyFields[1] = "Officer Title";

        testGlobalValues = new string[](1);
        testGlobalValues[0] = "global value 0";

        testParties = new address[](2);
        testParties[0] = alice;
        testParties[1] = bob;

        testPartyValues = new string[][](2);
        testPartyValues[0] = new string[](2);
        testPartyValues[0][0] = "Alice";
        testPartyValues[0][1] = "Test title";
        testPartyValues[1] = new string[](2);
        testPartyValues[1][0] = "Bob";
        testPartyValues[1][1] = "Test title 2";

        // Calculate the expected standalone template ID
        expectedStandaloneTemplateId = keccak256(abi.encode(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields
        ));

        // Create a test template
        registry.createTemplate(
            testTemplateId,
            "Test",
            testLegalContractUri,
            testGlobalFields,
            testPartyFields
        );

        vm.stopPrank();
    }

    /// @notice Should be able to prepare & sign a standalone agreement in one tx
    function test_createStandaloneContractAndSign() public {
        uint256 salt = uint256(keccak256("test_createStandaloneContractAndSign"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        vm.stopPrank();

        (string memory templateUri, ) = registry.templates(expectedStandaloneTemplateId);
        assertEq(templateUri, testLegalContractUri, "just-in-time template should have been created");

        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");
    }

    /// @notice Third-party should be able to prepare & forward a pre-signed standalone agreement in one tx
    function test_createStandaloneContractAndSignFor() public {
        uint256 salt = uint256(keccak256("test_createStandaloneContractAndSignFor"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(deployer); // third-party
        bytes32 agreementId = registry.createStandaloneContractAndSignFor(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            alice, // on behalf of
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        vm.stopPrank();

        (string memory templateUri, ) = registry.templates(expectedStandaloneTemplateId);
        assertEq(templateUri, testLegalContractUri, "just-in-time template should have been created");

        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");
    }

    /// @notice Third-party should be able to prepare & sign a standalone agreement (on delegator's behalf) in one tx
    function test_createStandaloneContractAndSignForDelegator() public {
        uint256 salt = uint256(keccak256("test_createStandaloneContractAndSignForDelegator"));

        // alice to delegate to bob

        vm.prank(alice);
        registry.setDelegation(bob, block.timestamp + 10);
        assertTrue(registry.isValidDelegate(alice, bob), "alice should've delegated to bob");

        // Bob to prepare and sign agreement as the delegate

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(bob);
        bytes32 agreementId = registry.createStandaloneContractAndSignFor(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            alice, // on behalf of
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                bobPrivateKey // delegate's own private key
            )
        );
        vm.stopPrank();

        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");
    }

    /// @notice Should be able to create duplicate simple agreements as long as their salts are different.
    /// The duplicate agreements should have the same template ID, too.
    function test_test_createStandaloneContractAndSignDuplicate() public {
        vm.startPrank(alice);

        uint256 salt0 = uint256(keccak256("test_createSimpleContractDifferentSalts.0"));
        bytes32 expectedAgreementId0 = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt0,
            testGlobalValues,
            testParties
        ));
        bytes32 agreementId0 = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt0,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId0,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        (bytes32 templateId0,,,,,,,,, ) = registry.getContractDetails(agreementId0);

        uint256 salt1 = uint256(keccak256("test_createSimpleContractDifferentSalts.1"));
        bytes32 expectedAgreementId1 = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt1,
            testGlobalValues,
            testParties
        ));
        bytes32 agreementId1 = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt1,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId1,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        (bytes32 templateId1,,,,,,,,, ) = registry.getContractDetails(agreementId1);

        assertNotEq(agreementId0, agreementId1, "two agreements should have different IDs");
        assertEq(templateId0, templateId1, "two agreements should share the same template");
    }

    /// @notice Contract should automatically finalize if (1) all parties are signed, and (2) finalizer is undefined
    function test_signContractAndFinalize() public {
        uint256 salt = uint256(keccak256("test_signContractAndFinalize"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        vm.stopPrank();
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");

        vm.startPrank(bob);
        registry.signContract(
            agreementId,
            testPartyValues[1],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[1],
                bobPrivateKey
            ),
            false,
            "" // secret
        );
        vm.stopPrank();
        assertTrue(registry.hasSigned(agreementId, bob), "bob should have signed now");

        assertTrue(registry.isFinalized(agreementId), "agreement should be finalized by now");
    }

    /// @notice Should allow `signContractFor()` even if finalizer is not defined
    /// This is for simple standalone cases to work because the finalizer would be undefined
    function test_signContractForUndefinedFinalizer() public {
        uint256 salt = uint256(keccak256("test_signContractForUndefinedFinalizer"));

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            "",
            address(0), // finalizer undefined
            block.timestamp + 10
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            testGlobalValues,
            testPartyValues[0],
            alicePrivateKey
        );

        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.AgreementSigned(agreementId, alice, block.timestamp);
        vm.prank(bob);
        registry.signContractFor(
            alice,
            agreementId,
            testPartyValues[0],
            signature,
            false,
            ""
        );
    }

    /// @notice Should not allow escrow-sign when finalizer is undefined
    function test_RevertIf_signContractWithEscrowUndefinedFinalizer() public {
        uint256 salt = uint256(keccak256("test_RevertIf_signContractWithEscrowUndefinedFinalizer"));

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            "",
            address(0), // finalizer undefined
            block.timestamp + 10
        );

        // Bob should not be able to fake alice's escrow signature
        vm.expectRevert(CyberAgreementRegistry.FinalizerNotDefined.selector);
        vm.prank(bob);
        registry.signContractWithEscrow(
            alice,
            agreementId,
            testPartyValues[0],
            "",
            false,
            ""
        );
    }

    function test_voidContractForSelf() public {
        uint256 salt = uint256(keccak256("test_voidContractForSelf"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");

        registry.voidContractFor(
            agreementId,
            alice,
            CyberAgreementUtils.signVoidAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.VOIDSIGNATUREDATA_TYPEHASH(),
                agreementId,
                alice,
                alicePrivateKey
            )
        );
        assertTrue(registry.isVoided(agreementId), "agreement should've been voided now");
        vm.stopPrank();
    }

    function test_voidContractForOthers() public {
        uint256 salt = uint256(keccak256("test_voidContractForOthers"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startPrank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            block.timestamp + 10,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                alicePrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");
        vm.stopPrank();

        vm.startPrank(bob);
        registry.voidContractFor(
            agreementId,
            alice,
            CyberAgreementUtils.signVoidAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.VOIDSIGNATUREDATA_TYPEHASH(),
                agreementId,
                alice,
                alicePrivateKey
            )
        );
        assertTrue(registry.isVoided(agreementId), "agreement should've been voided now");
        vm.stopPrank();
    }

    /// @notice A signer should be able to delegate to a third-party for signing (ex. multisig delegates to EOA)
    function test_setDelegation() public {
        uint256 salt = uint256(keccak256("test_setDelegation"));

        vm.startPrank(alice);

        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            "",
            address(0), // finalizer undefined
            block.timestamp + 10
        );

        // alice to delegate to bob
        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.DelegationSet(alice, bob, block.timestamp + 10);
        registry.setDelegation(bob, block.timestamp + 10);
        assertTrue(registry.isValidDelegate(alice, bob), "alice should've delegated to bob");
        (address delegate, uint256 expiry) = registry.getDelegation(alice);
        assertEq(delegate, bob, "unexpected delegate");
        assertEq(expiry, block.timestamp + 10, "unexpected delegation expiry");

        vm.stopPrank();

        // bob to sign for alice
        vm.startPrank(bob);
        registry.signContractFor(
            alice,
            agreementId,
            testPartyValues[0],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                bobPrivateKey
            ),
            false,
            ""
        );
        vm.stopPrank();
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");
    }

    /// @notice Should be able to revoke a delegation
    function test_revokeDelegate() public {
        uint256 salt = uint256(keccak256("test_revokeDelegate"));

        vm.startPrank(alice);

        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            "",
            address(0), // finalizer undefined
            block.timestamp + 10
        );

        // alice to delegate to bob but revoke immediately
        registry.setDelegation(bob, block.timestamp + 10);

        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.DelegationRevoked(alice, bob);
        registry.revokeDelegation();

        assertFalse(registry.isValidDelegate(alice, bob), "alice should not have delegated to bob");
        (address delegate, uint256 expiry) = registry.getDelegation(alice);
        assertEq(delegate, address(0), "unexpected delegate");
        assertEq(expiry, 0, "unexpected delegation expiry");

        vm.stopPrank();

        // bob should not be able to sign for alice
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            testGlobalValues,
            testPartyValues[0],
            bobPrivateKey
        );
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        vm.startPrank(bob);
        registry.signContractFor(
            alice,
            agreementId,
            testPartyValues[0],
            signature,
            false,
            ""
        );
        vm.stopPrank();
    }
}
