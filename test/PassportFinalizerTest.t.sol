// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {PassportFinalizer} from "../src/PassportFinalizer.sol";
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

contract PassportFinalizerTest is Test {
    string constant DOMAIN = "app.metalex.tech";
    string constant SCOPE = "cyberagreement-passport";
    string constant LEGAL_URI = "https://example.com/agreement";
    bytes32 constant TEMPLATE_ID = keccak256("passport-template");

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
    PassportFinalizer finalizer;

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
        finalizer = PassportFinalizer(
            address(
                new ERC1967Proxy(
                    address(new PassportFinalizer()),
                    abi.encodeWithSelector(
                        PassportFinalizer.initialize.selector,
                        address(auth),
                        address(registry),
                        address(verifier),
                        DOMAIN,
                        SCOPE
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

    function _pins(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory pins) {
        pins = new bytes32[](3);
        pins[0] = a;
        pins[1] = b;
        pins[2] = c;
    }

    function _create(uint256 salt, bytes32[] memory pins) internal returns (bytes32) {
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

    // ── Create ───────────────────────────────────────────────────────────────

    function test_Create_RegistersAgreementWithPinsAndFinalizer() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));

        assertTrue(finalizer.isRegistered(contractId));
        assertEq(finalizer.pinOf(contractId, alice), bytes32(0));
        assertEq(finalizer.pinOf(contractId, bob), PASSPORT_B);
        assertEq(finalizer.pinOf(contractId, chad), bytes32(0));
        address[] memory stored = registry.getParties(contractId);
        assertEq(stored.length, 3);
        assertEq(stored[1], bob);
    }

    function test_Create_ContractIdBindsPins() public {
        bytes32[] memory pins = _pins(bytes32(0), PASSPORT_B, bytes32(0));
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
        bytes32[] memory pins = new bytes32[](2);
        vm.expectRevert(PassportFinalizer.PassportIdsLengthMismatch.selector);
        _create(1, pins);
    }

    function test_RevertIf_Create_DuplicatePin() public {
        bytes32[] memory pins = _pins(PASSPORT_B, bytes32(0), PASSPORT_B);
        vm.expectRevert(PassportFinalizer.DuplicatePin.selector);
        _create(1, pins);
    }

    function test_RevertIf_Create_OpenSlot() public {
        parties[2] = address(0);
        partyValues.pop();
        bytes32[] memory pins = _pins(bytes32(0), bytes32(0), bytes32(0));
        vm.expectRevert(PassportFinalizer.OpenSlotNotSupported.selector);
        _create(1, pins);
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

        vm.expectRevert(PassportFinalizer.PassportPinMismatch.selector);
        finalizer.signWithProof(contractId, params, partyValues[1], signature);
    }

    function test_RevertIf_SignWithProof_PassportUsedByAnotherParty() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        _signWithProof(contractId, 0, aliceKey, PASSPORT_A);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, bob);
        bytes memory signature = _sign(contractId, 1, bobKey);

        vm.expectRevert(PassportFinalizer.PassportAlreadyUsed.selector);
        finalizer.signWithProof(contractId, params, partyValues[1], signature);
    }

    function test_RevertIf_SignWithProof_UnpinnedPartyUsesPinnedPassport() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), PASSPORT_B, bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_B, chad);
        bytes memory signature = _sign(contractId, 2, chadKey);

        vm.expectRevert(PassportFinalizer.PassportAlreadyUsed.selector);
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

        vm.expectRevert(PassportFinalizer.AgreementNotRegistered.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ProofNotVerified() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        verifier.setShouldVerify(false);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.InvalidProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ZeroHelper() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        verifier.setShouldReturnZeroHelper(true);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.InvalidProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_WrongScope() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(
            PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), "evil.example", false
        );
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.InvalidScope.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_WrongChain() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid + 1, Strings.toHexString(uint256(contractId), 32), DOMAIN, false);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.InvalidBoundChainId.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_ProofForAnotherAgreement() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        bytes32 otherId = _create(2, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(otherId, PASSPORT_A, alice);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.InvalidBoundContractId.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_DevMode() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.DevModeProof.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
    }

    function test_RevertIf_SignWithProof_BoundSenderNotAParty() public {
        bytes32 contractId = _create(1, _pins(bytes32(0), bytes32(0), bytes32(0)));
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, relayer);
        bytes memory signature = _sign(contractId, 0, aliceKey);

        vm.expectRevert(PassportFinalizer.NotAParty.selector);
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

        vm.expectRevert(PassportFinalizer.AlreadyRecorded.selector);
        finalizer.signWithProof(contractId, params, partyValues[0], signature);
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

        vm.expectRevert(PassportFinalizer.NotSigned.selector);
        finalizer.attest(contractId, params);
    }

    // ── Admin ────────────────────────────────────────────────────────────────

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
