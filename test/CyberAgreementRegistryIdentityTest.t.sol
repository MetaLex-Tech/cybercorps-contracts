// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {MockZKPassportHelper} from "./NonUSNationalityConditionTest.t.sol";
import {
    BoundData,
    IZKPassportHelper,
    IZKPassportVerifier,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";

/// @notice Verifier mock for the registry's constant verifier address. It has no constructor
/// state, because vm.etch copies only the code.
contract MockIdentityVerifier is IZKPassportVerifier {
    bool public rejectProof;
    bytes32 public uniqueId;
    IZKPassportHelper public helper;

    function configure(bool _rejectProof, bytes32 _uniqueId, address _helper) external {
        rejectProof = _rejectProof;
        uniqueId = _uniqueId;
        helper = IZKPassportHelper(_helper);
    }

    function verify(ProofVerificationParams calldata)
        external
        view
        returns (bool, bytes32, IZKPassportHelper)
    {
        if (rejectProof) return (false, bytes32(0), IZKPassportHelper(address(0)));
        return (true, uniqueId, helper);
    }
}

contract CyberAgreementRegistryIdentityTest is Test {
    address deployer;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;
    // Carol's wallet. Only her passport proof links it to her.
    address carolWallet;
    uint256 carolWalletPrivateKey;
    address carolDelegate;
    uint256 carolDelegatePrivateKey;
    address finalizer;

    BorgAuth auth;
    CyberAgreementRegistry registry;
    MockZKPassportHelper helper;
    MockIdentityVerifier verifier;

    string constant DOMAIN = "metalex.tech";
    string constant SCOPE = "cyberagreement-identity";
    bytes32 constant CAROL_ID = keccak256("carol-passport-salted-id");
    uint256 constant VALIDITY = 1 days;

    bytes32 templateId = keccak256("identity-template");
    string legalContractUri = "ipfs://identity-template";
    string[] globalFields;
    string[] partyFields;
    string[] globalValues;
    string[] aliceValues;
    string[] carolValues;
    string[] bobValues;

    function setUp() public {
        deployer = makeAddr("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        (carolWallet, carolWalletPrivateKey) = makeAddrAndKey("carolWallet");
        (carolDelegate, carolDelegatePrivateKey) = makeAddrAndKey("carolDelegate");
        finalizer = makeAddr("finalizer");

        vm.startPrank(deployer);
        auth = new BorgAuth(deployer);
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry(false)),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );

        globalFields = new string[](1);
        globalFields[0] = "Global Field";
        partyFields = new string[](1);
        partyFields[0] = "Name";
        globalValues = new string[](1);
        globalValues[0] = "global value";
        aliceValues = new string[](1);
        aliceValues[0] = "Alice";
        carolValues = new string[](1);
        carolValues[0] = "Carol";
        bobValues = new string[](1);
        bobValues[0] = "Bob";

        registry.createTemplate(templateId, "Identity", legalContractUri, globalFields, partyFields);
        registry.setIdentityScope(DOMAIN, SCOPE);
        vm.stopPrank();

        helper = new MockZKPassportHelper();
        vm.etch(registry.ZKPASSPORT_VERIFIER(), address(new MockIdentityVerifier()).code);
        verifier = MockIdentityVerifier(registry.ZKPASSPORT_VERIFIER());
        verifier.configure(false, CAROL_ID, address(helper));
    }

    // ─── Admin config ───────────────────────────────────────────────────────

    function test_setIdentityScope() public {
        vm.expectEmit(address(registry));
        emit CyberAgreementRegistry.IdentityScopeSet("new.domain", "new-scope");
        vm.prank(deployer);
        registry.setIdentityScope("new.domain", "new-scope");
        assertEq(registry.identityDomain(), "new.domain");
        assertEq(registry.identityScope(), "new-scope");
    }

    function test_RevertIf_setIdentityScopeNotAdmin() public {
        vm.expectRevert();
        vm.prank(alice);
        registry.setIdentityScope("new.domain", "new-scope");
    }

    // ─── Create ─────────────────────────────────────────────────────────────

    function test_createContractWithIdentitySlots() public {
        address[] memory parties = _parties(2);
        uint256[] memory slots = _uints(1);
        bytes32[] memory ids = _ids(CAROL_ID);
        bytes32 scopeHash = keccak256(abi.encode(DOMAIN, SCOPE));
        bytes32 expectedId = keccak256(
            abi.encode(templateId, uint256(1), globalValues, parties, bytes32(0), address(0), slots, ids, scopeHash)
        );

        vm.expectEmit(address(registry));
        emit CyberAgreementRegistry.IdentitySlotsCreated(expectedId, slots, ids, DOMAIN, SCOPE);
        vm.prank(alice);
        bytes32 contractId = registry.createContractWithIdentitySlots(
            templateId, 1, globalValues, parties, _aliceOnlyValues(), bytes32(0), address(0), 0, slots, ids
        );

        assertEq(contractId, expectedId);
        assertEq(registry.slotIdentityConstraints(contractId, 1), CAROL_ID);
        assertEq(registry.identityScopeHash(contractId), scopeHash);
    }

    function test_RevertIf_createWithIdentityScopeNotSet() public {
        vm.prank(deployer);
        registry.setIdentityScope("", "");
        vm.expectRevert(CyberAgreementRegistry.IdentityScopeNotSet.selector);
        _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
    }

    function test_RevertIf_createIdentitySlotOnSlotZero() public {
        vm.expectRevert(CyberAgreementRegistry.IdentitySlotNotOpen.selector);
        _create(_parties(2), _uints(0), _ids(CAROL_ID), address(0), bytes32(0));
    }

    function test_RevertIf_createIdentitySlotOnNamedSlot() public {
        address[] memory parties = _parties(2);
        parties[1] = bob;
        vm.expectRevert(CyberAgreementRegistry.IdentitySlotNotOpen.selector);
        _create(parties, _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
    }

    function test_RevertIf_createIdentitySlotOutOfRange() public {
        vm.expectRevert(CyberAgreementRegistry.IdentitySlotNotOpen.selector);
        _create(_parties(2), _uints(2), _ids(CAROL_ID), address(0), bytes32(0));
    }

    function test_RevertIf_createDuplicateIdentitySlot() public {
        uint256[] memory slots = new uint256[](2);
        slots[0] = 1;
        slots[1] = 1;
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = CAROL_ID;
        ids[1] = keccak256("other");
        vm.expectRevert(CyberAgreementRegistry.IdentitySlotNotOpen.selector);
        _create(_parties(3), slots, ids, address(0), bytes32(0));
    }

    function test_RevertIf_createZeroUniqueIdentifier() public {
        vm.expectRevert(CyberAgreementRegistry.ZeroUniqueIdentifier.selector);
        _create(_parties(2), _uints(1), _ids(bytes32(0)), address(0), bytes32(0));
    }

    function test_RevertIf_createMismatchedIdentitySlotsLength() public {
        vm.expectRevert(CyberAgreementRegistry.MismatchedIdentitySlotsLength.selector);
        _create(_parties(2), _uints(1), new bytes32[](0), address(0), bytes32(0));
    }

    function test_RevertIf_createNoIdentitySlots() public {
        vm.expectRevert(CyberAgreementRegistry.MismatchedIdentitySlotsLength.selector);
        _create(_parties(2), new uint256[](0), new bytes32[](0), address(0), bytes32(0));
    }

    /// @notice A front-runner cannot take the id with a different constraint
    function test_contractIdBindsIdentityConstraints() public {
        bytes32 idCarol = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes32 idOther = _create(_parties(2), _uints(1), _ids(keccak256("attacker")), address(0), bytes32(0));
        assertNotEq(idCarol, idOther);
    }

    /// @notice An admin scope change does not affect an existing agreement
    function test_scopeChangeKeepsAgreementScope() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        vm.prank(deployer);
        registry.setIdentityScope("new.domain", "new-scope");

        ProofVerificationParams memory newScopeProof = _proof(carolWallet, contractId);
        newScopeProof.serviceConfig.domain = "new.domain";
        newScopeProof.serviceConfig.scope = "new-scope";
        newScopeProof.proofVerificationData.publicInputs = _publicInputs("new.domain", "new-scope", block.timestamp);
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        vm.expectRevert(CyberAgreementRegistry.IdentityScopeMismatch.selector);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", newScopeProof);

        _signWithIdentity(contractId, _proof(carolWallet, contractId));
        assertTrue(registry.hasSigned(contractId, carolWallet));
    }

    // ─── Sign: success ──────────────────────────────────────────────────────

    function test_signContractWithIdentityFor() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _signAs(contractId, aliceValues, alice, alicePrivateKey);

        _signWithIdentity(contractId, _proof(carolWallet, contractId));

        address[] memory parties = registry.getParties(contractId);
        assertEq(parties[1], carolWallet);
        assertTrue(registry.hasSigned(contractId, carolWallet));
        assertEq(registry.getSignerValues(contractId, carolWallet)[0], "Carol");
        assertTrue(registry.isFinalized(contractId), "no finalizer: finalize when all parties signed");
    }

    function test_signContractWithIdentityForViaDelegate() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        vm.prank(carolWallet);
        registry.setDelegation(carolDelegate, 0);

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            legalContractUri,
            globalFields,
            partyFields,
            globalValues,
            carolValues,
            carolWallet,
            carolDelegatePrivateKey
        );
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.prank(carolDelegate);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
        assertTrue(registry.hasSigned(contractId, carolWallet));
    }

    function test_signContractWithIdentityForByFinalizer() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), finalizer, bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.prank(finalizer);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
        assertTrue(registry.hasSigned(contractId, carolWallet));
        assertFalse(registry.isFinalized(contractId), "finalizer set: no auto-finalize");
    }

    function test_RevertIf_signContractWithIdentityForByThirdPartyWithFinalizer() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), finalizer, bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.expectRevert(CyberAgreementRegistry.NotFinalizer.selector);
        vm.prank(bob);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
    }

    function test_signContractWithIdentityForWithSecret() public {
        bytes32 contractId = _create(
            _parties(2), _uints(1), _ids(CAROL_ID), address(0), keccak256(abi.encode("open sesame"))
        );
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);

        vm.expectRevert(CyberAgreementRegistry.InvalidSecret.selector);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "wrong", proof);

        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "open sesame", proof);
        assertTrue(registry.hasSigned(contractId, carolWallet));
    }

    // ─── Standalone ─────────────────────────────────────────────────────────

    function test_createStandaloneContractWithIdentitySlotsAndSign() public {
        bytes32 contractId = _expectedStandaloneId(42);
        bytes memory signature = _sig(contractId, aliceValues, alicePrivateKey);

        vm.prank(alice);
        bytes32 createdId = registry.createStandaloneContractWithIdentitySlotsAndSign(
            "Standalone", legalContractUri, globalFields, partyFields, 42, globalValues, _parties(2),
            _aliceOnlyValues(), 0, _uints(1), _ids(CAROL_ID), signature
        );

        assertEq(createdId, contractId);
        assertTrue(registry.hasSigned(contractId, alice));
        assertEq(registry.slotIdentityConstraints(contractId, 1), CAROL_ID);

        _signWithIdentity(contractId, _proof(carolWallet, contractId));
        assertTrue(registry.isFinalized(contractId), "no finalizer: finalize when all parties signed");
    }

    function test_createStandaloneContractWithIdentitySlotsAndSignFor() public {
        bytes32 contractId = _expectedStandaloneId(43);
        bytes memory signature = _sig(contractId, aliceValues, alicePrivateKey);

        // bob relays alice's signature
        vm.prank(bob);
        registry.createStandaloneContractWithIdentitySlotsAndSignFor(
            "Standalone", legalContractUri, globalFields, partyFields, 43, globalValues, _parties(2),
            _aliceOnlyValues(), 0, _uints(1), _ids(CAROL_ID), alice, signature
        );

        assertTrue(registry.hasSigned(contractId, alice));
        assertEq(registry.slotIdentityConstraints(contractId, 1), CAROL_ID);
    }

    function test_RevertIf_createStandaloneWithIdentitySlotsBadSignature() public {
        bytes32 contractId = _expectedStandaloneId(44);
        bytes memory signature = _sig(contractId, aliceValues, bobPrivateKey);

        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        vm.prank(alice);
        registry.createStandaloneContractWithIdentitySlotsAndSign(
            "Standalone", legalContractUri, globalFields, partyFields, 44, globalValues, _parties(2),
            _aliceOnlyValues(), 0, _uints(1), _ids(CAROL_ID), signature
        );
    }

    // ─── Sign: proof refusals ───────────────────────────────────────────────

    function test_RevertIf_proofNotVerified() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        verifier.configure(true, CAROL_ID, address(helper));
        _expectIdentitySignRevert(contractId, _proof(carolWallet, contractId), CyberAgreementRegistry.ProofNotVerified.selector);
    }

    function test_RevertIf_proofZeroHelper() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        verifier.configure(false, CAROL_ID, address(0));
        _expectIdentitySignRevert(contractId, _proof(carolWallet, contractId), CyberAgreementRegistry.ProofNotVerified.selector);
    }

    function test_RevertIf_uniqueIdentifierMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        verifier.configure(false, keccak256("someone-else"), address(helper));
        _expectIdentitySignRevert(
            contractId, _proof(carolWallet, contractId), CyberAgreementRegistry.UniqueIdentifierMismatch.selector
        );
    }

    function test_RevertIf_proofDomainMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.serviceConfig.domain = "evil.domain";
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.IdentityScopeMismatch.selector);
    }

    function test_RevertIf_proofScopeMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.serviceConfig.scope = "other-scope";
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.IdentityScopeMismatch.selector);
    }

    /// @notice The proof's public inputs must commit to the domain and scope in its service config
    function test_RevertIf_verifyScopesFails() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.proofVerificationData.publicInputs = _publicInputs("evil.domain", SCOPE, block.timestamp);
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.IdentityScopeMismatch.selector);
    }

    function test_RevertIf_boundSenderMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _expectIdentitySignRevert(contractId, _proof(bob, contractId), CyberAgreementRegistry.BoundSenderMismatch.selector);
    }

    function test_RevertIf_boundChainIdMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.committedInputs = abi.encode(
            BoundData({senderAddress: carolWallet, chainId: block.chainid + 1, customData: vm.toString(contractId)})
        );
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.BoundChainIdMismatch.selector);
    }

    /// @notice A proof made for one agreement does not work for another
    function test_RevertIf_boundCustomDataMismatch() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes32 otherId = keccak256("other-agreement");
        _expectIdentitySignRevert(
            contractId, _proof(carolWallet, otherId), CyberAgreementRegistry.BoundCustomDataMismatch.selector
        );
    }

    /// @notice A proof with no custom data does not work
    function test_RevertIf_boundCustomDataEmpty() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _expectIdentitySignRevert(
            contractId,
            _proofWithCustomData(carolWallet, ""),
            CyberAgreementRegistry.BoundCustomDataMismatch.selector
        );
    }

    /// @notice The custom data must be the contractId as a 0x lowercase hex string, with no other format
    function test_RevertIf_boundCustomDataWrongFormat() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        string memory lowercaseHex = vm.toString(contractId);
        assertEq(lowercaseHex, registry._bytes32ToString(contractId), "registry format is 0x lowercase hex");

        string[] memory wrongFormats = new string[](3);
        wrongFormats[0] = vm.toUppercase(lowercaseHex); // 0X... uppercase
        wrongFormats[1] = vm.replace(lowercaseHex, "0x", ""); // no 0x prefix
        wrongFormats[2] = string.concat(lowercaseHex, " "); // trailing space
        for (uint256 i = 0; i < wrongFormats.length; i++) {
            _expectIdentitySignRevert(
                contractId,
                _proofWithCustomData(carolWallet, wrongFormats[i]),
                CyberAgreementRegistry.BoundCustomDataMismatch.selector
            );
        }
    }

    function test_RevertIf_devModeProof() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.serviceConfig.devMode = true;
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.DevModeProof.selector);
    }

    /// @notice A testnet implementation accepts dev-mode proofs
    function test_devModeProofOnDevModeImplementation() public {
        assertFalse(registry.ZKP_DEV_MODE());
        address devImplementation = address(new CyberAgreementRegistry(true));
        vm.prank(deployer);
        registry.upgradeToAndCall(devImplementation, "");
        assertTrue(registry.ZKP_DEV_MODE());

        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        proof.serviceConfig.devMode = true;
        _signWithIdentity(contractId, proof);
        assertTrue(registry.hasSigned(contractId, carolWallet));
    }

    function test_RevertIf_proofExpired() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.warp(block.timestamp + VALIDITY + 1);
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.ProofExpired.selector);
    }

    // ─── Sign: slot and agreement refusals ──────────────────────────────────

    function test_RevertIf_slotHasNoIdentityConstraint() public {
        bytes32 contractId = _create(_parties(3), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.expectRevert(CyberAgreementRegistry.NotIdentitySlot.selector);
        registry.signContractWithIdentityFor(carolWallet, contractId, 2, carolValues, signature, "", proof);
    }

    function test_RevertIf_slotIndexOutOfRange() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.expectRevert(CyberAgreementRegistry.NotIdentitySlot.selector);
        registry.signContractWithIdentityFor(carolWallet, contractId, 5, carolValues, signature, "", proof);
    }

    function test_RevertIf_identitySlotAlreadyFilled() public {
        bytes32 contractId = _create(_parties(3), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _signWithIdentity(contractId, _proof(carolWallet, contractId));

        // Carol tries again from a second wallet
        (address secondWallet, uint256 secondKey) = makeAddrAndKey("carolSecondWallet");
        bytes memory signature = _sig(contractId, carolValues, secondKey);
        ProofVerificationParams memory proof = _proof(secondWallet, contractId);
        vm.expectRevert(CyberAgreementRegistry.IdentitySlotNotOpen.selector);
        registry.signContractWithIdentityFor(secondWallet, contractId, 1, carolValues, signature, "", proof);
    }

    function test_RevertIf_signerAlreadyParty() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, alicePrivateKey);
        ProofVerificationParams memory proof = _proof(alice, contractId);
        vm.expectRevert(CyberAgreementRegistry.DuplicateParty.selector);
        registry.signContractWithIdentityFor(alice, contractId, 1, carolValues, signature, "", proof);
    }

    function test_RevertIf_identitySignatureInvalid() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes memory signature = _sig(contractId, carolValues, bobPrivateKey);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
    }

    function test_RevertIf_identitySignContractExpired() public {
        bytes32 contractId = _createWithExpiry(block.timestamp + 10);
        ProofVerificationParams memory proof = _proof(carolWallet, contractId);
        vm.warp(block.timestamp + 11);
        _expectIdentitySignRevert(contractId, proof, CyberAgreementRegistry.ContractExpired.selector);
    }

    function test_RevertIf_identitySignContractVoided() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _signAs(contractId, aliceValues, alice, alicePrivateKey);
        _requestVoid(contractId, alice, alicePrivateKey);
        assertTrue(registry.isVoided(contractId));
        _expectIdentitySignRevert(contractId, _proof(carolWallet, contractId), CyberAgreementRegistry.ContractAlreadyVoided.selector);
    }

    function test_RevertIf_identitySignContractDoesNotExist() public {
        bytes32 contractId = keccak256("missing");
        _expectIdentitySignRevert(contractId, _proof(carolWallet, contractId), CyberAgreementRegistry.ContractDoesNotExist.selector);
    }

    // ─── Existing paths skip identity slots ─────────────────────────────────

    function test_RevertIf_signContractFillsIdentitySlot() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        bytes memory signature = _sig(contractId, bobValues, bobPrivateKey);
        vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
        vm.prank(bob);
        registry.signContract(contractId, bobValues, signature, true, "");
    }

    function test_signContractFillsUnconstrainedSlotOnly() public {
        bytes32 contractId = _create(_parties(3), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _signAs(contractId, bobValues, bob, bobPrivateKey);

        address[] memory parties = registry.getParties(contractId);
        assertEq(parties[1], address(0), "identity slot stays open");
        assertEq(parties[2], bob);

        _signWithIdentity(contractId, _proof(carolWallet, contractId));
        assertEq(registry.getParties(contractId)[1], carolWallet);
    }

    function test_RevertIf_signContractWithEscrowFillsIdentitySlot() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), finalizer, bytes32(0));
        vm.expectRevert(CyberAgreementRegistry.NotAParty.selector);
        vm.prank(finalizer);
        registry.signContractWithEscrow(bob, contractId, bobValues, "", true, "");
    }

    // ─── Filled wallet is a normal party ────────────────────────────────────

    function test_identityPartyIsNormalParty() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), address(0), bytes32(0));
        _signWithIdentity(contractId, _proof(carolWallet, contractId));

        bytes32[] memory carolAgreements = registry.getAgreementsForParty(carolWallet);
        assertEq(carolAgreements.length, 1);
        assertEq(carolAgreements[0], contractId);
    }

    function test_identityPartyCanVoid() public {
        bytes32 contractId = _create(_parties(2), _uints(1), _ids(CAROL_ID), finalizer, bytes32(0));
        _signWithIdentity(contractId, _proof(carolWallet, contractId));

        _requestVoid(contractId, carolWallet, carolWalletPrivateKey);
        assertFalse(registry.isVoided(contractId));
        _requestVoid(contractId, alice, alicePrivateKey);
        assertTrue(registry.isVoided(contractId));
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    /// @notice alice in slot 0, then `count - 1` open slots
    function _parties(uint256 count) private view returns (address[] memory parties) {
        parties = new address[](count);
        parties[0] = alice;
    }

    function _aliceOnlyValues() private view returns (string[][] memory values) {
        values = new string[][](1);
        values[0] = aliceValues;
    }

    function _uints(uint256 value) private pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _ids(bytes32 value) private pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = value;
    }

    function _create(
        address[] memory parties,
        uint256[] memory slots,
        bytes32[] memory ids,
        address _finalizer,
        bytes32 secretHash
    ) private returns (bytes32) {
        vm.prank(alice);
        return registry.createContractWithIdentitySlots(
            templateId, uint256(keccak256(abi.encode(ids))), globalValues, parties, _aliceOnlyValues(),
            secretHash, _finalizer, 0, slots, ids
        );
    }

    function _createWithExpiry(uint256 expiry) private returns (bytes32) {
        vm.prank(alice);
        return registry.createContractWithIdentitySlots(
            templateId, 1, globalValues, _parties(2), _aliceOnlyValues(), bytes32(0), address(0), expiry,
            _uints(1), _ids(CAROL_ID)
        );
    }

    function _expectedStandaloneId(uint256 salt) private view returns (bytes32) {
        bytes32 standaloneTemplateId = keccak256(abi.encode("Standalone", legalContractUri, globalFields, partyFields));
        return keccak256(
            abi.encode(
                standaloneTemplateId, salt, globalValues, _parties(2), bytes32(0), address(0), _uints(1),
                _ids(CAROL_ID), keccak256(abi.encode(DOMAIN, SCOPE))
            )
        );
    }

    function _publicInputs(string memory domain, string memory scope, uint256 timestamp)
        private
        pure
        returns (bytes32[] memory inputs)
    {
        inputs = new bytes32[](3);
        inputs[0] = keccak256(bytes(domain));
        inputs[1] = keccak256(bytes(scope));
        inputs[2] = bytes32(timestamp);
    }

    function _proof(address boundSender, bytes32 boundContractId)
        private
        view
        returns (ProofVerificationParams memory)
    {
        return _proofWithCustomData(boundSender, vm.toString(boundContractId));
    }

    function _proofWithCustomData(address boundSender, string memory customData)
        private
        view
        returns (ProofVerificationParams memory)
    {
        return ProofVerificationParams({
            version: bytes32(0),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(0),
                proof: "",
                publicInputs: _publicInputs(DOMAIN, SCOPE, block.timestamp)
            }),
            committedInputs: abi.encode(
                BoundData({senderAddress: boundSender, chainId: block.chainid, customData: customData})
            ),
            serviceConfig: ServiceConfig({validityPeriodInSeconds: VALIDITY, domain: DOMAIN, scope: SCOPE, devMode: false})
        });
    }

    function _sig(bytes32 contractId, string[] memory partyValues, uint256 privateKey)
        private
        view
        returns (bytes memory)
    {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            legalContractUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues,
            privateKey
        );
    }

    function _signAs(bytes32 contractId, string[] memory partyValues, address signer, uint256 privateKey) private {
        bytes memory signature = _sig(contractId, partyValues, privateKey);
        vm.prank(signer);
        registry.signContract(contractId, partyValues, signature, true, "");
    }

    function _signWithIdentity(bytes32 contractId, ProofVerificationParams memory proof) private {
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        vm.prank(carolWallet);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
    }

    function _expectIdentitySignRevert(bytes32 contractId, ProofVerificationParams memory proof, bytes4 selector)
        private
    {
        bytes memory signature = _sig(contractId, carolValues, carolWalletPrivateKey);
        vm.expectRevert(selector);
        vm.prank(carolWallet);
        registry.signContractWithIdentityFor(carolWallet, contractId, 1, carolValues, signature, "", proof);
    }

    function _voidSig(bytes32 contractId, address party, uint256 privateKey) private view returns (bytes memory) {
        return CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), contractId, party, privateKey
        );
    }

    function _requestVoid(bytes32 contractId, address party, uint256 privateKey) private {
        bytes memory signature = _voidSig(contractId, party, privateKey);
        registry.voidContractFor(contractId, party, signature);
    }
}
