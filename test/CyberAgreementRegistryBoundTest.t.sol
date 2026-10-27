// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import "../src/interfaces/ICyberAgreementRegistry.sol";
import {ISignerCondition, SignerCondition} from "../src/interfaces/ISignerCondition.sol";
import {IERC165} from "openzeppelin-contracts/utils/introspection/IERC165.sol";

/// @dev A third-party check that passes for the parties on its list.
contract AllowListSignerCondition is ISignerCondition {
    mapping(address => bool) public allowed;

    function setAllowed(address party, bool _allowed) external {
        allowed[party] = _allowed;
    }

    function checkSigner(address, bytes32, address party, bytes calldata) external view returns (bool) {
        return allowed[party];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISignerCondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

contract CyberAgreementRegistryBoundTest is Test {
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;
    address chad;

    CyberAgreementRegistry registry;
    AllowListSignerCondition allowList;
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
        allowList = new AllowListSignerCondition();
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

        parties[1] = address(0);
        vm.expectRevert(CyberAgreementRegistry.FirstPartyZeroAddress.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        parties[1] = bob;
        partyValues.pop();
        vm.expectRevert(CyberAgreementRegistry.MismatchedPartyValuesLength.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);

        vm.stopPrank();
    }

    function test_getContractJson() public {
        bytes32 templateId = keccak256("json-template");
        partyValues[1][0] = "Bob \"B\"";
        vm.startPrank(alice);
        registry.createTemplate(
            templateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );
        bytes32 contractId =
            registry.createContract(templateId, 1, globalValues, parties, partyValues, bytes32(0), address(0), expiry);
        registry.signContract(contractId, partyValues[0], _sign(contractId, 0, alicePrivateKey), false, "");
        vm.stopPrank();

        assertEq(registry.getContractJson(contractId), EXPECTED_JSON);
    }

    // ── Signer conditions ────────────────────────────────────────────────────

    /// @dev Alice has the allow-list check with `data`, Bob has none.
    function _aliceGated(bytes memory data) internal view returns (SignerCondition[] memory conditions) {
        conditions = new SignerCondition[](2);
        conditions[0] = SignerCondition({condition: allowList, data: data});
    }

    function _bothGated() internal view returns (SignerCondition[] memory conditions) {
        conditions = new SignerCondition[](2);
        conditions[0] = SignerCondition({condition: allowList, data: ""});
        conditions[1] = SignerCondition({condition: allowList, data: ""});
    }

    function _boundIdsOf(address creator, uint256 salt, SignerCondition[] memory conditions)
        internal
        view
        returns (bytes32 templateId, bytes32 contractId)
    {
        return registry.boundIdsOf(creator, template, salt, globalValues, parties, partyValues, expiry, conditions);
    }

    function test_boundIdsOf_noConditions_sameAsExistingFormula() public {
        (bytes32 expectedTemplateId, bytes32 expectedId) = _ids(alice, 1);
        (bytes32 templateId, bytes32 contractId) = _boundIdsOf(alice, 1, new SignerCondition[](0));
        assertEq(templateId, expectedTemplateId);
        assertEq(contractId, expectedId);

        vm.prank(alice);
        (, bytes32 createdId) = registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry);
        assertEq(createdId, expectedId);
    }

    function test_createBoundContract_withConditions() public {
        SignerCondition[] memory conditions = _aliceGated("pin");
        (bytes32 expectedTemplateId, bytes32 expectedId) = _boundIdsOf(alice, 1, conditions);
        (, bytes32 plainId) = _ids(alice, 1);
        assertNotEq(expectedId, plainId);

        vm.expectEmit(address(registry));
        emit ICyberAgreementRegistry.ContractCreated(expectedId, expectedTemplateId, parties);
        vm.expectEmit(address(registry));
        emit CyberAgreementRegistry.SignerConditionSet(expectedId, alice, address(allowList), "pin");
        vm.recordLogs();
        vm.prank(alice);
        (bytes32 templateId, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);
        assertEq(templateId, expectedTemplateId);
        assertEq(contractId, expectedId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 conditionEvents;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == CyberAgreementRegistry.SignerConditionSet.selector) conditionEvents++;
        }
        assertEq(conditionEvents, 1);

        SignerCondition memory aliceCondition = registry.getSignerCondition(contractId, alice);
        assertEq(address(aliceCondition.condition), address(allowList));
        assertEq(aliceCondition.data, "pin");
        SignerCondition memory bobCondition = registry.getSignerCondition(contractId, bob);
        assertEq(address(bobCondition.condition), address(0));
        assertEq(bobCondition.data, "");
    }

    function test_createBoundContract_emptyConditions_sameAsNoConditions() public {
        (, bytes32 plainId) = _ids(alice, 1);
        vm.prank(alice);
        (, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, new SignerCondition[](0));
        assertEq(contractId, plainId);
    }

    function test_boundIdsOf_dependsOnConditions() public {
        AllowListSignerCondition otherCondition = new AllowListSignerCondition();
        (, bytes32 id) = _boundIdsOf(alice, 1, _aliceGated("a"));
        (, bytes32 otherData) = _boundIdsOf(alice, 1, _aliceGated("b"));
        SignerCondition[] memory otherAddress = _aliceGated("a");
        otherAddress[0].condition = otherCondition;
        (, bytes32 otherAddressId) = _boundIdsOf(alice, 1, otherAddress);
        (, bytes32 bothId) = _boundIdsOf(alice, 1, _bothGated());

        assertNotEq(id, otherData);
        assertNotEq(id, otherAddressId);
        assertNotEq(id, bothId);
    }

    function test_RevertIf_createBoundContract_conditionsLengthMismatch() public {
        SignerCondition[] memory conditions = new SignerCondition[](1);
        conditions[0] = SignerCondition({condition: allowList, data: ""});
        vm.expectRevert(CyberAgreementRegistry.SignerConditionsLengthMismatch.selector);
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);
    }

    function test_RevertIf_createBoundContract_invalidCondition() public {
        SignerCondition[] memory conditions = _aliceGated("");

        conditions[0].condition = ISignerCondition(chad);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.InvalidSignerCondition.selector, chad));
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);

        conditions[0].condition = ISignerCondition(address(registry));
        vm.expectRevert(
            abi.encodeWithSelector(CyberAgreementRegistry.InvalidSignerCondition.selector, address(registry))
        );
        registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);
    }

    function test_RevertIf_signContract_conditionNotMet() public {
        vm.prank(alice);
        (, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, _bothGated());
        bytes memory bobSignature = _sign(contractId, 1, bobPrivateKey);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, allowList));
        registry.signContract(contractId, partyValues[1], bobSignature, false, "");

        vm.prank(chad);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, allowList));
        registry.signContractFor(bob, contractId, partyValues[1], bobSignature, false, "");

        assertFalse(registry.hasSigned(contractId, bob));
    }

    function test_signContract_conditionMet_lastOneFinalizes() public {
        vm.prank(alice);
        (, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, _bothGated());
        allowList.setAllowed(alice, true);
        allowList.setAllowed(bob, true);
        bytes memory aliceSignature = _sign(contractId, 0, alicePrivateKey);
        bytes memory bobSignature = _sign(contractId, 1, bobPrivateKey);

        vm.prank(chad);
        registry.signContractFor(alice, contractId, partyValues[0], aliceSignature, false, "");
        assertFalse(registry.isFinalized(contractId));
        vm.prank(bob);
        registry.signContract(contractId, partyValues[1], bobSignature, false, "");
        assertTrue(registry.isFinalized(contractId));
    }

    function test_signContract_partyWithoutCondition_signsWithoutCheck() public {
        vm.prank(alice);
        (, bytes32 contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, _aliceGated(""));
        bytes memory bobSignature = _sign(contractId, 1, bobPrivateKey);

        vm.prank(chad);
        registry.signContractFor(bob, contractId, partyValues[1], bobSignature, false, "");
        assertTrue(registry.hasSigned(contractId, bob));
    }

    function test_createBoundContractAndSignFor_withConditions() public {
        SignerCondition[] memory conditions = _aliceGated("");
        (, bytes32 expectedId) = _boundIdsOf(alice, 1, conditions);
        bytes memory aliceSignature = _sign(expectedId, 0, alicePrivateKey);
        allowList.setAllowed(alice, true);

        vm.prank(chad);
        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, conditions, aliceSignature
        );
        assertEq(contractId, expectedId);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_createBoundContractAndSignFor_creatorConditionNotMet() public {
        SignerCondition[] memory conditions = _aliceGated("");
        (, bytes32 expectedId) = _boundIdsOf(alice, 1, conditions);
        bytes memory aliceSignature = _sign(expectedId, 0, alicePrivateKey);

        vm.prank(chad);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, allowList));
        registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, conditions, aliceSignature
        );
        assertEq(registry.getParties(expectedId).length, 0);
    }

    function test_createContract_hasNoSignerCondition() public {
        bytes32 templateId = keccak256("plain-template");
        vm.startPrank(alice);
        registry.createTemplate(
            templateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );
        bytes32 contractId =
            registry.createContract(templateId, 1, globalValues, parties, partyValues, bytes32(0), address(0), expiry);
        registry.signContract(contractId, partyValues[0], _sign(contractId, 0, alicePrivateKey), false, "");
        vm.stopPrank();

        assertEq(address(registry.getSignerCondition(contractId, alice).condition), address(0));
        assertTrue(registry.hasSigned(contractId, alice));
    }

    string constant EXPECTED_JSON =
        '{"templateId": "0x3b9c898fa0d07424fa7c6857fd02533b65dee60307f6b38807497574c159add5", "title": "Test agreement", "legalContractUri": "ipfs://template", "ContractFields": {"Global Field": "global value 0"}, "parties": {"0x328809bc894f92807417d2dad6b7c998c1afdac6": {"Name": "Alice","Contact": "alice@example.com","signedAt": 1700000000},"0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e": {"Name": "Bob \\"B\\"","Contact": "bob@example.com","signedAt": 0}}, "numSignatures": 1, "isComplete": false, "voided": false, "voidRequestedBy": [], "finalized": false}';
}
