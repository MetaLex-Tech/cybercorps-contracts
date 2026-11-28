// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import "../src/interfaces/ICyberAgreementRegistry.sol";
import {ISignerConditions, SignerCondition} from "../src/interfaces/ISignerConditions.sol";

contract CyberAgreementRegistryBoundTest is Test {
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;
    address chad;

    CyberAgreementRegistry registry;
    ICyberAgreementRegistry.Template template;
    string[] globalValues;
    address[] parties;
    string[][] partyValues;
    uint256 expiry;

    function setUp() public {
        vm.warp(1_700_000_000);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        chad = makeAddr("chad");
        address deployer = makeAddr("deployer");

        vm.startPrank(deployer);
        BorgAuth auth = new BorgAuth(deployer);
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        vm.stopPrank();

        template.title = "Test agreement";
        template.legalContractUri = "ipfs://template";
        template.globalFields.push("Global Field");
        template.partyFields.push("Name");
        template.partyFields.push("Contact");

        globalValues.push("global value 0");
        parties.push(alice);
        parties.push(bob);
        partyValues.push(["Alice", "alice@example.com"]);
        partyValues.push(["Bob", "bob@example.com"]);
        expiry = block.timestamp + 1 days;
    }

    function _ids(address creator, uint256 salt) internal view returns (bytes32 templateId, bytes32 contractId) {
        templateId = keccak256(
            abi.encode(
                registry.BOUND_TEMPLATE_DOMAIN(),
                creator,
                salt,
                template.title,
                template.legalContractUri,
                template.globalFields,
                template.partyFields
            )
        );
        contractId = keccak256(
            abi.encode(
                registry.BOUND_AGREEMENT_DOMAIN(),
                keccak256(
                    abi.encode(
                        creator, templateId, salt, globalValues, parties, keccak256(abi.encode(partyValues)), expiry
                    )
                )
            )
        );
    }

    function _sign(bytes32 contractId, uint256 index, uint256 privateKey) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            globalValues,
            partyValues[index],
            privateKey
        );
    }

    function _signValues(bytes32 contractId, address signer, string[] memory values, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            globalValues,
            values,
            signer,
            privateKey
        );
    }

    function test_createBoundContract() public {
        (bytes32 expectedTemplateId, bytes32 expectedId) = _ids(alice, 1);

        vm.expectEmit(address(registry));
        emit ICyberAgreementRegistry.TemplateCreated(
            expectedTemplateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );
        vm.expectEmit(address(registry));
        emit ICyberAgreementRegistry.ContractCreated(expectedId, expectedTemplateId, parties);
        vm.prank(alice);
        (bytes32 templateId, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        assertEq(templateId, expectedTemplateId);
        assertEq(contractId, expectedId);

        (, string memory uri,,,, address[] memory storedParties, string[][] memory storedValues,, uint256 numSignatures,) =
            registry.getContractDetails(contractId);
        assertEq(uri, template.legalContractUri);
        assertEq(storedParties[1], bob);
        assertEq(storedValues[1][1], "bob@example.com");
        assertEq(numSignatures, 0);

        bytes memory aliceSignature = _sign(contractId, 0, alicePrivateKey);
        bytes memory bobSignature = _sign(contractId, 1, bobPrivateKey);
        vm.prank(alice);
        registry.signContract(contractId, partyValues[0], aliceSignature, false, "");
        vm.prank(bob);
        registry.signContract(contractId, partyValues[1], bobSignature, false, "");
        assertTrue(registry.isFinalized(contractId));
    }

    function test_createBoundContract_idDependsOnSender() public {
        vm.prank(chad);
        (, bytes32 chadId) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        vm.prank(alice);
        (, bytes32 aliceId) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        assertNotEq(chadId, aliceId);
    }

    function test_createBoundContract_idDependsOnExpiryAndPartyValues() public {
        vm.startPrank(alice);
        (, bytes32 id) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        (, bytes32 otherExpiry) =
            registry.createBoundContract(template, 2, globalValues, parties, partyValues, expiry + 1);
        partyValues[1][1] = "other@example.com";
        (, bytes32 otherValues) = registry.createBoundContract(template, 3, globalValues, parties, partyValues, expiry);
        vm.stopPrank();

        (, bytes32 expectedOtherValues) = _ids(alice, 3);
        assertEq(otherValues, expectedOtherValues);
        expiry += 1;
        partyValues[1][1] = "bob@example.com";
        (, bytes32 expectedOtherExpiry) = _ids(alice, 2);
        assertEq(otherExpiry, expectedOtherExpiry);
        assertNotEq(id, otherExpiry);
        assertNotEq(id, otherValues);
    }

    function test_createBoundContractAndSignFor() public {
        (, bytes32 expectedId) = _ids(alice, 1);
        bytes memory aliceSignature = _sign(expectedId, 0, alicePrivateKey);

        vm.prank(chad);
        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, aliceSignature
        );
        assertEq(contractId, expectedId);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_createBoundContractAndSignFor_notFirstParty() public {
        (, bytes32 expectedId) = _ids(alice, 1);
        bytes memory bobSignature = _sign(expectedId, 0, bobPrivateKey);

        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        registry.createBoundContractAndSignFor(template, 1, globalValues, parties, partyValues, expiry, bobSignature);
    }

    function test_RevertIf_createBoundContract_templateExists() public {
        (bytes32 templateId,) = _ids(alice, 1);
        vm.prank(chad);
        registry.createTemplate(templateId, "Other", "ipfs://other", template.globalFields, template.partyFields);

        vm.startPrank(alice);
        vm.expectRevert(CyberAgreementRegistry.TemplateAlreadyExists.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        registry.createBoundContract(template, 2, globalValues, parties, partyValues, expiry);
        vm.stopPrank();
    }

    function test_RevertIf_createBoundContract_invalidInput() public {
        vm.startPrank(alice);

        vm.expectRevert(CyberAgreementRegistry.ExpiryNotInFuture.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, block.timestamp);

        parties[1] = alice;
        vm.expectRevert(CyberAgreementRegistry.DuplicateParty.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        parties[0] = address(0);
        parties[1] = bob;
        vm.expectRevert(CyberAgreementRegistry.FirstPartyZeroAddress.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        // An open slot gets its values from the signer who fills it.
        parties[0] = alice;
        parties[1] = address(0);
        vm.expectRevert(CyberAgreementRegistry.MismatchedFieldsLength.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        parties[1] = bob;
        partyValues.pop();
        vm.expectRevert(CyberAgreementRegistry.MismatchedPartyValuesLength.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        vm.stopPrank();
    }

    /// @notice A signer fills each open slot of a bound agreement with its own values.
    function test_createBoundContract_openSlots() public {
        (address dave, uint256 davePrivateKey) = makeAddrAndKey("dave");
        (address erin, uint256 erinPrivateKey) = makeAddrAndKey("erin");
        parties[1] = address(0);
        parties.push(address(0));
        partyValues[1] = new string[](0);
        partyValues.push(new string[](0));
        (, bytes32 expectedId) = _ids(alice, 1);

        vm.prank(alice);
        (, bytes32 contractId) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        assertEq(contractId, expectedId);
        assertEq(registry.getAgreementsForParty(address(0)).length, 0);

        string[] memory daveValues = new string[](2);
        daveValues[0] = "Dave";
        daveValues[1] = "dave@example.com";
        string[] memory erinValues = new string[](2);
        erinValues[0] = "Erin";
        erinValues[1] = "erin@example.com";
        bytes memory daveSignature = _signValues(contractId, dave, daveValues, davePrivateKey);
        bytes memory erinSignature = _signValues(contractId, erin, erinValues, erinPrivateKey);
        bytes memory aliceSignature = _sign(contractId, 0, alicePrivateKey);

        vm.prank(dave);
        registry.signContractFor(dave, contractId, daveValues, daveSignature, true, "");
        vm.prank(erin);
        registry.signContractFor(erin, contractId, erinValues, erinSignature, true, "");
        vm.prank(alice);
        registry.signContract(contractId, partyValues[0], aliceSignature, false, "");

        (,,,,, address[] memory storedParties, string[][] memory storedValues,,,) =
            registry.getContractDetails(contractId);
        assertEq(storedParties[1], dave);
        assertEq(storedParties[2], erin);
        assertEq(storedValues[2][0], "Erin");
        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_createBoundContract_openSlotHasConditions() public {
        parties[1] = address(0);
        partyValues[1] = new string[](0);
        SignerCondition[][] memory conditions = new SignerCondition[][](2);
        conditions[1] = new SignerCondition[](1);

        vm.prank(alice);
        vm.expectRevert(ISignerConditions.OpenSlotHasSignerConditions.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);
    }

    /// @notice MTLX1-39: a front-run with a later expiry gives another id, so the creator's
    /// signature does not count on it and the creator's own creation still succeeds.
    function test_createBoundContractAndSignFor_frontRunWithLaterExpiryGetsOtherId() public {
        parties[1] = address(0);
        partyValues[1] = new string[](0);
        (, bytes32 aliceId) = _ids(alice, 1);
        bytes memory aliceSignature = _sign(aliceId, 0, alicePrivateKey);

        vm.prank(chad);
        (, bytes32 chadId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry + 30 days);
        assertNotEq(chadId, aliceId);

        vm.prank(chad);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        registry.signContractFor(alice, chadId, partyValues[0], aliceSignature, false, "");

        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, aliceSignature
        );
        assertEq(contractId, aliceId);
        assertTrue(registry.hasSigned(aliceId, alice));
    }

    function test_getContractJson() public {
        bytes32 templateId = keccak256("json-template");
        partyValues[1][0] = "Bob \"B\"";
        vm.startPrank(alice);
        registry.createTemplate(
            templateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );
        vm.stopPrank();
        // A legacy agreement with no finalizer. Only the zero address can create one now.
        vm.prank(address(0));
        bytes32 contractId =
            registry.createContract(templateId, 1, globalValues, parties, partyValues, bytes32(0), address(0), expiry);
        bytes memory aliceSignature = _sign(contractId, 0, alicePrivateKey);
        vm.prank(alice);
        registry.signContract(contractId, partyValues[0], aliceSignature, false, "");

        assertEq(registry.getContractJson(contractId), EXPECTED_JSON);
    }

    function test_boundIdsOf_noConditions_sameAsExistingFormula() public {
        (bytes32 expectedTemplateId, bytes32 expectedId) = _ids(alice, 1);
        (bytes32 templateId, bytes32 contractId) = registry.boundIdsOf(
            alice, template, 1, globalValues, parties, partyValues, expiry, new SignerCondition[][](0)
        );
        assertEq(templateId, expectedTemplateId);
        assertEq(contractId, expectedId);

        vm.prank(alice);
        (, bytes32 createdId) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        assertEq(createdId, expectedId);
    }

    function test_createBoundContract_emptyConditions_sameAsNoConditions() public {
        (, bytes32 plainId) = _ids(alice, 1);
        vm.prank(alice);
        (, bytes32 contractId) = registry.createBoundContract(
            template, 1, globalValues, parties, partyValues, expiry, new SignerCondition[][](0)
        );
        assertEq(contractId, plainId);
    }

    string constant EXPECTED_JSON =
        '{"templateId": "0x3b9c898fa0d07424fa7c6857fd02533b65dee60307f6b38807497574c159add5", "title": "Test agreement", "legalContractUri": "ipfs://template", "ContractFields": {"Global Field": "global value 0"}, "parties": {"0x328809bc894f92807417d2dad6b7c998c1afdac6": {"Name": "Alice","Contact": "alice@example.com","signedAt": 1700000000},"0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e": {"Name": "Bob \\"B\\"","Contact": "bob@example.com","signedAt": 0}}, "numSignatures": 1, "isComplete": false, "voided": false, "voidRequestedBy": [], "finalized": false}';
}
