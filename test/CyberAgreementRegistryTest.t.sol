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
    address chad;
    uint256 chadPrivateKey;

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
        (chad, chadPrivateKey) = makeAddrAndKey("chad");

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

    /// @notice Contract should automatically finalize if (1) all parties are signed, and (2) finalizer is undefined
    function test_signContractAndFinalize() public {
        uint256 salt = uint256(keccak256("test_signContractAndFinalize"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties,
            bytes32(0),
            address(0)));

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

    /// @notice Should fill unallocated slots if it's an open agreement
    function test_signContractFillUnallocated() public {
        uint256 salt = uint256(keccak256("test_signContractFillUnallocated"));

        // Alice to create an open agreement

        address[] memory parties = new address[](2);
        parties[0] = alice;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = testPartyValues[0]; // alice's test values

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            parties, // open agreement
            partyValues,
            "",
            address(0), // finalizer undefined
            block.timestamp + 10
        );

        // bob to fill the unallocated slot

        {
            bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[1], // bob's test values
                bobPrivateKey
            );

                vm.prank(bob);
                registry.signContract(
                    agreementId,
                    testPartyValues[1], // bob's test values
                    signature,
                    true, // fillUnallocated
                    ""
                );

                assertTrue(registry.hasSigned(agreementId, bob), "bob should have signed now");
        }

        // since all unallocated slots are filled, chad should not be able to sign

        {
            bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[1], // reuse bob's test values. It does not matter
                chadPrivateKey
            );

            vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
            vm.prank(chad);
            registry.signContract(
                agreementId,
                testPartyValues[1], // reuse bob's test values. It does not matter
                signature,
                true, // fillUnallocated
                ""
            );
        }
    }

    /// @notice Should not be able to fill unallocated slots if it's a closed agreement
    function test_RevertIf_signContractFillUnallocatedClosed() public {
        uint256 salt = uint256(keccak256("test_RevertIf_signContractFillUnallocatedClosed"));

        // Alice to create a closed agreement

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

        // chad should not be able to fill the slot because he's not a party

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            testGlobalValues,
            testPartyValues[1], // reuse bob's test values. It does not matter
            bobPrivateKey
        );

        vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
        vm.prank(chad);
        registry.signContract(
            agreementId,
            testPartyValues[1], // bob's test values
            signature,
            false, // fillUnallocated
            ""
        );

        // using `fallUnallocated = true` should not work either
        vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
        vm.prank(chad);
        registry.signContract(
            agreementId,
            testPartyValues[1], // bob's test values
            signature,
            true, // fillUnallocated
            ""
        );
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
            testParties,
            bytes32(0),
            address(0)));

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
            testParties,
            bytes32(0),
            address(0)));

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

    /// @notice A delegate must not be counted as an independent party for signature quorum.
    /// Showcases the exploit where a party (alice) and her own delegate (bob) reach the
    /// full-signature threshold of an [alice, chad] agreement without chad ever signing.
    /// The delegate's own address is not a listed party, so signing under it must revert
    /// `NotAParty`. Regression guard: `isParty()` must not treat a delegate address as a party.
    function test_delegateCannotCountAsIndependentPartyForQuorum() public {
        uint256 salt = uint256(keccak256("test_delegateCannotCountAsIndependentPartyForQuorum"));

        // Agreement between alice (party) and chad (counterparty)
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = chad;

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            testGlobalValues,
            parties,
            testPartyValues,
            "", // secretHash
            address(0), // finalizer undefined -> auto-finalize on full quorum
            block.timestamp + 100
        );

        // alice delegates to bob
        vm.prank(alice);
        registry.setDelegation(bob, block.timestamp + 100);

        // alice signs as herself
        vm.prank(alice);
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
                alicePrivateKey
            ),
            false,
            ""
        );

        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed");
        assertFalse(registry.hasSigned(agreementId, chad), "chad has not signed");
        assertFalse(registry.allPartiesSigned(agreementId), "quorum must not be reached yet");

        // EXPLOIT: bob (alice's delegate) signs using his OWN address as the signer,
        // padding numSignatures to reach quorum without chad's consent.
        bytes memory bobExploitSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            testGlobalValues,
            testPartyValues[1],
            bobPrivateKey
        );

        vm.prank(bob);
        vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
        registry.signContractFor(
            bob,
            agreementId,
            testPartyValues[1],
            bobExploitSig,
            false,
            ""
        );

        // The counterparty's consent must still be outstanding
        assertFalse(registry.allPartiesSigned(agreementId), "quorum must not be reachable without chad");
        assertFalse(registry.isFinalized(agreementId), "agreement must not finalize without chad");
    }

    /// @notice Should be able to prepare & sign a standalone agreement in one tx
    function test_createStandaloneContractAndSign() public {
        uint256 salt = uint256(keccak256("test_createStandaloneContractAndSign"));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties,
            bytes32(0),
            address(0)));

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
            testParties,
            bytes32(0),
            address(0)));

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
            testParties,
            bytes32(0),
            address(0)));

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
    function test_createStandaloneContractAndSignDuplicate() public {
        vm.startPrank(alice);

        uint256 salt0 = uint256(keccak256("test_createSimpleContractDifferentSalts.0"));
        bytes32 expectedAgreementId0 = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt0,
            testGlobalValues,
            testParties,
            bytes32(0),
            address(0)));
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
            testParties,
            bytes32(0),
            address(0)));
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

    // ===== AUDIT: instantiation-hijack via front-running is blocked =====
    // contractId now = keccak256(templateId, salt, globalValues, parties, secretHash, finalizer).
    // An attacker who front-runs createContract with the same (templateId, salt, globalValues, parties)
    // but hostile lifecycle params gets a DIFFERENT contractId, so it can neither collide with the
    // victim's intended instance nor accept the victim's signature. Each test isolates one field.

    /// @dev Recompute the standalone contractId the way createContract now does.
    function _standaloneId(
        uint256 salt,
        address[] memory parties,
        bytes32 secretHash,
        address finalizer
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            expectedStandaloneTemplateId, salt, testGlobalValues, parties, secretHash, finalizer
        ));
    }

    /// @notice A hostile finalizer yields a different contractId, so the victim's standalone agreement
    /// (finalizer == address(0)) is created and auto-finalized exactly as intended.
    function test_AUDIT_frontRunFinalizerCannotHijack() public {
        uint256 salt = uint256(keccak256("test_AUDIT_frontRunFinalizerCannotHijack"));
        uint256 expiry = block.timestamp + 10;

        address[] memory parties = new address[](1);
        parties[0] = alice;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = testPartyValues[0];

        bytes32 victimId = _standaloneId(salt, parties, bytes32(0), address(0));
        bytes memory aliceSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            victimId, testLegalContractUri, testGlobalFields, testPartyFields,
            testGlobalValues, partyValues[0], alicePrivateKey
        );

        // Attacker front-runs with a hostile finalizer -> different contractId, no collision
        vm.startPrank(chad);
        registry.createTemplate(
            expectedStandaloneTemplateId, testTitle, testLegalContractUri, testGlobalFields, testPartyFields
        );
        bytes32 attackerId = registry.createContract(
            expectedStandaloneTemplateId, salt, testGlobalValues, parties, partyValues,
            bytes32(0), chad, expiry
        );
        vm.stopPrank();
        assertNotEq(attackerId, victimId, "hostile finalizer must not collide with the intended id");

        // The victim's standalone tx is unaffected and its agreement auto-finalizes
        vm.prank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields,
            salt, testGlobalValues, parties, partyValues, expiry, aliceSig
        );
        assertEq(agreementId, victimId, "victim gets the intended contractId");
        assertTrue(registry.isFinalized(agreementId), "victim's no-finalizer agreement auto-finalizes");
    }

    /// @notice `expiry` is NOT bound into contractId, so a front-runner CAN squat the victim's id with a
    /// hostile expiry. This is an accepted trade-off: binding it would make presigned flows unusable,
    /// because callers derive expiry from block.timestamp and an off-chain signer cannot predict it.
    /// The squat is a denial-of-service (victim's create reverts), not a signature hijack: the victim
    /// never signs the attacker's instance, and `salt` lets them retry on a fresh id.
    function test_AUDIT_frontRunExpirySquatsIdButCannotStealSignature() public {
        uint256 salt = uint256(keccak256("test_AUDIT_frontRunExpirySquatsId"));
        uint256 expiry = block.timestamp + 10;

        address[] memory parties = new address[](1);
        parties[0] = alice;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = testPartyValues[0];

        bytes32 victimId = _standaloneId(salt, parties, bytes32(0), address(0));

        // Attacker front-runs with a different expiry -> SAME contractId, so the id is taken
        vm.startPrank(chad);
        registry.createTemplate(
            expectedStandaloneTemplateId, testTitle, testLegalContractUri, testGlobalFields, testPartyFields
        );
        bytes32 attackerId = registry.createContract(
            expectedStandaloneTemplateId, salt, testGlobalValues, parties, partyValues,
            bytes32(0), address(0), block.timestamp + 1000
        );
        vm.stopPrank();
        assertEq(attackerId, victimId, "expiry is not bound, so the ids collide");

        bytes memory aliceSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            victimId, testLegalContractUri, testGlobalFields, testPartyFields,
            testGlobalValues, partyValues[0], alicePrivateKey
        );

        // The victim's own creation reverts rather than silently adopting the attacker's terms
        vm.prank(alice);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyExists.selector);
        registry.createStandaloneContractAndSign(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields,
            salt, testGlobalValues, parties, partyValues, expiry, aliceSig
        );

        // A fresh salt sidesteps the squatted id entirely
        uint256 freshSalt = salt + 1;
        bytes32 freshId = _standaloneId(freshSalt, parties, bytes32(0), address(0));
        bytes memory aliceFreshSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            freshId, testLegalContractUri, testGlobalFields, testPartyFields,
            testGlobalValues, partyValues[0], alicePrivateKey
        );
        vm.prank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields,
            freshSalt, testGlobalValues, parties, partyValues, expiry, aliceFreshSig
        );
        assertEq(agreementId, freshId, "victim gets the intended contractId on a fresh salt");
        assertTrue(registry.isFinalized(agreementId), "victim's agreement auto-finalizes");
    }

    /// @notice A hostile secretHash yields a different contractId, so it cannot pre-empt the victim's instance.
    function test_AUDIT_frontRunSecretHashCannotHijack() public {
        uint256 salt = uint256(keccak256("test_AUDIT_frontRunSecretHashCannotHijack"));
        uint256 expiry = block.timestamp + 10;

        address[] memory parties = new address[](1);
        parties[0] = alice;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = testPartyValues[0];

        bytes32 victimId = _standaloneId(salt, parties, bytes32(0), address(0));
        bytes memory aliceSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            victimId, testLegalContractUri, testGlobalFields, testPartyFields,
            testGlobalValues, partyValues[0], alicePrivateKey
        );

        // Attacker front-runs with a hostile secretHash -> different contractId, no collision
        vm.startPrank(chad);
        registry.createTemplate(
            expectedStandaloneTemplateId, testTitle, testLegalContractUri, testGlobalFields, testPartyFields
        );
        bytes32 attackerId = registry.createContract(
            expectedStandaloneTemplateId, salt, testGlobalValues, parties, partyValues,
            keccak256(abi.encode("chad-secret")), address(0), expiry
        );
        vm.stopPrank();
        assertNotEq(attackerId, victimId, "hostile secretHash must not collide with the intended id");

        vm.prank(alice);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle, testLegalContractUri, testGlobalFields, testPartyFields,
            salt, testGlobalValues, parties, partyValues, expiry, aliceSig
        );
        assertEq(agreementId, victimId, "victim gets the intended contractId");
        assertTrue(registry.isFinalized(agreementId), "victim's agreement auto-finalizes");
    }
}
