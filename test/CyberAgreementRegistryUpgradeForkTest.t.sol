// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ICyberAgreementRegistry} from "../src/interfaces/ICyberAgreementRegistry.sol";
import {UpgradeCoreRegistryHarness} from "./createx/UpgradeCoreRegistryForkTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @notice Upgrades the live Base registry from the single-contract version to the router, through the
///         `UpgradeCoreScript` Safe batch. Live data must read the same, and every flow must work after it.
/// @dev The fork is pinned, so the live state and the batch are always the same.
contract CyberAgreementRegistryUpgradeForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 53_264_116;
    bytes32 internal constant LIVE_AGREEMENT_ID = 0x78f6ea3db4c0a2d53384b845ccdaa42419787e6c12fa618594eba1704f10dd84;
    uint256 internal constant DEPLOYER_KEY = 0xA11CE;

    CyberAgreementRegistry internal registry;
    address internal oldImplementation;
    address internal liveParty;
    bytes32 internal liveTemplateId;
    bytes[] internal liveViewCalls;
    bytes[] internal liveViewResults;

    address internal alice;
    uint256 internal aliceKey;
    address internal bob;
    uint256 internal bobKey;
    address internal chad;
    uint256 internal chadKey;

    bytes32 internal templateId = keccak256("CyberAgreementRegistryUpgradeForkTest");
    string internal legalContractUri = "ipfs://upgrade-fork-test";
    string[] internal globalFields;
    string[] internal partyFields;
    string[] internal globalValues;
    address[] internal parties;
    string[][] internal partyValues;
    bytes32 internal pendingId;
    bytes32 internal domainSeparator;
    bytes32 internal signatureTypehash;

    function setUp() public {
        vm.createSelectFork("base", PINNED_BLOCK);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        registry = CyberAgreementRegistry(core.cyberAgreementRegistry);
        oldImplementation = _implementation();
        domainSeparator = registry.DOMAIN_SEPARATOR();
        signatureTypehash = registry.SIGNATUREDATA_TYPEHASH();
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (chad, chadKey) = makeAddrAndKey("chad");
        _setUpAgreementData();

        _recordLiveViews();
        _createPendingAgreementOnOldImplementation();

        vm.deal(vm.addr(DEPLOYER_KEY), 100 ether);
        GnosisTransaction[] memory safeTxs =
            (new UpgradeCoreRegistryHarness()).runRegistryWithArgs(block.chainid, DEPLOYER_KEY);
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(core.metalexSafe);
            (bool success, bytes memory result) = safeTxs[i].to.call(safeTxs[i].data);
            assertTrue(success, vm.toString(result));
        }
    }

    function test_UpgradeSwitchesProxyToRouter() public view {
        assertNotEq(_implementation(), oldImplementation);
        assertNotEq(registry.facetOf(ICyberAgreementRegistry.createContract.selector), address(0));
        assertNotEq(registry.facetOf(CyberAgreementRegistry.boundIdsOf.selector), address(0));
        assertNotEq(registry.facetOf(ICyberAgreementRegistry.getContractJson.selector), address(0));
    }

    function test_LiveDataReadsSameAfterUpgrade() public {
        for (uint256 i = 0; i < liveViewCalls.length; i++) {
            (bool success, bytes memory result) = address(registry).staticcall(liveViewCalls[i]);
            assertTrue(success, vm.toString(liveViewCalls[i]));
            assertEq(result, liveViewResults[i], vm.toString(liveViewCalls[i]));
        }
    }

    function test_AgreementSignedOnOldImplementationCompletesAfterUpgrade() public {
        assertTrue(registry.hasSigned(pendingId, alice));
        assertFalse(registry.isFinalized(pendingId));

        vm.prank(bob);
        registry.signContract(pendingId, partyValues[1], _sign(pendingId, 1, bobKey), false, "");

        assertTrue(registry.allPartiesSigned(pendingId));
        assertTrue(registry.isFinalized(pendingId));
    }

    function test_NewAgreementSignsAndFinalizesAfterUpgrade() public {
        bytes32 id = _createContract(1);

        vm.prank(alice);
        registry.signContract(id, partyValues[0], _sign(id, 0, aliceKey), false, "");
        vm.prank(bob);
        registry.signContract(id, partyValues[1], _sign(id, 1, bobKey), false, "");

        assertTrue(registry.isFinalized(id));
        assertEq(registry.getAgreementsForParty(alice)[1], id);
        assertGt(bytes(registry.getContractJson(id)).length, 0);
    }

    function test_NewAgreementVoidsAfterUpgrade() public {
        bytes32 id = _createContract(2);
        vm.prank(alice);
        registry.signContract(id, partyValues[0], _sign(id, 0, aliceKey), false, "");

        bytes memory voidSignature = CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), id, alice, aliceKey
        );
        registry.voidContractFor(id, alice, voidSignature);

        assertTrue(registry.isVoided(id));
        assertEq(registry.getVoidRequestedBy(id)[0], alice);
    }

    function test_DelegateSignsAfterUpgrade() public {
        vm.prank(alice);
        registry.setDelegation(chad, 0);
        assertTrue(registry.isValidDelegate(alice, chad));

        bytes32 id = _createContract(3);
        registry.signContractFor(alice, id, partyValues[0], _sign(id, 0, chadKey), false, "");
        assertTrue(registry.hasSigned(id, alice));

        vm.prank(alice);
        registry.revokeDelegation();
        assertFalse(registry.isValidDelegation(alice));
    }

    function test_BoundAgreementSignsAfterUpgrade() public {
        ICyberAgreementRegistry.Template memory template = ICyberAgreementRegistry.Template({
            legalContractUri: legalContractUri, title: "Bound", globalFields: globalFields, partyFields: partyFields
        });
        vm.prank(alice);
        (, bytes32 id) =
            registry.createBoundContract(template, 1, globalValues, parties, partyValues, block.timestamp + 1 days);

        vm.prank(alice);
        registry.signContract(id, partyValues[0], _sign(id, 0, aliceKey), false, "");
        vm.prank(bob);
        registry.signContract(id, partyValues[1], _sign(id, 1, bobKey), false, "");

        assertTrue(registry.isFinalized(id));
    }

    function _setUpAgreementData() internal {
        globalFields = new string[](1);
        globalFields[0] = "Purpose";
        partyFields = new string[](1);
        partyFields[0] = "Name";
        globalValues = new string[](1);
        globalValues[0] = "Upgrade check";
        parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;
        partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Alice";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Bob";
    }

    function _recordLiveViews() internal {
        liveParty = registry.getParties(LIVE_AGREEMENT_ID)[0];
        (liveTemplateId,,,,,,,,,) = registry.getContractDetails(LIVE_AGREEMENT_ID);

        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.version, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.name, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.AUTH, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.DOMAIN_SEPARATOR, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.SIGNATUREDATA_TYPEHASH, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.VOIDSIGNATUREDATA_TYPEHASH, ()));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.templates, (liveTemplateId)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getTemplateDetails, (liveTemplateId)));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.agreements, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getContractDetails, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getParties, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getContractJson, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.getVoidRequestedBy, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.isFinalized, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.isVoided, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.allPartiesSigned, (LIVE_AGREEMENT_ID)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.hasSigned, (LIVE_AGREEMENT_ID, liveParty)));
        liveViewCalls.push(
            abi.encodeCall(ICyberAgreementRegistry.getSignatureTimestamp, (LIVE_AGREEMENT_ID, liveParty))
        );
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getSignerValues, (LIVE_AGREEMENT_ID, liveParty)));
        liveViewCalls.push(abi.encodeCall(ICyberAgreementRegistry.getAgreementsForParty, (liveParty)));
        liveViewCalls.push(abi.encodeCall(CyberAgreementRegistry.delegations, (liveParty)));

        for (uint256 i = 0; i < liveViewCalls.length; i++) {
            (bool success, bytes memory result) = address(registry).staticcall(liveViewCalls[i]);
            assertTrue(success, vm.toString(liveViewCalls[i]));
            liveViewResults.push(result);
        }
    }

    function _createPendingAgreementOnOldImplementation() internal {
        registry.createTemplate(templateId, "Upgrade check", legalContractUri, globalFields, partyFields);
        pendingId = _createContract(0);
        vm.prank(alice);
        registry.signContract(pendingId, partyValues[0], _sign(pendingId, 0, aliceKey), false, "");
    }

    function _createContract(uint256 salt) internal returns (bytes32) {
        return registry.createContract(
            templateId, salt, globalValues, parties, partyValues, bytes32(0), address(0), block.timestamp + 1 days
        );
    }

    /// @dev Signs for the party at `partyIndex` with `key`, which can be the party's delegate. Makes no registry
    ///      call, so a `vm.prank` before the sign call still applies to it.
    function _sign(bytes32 id, uint256 partyIndex, uint256 key) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            domainSeparator,
            signatureTypehash,
            id,
            legalContractUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[partyIndex],
            parties[partyIndex],
            key
        );
    }

    function _implementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(registry), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }
}
