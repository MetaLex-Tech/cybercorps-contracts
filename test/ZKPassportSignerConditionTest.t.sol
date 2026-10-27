// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ZKPassportSignerCondition} from "../src/ZKPassportSignerCondition.sol";
import "../src/interfaces/ICyberAgreementRegistry.sol";
import {ISignerCondition, SignerCondition} from "../src/interfaces/ISignerCondition.sol";
import "../src/interfaces/IZKPassportVerifier.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {MockPassportHelper, MockPassportVerifier} from "./ZKPassportFinalizerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IERC165} from "openzeppelin-contracts/utils/introspection/IERC165.sol";

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

contract ZKPassportSignerConditionTest is Test {
    string constant DOMAIN = "app.metalex.tech";
    string constant SCOPE = "cyberagreement-passport";
    string constant LEGAL_URI = "https://example.com/agreement";
    string constant TITLE = "Passport Agreement";

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
    ZKPassportSignerCondition condition;

    string[] globalFields;
    string[] partyFields;
    string[] globalValues;
    address[] parties;
    string[][] partyValues;
    uint256 expiry;

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
        condition = _deployCondition(address(registry), false);
        vm.stopPrank();

        globalFields.push("Effective Date");
        partyFields.push("Name");
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

    function _deployCondition(address _registry, bool _devMode) internal returns (ZKPassportSignerCondition) {
        return ZKPassportSignerCondition(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportSignerCondition()),
                    abi.encodeWithSelector(
                        ZKPassportSignerCondition.initialize.selector,
                        address(auth),
                        _registry,
                        address(verifier),
                        DOMAIN,
                        SCOPE,
                        _devMode
                    )
                )
            )
        );
    }

    function _one(string memory value) internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = value;
    }

    function _template() internal view returns (ICyberAgreementRegistry.Template memory) {
        return ICyberAgreementRegistry.Template({
            legalContractUri: LEGAL_URI, title: TITLE, globalFields: globalFields, partyFields: partyFields
        });
    }

    /// @dev Alice needs any passport, Bob needs none, Chad needs PASSPORT_C.
    function _conditions() internal view returns (SignerCondition[] memory conditions) {
        conditions = new SignerCondition[](3);
        conditions[0] = SignerCondition({condition: condition, data: ""});
        conditions[2] = SignerCondition({condition: condition, data: abi.encode(PASSPORT_C)});
    }

    function _id(uint256 salt) internal view returns (bytes32 contractId) {
        (, contractId) =
            registry.boundIdsOf(alice, _template(), salt, globalValues, parties, partyValues, expiry, _conditions());
    }

    function _create(uint256 salt) internal returns (bytes32 contractId) {
        vm.prank(alice);
        (, contractId) =
            registry.createBoundContract(_template(), salt, globalValues, parties, partyValues, expiry, _conditions());
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

    function _submit(bytes32 contractId, bytes32 passportId, address sender) internal {
        ProofVerificationParams memory params = _proof(contractId, passportId, sender);
        vm.prank(relayer);
        condition.submitProof(contractId, params);
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

    function _relaySign(bytes32 contractId, uint256 index, uint256 key) internal {
        bytes memory signature = _sign(contractId, index, key);
        vm.prank(relayer);
        registry.signContractFor(parties[index], contractId, partyValues[index], signature, false, "");
    }

    // ── Sign ─────────────────────────────────────────────────────────────────

    function test_SubmitProofBeforeCreation_ThenCreateAndSign() public {
        bytes32 expectedId = _id(1);
        _submit(expectedId, PASSPORT_A, alice);
        bytes memory aliceSignature = _sign(expectedId, 0, aliceKey);

        vm.prank(relayer);
        (, bytes32 contractId) = registry.createBoundContractAndSignFor(
            _template(), 1, globalValues, parties, partyValues, expiry, _conditions(), aliceSignature
        );
        assertEq(contractId, expectedId);
        assertTrue(registry.hasSigned(contractId, alice));
        assertEq(condition.passportOf(contractId, alice), PASSPORT_A);
    }

    function test_RevertIf_CreateAndSign_CreatorHasNoProof() public {
        bytes32 expectedId = _id(1);
        bytes memory aliceSignature = _sign(expectedId, 0, aliceKey);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, condition));
        registry.createBoundContractAndSignFor(
            _template(), 1, globalValues, parties, partyValues, expiry, _conditions(), aliceSignature
        );
    }

    function test_ThreeParties_MixedConditions_LastOneFinalizes() public {
        bytes32 contractId = _create(1);
        _submit(contractId, PASSPORT_A, alice);
        _submit(contractId, PASSPORT_C, chad);

        _relaySign(contractId, 0, aliceKey);
        _relaySign(contractId, 1, bobKey);
        assertFalse(registry.isFinalized(contractId));
        _relaySign(contractId, 2, chadKey);
        assertTrue(registry.isFinalized(contractId));
    }

    function test_RevertIf_Sign_NoProof() public {
        bytes32 contractId = _create(1);
        bytes memory chadSignature = _sign(contractId, 2, chadKey);

        vm.prank(chad);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, condition));
        registry.signContract(contractId, partyValues[2], chadSignature, false, "");
    }

    function test_RevertIf_Sign_PinMismatch() public {
        bytes32 contractId = _create(1);
        _submit(contractId, PASSPORT_X, chad);
        assertFalse(condition.checkSigner(address(registry), contractId, chad, abi.encode(PASSPORT_C)));

        bytes memory chadSignature = _sign(contractId, 2, chadKey);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignerConditionNotMet.selector, condition));
        registry.signContractFor(chad, contractId, partyValues[2], chadSignature, false, "");
    }

    // ── Submit proof ─────────────────────────────────────────────────────────

    function test_SubmitProof_RecordsPassport() public {
        bytes32 contractId = _create(1);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);

        vm.expectEmit(address(condition));
        emit ZKPassportSignerCondition.PassportRecorded(contractId, alice, PASSPORT_A);
        vm.prank(relayer);
        condition.submitProof(contractId, params);
        assertEq(condition.passportOf(contractId, alice), PASSPORT_A);
        assertTrue(condition.checkSigner(address(registry), contractId, alice, ""));
    }

    function test_RevertIf_SubmitProof_PassportUsedByAnotherParty() public {
        bytes32 contractId = _create(1);
        _submit(contractId, PASSPORT_A, alice);

        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, chad);
        vm.expectRevert(ZKPassportSignerCondition.PassportAlreadyUsed.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_SamePartyTwice() public {
        bytes32 contractId = _create(1);
        _submit(contractId, PASSPORT_A, alice);

        ProofVerificationParams memory params = _proof(contractId, PASSPORT_X, alice);
        vm.expectRevert(ZKPassportSignerCondition.AlreadyRecorded.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_ProofForAnotherAgreement() public {
        bytes32 contractId = _create(1);
        ProofVerificationParams memory params = _proof(_id(2), PASSPORT_A, alice);

        vm.expectRevert(ZKPassportSignerCondition.InvalidBoundContractId.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_WrongChain() public {
        bytes32 contractId = _create(1);
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid + 1, Strings.toHexString(uint256(contractId), 32), DOMAIN, false);

        vm.expectRevert(ZKPassportSignerCondition.InvalidBoundChainId.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_WrongScope() public {
        bytes32 contractId = _create(1);
        ProofVerificationParams memory params = _proof(
            PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), "other.domain", false
        );

        vm.expectRevert(ZKPassportSignerCondition.InvalidScope.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_DevMode() public {
        bytes32 contractId = _create(1);
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true);

        vm.expectRevert(ZKPassportSignerCondition.DevModeProof.selector);
        condition.submitProof(contractId, params);
    }

    function test_SubmitProof_DevModeDeploymentAcceptsDevModeProof() public {
        ZKPassportSignerCondition devCondition = _deployCondition(address(registry), true);
        bytes32 contractId = _id(1);
        ProofVerificationParams memory params =
            _proof(PASSPORT_A, alice, block.chainid, Strings.toHexString(uint256(contractId), 32), DOMAIN, true);

        devCondition.submitProof(contractId, params);
        assertEq(devCondition.passportOf(contractId, alice), PASSPORT_A);
    }

    function test_RevertIf_SubmitProof_ProofNotVerified() public {
        bytes32 contractId = _create(1);
        verifier.setShouldVerify(false);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);

        vm.expectRevert(ZKPassportSignerCondition.InvalidProof.selector);
        condition.submitProof(contractId, params);
    }

    function test_RevertIf_SubmitProof_ZeroHelper() public {
        bytes32 contractId = _create(1);
        verifier.setShouldReturnZeroHelper(true);
        ProofVerificationParams memory params = _proof(contractId, PASSPORT_A, alice);

        vm.expectRevert(ZKPassportSignerCondition.InvalidProof.selector);
        condition.submitProof(contractId, params);
    }

    // ── Relayer settlement in one transaction ────────────────────────────────

    /// @dev Proofs for Alice (any passport) and Chad (pinned PASSPORT_C), creation with Alice's
    /// signature, and the signatures of Bob and Chad. All for the agreement id from `boundIdsOf`.
    function _settlementCalls(bool withChadProof) internal view returns (IMulticall3.Call3[] memory calls) {
        bytes32 contractId = _id(1);
        calls = new IMulticall3.Call3[](withChadProof ? 5 : 4);
        uint256 n;
        calls[n++] = IMulticall3.Call3(
            address(condition),
            false,
            abi.encodeCall(ZKPassportSignerCondition.submitProof, (contractId, _proof(contractId, PASSPORT_A, alice)))
        );
        if (withChadProof) {
            calls[n++] = IMulticall3.Call3(
                address(condition),
                false,
                abi.encodeCall(
                    ZKPassportSignerCondition.submitProof, (contractId, _proof(contractId, PASSPORT_C, chad))
                )
            );
        }
        calls[n++] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeWithSignature(
                "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(address,bytes)[],bytes)",
                _template(),
                1,
                globalValues,
                parties,
                partyValues,
                expiry,
                _conditions(),
                _sign(contractId, 0, aliceKey)
            )
        );
        calls[n++] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeCall(
                CyberAgreementRegistry.signContractFor,
                (bob, contractId, partyValues[1], _sign(contractId, 1, bobKey), false, "")
            )
        );
        calls[n++] = IMulticall3.Call3(
            address(registry),
            false,
            abi.encodeCall(
                CyberAgreementRegistry.signContractFor,
                (chad, contractId, partyValues[2], _sign(contractId, 2, chadKey), false, "")
            )
        );
    }

    function test_RelayerSettlesInOneTransaction() public {
        Multicall3Aggregate3 multicall = new Multicall3Aggregate3();
        bytes32 contractId = _id(1);
        IMulticall3.Call3[] memory calls = _settlementCalls(true);

        // The parties only sign off-chain. The relayer sends the only transaction.
        vm.expectEmit(address(registry));
        emit ICyberAgreementRegistry.ContractFullySigned(contractId, block.timestamp);
        vm.prank(relayer);
        multicall.aggregate3(calls);

        assertTrue(registry.isFinalized(contractId));
        assertTrue(registry.hasSigned(contractId, alice));
        assertTrue(registry.hasSigned(contractId, bob));
        assertTrue(registry.hasSigned(contractId, chad));
        assertEq(condition.passportOf(contractId, alice), PASSPORT_A);
        assertEq(condition.passportOf(contractId, chad), PASSPORT_C);
    }

    function test_RevertIf_RelayerSettlement_ProofMissing_NothingStays() public {
        Multicall3Aggregate3 multicall = new Multicall3Aggregate3();
        bytes32 contractId = _id(1);
        IMulticall3.Call3[] memory calls = _settlementCalls(false);

        vm.prank(relayer);
        vm.expectRevert("Multicall3: call failed");
        multicall.aggregate3(calls);

        assertEq(registry.getParties(contractId).length, 0);
        assertEq(condition.passportOf(contractId, alice), bytes32(0));
    }

    // ── Check and admin ──────────────────────────────────────────────────────

    function test_CheckSigner_OtherRegistry_False() public {
        bytes32 contractId = _create(1);
        _submit(contractId, PASSPORT_A, alice);

        assertTrue(condition.checkSigner(address(registry), contractId, alice, ""));
        assertFalse(condition.checkSigner(makeAddr("otherRegistry"), contractId, alice, ""));
    }

    function test_SupportsInterface() public view {
        assertTrue(condition.supportsInterface(type(ISignerCondition).interfaceId));
        assertTrue(condition.supportsInterface(type(IERC165).interfaceId));
        assertFalse(condition.supportsInterface(0xffffffff));
    }

    function test_RevertIf_Initialize_ZeroRegistry() public {
        ZKPassportSignerCondition implementation = new ZKPassportSignerCondition();
        bytes memory data = abi.encodeWithSelector(
            ZKPassportSignerCondition.initialize.selector,
            address(auth),
            address(0),
            address(verifier),
            DOMAIN,
            SCOPE,
            false
        );
        vm.expectRevert(ZKPassportSignerCondition.InvalidRegistry.selector);
        new ERC1967Proxy(address(implementation), data);
    }

    function test_RevertIf_Initialize_ZeroVerifier() public {
        ZKPassportSignerCondition implementation = new ZKPassportSignerCondition();
        bytes memory data = abi.encodeWithSelector(
            ZKPassportSignerCondition.initialize.selector,
            address(auth),
            address(registry),
            address(0),
            DOMAIN,
            SCOPE,
            false
        );
        vm.expectRevert(ZKPassportSignerCondition.InvalidVerifier.selector);
        new ERC1967Proxy(address(implementation), data);
    }

    function test_UpdateVerifier_OnlyAdmin() public {
        address newVerifier = makeAddr("newVerifier");

        vm.prank(relayer);
        vm.expectRevert();
        condition.updateVerifier(newVerifier);

        vm.prank(deployer);
        condition.updateVerifier(newVerifier);
        assertEq(address(condition.verifier()), newVerifier);
    }
}
