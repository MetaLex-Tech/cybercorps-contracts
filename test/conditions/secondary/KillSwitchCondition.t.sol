// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {KillSwitchCondition} from "../../../src/libs/conditions/secondary/KillSwitchCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// KillSwitchCondition — finalization kill switch (closing condition).
//
// Legal/economic intent: an emergency brake on settlement, at two scopes. Two admin slots (MetaLeX,
// Legion); either can raise a flag unilaterally (fast response), but lowering takes both (one
// proposes, the other confirms) so no single key can silently re-enable a trade. The platform-wide
// flag blocks every lot; a per-settlement flag blocks only its own agreement. Each admin can rotate
// its own key.
//
// Scenario × outcome
// |  # | scenario                                              | expect                       |
// |----|-------------------------------------------------------|------------------------------|
// |  1 | fresh deployment                                      | checkCondition true          |
// |  2 | global raised by MetaLeX admin                        | checkCondition false         |
// |  3 | global raised by Legion admin                         | checkCondition false         |
// |  4 | global raise by non-admin                             | revert NotKillAdmin          |
// |  5 | global raise while already killed                     | revert AlreadyKilled         |
// |  6 | global proposer tries to self-confirm the lower       | revert ProposerCannotConfirm |
// |  7 | global other admin confirms the lower                 | flag drops, checkCondition true |
// |  8 | global confirm with no pending proposal               | revert NoLowerProposal       |
// |  9 | global propose lower while not killed                 | revert NotKilled             |
// | 10 | rotate own slot: new key works, old key barred        | rotation effective           |
// | 11 | rotate to an existing admin address                   | revert InvalidAdmin          |
// | 12 | rotate by non-admin                                   | revert NotKillAdmin          |
// | 13 | construct with a zero admin                           | revert InvalidAdmin          |
// | 14 | construct with identical admins                       | revert InvalidAdmin          |
// | 15 | settlement raised: its lot blocked, another passes    | checkCondition false / true  |
// | 16 | settlement raise by non-admin                         | revert NotKillAdmin          |
// | 17 | settlement raise while already killed                 | revert AlreadyKilled         |
// | 18 | settlement proposer tries to self-confirm             | revert ProposerCannotConfirm |
// | 19 | settlement other admin confirms the lower             | flag drops, checkCondition true |
// | 20 | settlement confirm with no pending proposal           | revert NoLowerProposal       |
// | 21 | settlement propose lower while not killed             | revert NotKilled             |
// | 22 | global proposer rotates its own slot, then confirms   | revert ProposerNotAdmin      |
// | 23 | settlement proposer rotates its slot, then confirms   | revert ProposerNotAdmin      |
// | 24 | rotated slot re-proposes, other admin confirms        | flag drops, checkCondition true |
// ─────────────────────────────────────────────────────────────────────────────

