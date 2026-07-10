// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {TimeSettlementPeriodCondition} from "../../../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// TimeSettlementPeriodCondition — minimum delay between acceptance and finalization (closing).
//
// Legal/economic intent: a structural cooling-off window between acceptance and finalization — the
// intervention window for the Compromised Credential voidness provision and the Global Kill, and the
// timer the keeper waits on. Default 24h from acceptance; per-DealManager overrides. Acceptance time
// is reconstructed as escrow.expiry - settlementWindow.
//
// Scenario × outcome (default delay 24h; acceptance at A, window 7d, expiry = A + 7d)
// | # | scenario                                     | expect | rationale                          |
// |---|----------------------------------------------|:------:|------------------------------------|
// | 1 | posting (no settlement id)                   |  pass  | silent, evaluated at finalize      |
// | 2 | at acceptance (no time elapsed)              |  fail  | window not yet elapsed             |
// | 3 | exactly A + 24h                              |  pass  | window elapsed (>=)                |
// | 4 | finalizableAt == A + DEFAULT_DELAY           |  true  | getter matches                     |
// | 5 | delay override 2d: at A + 24h                 |  fail  | longer window not yet elapsed      |
// | 6 | delay override 2d: at A + 2d                  |  pass  | overridden window elapsed          |
// | 7 | override back to 0 restores default          |  pass  | 0 == DEFAULT_DELAY                  |
//
// Config/authorization
// | # | case                              | expect                  |
// |---|-----------------------------------|-------------------------|
// | 8 | setDelayOverride zero dealManager | revert InvalidDealManager |
// | 9 | setDelayOverride by non-owner     | revert (not owner)      |
// ─────────────────────────────────────────────────────────────────────────────

contract TimeSettlementPeriodConditionTest is SecondaryConditionTestBase {
    TimeSettlementPeriodCondition internal timing;
    uint256 internal constant A = 100 days; // acceptance timestamp
    uint256 internal constant WINDOW = 7 days;

    function setUp() public {
        _setUpBase();
        timing = new TimeSettlementPeriodCondition();
        dm.setSettlementWindow(WINDOW);
        SecondaryEscrow memory e = _sellEscrow();
        e.expiry = A + WINDOW; // acceptOffer stamps expiry = acceptance + window
        dm.setEscrow(AGREEMENT_ID, e);
    }

    function _check() internal view returns (bool) {
        return timing.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, AGREEMENT_ID);
    }

    // 1
    function test_Posting_Silent_Passes() public view {
        assertTrue(timing.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0)));
    }

    // 2
    function test_AtAcceptance_Fails() public {
        vm.warp(A);
        assertFalse(_check());
    }

    // 3
    function test_AtWindowEnd_Passes() public {
        vm.warp(A + timing.DEFAULT_DELAY());
        assertTrue(_check());
    }

    // 4
    function test_FinalizableAt_MatchesDefault() public view {
        assertEq(timing.finalizableAt(IDealManager(address(dm)), AGREEMENT_ID), A + timing.DEFAULT_DELAY());
    }

    // 5
    function test_Override2d_BeforeElapsed_Fails() public {
        timing.setDelayOverride(address(dm), 2 days);
        vm.warp(A + 1 days);
        assertFalse(_check());
    }

    // 6
    function test_Override2d_AfterElapsed_Passes() public {
        timing.setDelayOverride(address(dm), 2 days);
        vm.warp(A + 2 days);
        assertTrue(_check());
    }

    // 7
    function test_OverrideZero_RestoresDefault() public {
        timing.setDelayOverride(address(dm), 2 days);
        timing.setDelayOverride(address(dm), 0);
        assertEq(timing.delayFor(address(dm)), timing.DEFAULT_DELAY());
        vm.warp(A + timing.DEFAULT_DELAY());
        assertTrue(_check());
    }

    // 8
    function test_SetDelayOverride_ZeroDealManager_Reverts() public {
        vm.expectRevert(TimeSettlementPeriodCondition.InvalidDealManager.selector);
        timing.setDelayOverride(address(0), 1 days);
    }

    // 9
    function test_SetDelayOverride_ByNonOwner_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        timing.setDelayOverride(address(dm), 1 days);
    }
}
