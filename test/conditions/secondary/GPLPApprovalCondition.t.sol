// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {GPLPApprovalCondition} from "../../../src/libs/conditions/secondary/GPLPApprovalCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// GPLPApprovalCondition — per-deal GP/LP manual approval gate.
//
// Legal/economic intent: where governing documents require manual approval or LP-level consents
// (spousal, co-investor), the deal cannot clear until the DealManager's designated approver signs off
// on the specific deal — the offerId (pre-approving every settlement) or a specific
// settlementAgreementId. Silent at posting; withdrawal bites at finalize (conditions re-run there).
//
// Real integration: approvals are keyed by the real DealManager and gated on its BorgAuth (setApprover =
// owner, setDealApproval = the approver). The condition never reads the offer/escrow, so a real posted
// offer + accepted settlement supply the offerId/settlementId keys.
//
// Scenario × outcome
// | # | context   | approval present            | expect | rationale                     |
// |---|-----------|-----------------------------|:------:|-------------------------------|
// | 1 | posting   | n/a                         |  pass  | no settlement yet             |
// | 2 | accepted  | none                        |  fail  | approval outstanding          |
// | 3 | accepted  | approved on offerId         |  pass  | offer-level pre-approval      |
// | 4 | accepted  | approved on settlementId    |  pass  | settlement-level approval     |
// | 5 | accepted  | approved then withdrawn     |  fail  | withdrawal bites              |
//
// Config/authorization
// | # | case                             | expect                    |
// |---|----------------------------------|---------------------------|
// | 6 | setApprover by non-owner         | revert (not owner)        |
// | 7 | setApprover zero dealManager     | revert InvalidDealManager |
// | 8 | setDealApproval by non-approver  | revert NotApprover        |
// | 9 | setDealApproval zero dealId      | revert InvalidDealId      |
// ─────────────────────────────────────────────────────────────────────────────

contract GPLPApprovalConditionTest is SecondaryConditionIntegrationBase {
    GPLPApprovalCondition internal gplp;
    address internal approver = makeAddr("approver");
    bytes32 internal offerId;
    bytes32 internal settlementId;

    function setUp() public {
        _setUpIntegration();
        gplp = GPLPApprovalCondition(
            _proxy(
                address(new GPLPApprovalCondition()), abi.encodeCall(GPLPApprovalCondition.initialize, (address(auth)))
            )
        );
        gplp.setApprover(address(dm), approver);
        (offerId, settlementId) = _postAndAcceptSell();
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return gplp.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    function _approve(bytes32 dealId, bool approved) internal {
        vm.prank(approver);
        gplp.setDealApproval(address(dm), dealId, approved);
    }

    // 1
    function test_Posting_Silent_Passes() public view {
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_Accepted_NoApproval_Fails() public view {
        assertFalse(_check(settlementId));
    }

    // 3
    function test_Accepted_ApprovedOnOffer_Passes() public {
        _approve(offerId, true);
        assertTrue(_check(settlementId));
    }

    // 4
    function test_Accepted_ApprovedOnSettlement_Passes() public {
        _approve(settlementId, true);
        assertTrue(_check(settlementId));
    }

    // 5
    function test_Accepted_ApprovalWithdrawn_Fails() public {
        _approve(offerId, true);
        assertTrue(_check(settlementId));
        _approve(offerId, false);
        assertFalse(_check(settlementId));
    }

    // 6
    function test_SetApprover_ByNonOwner_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        gplp.setApprover(address(dm), approver);
    }

    // 7
    function test_SetApprover_ZeroDealManager_Reverts() public {
        vm.expectRevert(GPLPApprovalCondition.InvalidDealManager.selector);
        gplp.setApprover(address(0), approver);
    }

    // 8
    function test_SetDealApproval_ByNonApprover_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert(GPLPApprovalCondition.NotApprover.selector);
        gplp.setDealApproval(address(dm), offerId, true);
    }

    // 9
    function test_SetDealApproval_ZeroDealId_Reverts() public {
        vm.prank(approver);
        vm.expectRevert(GPLPApprovalCondition.InvalidDealId.selector);
        gplp.setDealApproval(address(dm), bytes32(0), true);
    }
}
