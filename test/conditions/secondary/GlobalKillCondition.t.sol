// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {GlobalKillCondition} from "../../../src/libs/conditions/secondary/GlobalKillCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// GlobalKillCondition — platform-wide finalization kill switch (closing condition).
//
// Legal/economic intent: an emergency brake on settlement. Two admin slots (MetaLeX, Legion); either
// can raise the flag unilaterally (fast response), but lowering takes both (one proposes, the other
// confirms) so no single key can silently re-enable the platform. While raised, finalization is
// blocked platform-wide. Each admin can rotate its own key.
//
// Scenario × outcome
// |  # | scenario                                        | expect                       |
// |----|-------------------------------------------------|------------------------------|
// |  1 | fresh deployment                                | checkCondition true          |
// |  2 | raised by MetaLeX admin                         | checkCondition false         |
// |  3 | raised by Legion admin                          | checkCondition false         |
// |  4 | raise by non-admin                              | revert NotKillAdmin          |
// |  5 | raise while already killed                      | revert AlreadyKilled         |
// |  6 | proposer tries to self-confirm the lower        | revert ProposerCannotConfirm |
// |  7 | other admin confirms the lower                  | flag drops, checkCondition true |
// |  8 | confirm with no pending proposal                | revert NoLowerProposal       |
// |  9 | propose lower while not killed                  | revert NotKilled             |
// | 10 | rotate own slot: new key works, old key barred  | rotation effective           |
// | 11 | rotate to an existing admin address             | revert InvalidAdmin          |
// | 12 | rotate by non-admin                             | revert NotKillAdmin          |
// | 13 | construct with a zero admin                      | revert InvalidAdmin          |
// | 14 | construct with identical admins                  | revert InvalidAdmin          |
// ─────────────────────────────────────────────────────────────────────────────

contract GlobalKillConditionTest is SecondaryConditionTestBase {
    GlobalKillCondition internal kill;
    address internal metalex = makeAddr("metalexAdmin");
    address internal legion = makeAddr("legionAdmin");

    function setUp() public {
        _setUpBase();
        kill = new GlobalKillCondition(metalex, legion);
    }

    function _check() internal view returns (bool) {
        return kill.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, AGREEMENT_ID);
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
        vm.expectRevert(GlobalKillCondition.NotKillAdmin.selector);
        kill.raiseKill();
    }

    // 5
    function test_RaiseWhenAlreadyKilled_Reverts() public {
        vm.prank(metalex);
        kill.raiseKill();
        vm.prank(legion);
        vm.expectRevert(GlobalKillCondition.AlreadyKilled.selector);
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
        vm.expectRevert(GlobalKillCondition.ProposerCannotConfirm.selector);
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
        vm.expectRevert(GlobalKillCondition.NoLowerProposal.selector);
        kill.confirmLower();
    }

    // 9
    function test_ProposeWhenNotKilled_Reverts() public {
        vm.prank(metalex);
        vm.expectRevert(GlobalKillCondition.NotKilled.selector);
        kill.proposeLower();
    }

    // 10
    function test_RotateOwnSlot() public {
        address newMetalex = makeAddr("newMetalex");
        vm.prank(metalex);
        kill.rotateAdmin(newMetalex);

        // Old key is no longer an admin.
        vm.prank(metalex);
        vm.expectRevert(GlobalKillCondition.NotKillAdmin.selector);
        kill.raiseKill();

        // New key works.
        vm.prank(newMetalex);
        kill.raiseKill();
        assertFalse(_check());
    }

    // 11
    function test_RotateToExistingAdmin_Reverts() public {
        vm.prank(metalex);
        vm.expectRevert(GlobalKillCondition.InvalidAdmin.selector);
        kill.rotateAdmin(legion);
    }

    // 12
    function test_RotateByNonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert(GlobalKillCondition.NotKillAdmin.selector);
        kill.rotateAdmin(makeAddr("whoever"));
    }

    // 13
    function test_Construct_ZeroAdmin_Reverts() public {
        vm.expectRevert(GlobalKillCondition.InvalidAdmin.selector);
        new GlobalKillCondition(address(0), legion);
    }

    // 14
    function test_Construct_IdenticalAdmins_Reverts() public {
        vm.expectRevert(GlobalKillCondition.InvalidAdmin.selector);
        new GlobalKillCondition(metalex, metalex);
    }
}
