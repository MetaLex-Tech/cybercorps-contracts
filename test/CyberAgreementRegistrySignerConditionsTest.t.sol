// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import "../src/interfaces/ICyberAgreementRegistry.sol";
import {ISignerConditions, SignerCondition} from "../src/interfaces/ISignerConditions.sol";
import "../src/interfaces/IZKPassportVerifier.sol";
import {
    ZKPassportCondition,
    ZKPassportConditionLib,
    ZKPassportConfig,
    ZKPassportEvidence,
    ZKPassportResult
} from "../src/libs/ZKPassportConditionLib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {MockPassportHelper, MockPassportVerifier} from "./ZKPassportFinalizerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @dev Same behavior as the canonical Multicall3 `aggregate3`. A relayer sends one transaction
/// that makes each call in order. A failed call with `allowFailure = false` reverts the whole batch.
contract Multicall3Aggregate3 {
    function aggregate3(IMulticall3.Call3[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory returnData)
    {
        returnData = new IMulticall3.Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory data) = calls[i].target.call(calls[i].callData);
            if (!success && !calls[i].allowFailure) revert("Multicall3: call failed");
            returnData[i] = IMulticall3.Result(success, data);
        }
    }
}

contract CyberAgreementRegistrySignerConditionsTest is Test {
    string constant DOMAIN = "app.metalex.tech";
    string constant SCOPE = "cyberagreement-passport";
    bytes32 constant ZKPASSPORT = keccak256("MetaLeX.SignerCondition.ZKPassport.v1");

    bytes32 constant PASSPORT_A = keccak256("passport-a");
    bytes32 constant PASSPORT_C = keccak256("passport-c");
    bytes32 constant PASSPORT_X = keccak256("passport-x");

    address deployer = makeAddr("deployer");
    address relayer = makeAddr("relayer");
    address alice;
    uint256 aliceKey;
    address bob;
    uint256 bobKey;
    address chad;
    uint256 chadKey;

    BorgAuth auth;
    CyberAgreementRegistry registry;
    MockPassportVerifier verifier;

    ICyberAgreementRegistry.Template template;
    string[] globalValues;
    address[] parties;
    string[][] partyValues;
    uint256 expiry;

    function setUp() public {
        vm.warp(1_700_000_000);
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (chad, chadKey) = makeAddrAndKey("chad");

        vm.startPrank(deployer);
        auth = new BorgAuth(deployer);
        registry = _deployRegistry();
        verifier = new MockPassportVerifier(new MockPassportHelper());
        registry.setSignerConditionConfig(ZKPASSPORT, _config(address(verifier), false));
        vm.stopPrank();

        template.title = "Passport Agreement";
        template.legalContractUri = "ipfs://passport-agreement";
        template.globalFields.push("Effective Date");
        template.partyFields.push("Name");
        globalValues.push("2026-10-27");
        parties.push(alice);
        parties.push(bob);
        parties.push(chad);
        partyValues.push(_one("Alice"));
        partyValues.push(_one("Bob"));
        partyValues.push(_one("Chad"));
        expiry = block.timestamp + 1 days;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _deployRegistry() internal returns (CyberAgreementRegistry) {
        return CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
    }

    function _config(address _verifier, bool _devMode) internal pure returns (bytes memory) {
        return abi.encode(ZKPassportConfig({verifier: _verifier, domain: DOMAIN, scope: SCOPE, devMode: _devMode}));
    }

    function _one(string memory value) internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = value;
    }

    function _zkp(bytes32 uniqueIdentifier) internal pure returns (SignerCondition memory) {
        return SignerCondition({kind: ZKPASSPORT, params: abi.encode(ZKPassportCondition(uniqueIdentifier))});
    }

    function _list(SignerCondition memory condition) internal pure returns (SignerCondition[] memory list) {
        list = new SignerCondition[](1);
        list[0] = condition;
    }

    /// @dev Alice needs any passport, Bob has no condition, Chad needs PASSPORT_C.
    function _conditions() internal pure returns (SignerCondition[][] memory conditions) {
        conditions = new SignerCondition[][](3);
        conditions[0] = _list(_zkp(bytes32(0)));
        conditions[2] = _list(_zkp(PASSPORT_C));
    }

    function _id(SignerCondition[][] memory conditions) internal view returns (bytes32 contractId) {
        (, contractId) = registry.boundIdsOf(alice, template, 1, globalValues, parties, partyValues, expiry, conditions);
    }

    function _create(SignerCondition[][] memory conditions) internal returns (bytes32 contractId) {
        vm.prank(alice);
        (, contractId) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, expiry, conditions);
    }

    function _create() internal returns (bytes32) {
        return _create(_conditions());
    }

    function _proof(
        bytes32 uniqueIdentifier,
        address sender,
        uint256 chainId,
        string memory customData,
        string memory domain,
        bool devMode
    ) internal pure returns (ProofVerificationParams memory params) {
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = keccak256(bytes(domain));
        publicInputs[1] = keccak256(bytes(SCOPE));
        params.proofVerificationData = ProofVerificationData({
            vkeyHash: bytes32(0), proof: abi.encode(uniqueIdentifier), publicInputs: publicInputs
        });
        params.committedInputs =
            abi.encode(BoundData({senderAddress: sender, chainId: chainId, customData: customData}));
        params.serviceConfig =
            ServiceConfig({validityPeriodInSeconds: 1 days, domain: domain, scope: SCOPE, devMode: devMode});
    }

    function _evidence(ProofVerificationParams memory proof) internal pure returns (bytes[] memory evidence) {
        evidence = new bytes[](1);
        evidence[0] = abi.encode(ZKPassportEvidence(proof));
    }

    /// @dev A valid proof of `uniqueIdentifier` for `sender` and `contractId`.
    function _evidence(bytes32 contractId, bytes32 uniqueIdentifier, address sender)
        internal
        view
        returns (bytes[] memory)
    {
        return _evidence(
            _proof(uniqueIdentifier, sender, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, false)
        );
    }

    function _signWithEvidence(bytes32 contractId, uint256 index, uint256 key, bytes[] memory evidence)
        internal
        view
        returns (bytes memory)
    {
        return CyberAgreementUtils.signAgreementWithEvidenceTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREWITHEVIDENCEDATA_TYPEHASH(),
            contractId,
            parties[index],
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            globalValues,
            partyValues[index],
            evidence,
            key
        );
    }

    function _signLegacy(bytes32 contractId, uint256 index, uint256 key) internal view returns (bytes memory) {
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
            key
        );
    }

    /// @dev The relayer sends the party's evidence and signature.
    function _relayWithEvidence(bytes32 contractId, uint256 index, uint256 key, bytes32 uniqueIdentifier) internal {
        bytes[] memory evidence = _evidence(contractId, uniqueIdentifier, parties[index]);
        bytes memory signature = _signWithEvidence(contractId, index, key, evidence);
        vm.prank(relayer);
        registry.signContractWithEvidenceFor(parties[index], contractId, partyValues[index], evidence, signature);
    }

    function _relayLegacy(bytes32 contractId, uint256 index, uint256 key) internal {
        bytes memory signature = _signLegacy(contractId, index, key);
        vm.prank(relayer);
        registry.signContractFor(parties[index], contractId, partyValues[index], signature, false, "");
    }

    function _void(bytes32 contractId, uint256 index, uint256 key) internal {
        bytes memory signature = CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), contractId, parties[index], key
        );
        vm.prank(relayer);
        registry.voidContractFor(contractId, parties[index], signature);
    }

    function _expectRevertOnRelay(
        bytes32 contractId,
        uint256 index,
        uint256 key,
        bytes[] memory evidence,
        bytes memory err
    ) internal {
        bytes memory signature = _signWithEvidence(contractId, index, key, evidence);
        vm.prank(relayer);
        vm.expectRevert(err);
        registry.signContractWithEvidenceFor(parties[index], contractId, partyValues[index], evidence, signature);
    }

    // ── Config ───────────────────────────────────────────────────────────────

    function test_TypeHash_MatchesTypeString() public view {
        assertEq(
            registry.SIGNATUREWITHEVIDENCEDATA_TYPEHASH(),
            keccak256(
                "SignatureWithEvidenceData(bytes32 contractId,address signer,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues,bytes[] evidence)"
            )
        );
    }

    function test_SetConfig_OnlyAdmin() public {
        bytes memory config = _config(makeAddr("newVerifier"), true);

        vm.prank(relayer);
        vm.expectRevert();
        registry.setSignerConditionConfig(ZKPASSPORT, config);

        vm.expectEmit(address(registry));
        emit ISignerConditions.SignerConditionConfigSet(ZKPASSPORT, config);
        vm.prank(deployer);
        registry.setSignerConditionConfig(ZKPASSPORT, config);
        assertEq(registry.getSignerConditionConfig(ZKPASSPORT), config);
    }

    function test_RevertIf_SetConfig_UnknownKind() public {
        bytes32 kind = keccak256("unknown");
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(ISignerConditions.UnknownSignerConditionKind.selector, kind));
        registry.setSignerConditionConfig(kind, _config(address(verifier), false));
    }

    function test_RevertIf_SetConfig_ZeroVerifier() public {
        vm.prank(deployer);
        vm.expectRevert(ZKPassportConditionLib.InvalidVerifier.selector);
        registry.setSignerConditionConfig(ZKPASSPORT, _config(address(0), false));
    }

    // ── Create ───────────────────────────────────────────────────────────────

    function test_Create_EmitsConditionsAndUsesConditionedId() public {
        bytes32 expectedId = _id(_conditions());
        (, bytes32 plainId) = registry.boundIdsOf(
            alice, template, 1, globalValues, parties, partyValues, expiry, new SignerCondition[][](0)
        );
        assertNotEq(expectedId, plainId);

        vm.expectEmit(address(registry));
        emit ISignerConditions.SignerConditionSet(expectedId, alice, 0, ZKPASSPORT, _zkp(bytes32(0)).params);
        vm.expectEmit(address(registry));
        emit ISignerConditions.SignerConditionSet(expectedId, chad, 0, ZKPASSPORT, _zkp(PASSPORT_C).params);
        vm.recordLogs();
        bytes32 contractId = _create();
        assertEq(contractId, expectedId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 conditionEvents;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == ISignerConditions.SignerConditionSet.selector) conditionEvents++;
        }
        assertEq(conditionEvents, 2);
    }

    function test_Create_IdDependsOnConditions() public view {
        bytes32 id = _id(_conditions());

        SignerCondition[][] memory otherPin = _conditions();
        otherPin[2] = _list(_zkp(PASSPORT_X));
        SignerCondition[][] memory bobGated = _conditions();
        bobGated[1] = _list(_zkp(bytes32(0)));

        assertNotEq(id, _id(otherPin));
        assertNotEq(id, _id(bobGated));
    }

    function test_Create_SameKindTwiceForOneParty() public {
        SignerCondition[][] memory conditions = _conditions();
        conditions[0] = new SignerCondition[](2);
        conditions[0][0] = _zkp(bytes32(0));
        conditions[0][1] = _zkp(PASSPORT_A);
        bytes32 contractId = _create(conditions);

        bytes[] memory evidence = new bytes[](2);
        evidence[0] = _evidence(contractId, PASSPORT_A, alice)[0];
        evidence[1] = evidence[0];
        bytes memory signature = _signWithEvidence(contractId, 0, aliceKey, evidence);
        vm.prank(relayer);
        registry.signContractWithEvidenceFor(alice, contractId, partyValues[0], evidence, signature);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_Create_ConditionsLengthMismatch() public {
        SignerCondition[][] memory conditions = new SignerCondition[][](2);
        vm.expectRevert(ISignerConditions.SignerConditionsLengthMismatch.selector);
        _create(conditions);
    }

    function test_RevertIf_Create_UnknownKind() public {
        SignerCondition[][] memory conditions = _conditions();
        conditions[1] = _list(SignerCondition({kind: bytes32(0), params: ""}));
        vm.expectRevert(abi.encodeWithSelector(ISignerConditions.UnknownSignerConditionKind.selector, bytes32(0)));
        _create(conditions);
    }

    function test_RevertIf_Create_InvalidZKPassportParams() public {
        SignerCondition[][] memory conditions = _conditions();
        conditions[0][0].params = "";
        vm.expectRevert(ZKPassportConditionLib.InvalidZKPassportConditionParams.selector);
        _create(conditions);

        conditions[0][0].params = abi.encode(PASSPORT_A, PASSPORT_C);
        vm.expectRevert(ZKPassportConditionLib.InvalidZKPassportConditionParams.selector);
        _create(conditions);
    }

    function test_RevertIf_Create_ZKPassportNotConfigured() public {
        vm.prank(deployer);
        registry = _deployRegistry();
        vm.expectRevert(ZKPassportConditionLib.ZKPassportNotConfigured.selector);
        _create();
    }

    // ── Sign ─────────────────────────────────────────────────────────────────

    function test_Lifecycle_AllPartiesSign_LastOneFinalizes() public {
        bytes32 contractId = _create();

        vm.expectEmit(address(registry));
        emit ISignerConditions.SignerConditionMet(
            contractId, alice, 0, ZKPASSPORT, abi.encode(ZKPassportResult(PASSPORT_A))
        );
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);
        _relayLegacy(contractId, 1, bobKey);
        assertFalse(registry.isFinalized(contractId));
        _relayWithEvidence(contractId, 2, chadKey, PASSPORT_C);

        assertTrue(registry.isFinalized(contractId));
        assertTrue(registry.allPartiesSigned(contractId));
    }

    function test_CreateAndSign_CreatorWithEvidence() public {
        bytes32 expectedId = _id(_conditions());
        bytes[] memory evidence = _evidence(expectedId, PASSPORT_A, alice);
        bytes memory signature = _signWithEvidence(expectedId, 0, aliceKey, evidence);

        vm.prank(relayer);
        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, _conditions(), evidence, signature
        );
        assertEq(contractId, expectedId);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_CreateAndSign_CreatorWithoutConditions_SignsWithoutEvidence() public {
        SignerCondition[][] memory conditions = _conditions();
        conditions[0] = new SignerCondition[](0);
        bytes32 expectedId = _id(conditions);
        bytes memory signature = _signLegacy(expectedId, 0, aliceKey);

        vm.prank(relayer);
        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, conditions, new bytes[](0), signature
        );
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_CreateAndSign_CreatorWithConditionsWithoutEvidence() public {
        bytes32 expectedId = _id(_conditions());
        bytes memory signature = _signLegacy(expectedId, 0, aliceKey);

        vm.prank(relayer);
        vm.expectRevert(ISignerConditions.EvidenceRequired.selector);
        registry.createBoundContractAndSignFor(
            template, 1, globalValues, parties, partyValues, expiry, _conditions(), new bytes[](0), signature
        );
    }

    function test_RevertIf_SignContractFor_PartyHasConditions() public {
        bytes32 contractId = _create();
        bytes memory signature = _signLegacy(contractId, 0, aliceKey);

        vm.prank(alice);
        vm.expectRevert(ISignerConditions.EvidenceRequired.selector);
        registry.signContract(contractId, partyValues[0], signature, false, "");

        vm.prank(relayer);
        vm.expectRevert(ISignerConditions.EvidenceRequired.selector);
        registry.signContractFor(alice, contractId, partyValues[0], signature, false, "");
    }

    function test_RevertIf_SignWithEvidence_PartyWithoutConditions() public {
        bytes32 contractId = _create();
        _expectRevertOnRelay(
            contractId,
            1,
            bobKey,
            _evidence(contractId, PASSPORT_X, bob),
            abi.encodeWithSelector(ISignerConditions.NoSignerConditions.selector)
        );
    }

    function test_RevertIf_SignWithEvidence_LegacyAgreement() public {
        bytes32 templateId = keccak256("legacy-template");
        vm.startPrank(alice);
        registry.createTemplate(
            templateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );
        bytes32 contractId =
            registry.createContract(templateId, 1, globalValues, parties, partyValues, bytes32(0), address(0), expiry);
        vm.stopPrank();

        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(ISignerConditions.NoSignerConditions.selector)
        );

        _relayLegacy(contractId, 0, aliceKey);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_SignWithEvidence_EvidenceLengthMismatch() public {
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(contractId, PASSPORT_A, alice);

        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            new bytes[](0),
            abi.encodeWithSelector(ISignerConditions.EvidenceLengthMismatch.selector)
        );

        bytes[] memory twoItems = new bytes[](2);
        twoItems[0] = evidence[0];
        twoItems[1] = evidence[0];
        _expectRevertOnRelay(
            contractId, 0, aliceKey, twoItems, abi.encodeWithSelector(ISignerConditions.EvidenceLengthMismatch.selector)
        );
    }

    function test_RevertIf_SignatureDoesNotCoverSubmittedEvidence() public {
        bytes32 contractId = _create();
        bytes[] memory signedEvidence = _evidence(contractId, PASSPORT_A, alice);
        bytes[] memory otherEvidence = _evidence(contractId, PASSPORT_X, alice);
        bytes memory signature = _signWithEvidence(contractId, 0, aliceKey, signedEvidence);

        vm.prank(relayer);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        registry.signContractWithEvidenceFor(alice, contractId, partyValues[0], otherEvidence, signature);
    }

    function test_RevertIf_LegacySignatureOnEvidencePath() public {
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(contractId, PASSPORT_A, alice);
        bytes memory signature = _signLegacy(contractId, 0, aliceKey);

        vm.prank(relayer);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        registry.signContractWithEvidenceFor(alice, contractId, partyValues[0], evidence, signature);
    }

    function test_SignWithEvidence_ByDelegate() public {
        (address delegate, uint256 delegateKey) = makeAddrAndKey("delegate");
        vm.prank(alice);
        registry.setDelegation(delegate, 0);
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(contractId, PASSPORT_A, alice);
        bytes memory signature = _signWithEvidence(contractId, 0, delegateKey, evidence);

        vm.prank(relayer);
        registry.signContractWithEvidenceFor(alice, contractId, partyValues[0], evidence, signature);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_SignWithEvidence_PartyValuesMismatch() public {
        bytes32 contractId = _create();
        partyValues[0] = _one("Mallory");
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(CyberAgreementRegistry.ClosedAgreementPartyValueMismatch.selector)
        );
    }

    function test_RevertIf_SignWithEvidence_AlreadySigned() public {
        bytes32 contractId = _create();
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(CyberAgreementRegistry.AlreadySigned.selector)
        );
    }

    function test_RevertIf_SignWithEvidence_ContractDoesNotExist() public {
        bytes32 contractId = _id(_conditions());
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(CyberAgreementRegistry.ContractDoesNotExist.selector)
        );
    }

    // ── ZKPassport checks ────────────────────────────────────────────────────

    function test_RevertIf_Proof_ForAnotherAgreement() public {
        bytes32 contractId = _create();
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(keccak256("other"), PASSPORT_A, alice),
            abi.encodeWithSelector(ZKPassportConditionLib.InvalidBoundContractId.selector)
        );
    }

    function test_RevertIf_Proof_WrongChain() public {
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(
            _proof(PASSPORT_A, alice, block.chainid + 1, Strings.toHexString(uint256(contractId), 32), DOMAIN, false)
        );
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            evidence,
            abi.encodeWithSelector(ZKPassportConditionLib.InvalidBoundChainId.selector)
        );
    }

    function test_RevertIf_Proof_WrongScope() public {
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(
            _proof(
                PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), "other.domain", false
            )
        );
        _expectRevertOnRelay(
            contractId, 0, aliceKey, evidence, abi.encodeWithSelector(ZKPassportConditionLib.InvalidScope.selector)
        );
    }

    function test_RevertIf_Proof_DevMode() public {
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true)
        );
        _expectRevertOnRelay(
            contractId, 0, aliceKey, evidence, abi.encodeWithSelector(ZKPassportConditionLib.DevModeProof.selector)
        );
    }

    function test_Proof_DevModeConfigAcceptsDevModeProof() public {
        vm.prank(deployer);
        registry.setSignerConditionConfig(ZKPASSPORT, _config(address(verifier), true));
        bytes32 contractId = _create();
        bytes[] memory evidence = _evidence(
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true)
        );
        bytes memory signature = _signWithEvidence(contractId, 0, aliceKey, evidence);

        vm.prank(relayer);
        registry.signContractWithEvidenceFor(alice, contractId, partyValues[0], evidence, signature);
        assertTrue(registry.hasSigned(contractId, alice));
    }

    function test_RevertIf_Proof_NotVerified() public {
        bytes32 contractId = _create();
        verifier.setShouldVerify(false);
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(ZKPassportConditionLib.InvalidProof.selector)
        );
    }

    function test_RevertIf_Proof_ZeroHelper() public {
        bytes32 contractId = _create();
        verifier.setShouldReturnZeroHelper(true);
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(ZKPassportConditionLib.InvalidProof.selector)
        );
    }

    function test_RevertIf_Proof_BoundToAnotherWallet() public {
        bytes32 contractId = _create();
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, chad),
            abi.encodeWithSelector(ZKPassportConditionLib.InvalidBoundSender.selector)
        );
    }

    function test_RevertIf_Proof_PinMismatch() public {
        bytes32 contractId = _create();
        _expectRevertOnRelay(
            contractId,
            2,
            chadKey,
            _evidence(contractId, PASSPORT_X, chad),
            abi.encodeWithSelector(ZKPassportConditionLib.UniqueIdentifierMismatch.selector)
        );
    }

    function test_RevertIf_Proof_PassportUsedByAnotherParty() public {
        SignerCondition[][] memory conditions = _conditions();
        conditions[2] = _list(_zkp(bytes32(0)));
        bytes32 contractId = _create(conditions);
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);

        _expectRevertOnRelay(
            contractId,
            2,
            chadKey,
            _evidence(contractId, PASSPORT_A, chad),
            abi.encodeWithSelector(ZKPassportConditionLib.UniqueIdentifierAlreadyUsed.selector)
        );
    }

    // ── Expiry and void ──────────────────────────────────────────────────────

    function test_RevertIf_SignWithEvidence_AfterExpiry() public {
        bytes32 contractId = _create();
        vm.warp(expiry + 1);
        _expectRevertOnRelay(
            contractId,
            0,
            aliceKey,
            _evidence(contractId, PASSPORT_A, alice),
            abi.encodeWithSelector(CyberAgreementRegistry.ContractExpired.selector)
        );
    }

    function test_Void_AfterExpiry() public {
        bytes32 contractId = _create();
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);
        vm.warp(expiry + 1);

        _void(contractId, 2, chadKey);
        assertTrue(registry.isVoided(contractId));
    }

    function test_Void_ByProposerAfterOwnSignature_ThenSignRefused() public {
        bytes32 contractId = _create();
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);

        _void(contractId, 0, aliceKey);
        assertTrue(registry.isVoided(contractId));

        _expectRevertOnRelay(
            contractId,
            2,
            chadKey,
            _evidence(contractId, PASSPORT_C, chad),
            abi.encodeWithSelector(CyberAgreementRegistry.ContractAlreadyVoided.selector)
        );
    }

    function test_Void_AllPartiesBeforeAnySignature() public {
        bytes32 contractId = _create();
        _void(contractId, 0, aliceKey);
        _void(contractId, 1, bobKey);
        assertFalse(registry.isVoided(contractId));
        _void(contractId, 2, chadKey);
        assertTrue(registry.isVoided(contractId));
    }

    function test_RevertIf_Void_AfterFinalized() public {
        bytes32 contractId = _create();
        _relayWithEvidence(contractId, 0, aliceKey, PASSPORT_A);
        _relayLegacy(contractId, 1, bobKey);
        _relayWithEvidence(contractId, 2, chadKey, PASSPORT_C);

        bytes memory signature = CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), contractId, alice, aliceKey
        );
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyFinalized.selector);
        registry.voidContractFor(contractId, alice, signature);
    }

    // ── Relayer settlement in one transaction ────────────────────────────────

    /// @dev Creation with Alice's evidence and signature, then Bob's and Chad's signatures.
    function _settlementCalls(bytes[] memory chadEvidence) internal view returns (IMulticall3.Call3[] memory calls) {
        bytes32 contractId = _id(_conditions());
        bytes[] memory aliceEvidence = _evidence(contractId, PASSPORT_A, alice);
        calls = new IMulticall3.Call3[](3);
        calls[0] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeWithSignature(
                "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][],bytes[],bytes)",
                template,
                1,
                globalValues,
                parties,
                partyValues,
                expiry,
                _conditions(),
                aliceEvidence,
                _signWithEvidence(contractId, 0, aliceKey, aliceEvidence)
            )
        );
        calls[1] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeCall(
                CyberAgreementRegistry.signContractFor,
                (bob, contractId, partyValues[1], _signLegacy(contractId, 1, bobKey), false, "")
            )
        );
        calls[2] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeCall(
                CyberAgreementRegistry.signContractWithEvidenceFor,
                (
                    chad,
                    contractId,
                    partyValues[2],
                    chadEvidence,
                    _signWithEvidence(contractId, 2, chadKey, chadEvidence)
                )
            )
        );
    }

    function test_RelayerSettlesInOneTransaction() public {
        Multicall3Aggregate3 multicall = new Multicall3Aggregate3();
        bytes32 contractId = _id(_conditions());
        IMulticall3.Call3[] memory calls = _settlementCalls(_evidence(contractId, PASSPORT_C, chad));

        // The parties only sign off-chain. The relayer sends the only transaction.
        vm.expectEmit(address(registry));
        emit ICyberAgreementRegistry.ContractFullySigned(contractId, block.timestamp);
        vm.prank(relayer);
        multicall.aggregate3(calls);

        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_RelayerSettlement_InvalidProof_NothingStays() public {
        Multicall3Aggregate3 multicall = new Multicall3Aggregate3();
        bytes32 contractId = _id(_conditions());
        IMulticall3.Call3[] memory calls = _settlementCalls(_evidence(contractId, PASSPORT_X, chad));

        vm.prank(relayer);
        vm.expectRevert("Multicall3: call failed");
        multicall.aggregate3(calls);

        assertEq(registry.getParties(contractId).length, 0);
    }
}
