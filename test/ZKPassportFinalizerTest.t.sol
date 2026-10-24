// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ZKPassportFinalizer} from "../src/ZKPassportFinalizer.sol";
import "../src/interfaces/ICyberAgreementRegistry.sol";
import "../src/interfaces/IZKPassportVerifier.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @dev publicInputs[0..1] carry the domain and scope hashes. committedInputs is an abi-encoded BoundData.
contract MockPassportHelper is IZKPassportHelper {
    function verifyScopes(bytes32[] calldata publicInputs, string calldata domain, string calldata scope)
        external
        pure
        returns (bool)
    {
        return publicInputs[0] == keccak256(bytes(domain)) && publicInputs[1] == keccak256(bytes(scope));
    }

    function getBoundData(bytes calldata committedInputs) external pure returns (BoundData memory) {
        return abi.decode(committedInputs, (BoundData));
    }

    function getProofTimestamp(bytes32[] calldata) external pure returns (uint256) {
        return 0;
    }

    function isNationalityOut(string[] memory, bytes calldata) external pure returns (bool) {
        return true;
    }

    function enforceSanctionsRoot(uint256, bool, bytes calldata) external pure {}
}

/// @dev The proof bytes carry the passport id, so each test picks the passport per proof.
contract MockPassportVerifier is IZKPassportVerifier {
    bool public shouldVerify = true;
    bool public shouldReturnZeroHelper;
    IZKPassportHelper public helper;

    constructor(IZKPassportHelper _helper) {
        helper = _helper;
    }

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function setShouldReturnZeroHelper(bool _should) external {
        shouldReturnZeroHelper = _should;
    }

    function verify(ProofVerificationParams calldata params) external view returns (bool, bytes32, IZKPassportHelper) {
        bytes32 passportId = abi.decode(params.proofVerificationData.proof, (bytes32));
        if (!shouldVerify) return (false, bytes32(0), IZKPassportHelper(address(0)));
        if (shouldReturnZeroHelper) return (true, passportId, IZKPassportHelper(address(0)));
        return (true, passportId, helper);
    }
}

