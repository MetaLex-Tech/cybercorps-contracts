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
    
    bytes32 testTemplateId = keccak256("test-template-id");
    string testLegalDocUri = "ipfs://template";
    string[] testGlobalFields;
    string[] testPartyFields;

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
        registry.createTemplate(
            testTemplateId,
            "Test",
            testLegalDocUri,
            testGlobalFields,
            testPartyFields
        );

        vm.stopPrank();
    }

    //
    // Regular contracts
    //

    /// @notice Should allow `signContractFor()` even if finalizer is not defined
    function test_signContractForUndefinedFinalizer() public {
        uint256 salt = uint256(keccak256("test_signContractForUndefinedFinalizer"));

        address[] memory parties = new address[](1);
        parties[0] = alice;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global value 0";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Alice";
        partyValues[0][1] = "Test title";

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "",
            address(0),
            block.timestamp + 10
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            testLegalDocUri,
            testGlobalFields,
            testPartyFields,
            globalValues,
            partyValues[0],
            alicePrivateKey
        );

        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.AgreementSigned(agreementId, alice, block.timestamp);
        vm.prank(bob);
        registry.signContractFor(
            alice,
            agreementId,
            partyValues[0],
            signature,
            false,
            ""
        );
    }

    /// @notice Should not allow escrow-sign when finalizer is undefined
    function test_RevertIf_signContractWithEscrowUndefinedFinalizer() public {
        uint256 salt = uint256(keccak256("test_RevertIf_signContractWithEscrowUndefinedFinalizer"));

        address[] memory parties = new address[](1);
        parties[0] = alice;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global value 0";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Alice";
        partyValues[0][1] = "Test title";

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "",
            address(0),
            block.timestamp + 10
        );

        vm.expectRevert(CyberAgreementRegistry.FinalizerNotDefined.selector);
        vm.prank(bob);
        registry.signContractWithEscrow(
            alice,
            agreementId,
            partyValues[0],
            "",
            false,
            ""
        );
    }

    //
    // Simple contracts
    //

    /// @notice Should be able to create duplicate simple agreements as long as their salts are different.
    /// The duplicate agreements should have the same template ID, too.
    function test_createSimpleContractDuplicate() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string memory legalDocUri = "ipfs://my/legal/doc";

        vm.startPrank(alice);

        bytes32 agreementId0 = registry.createSimpleContract(
            uint256(keccak256("test_createSimpleContractDifferentSalts.0")),
            legalDocUri,
            parties,
            block.timestamp + 10
        );
        (bytes32 templateId0,,,,,,,,, ) = registry.getContractDetails(agreementId0);

        bytes32 agreementId1 = registry.createSimpleContract(
            uint256(keccak256("test_createSimpleContractDifferentSalts.1")),
            legalDocUri,
            parties,
            block.timestamp + 10
        );
        (bytes32 templateId1,,,,,,,,, ) = registry.getContractDetails(agreementId1);

        assertNotEq(agreementId0, agreementId1, "two agreements should have different IDs");
        assertEq(templateId0, templateId1, "two agreements should share the same template");
    }

    /// @notice Parties should be able to sign a simple contract
    function test_signSimpleContract() public {
        uint256 salt = uint256(keccak256("test_signSimpleContract"));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string memory legalDocUri = "ipfs://my/legal/doc";

        vm.startPrank(alice);

        bytes32 agreementId = registry.createSimpleContract(
            salt,
            legalDocUri,
            parties,
            block.timestamp + 10
        );
        {
            (string memory templateUri, ) = registry.templates(keccak256(bytes(legalDocUri)));
            assertEq(templateUri, legalDocUri, "burner template should have been created");
        }

        registry.signSimpleContract(
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                legalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
                alicePrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");

        vm.stopPrank();

        vm.startPrank(bob);

        registry.signSimpleContract(
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                legalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
                bobPrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, bob), "bob should have signed now");

        vm.stopPrank();

        assertTrue(registry.isFinalized(agreementId), "agreement should be finalized by now");
    }

    /// @notice Third-parties should be able to forward our signatures for a simple contract
    function test_signSimpleContractFor() public {
        uint256 salt = uint256(keccak256("test_signSimpleContractFor"));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string memory legalDocUri = "ipfs://my/legal/doc";

        vm.startPrank(alice);
        bytes32 agreementId = registry.createSimpleContract(
            salt,
            legalDocUri,
            parties,
            block.timestamp + 10
        );
        vm.stopPrank();

        vm.startPrank(deployer);

        // third-party to submit alice's signature for her
        registry.signSimpleContractFor(
            alice,
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                legalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
                alicePrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, alice), "alice should have signed now");

        // third-party to submit bob's signature for him
        registry.signSimpleContractFor(
            bob,
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                legalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
                bobPrivateKey
            )
        );
        assertTrue(registry.hasSigned(agreementId, bob), "bob should have signed now");

        vm.stopPrank();

        assertTrue(registry.isFinalized(agreementId), "agreement should be finalized by now");
    }

    function test_voidContractForSelf() public {
        uint256 salt = uint256(keccak256("test_voidContractForSelf"));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global value 0";

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Alice";
        partyValues[0][1] = "Test title";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Bob";
        partyValues[1][1] = "Test title 2";

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "",
            address(0),
            block.timestamp + 10
        );

        vm.startPrank(alice);
        registry.signContract(
            agreementId,
            partyValues[0],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalDocUri,
                testGlobalFields,
                testPartyFields,
                globalValues,
                partyValues[0],
                alicePrivateKey
            ),
            false,
            ""
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

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global value 0";

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Alice";
        partyValues[0][1] = "Test title";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Bob";
        partyValues[1][1] = "Test title 2";

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "",
            address(0),
            block.timestamp + 10
        );

        vm.startPrank(alice);
        registry.signContract(
            agreementId,
            partyValues[0],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalDocUri,
                testGlobalFields,
                testPartyFields,
                globalValues,
                partyValues[0],
                alicePrivateKey
            ),
            false,
            ""
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

    function test_voidSimpleContractForSelf() public {
        uint256 salt = uint256(keccak256("test_voidSimpleContractForSelf"));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        vm.prank(alice);
        bytes32 agreementId = registry.createSimpleContract(
            salt,
            testLegalDocUri,
            parties,
            block.timestamp + 10
        );

        vm.startPrank(alice);
        registry.signSimpleContract(
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
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

    function test_voidSimpleContractForOthers() public {
        uint256 salt = uint256(keccak256("test_voidSimpleContractForOthers"));

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        vm.prank(alice);
        bytes32 agreementId = registry.createSimpleContract(
            salt,
            testLegalDocUri,
            parties,
            block.timestamp + 10
        );

        vm.startPrank(alice);
        registry.signSimpleContract(
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalDocUri,
                new string[](0),
                new string[](0),
                new string[](0),
                new string[](0),
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
}