contract KillSwitchConditionTest is SecondaryConditionIntegrationBase {
    KillSwitchCondition internal kill;
    address internal metalex = makeAddr("metalexAdmin");
    address internal legion = makeAddr("legionAdmin");

    // The kill switch is a standalone closing condition keyed only by settlement id; it never reads the
    // offer/escrow, so these ids are plain keys.
    bytes32 internal constant OFFER_ID = keccak256("offer");
    bytes32 internal constant AGREEMENT_ID = keccak256("settlement");
    bytes32 internal constant AGREEMENT_ID_2 = keccak256("settlement.other");

    function setUp() public {
        _setUpIntegration();
        kill = new KillSwitchCondition(metalex, legion);
    }

    function _check() internal view returns (bool) {
        return kill.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, AGREEMENT_ID);
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return kill.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_Fresh_NotKilled() public view {
        assertTrue(_check());
    }

    // 2
    function test_RaisedByMetalex_Blocks() public {
        vm.prank(metalex);
        kill.raiseKill();
        assertFalse(_check());
    }

    // 3
    function test_RaisedByLegion_Blocks() public {
        vm.prank(legion);
        kill.raiseKill();
        assertFalse(_check());
    }

    // 4
    function test_RaiseByNonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert(KillSwitchCondition.NotKillAdmin.selector);
        kill.raiseKill();
    }

    // 5
    function test_RaiseWhenAlreadyKilled_Reverts() public {
        vm.prank(metalex);
        kill.raiseKill();
        vm.prank(legion);
        vm.expectRevert(KillSwitchCondition.AlreadyKilled.selector);
        kill.raiseKill();
    }

    // 6 & 7
    function test_TwoCallLower() public {
        vm.prank(metalex);
        kill.raiseKill();

        vm.prank(metalex);
        kill.proposeLower();

        // 6 — proposer cannot also confirm
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.ProposerCannotConfirm.selector);
        kill.confirmLower();

        // 7 — the other admin confirms and the flag drops
        vm.prank(legion);
        kill.confirmLower();
        assertTrue(_check());
    }

    // 8
    function test_ConfirmWithoutProposal_Reverts() public {
        vm.prank(metalex);
        kill.raiseKill();
        vm.prank(legion);
        vm.expectRevert(KillSwitchCondition.NoLowerProposal.selector);
        kill.confirmLower();
    }

    // 9
    function test_ProposeWhenNotKilled_Reverts() public {
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.NotKilled.selector);
        kill.proposeLower();
    }

    // 10
    function test_RotateOwnSlot() public {
        address newMetalex = makeAddr("newMetalex");
        vm.prank(metalex);
        kill.rotateAdmin(newMetalex);

        // Old key is no longer an admin.
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.NotKillAdmin.selector);
        kill.raiseKill();

        // New key works.
        vm.prank(newMetalex);
        kill.raiseKill();
        assertFalse(_check());
    }

    // 11
    function test_RotateToExistingAdmin_Reverts() public {
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.InvalidAdmin.selector);
        kill.rotateAdmin(legion);
    }

    // 12
    function test_RotateByNonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert(KillSwitchCondition.NotKillAdmin.selector);
        kill.rotateAdmin(makeAddr("whoever"));
    }

    // 13
    function test_Construct_ZeroAdmin_Reverts() public {
        vm.expectRevert(KillSwitchCondition.InvalidAdmin.selector);
        new KillSwitchCondition(address(0), legion);
    }

    // 14
    function test_Construct_IdenticalAdmins_Reverts() public {
        vm.expectRevert(KillSwitchCondition.InvalidAdmin.selector);
        new KillSwitchCondition(metalex, metalex);
    }

    // 15 — targeted: kills its own lot, leaves a different settlement passing
    function test_SettlementKill_BlocksOnlyItsLot() public {
        vm.prank(legion);
        kill.raiseSettlementKill(AGREEMENT_ID);
        assertFalse(_check(AGREEMENT_ID));
        assertTrue(_check(AGREEMENT_ID_2));
    }

    // 16
    function test_SettlementRaiseByNonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert(KillSwitchCondition.NotKillAdmin.selector);
        kill.raiseSettlementKill(AGREEMENT_ID);
    }

    // 17
    function test_SettlementRaiseWhenAlreadyKilled_Reverts() public {
        vm.prank(metalex);
        kill.raiseSettlementKill(AGREEMENT_ID);
        vm.prank(legion);
        vm.expectRevert(KillSwitchCondition.AlreadyKilled.selector);
        kill.raiseSettlementKill(AGREEMENT_ID);
    }

    // 18 & 19
    function test_SettlementTwoCallLower() public {
        vm.prank(metalex);
        kill.raiseSettlementKill(AGREEMENT_ID);

        vm.prank(metalex);
        kill.proposeSettlementLower(AGREEMENT_ID);

        // 18 — proposer cannot also confirm
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.ProposerCannotConfirm.selector);
        kill.confirmSettlementLower(AGREEMENT_ID);

        // 19 — the other admin confirms and the flag drops
        vm.prank(legion);
        kill.confirmSettlementLower(AGREEMENT_ID);
        assertTrue(_check(AGREEMENT_ID));
    }

    // 20
    function test_SettlementConfirmWithoutProposal_Reverts() public {
        vm.prank(metalex);
        kill.raiseSettlementKill(AGREEMENT_ID);
        vm.prank(legion);
        vm.expectRevert(KillSwitchCondition.NoLowerProposal.selector);
        kill.confirmSettlementLower(AGREEMENT_ID);
    }

    // 21
    function test_SettlementProposeWhenNotKilled_Reverts() public {
        vm.prank(metalex);
        vm.expectRevert(KillSwitchCondition.NotKilled.selector);
        kill.proposeSettlementLower(AGREEMENT_ID);
    }

    // 22 — one admin must not lower alone by rotating to a second key it owns
    function test_ProposeThenRotateThenConfirm_Reverts() public {
        address newMetalex = makeAddr("newMetalex");

        vm.prank(metalex);
        kill.raiseKill();
        vm.prank(metalex);
        kill.proposeLower();
        vm.prank(metalex);
        kill.rotateAdmin(newMetalex);

        vm.prank(newMetalex);
        vm.expectRevert(KillSwitchCondition.ProposerNotAdmin.selector);
        kill.confirmLower();
        assertFalse(_check());
    }

    // 23
    function test_SettlementProposeThenRotateThenConfirm_Reverts() public {
        address newMetalex = makeAddr("newMetalex");

        vm.prank(metalex);
        kill.raiseSettlementKill(AGREEMENT_ID);
        vm.prank(metalex);
        kill.proposeSettlementLower(AGREEMENT_ID);
        vm.prank(metalex);
        kill.rotateAdmin(newMetalex);

        vm.prank(newMetalex);
        vm.expectRevert(KillSwitchCondition.ProposerNotAdmin.selector);
        kill.confirmSettlementLower(AGREEMENT_ID);
        assertFalse(_check(AGREEMENT_ID));
    }

    // 24 — a rotation does not brick the switch; two current admins still lower it
    function test_LowerAfterRotation_Works() public {
        address newMetalex = makeAddr("newMetalex");

        vm.prank(metalex);
        kill.raiseKill();
        vm.prank(metalex);
        kill.proposeLower();
        vm.prank(metalex);
        kill.rotateAdmin(newMetalex);

        vm.prank(newMetalex);
        kill.proposeLower();
        vm.prank(legion);
        kill.confirmLower();
        assertTrue(_check());
    }
}