contract ZKPassportFinalizerTest is Test {
    string constant DOMAIN = "app.metalex.tech";
    string constant SCOPE = "cyberagreement-passport";
    string constant LEGAL_URI = "https://example.com/agreement";
    bytes32 constant TEMPLATE_ID = keccak256("passport-template");
    string constant STANDALONE_TITLE = "Standalone Passport Agreement";

    bytes32 constant PASSPORT_A = keccak256("passport-a");
    bytes32 constant PASSPORT_B = keccak256("passport-b");
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
    ZKPassportFinalizer finalizer;

    string[] globalFields;
    string[] partyFields;
    string[] globalValues;
    address[] parties;
    string[][] partyValues;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (chad, chadKey) = makeAddrAndKey("chad");

        vm.startPrank(deployer);
        auth = new BorgAuth(deployer);
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        verifier = new MockPassportVerifier(new MockPassportHelper());
        finalizer = ZKPassportFinalizer(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportFinalizer()),
                    abi.encodeWithSelector(
                        ZKPassportFinalizer.initialize.selector,
                        address(auth),
                        address(registry),
                        address(verifier),
                        DOMAIN,
                        SCOPE,
                        false // devMode
                    )
                )
            )
        );

        globalFields.push("Effective Date");
        partyFields.push("Name");
        globalValues.push("2026-10-15");
        registry.createTemplate(TEMPLATE_ID, "Passport Agreement", LEGAL_URI, globalFields, partyFields);
        vm.stopPrank();

        parties.push(alice);
        parties.push(bob);
        parties.push(chad);
        partyValues.push(_one("Alice"));
        partyValues.push(_one("Bob"));
        partyValues.push(_one("Chad"));
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _one(string memory value) internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = value;
    }

    /// @dev Every party needs a proof. `bytes32(0)` means "any passport".
    function _pins(bytes32 a, bytes32 b, bytes32 c)
        internal
        pure
        returns (ZKPassportFinalizer.PartyGate[] memory pins)
    {
        pins = new ZKPassportFinalizer.PartyGate[](3);
        pins[0] = _gate(true, a);
        pins[1] = _gate(true, b);
        pins[2] = _gate(true, c);
    }

    function _gate(bool proofRequired, bytes32 passportId)
        internal
        pure
        returns (ZKPassportFinalizer.PartyGate memory)
    {
        return ZKPassportFinalizer.PartyGate({proofRequired: proofRequired, passportId: passportId});
    }

    /// @dev Alice needs a proof with any passport, Bob needs none, Chad needs PASSPORT_C.
    function _mixedGates() internal pure returns (ZKPassportFinalizer.PartyGate[] memory gates) {
        gates = new ZKPassportFinalizer.PartyGate[](3);
        gates[0] = _gate(true, bytes32(0));
        gates[1] = _gate(false, bytes32(0));
        gates[2] = _gate(true, PASSPORT_C);
    }

    function _signWithoutProof(bytes32 contractId, uint256 index, uint256 key) internal {
        bytes memory signature = _sign(contractId, index, key);
        vm.prank(relayer);
        finalizer.signWithoutProof(contractId, parties[index], partyValues[index], signature);
    }

    function _create(uint256 salt, ZKPassportFinalizer.PartyGate[] memory pins) internal returns (bytes32) {
        return
            finalizer.createContract(
                TEMPLATE_ID, salt, globalValues, parties, partyValues, block.timestamp + 1 days, pins
            );
    }

    function _proof(
        bytes32 passportId,
        address sender,
        uint256 chainId,
        string memory customData,
        string memory domain,
        bool devMode
    ) internal pure returns (ProofVerificationParams memory params) {
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = keccak256(bytes(domain));
        publicInputs[1] = keccak256(bytes(SCOPE));
        params.proofVerificationData =
            ProofVerificationData({vkeyHash: bytes32(0), proof: abi.encode(passportId), publicInputs: publicInputs});
        params.committedInputs =
            abi.encode(BoundData({senderAddress: sender, chainId: chainId, customData: customData}));
        params.serviceConfig =
            ServiceConfig({validityPeriodInSeconds: 1 days, domain: domain, scope: SCOPE, devMode: devMode});
    }

    function _proof(bytes32 contractId, bytes32 passportId, address sender)
        internal
        view
        returns (ProofVerificationParams memory)
    {
        return _proof(passportId, sender, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, false);
    }

    function _sign(bytes32 contractId, uint256 index, uint256 key) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            LEGAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[index],
            key
        );
    }

    function _signWithProof(bytes32 contractId, uint256 index, uint256 key, bytes32 passportId) internal {
        ProofVerificationParams memory params = _proof(contractId, passportId, parties[index]);
        bytes memory signature = _sign(contractId, index, key);
        vm.prank(relayer);
        finalizer.signWithProof(contractId, params, partyValues[index], signature);
    }

    function _standaloneId(uint256 salt, ZKPassportFinalizer.PartyGate[] memory pins) internal view returns (bytes32) {
        bytes32 templateId = keccak256(abi.encode(STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields));
        return keccak256(
            abi.encode(
                templateId,
                uint256(keccak256(abi.encode(salt, pins))),
                globalValues,
                parties,
                bytes32(0),
                address(finalizer)
            )
        );
    }

    function _standalone(
        uint256 salt,
        ZKPassportFinalizer.PartyGate[] memory pins,
        ProofVerificationParams memory params,
        bytes memory signature
    ) internal returns (bytes32) {
        vm.prank(relayer);
        return finalizer.createStandaloneContractAndSignWithProof(
            STANDALONE_TITLE,
            LEGAL_URI,
            globalFields,
            partyFields,
            salt,
            globalValues,
            parties,
            partyValues,
            block.timestamp + 1 days,
            pins,
            params,
            signature
        );
    }

    // ── Create ───────────────────────────────────────────────────────────────

    function test_Create_RegistersAgreementWithPinsAndFinalizer() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));

        assertTrue(finalizer.isRegistered(contractId));
        assertEq(finalizer.gateOf(contractId, alice).passportId, bytes32(0));
        assertEq(finalizer.gateOf(contractId, bob).passportId, PASSPORT_B);
        assertEq(finalizer.gateOf(contractId, chad).passportId, bytes32(0));
        address[] memory stored = registry.getParties(contractId);
        assertEq(stored.length, 3);
        assertEq(stored[1], bob);
    }

    function test_Create_ContractIdBindsPins() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), PASSPORT_B, bytes32(0));
        bytes32 expected = keccak256(
            abi.encode(
                TEMPLATE_ID,
                uint256(keccak256(abi.encode(uint256(1), pins))),
                globalValues,
                parties,
                bytes32(0),
                address(finalizer)
            )
        );
        bytes32 withPins = _create(1, pins);
        bytes32 withoutPins = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));

        assertEq(withPins, expected);
        assertTrue(withPins != withoutPins);
    }

    function test_RevertIf_Create_PassportIdsLengthMismatch() public {
        ZKPassportFinalizer.PartyGate[] memory pins = new ZKPassportFinalizer.PartyGate[](2);
        vm.expectRevert(ZKPassportFinalizer.GatesLengthMismatch.selector);
        _create(1, pins);
    }

    function test_RevertIf_Create_DuplicatePin() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(PASSPORT_B, bytes32(0), PASSPORT_B);
        vm.expectRevert(ZKPassportFinalizer.DuplicatePin.selector);
        _create(1, pins);
    }

    function test_RevertIf_Create_OpenSlot() public {
        parties[2] = address(0);
        partyValues.pop();
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), bytes32(0), bytes32(0));
        vm.expectRevert(ZKPassportFinalizer.OpenSlotNotSupported.selector);
        _create(1, pins);
    }

    function test_RevertIf_Create_DuplicateParty() public {
        parties[2] = alice;
        ZKPassportFinalizer.PartyGate[] memory gates = _mixedGates();
        vm.expectRevert(ZKPassportFinalizer.DuplicateParty.selector);
        _create(1, gates);
    }

    function test_Create_StoresGatePerParty() public {
        bytes32 contractId = _create(1, _mixedGates());

        assertTrue(finalizer.gateOf(contractId, alice).proofRequired);
        assertFalse(finalizer.gateOf(contractId, bob).proofRequired);
        assertTrue(finalizer.gateOf(contractId, chad).proofRequired);
        assertEq(finalizer.gateOf(contractId, chad).passportId, PASSPORT_C);
    }

    function test_Create_ContractIdBindsProofRequirement() public {
        ZKPassportFinalizer.PartyGate[] memory gates = _mixedGates();
        bytes32 mixed = _create(1, gates);
        gates[1].proofRequired = true;
        bytes32 allGated = _create(1, gates);

        assertTrue(mixed != allGated);
    }

    function test_RevertIf_Create_PinWithoutProofRequired() public {
        ZKPassportFinalizer.PartyGate[] memory gates = _mixedGates();
        gates[1].passportId = PASSPORT_B;
        vm.expectRevert(ZKPassportFinalizer.PinWithoutProofRequired.selector);
        _create(1, gates);
    }

    // ── Sign ─────────────────────────────────────────────────────────────────

    function test_SignWithProof_ThreeParties_LastOneFinalizes() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));

        _signWithProof(contractId, 2, chadKey, PASSPORT_C);
        assertFalse(registry.isFinalized(contractId));
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        assertFalse(registry.isFinalized(contractId));
        _signWithProof(contractId, 1, bobKey, PASSPORT_B);

        assertTrue(registry.isFinalized(contractId));
        assertEq(finalizer.passportOf(contractId, alice), PASSPORT_A);
        assertEq(finalizer.passportOf(contractId, bob), PASSPORT_B);
        assertEq(finalizer.passportOf(contractId, chad), PASSPORT_C);
    }

    function test_RevertIf_SignWithProof_PinMismatch() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_X, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.PassportPinMismatch.selector);
        finalizer.signWithProof(contractId, params, partyValues[1], signature);
    }

    function test_RevertIf_SignWithProof_PassportUsedByAnotherParty() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.PassportAlreadyUsed.selector);
        finalizer.signWithProof(contractId, params, partyValues[1], signature);
    }

    function test_RevertIf_SignWithProof_UnpinnedPartyUsesPinnedPassport() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_B, chad);
        bytes memory signature = _sign(contractId, 2, chadKey);

        vm.expectRevert(ZKPassportFinalizer.PassportAlreadyUsed.selector);
        finalizer.signWithProof(contractId, params, partyValues[2], signature);
    }

    function test_RevertIf_SignWithProof_AgreementNotRegistered() public {
        uint256 salt = uint256(keccak256(abi.encode(uint256(1), _pins(bytes32(0), bytes32(0), bytes32(0)))));
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID,
            salt,
            globalValues,
            parties,
            partyValues,
            bytes32(0),
            address(finalizer),
            block.timestamp + 1 days
        );
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.AgreementNotRegistered.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ProofNotVerified() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        verifier.setShouldVerify(false);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.InvalidProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ZeroHelper() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        verifier.setShouldReturnZeroHelper(true);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.InvalidProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_WrongScope() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(
            PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), "evil.example", false
        );
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.InvalidScope.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_WrongChain() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid + 1, Strings.toHexString(uint256(contractId), 32), DOMAIN, false);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.InvalidBoundChainId.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ProofForAnotherAgreement() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        bytes32 otherId = _create(2, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(otherId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.InvalidBoundContractId.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_DevMode() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.DevModeProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_SignWithProof_DevModeDeploymentAcceptsDevModeProof() public {
        ZKPassportFinalizer devFinalizer = ZKPassportFinalizer(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportFinalizer()),
                    abi.encodeCall(
                        ZKPassportFinalizer.initialize,
                        (address(auth), address(registry), address(verifier), DOMAIN, SCOPE, true)
                    )
                )
            )
        );
        bytes32 contractId = devFinalizer.createContract(
            TEMPLATE_ID,
            1,
            globalValues,
            parties,
            partyValues,
            block.timestamp + 1 days,
            _pins(bytes32(0), bytes32(0), bytes32(0))
        );
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        devFinalizer.signWithProof(contractId, params, partyValues[0], signature);

        assertTrue(devFinalizer.devMode());
        assertEq(devFinalizer.passportOf(contractId, alice), PASSPORT_A);
    }

    function test_RevertIf_SignWithProof_BoundSenderNotAParty() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, relayer);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.NotAParty.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_BadSignature_NoRecordStays() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, bobKey);

        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
        assertEq(finalizer.passportOf(contractId, alice), bytes32(0));
    }

    function test_RevertIf_SignWithProof_SamePartyTwice() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.AlreadyRecorded.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    // ── Per-party gates ──────────────────────────────────────────────────────

    function test_MixedGates_UngatedPartySignsWithoutProof_LastOneFinalizes() public {
        bytes32 contractId = _create(1, _mixedGates());

        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        _signWithProof(contractId, 2, chadKey, PASSPORT_C);
        assertFalse(registry.isFinalized(contractId));
        _signWithoutProof(contractId, 1, bobKey);

        assertTrue(registry.isFinalized(contractId));
        assertEq(finalizer.passportOf(contractId, bob), bytes32(0));
    }

    function test_MixedGates_GatedPartyLast_Finalizes() public {
        bytes32 contractId = _create(1, _mixedGates());

        _signWithoutProof(contractId, 1, bobKey);
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        assertFalse(registry.isFinalized(contractId));
        _signWithProof(contractId, 2, chadKey, PASSPORT_C);

        assertTrue(registry.isFinalized(contractId));
    }

    function test_NoGates_AllSignWithoutProof_Finalizes() public {
        ZKPassportFinalizer.PartyGate[] memory gates = new ZKPassportFinalizer.PartyGate[](3);
        bytes32 contractId = _create(1, gates);

        _signWithoutProof(contractId, 0, aliceKey);
        _signWithoutProof(contractId, 1, bobKey);
        _signWithoutProof(contractId, 2, chadKey);

        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_SignWithoutProof_ProofRequired() public {
        bytes32 contractId = _create(1, _mixedGates());
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.ProofRequired.selector);
        finalizer.signWithoutProof(contractId, alice, partyValues[0], signature);
    }

    function test_RevertIf_SignWithoutProof_AgreementNotRegistered() public {
        ZKPassportFinalizer.PartyGate[] memory gates = new ZKPassportFinalizer.PartyGate[](3);
        uint256 salt = uint256(keccak256(abi.encode(uint256(1), gates)));
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID,
            salt,
            globalValues,
            parties,
            partyValues,
            bytes32(0),
            address(finalizer),
            block.timestamp + 1 days
        );
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.AgreementNotRegistered.selector);
        finalizer.signWithoutProof(contractId, alice, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ProofNotRequired() public {
        bytes32 contractId = _create(1, _mixedGates());
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_B, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.ProofNotRequired.selector);
        finalizer.signWithProof(contractId, params, partyValues[1], signature);
    }

    // ── Finalize ─────────────────────────────────────────────────────────────

    function test_Finalize_AfterUngatedPartySignsDirectly() public {
        bytes32 contractId = _create(1, _mixedGates());
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        _signWithProof(contractId, 2, chadKey, PASSPORT_C);

        // Bob signs on the registry directly. The registry does not finalize, because the finalizer is set.
        bytes memory signature = _sign(contractId, 1, bobKey);
        vm.prank(bob);
        registry.signContract(contractId, partyValues[1], signature, false, "");
        assertFalse(registry.isFinalized(contractId));

        finalizer.finalize(contractId);

        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_Finalize_GatedPartyHasNoRecord() public {
        bytes32 contractId = _create(1, _mixedGates());
        _signWithoutProof(contractId, 1, bobKey);
        _signWithProof(contractId, 2, chadKey, PASSPORT_C);
        bytes memory signature = _sign(contractId, 0, aliceKey);
        vm.prank(alice);
        registry.signContract(contractId, partyValues[0], signature, false, "");

        vm.expectRevert(ZKPassportFinalizer.NotReadyToFinalize.selector);
        finalizer.finalize(contractId);
    }

    function test_RevertIf_Finalize_NotAllSigned() public {
        bytes32 contractId = _create(1, _mixedGates());
        _signWithoutProof(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.NotReadyToFinalize.selector);
        finalizer.finalize(contractId);
    }

    // ── Standalone ───────────────────────────────────────────────────────────

    function test_Standalone_CreatesTemplateAgreementAndFirstSignature() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), PASSPORT_B, bytes32(0));
        bytes32 contractId = _standaloneId(1, pins);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        assertEq(_standalone(1, pins, params, signature), contractId);

        (, string memory title,,) =
            registry.getTemplateDetails(keccak256(abi.encode(STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields)));
        assertEq(title, STANDALONE_TITLE);
        assertTrue(finalizer.isRegistered(contractId));
        assertEq(finalizer.gateOf(contractId, bob).passportId, PASSPORT_B);
        assertEq(finalizer.passportOf(contractId, alice), PASSPORT_A);
        assertTrue(registry.hasSigned(contractId, alice));
        assertFalse(registry.isFinalized(contractId));

        _signWithProof(contractId, 1, bobKey, PASSPORT_B);
        _signWithProof(contractId, 2, chadKey, PASSPORT_C);
        assertTrue(registry.isFinalized(contractId));
    }

    function test_Standalone_ReusesExistingTemplate() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), bytes32(0), bytes32(0));
        bytes32 firstId = _standaloneId(1, pins);
        _standalone(1, pins, _proof(firstId, PASSPORT_A, alice), _sign(firstId, 0, aliceKey));
        bytes32 secondId = _standaloneId(2, pins);
        ProofVerificationParams memory params = _proof(secondId, PASSPORT_A, alice);
        bytes memory signature = _sign(secondId, 0, aliceKey);

        assertEq(_standalone(2, pins, params, signature), secondId);
        assertTrue(registry.hasSigned(secondId, alice));
    }

    function test_Standalone_SingleParty_Finalizes() public {
        parties.pop();
        parties.pop();
        partyValues.pop();
        partyValues.pop();
        ZKPassportFinalizer.PartyGate[] memory pins = new ZKPassportFinalizer.PartyGate[](1);
        pins[0] = _gate(true, bytes32(0));
        bytes32 contractId = _standaloneId(1, pins);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        _standalone(1, pins, params, signature);

        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_Standalone_SignerNotFirstParty() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), bytes32(0), bytes32(0));
        bytes32 contractId = _standaloneId(1, pins);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_B, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.SignerNotFirstParty.selector);
        _standalone(1, pins, params, signature);
    }

    /// @dev Bob has the same party values as Alice, so the registry's value check passes for Bob.
    function test_RevertIf_Standalone_SignerNotFirstParty_SamePartyValues() public {
        partyValues[1] = partyValues[0];
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(bytes32(0), bytes32(0), bytes32(0));
        bytes32 contractId = _standaloneId(1, pins);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_B, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(ZKPassportFinalizer.SignerNotFirstParty.selector);
        _standalone(1, pins, params, signature);
        assertFalse(finalizer.isRegistered(contractId));
    }

    function test_RevertIf_Standalone_PinMismatch_NothingCreated() public {
        ZKPassportFinalizer.PartyGate[] memory pins = _pins(PASSPORT_A, bytes32(0), bytes32(0));
        bytes32 contractId = _standaloneId(1, pins);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_X, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(ZKPassportFinalizer.PassportPinMismatch.selector);
        _standalone(1, pins, params, signature);
        assertFalse(finalizer.isRegistered(contractId));
    }

    function test_StandaloneWithoutProof_UngatedFirstParty() public {
        ZKPassportFinalizer.PartyGate[] memory gates = _mixedGates();
        gates[0] = _gate(false, bytes32(0));
        gates[1] = _gate(true, bytes32(0));
        bytes32 contractId = _standaloneId(1, gates);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.prank(relayer);
        bytes32 created = finalizer.createStandaloneContractAndSignWithoutProof(
            STANDALONE_TITLE,
            LEGAL_URI,
            globalFields,
            partyFields,
            1,
            globalValues,
            parties,
            partyValues,
            block.timestamp + 1 days,
            gates,
            signature
        );

        assertEq(created, contractId);
        assertTrue(registry.hasSigned(contractId, alice));
        assertTrue(finalizer.gateOf(contractId, bob).proofRequired);
    }

    function test_RevertIf_StandaloneWithoutProof_FirstPartyGated() public {
        ZKPassportFinalizer.PartyGate[] memory gates = _mixedGates();
        bytes32 contractId = _standaloneId(1, gates);
        bytes memory signature = _sign(contractId, 0, aliceKey);
        string[] memory gFields = globalFields;
        string[] memory pFields = partyFields;
        string[] memory gValues = globalValues;
        address[] memory ps = parties;
        string[][] memory pValues = partyValues;
        uint256 expiry = block.timestamp + 1 days;

        vm.expectRevert(ZKPassportFinalizer.ProofRequired.selector);
        finalizer.createStandaloneContractAndSignWithoutProof(
            STANDALONE_TITLE, LEGAL_URI, gFields, pFields, 1, gValues, ps, pValues, expiry, gates, signature
        );
    }

    // ── Attest ───────────────────────────────────────────────────────────────

    function test_Attest_AfterDirectSign_LastOneFinalizes() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        _signWithProof(contractId, 1, bobKey, PASSPORT_B);

        // Chad signs on the registry directly and gives no proof.
        bytes memory signature = _sign(contractId, 2, chadKey);
        vm.prank(chad);
        registry.signContract(contractId, partyValues[2], signature, false, "");
        assertTrue(registry.allPartiesSigned(contractId));
        assertFalse(registry.isFinalized(contractId));

        finalizer.attest(contractId, _proof(contractId, PASSPORT_C, chad));

        assertTrue(registry.isFinalized(contractId));
        assertEq(finalizer.passportOf(contractId, chad), PASSPORT_C);
    }

    function test_RevertIf_Attest_NotSigned() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);

        vm.expectRevert(ZKPassportFinalizer.NotSigned.selector);
        finalizer.attest(contractId, params);
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    function test_RevertIf_Initialize_ZeroVerifier() public {
        address implementation = address(new ZKPassportFinalizer());
        bytes memory initCall = abi.encodeCall(
            ZKPassportFinalizer.initialize, (address(auth), address(registry), address(0), DOMAIN, SCOPE, false)
        );

        vm.expectRevert(ZKPassportFinalizer.InvalidVerifier.selector);
        new ERC1967Proxy(implementation, initCall);
    }

    function test_UpdateVerifier_OnlyAdmin() public {
        address newVerifier = makeAddr("newVerifier");
        vm.expectRevert();
        vm.prank(relayer);
        finalizer.updateVerifier(newVerifier);

        vm.prank(deployer);
        finalizer.updateVerifier(newVerifier);
        assertEq(address(finalizer.verifier()), newVerifier);
    }
}
