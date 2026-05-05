pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

contract CyberAgreementRegistryECDHTest is Test {
    CyberAgreementRegistry registry;

    address owner;
    uint256 ownerKey;
    address partyA;
    uint256 partyAKey;
    address partyB;
    uint256 partyBKey;

    bytes32 constant TEMPLATE_ID = bytes32(uint256(1));
    string constant LEGAL_URI = "ipfs://template-uri";

    string[] globalFields;
    string[] partyFields;
    string[] globalValues;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (partyA, partyAKey) = makeAddrAndKey("partyA");
        (partyB, partyBKey) = makeAddrAndKey("partyB");

        vm.startPrank(owner);
        BorgAuth auth = new BorgAuth(owner);
        registry = new CyberAgreementRegistry();
        registry.initialize(address(auth));

        globalFields = new string[](1);
        globalFields[0] = "globalField1";
        partyFields = new string[](1);
        partyFields[0] = "partyField1";
        globalValues = new string[](1);
        globalValues[0] = "globalValue1";

        registry.createTemplate(TEMPLATE_ID, "Test", LEGAL_URI, globalFields, partyFields);
        vm.stopPrank();
    }

    function _parties() internal view returns (address[] memory p, string[][] memory v) {
        p = new address[](2);
        p[0] = partyA;
        p[1] = partyB;
        v = new string[][](2);
        v[0] = new string[](1);
        v[0][0] = "valueA";
        v[1] = new string[](1);
        v[1][0] = "valueB";
    }

    function _capsules72() internal pure returns (bytes memory a, bytes memory b) {
        a = new bytes(72);
        b = new bytes(72);
        a[0] = 0xAA;
        b[0] = 0xBB;
    }

    // ── registerViewingPubKey ────────────────────────────────────────────────

    function test_registerViewingPubKey_storesAndEmits() public {
        bytes32 pubKey = bytes32(uint256(0xDEAD));

        vm.prank(partyA);
        vm.expectEmit(true, true, false, true);
        emit CyberAgreementRegistry.ViewingPubKeyRegistered(partyA, pubKey);
        registry.registerViewingPubKey(pubKey);

        assertEq(registry.viewingPubKeys(partyA), pubKey);
    }

    function test_registerViewingPubKey_eachPartyIndependent() public {
        bytes32 keyA = bytes32(uint256(0xAAAA));
        bytes32 keyB = bytes32(uint256(0xBBBB));

        vm.prank(partyA);
        registry.registerViewingPubKey(keyA);
        vm.prank(partyB);
        registry.registerViewingPubKey(keyB);

        assertEq(registry.viewingPubKeys(partyA), keyA);
        assertEq(registry.viewingPubKeys(partyB), keyB);
    }

    function test_registerViewingPubKey_cannotOverrideAnotherPartysKey() public {
        bytes32 keyA = bytes32(uint256(0xAAAA));

        vm.prank(partyA);
        registry.registerViewingPubKey(keyA);

        // partyB registers under their own address — partyA's slot is unaffected
        vm.prank(partyB);
        registry.registerViewingPubKey(bytes32(uint256(0xBEEF)));

        assertEq(registry.viewingPubKeys(partyA), keyA);
    }

    function test_registerViewingPubKey_zeroKeyClears() public {
        bytes32 keyA = bytes32(uint256(0xAAAA));

        vm.prank(partyA);
        registry.registerViewingPubKey(keyA);
        assertEq(registry.viewingPubKeys(partyA), keyA);

        // Overwrite with zero — treated as "no registration" by consistency check
        vm.prank(partyA);
        registry.registerViewingPubKey(bytes32(0));
        assertEq(registry.viewingPubKeys(partyA), bytes32(0));

        // createContract should now accept any pubkey for partyA without reverting
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xDEAD)); // would have mismatched keyA
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );

        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), pubKeys[0]);
    }

    // ── createContract (8-param) — STK getters return empty ─────────────────

    function test_createContract_8param_stkGettersReturnEmpty() public {
        (address[] memory p, string[][] memory v) = _parties();

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0
        );

        assertEq(registry.getCapsule(contractId, partyA).length, 0);
        assertEq(registry.getCapsule(contractId, partyB).length, 0);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), bytes32(0));
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), bytes32(0));
    }

    // ── createContract (10-param) — zero-length ECDH arrays ─────────────────

    function test_createContract_10param_emptyECDHArrays_stkGettersReturnEmpty() public {
        (address[] memory p, string[][] memory v) = _parties();

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            new bytes32[](0), new bytes[](0)
        );

        assertEq(registry.getCapsule(contractId, partyA).length, 0);
        assertEq(registry.getCapsule(contractId, partyB).length, 0);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), bytes32(0));
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), bytes32(0));
    }

    // ── createContract (10-param) — happy path ───────────────────────────────

    function test_createContract_10param_storesCapsulesAndPubKeys() public {
        (address[] memory p, string[][] memory v) = _parties();
        (bytes memory capsA, bytes memory capsB) = _capsules72();

        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xAAAA));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = capsA;
        capsules[1] = capsB;

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );

        assertEq(registry.getCapsule(contractId, partyA), capsA);
        assertEq(registry.getCapsule(contractId, partyB), capsB);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), pubKeys[0]);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), pubKeys[1]);
    }

    function test_createContract_10param_emitsCapsuleStored() public {
        (address[] memory p, string[][] memory v) = _parties();
        (bytes memory capsA, bytes memory capsB) = _capsules72();

        bytes32 pubKeyA = bytes32(uint256(0xAAAA));
        bytes32 pubKeyB = bytes32(uint256(0xBBBB));
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = pubKeyA;
        pubKeys[1] = pubKeyB;
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = capsA;
        capsules[1] = capsB;

        bytes32 expectedId = keccak256(abi.encode(TEMPLATE_ID, uint256(0), globalValues, p));

        vm.prank(partyA);
        vm.expectEmit(true, true, false, true);
        emit CyberAgreementRegistry.CapsuleStored(expectedId, partyA, pubKeyA);
        registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );
    }

    // ── createContract (10-param) — revert cases ────────────────────────────

    function test_createContract_10param_revertsOnMismatchedPubKeysLength() public {
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](1);
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.MismatchedViewingPubKeysLength.selector);
        registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );
    }

    function test_createContract_10param_revertsOnMismatchedCapsulesLength() public {
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        bytes[] memory capsules = new bytes[](1);
        capsules[0] = new bytes(72);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.MismatchedCapsulesLength.selector);
        registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );
    }

    function test_createContract_10param_revertsOnInvalidCapsuleLength() public {
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(71);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.InvalidCapsuleLength.selector);
        registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );
    }

    // ── ViewingPubKeyMismatch ────────────────────────────────────────────────

    function test_createContract_10param_revertsWhenPubKeyMismatchesGlobalRegistration() public {
        bytes32 registeredKey = bytes32(uint256(0xAAAA));
        vm.prank(partyA);
        registry.registerViewingPubKey(registeredKey);

        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xBEEF));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.ViewingPubKeyMismatch.selector);
        registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );
    }

    function test_createContract_10param_passesWhenPubKeyMatchesGlobalRegistration() public {
        bytes32 registeredKey = bytes32(uint256(0xAAAA));
        vm.prank(partyA);
        registry.registerViewingPubKey(registeredKey);

        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = registeredKey;
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );

        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), registeredKey);
    }

    function test_createContract_10param_passesWithNoGlobalRegistration() public {
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xAAAA));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        vm.prank(partyA);
        bytes32 contractId = registry.createContract(
            TEMPLATE_ID, 0, globalValues, p, v, bytes32(0), address(0), 0,
            pubKeys, capsules
        );

        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), pubKeys[0]);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), pubKeys[1]);
    }

    // ── createStandaloneContractAndSignFor (13-param) — zero-length ECDH arrays

    function test_createStandaloneContractAndSignFor_emptyECDHArrays_stkGettersReturnEmpty() public {
        uint256 salt = 100;
        (address[] memory p, string[][] memory v) = _parties();

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        bytes32 returnedId = registry.createStandaloneContractAndSignFor(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            partyA, sig,
            new bytes32[](0), new bytes[](0)
        );

        assertEq(returnedId, contractId);
        assertEq(registry.getCapsule(contractId, partyA).length, 0);
        assertEq(registry.getCapsule(contractId, partyB).length, 0);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), bytes32(0));
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), bytes32(0));
    }

    // ── createStandaloneContractAndSign ECDH ─────────────────────────────────

    string constant STANDALONE_TITLE = "Standalone Test";

    function _standaloneTemplateId() internal view returns (bytes32) {
        return keccak256(abi.encode(STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields));
    }

    function _standaloneContractId(uint256 salt, address[] memory p) internal view returns (bytes32) {
        return keccak256(abi.encode(_standaloneTemplateId(), salt, globalValues, p));
    }

    function _signForPartyA(bytes32 contractId, string[] memory partyValues) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            LEGAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues,
            partyAKey
        );
    }

    function test_createStandaloneContractAndSign_storesCapsulesAndPubKeys() public {
        uint256 salt = 1;
        (address[] memory p, string[][] memory v) = _parties();
        (bytes memory capsA, bytes memory capsB) = _capsules72();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xAAAA));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = capsA;
        capsules[1] = capsB;

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        bytes32 returnedId = registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );

        assertEq(returnedId, contractId);
        assertEq(registry.getCapsule(contractId, partyA), capsA);
        assertEq(registry.getCapsule(contractId, partyB), capsB);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), pubKeys[0]);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), pubKeys[1]);
    }

    function test_createStandaloneContractAndSign_emitsCapsuleStored() public {
        uint256 salt = 2;
        (address[] memory p, string[][] memory v) = _parties();
        (bytes memory capsA,) = _capsules72();
        bytes32 pubKeyA = bytes32(uint256(0xAAAA));
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = pubKeyA;
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = capsA;
        capsules[1] = new bytes(72);

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        vm.expectEmit(true, true, false, true);
        emit CyberAgreementRegistry.CapsuleStored(contractId, partyA, pubKeyA);
        registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );
    }

    function test_createStandaloneContractAndSign_revertsOnMismatchedPubKeysLength() public {
        uint256 salt = 3;
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](1);
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.MismatchedViewingPubKeysLength.selector);
        registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );
    }

    function test_createStandaloneContractAndSign_revertsOnMismatchedCapsulesLength() public {
        uint256 salt = 4;
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        bytes[] memory capsules = new bytes[](1);
        capsules[0] = new bytes(72);

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.MismatchedCapsulesLength.selector);
        registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );
    }

    function test_createStandaloneContractAndSign_revertsOnInvalidCapsuleLength() public {
        uint256 salt = 5;
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(71);
        capsules[1] = new bytes(72);

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.InvalidCapsuleLength.selector);
        registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );
    }

    function test_createStandaloneContractAndSign_revertsOnViewingPubKeyMismatch() public {
        bytes32 registeredKey = bytes32(uint256(0xAAAA));
        vm.prank(partyA);
        registry.registerViewingPubKey(registeredKey);

        uint256 salt = 6;
        (address[] memory p, string[][] memory v) = _parties();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xBEEF));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = new bytes(72);
        capsules[1] = new bytes(72);

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        vm.expectRevert(CyberAgreementRegistry.ViewingPubKeyMismatch.selector);
        registry.createStandaloneContractAndSign(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            sig, pubKeys, capsules
        );
    }

    function test_createStandaloneContractAndSignFor_storesCapsulesAndPubKeys() public {
        uint256 salt = 7;
        (address[] memory p, string[][] memory v) = _parties();
        (bytes memory capsA, bytes memory capsB) = _capsules72();
        bytes32[] memory pubKeys = new bytes32[](2);
        pubKeys[0] = bytes32(uint256(0xAAAA));
        pubKeys[1] = bytes32(uint256(0xBBBB));
        bytes[] memory capsules = new bytes[](2);
        capsules[0] = capsA;
        capsules[1] = capsB;

        bytes32 contractId = _standaloneContractId(salt, p);
        bytes memory sig = _signForPartyA(contractId, v[0]);

        vm.prank(partyA);
        bytes32 returnedId = registry.createStandaloneContractAndSignFor(
            STANDALONE_TITLE, LEGAL_URI, globalFields, partyFields,
            salt, globalValues, p, v, 0,
            partyA, sig,
            pubKeys, capsules
        );

        assertEq(returnedId, contractId);
        assertEq(registry.getCapsule(contractId, partyA), capsA);
        assertEq(registry.getCapsule(contractId, partyB), capsB);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyA), pubKeys[0]);
        assertEq(registry.getAgreementViewingPubKey(contractId, partyB), pubKeys[1]);
    }
}
