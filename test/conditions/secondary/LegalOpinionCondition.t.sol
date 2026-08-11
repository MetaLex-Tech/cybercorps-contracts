// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LegalOpinionCondition} from "../../../src/libs/conditions/secondary/LegalOpinionCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LegalOpinionCondition — §4(a)(1½) GP/issuer-counsel assurance gate.
//
// Legal/economic intent: a §4(a)(1½) resale needs the GP's compliance sign-off or a formal legal
// opinion. Each SPV chooses the mechanism (EITHER by default, or only GP sign-off, or only a formal
// opinion). Assurance is per-deal — keyed by the offerId (pre-approving every settlement) or a
// specific settlementAgreementId — and is silent at posting. Revoking sign-off bites at finalize
// because threshold conditions re-run there.
//
// Real integration: the mechanism is keyed by the SPV (offer.spvAddress = corp); sign-offs/opinions are
// keyed by the DealManager. offerId/settlementId come from a real posted+accepted sell offer.
//
// Scenario × outcome
// | # | mechanism | context  | assurance present            | expect | rationale                     |
// |---|-----------|----------|------------------------------|:------:|-------------------------------|
// | 1 | EITHER    | posting  | none                         |  pass  | silent, no settlement yet     |
// | 2 | EITHER    | accepted | none                         |  fail  | no assurance recorded         |
// | 3 | EITHER    | accepted | GP sign-off on offerId       |  pass  | offer-level pre-approval      |
// | 4 | EITHER    | accepted | GP sign-off on settlementId  |  pass  | settlement-level approval     |
// | 5 | EITHER    | accepted | formal opinion on offerId    |  pass  | opinion satisfies             |
// | 6 | GP_SIGNOFF| accepted | formal opinion only          |  fail  | mechanism requires sign-off   |
// | 7 | GP_SIGNOFF| accepted | GP sign-off                  |  pass  | mechanism satisfied           |
// | 8 | FORMAL    | accepted | GP sign-off only             |  fail  | mechanism requires opinion    |
// | 9 | EITHER    | accepted | sign-off recorded then revoked|  fail | revocation bites at finalize  |
//
// Config/authorization
// | # | case                              | expect                 |
// |---|-----------------------------------|------------------------|
// |10 | recordGPSignOff zero dealManager  | revert InvalidDealManager |
// |11 | recordGPSignOff zero dealId       | revert InvalidDealId   |
// |12 | recordGPSignOff by non-admin      | revert (not admin)     |
// |13 | submitOpinion zero hash           | revert InvalidOpinionHash |
// |14 | setMechanism by non-SPV-admin     | revert (not admin)     |
// ─────────────────────────────────────────────────────────────────────────────

contract LegalOpinionConditionTest is SecondaryConditionIntegrationBase {
    LegalOpinionCondition internal legal;
    bytes32 internal offerId;
    bytes32 internal settlementId;

    function setUp() public {
        _setUpIntegration();
        legal = LegalOpinionCondition(
            _proxy(
                address(new LegalOpinionCondition()), abi.encodeCall(LegalOpinionCondition.initialize, (address(auth)))
            )
        );
        (offerId, settlementId) = _postAndAcceptSell();
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return legal.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // 1
    function test_Posting_Silent_Passes() public view {
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_Accepted_NoAssurance_Fails() public view {
        assertFalse(_check(settlementId));
    }

    // 3
    function test_Either_SignOffOnOffer_Passes() public {
        legal.recordGPSignOff(address(dm), offerId);
        assertTrue(_check(settlementId));
    }

    // 4
    function test_Either_SignOffOnSettlement_Passes() public {
        legal.recordGPSignOff(address(dm), settlementId);
        assertTrue(_check(settlementId));
    }

    // 5
    function test_Either_FormalOpinion_Passes() public {
        legal.submitOpinion(address(dm), offerId, keccak256("opinion"), "ipfs://opinion");
        assertTrue(_check(settlementId));
    }

    // 6
    function test_GpSignoffMechanism_OpinionOnly_Fails() public {
        legal.setMechanism(address(corp), LegalOpinionCondition.OpinionMechanism.GP_SIGNOFF);
        legal.submitOpinion(address(dm), offerId, keccak256("opinion"), "ipfs://opinion");
        assertFalse(_check(settlementId));
    }

    // 7
    function test_GpSignoffMechanism_SignOff_Passes() public {
        legal.setMechanism(address(corp), LegalOpinionCondition.OpinionMechanism.GP_SIGNOFF);
        legal.recordGPSignOff(address(dm), offerId);
        assertTrue(_check(settlementId));
    }

    // 8
    function test_FormalMechanism_SignOffOnly_Fails() public {
        legal.setMechanism(address(corp), LegalOpinionCondition.OpinionMechanism.FORMAL_OPINION);
        legal.recordGPSignOff(address(dm), offerId);
        assertFalse(_check(settlementId));
    }

    // 9
    function test_SignOffRevoked_Fails() public {
        legal.recordGPSignOff(address(dm), offerId);
        assertTrue(_check(settlementId));
        legal.revokeGPSignOff(address(dm), offerId);
        assertFalse(_check(settlementId));
    }

    // 10
    function test_RecordSignOff_ZeroDealManager_Reverts() public {
        vm.expectRevert(LegalOpinionCondition.InvalidDealManager.selector);
        legal.recordGPSignOff(address(0), offerId);
    }

    // 11
    function test_RecordSignOff_ZeroDealId_Reverts() public {
        vm.expectRevert(LegalOpinionCondition.InvalidDealId.selector);
        legal.recordGPSignOff(address(dm), bytes32(0));
    }

    // 12
    function test_RecordSignOff_ByNonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        legal.recordGPSignOff(address(dm), offerId);
    }

    // 13
    function test_SubmitOpinion_ZeroHash_Reverts() public {
        vm.expectRevert(LegalOpinionCondition.InvalidOpinionHash.selector);
        legal.submitOpinion(address(dm), offerId, bytes32(0), "ipfs://opinion");
    }

    // 14
    function test_SetMechanism_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        legal.setMechanism(address(corp), LegalOpinionCondition.OpinionMechanism.GP_SIGNOFF);
    }
}
