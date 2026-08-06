// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {TimeSettlementPeriodCondition} from "../../../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// TimeSettlementPeriodCondition — minimum delay between acceptance and finalization (closing).
//
// Legal/economic intent: a structural cooling-off window between acceptance and finalization — the
// intervention window for the Compromised Credential voidness provision and the kill switch, and the
// timer the keeper waits on. Default 24h from acceptance; per-DealManager overrides. The delay is
// measured from the escrow's stamped acceptedAt.
//
// Real integration: acceptedAt is stamped by a real acceptOffer, so we warp to the acceptance time A
// before accepting; the settlement window is set on the real DealManager. finalizableAt reads the real
// escrow's acceptedAt.
//
// Scenario × outcome (default delay 24h; acceptance at A, window 7d)
// | #  | scenario                                     | expect | rationale                          |
// |----|----------------------------------------------|:------:|------------------------------------|
// | 1  | posting (no settlement id)                   |  pass  | silent, evaluated at finalize      |
// | 2  | at acceptance (no time elapsed)              |  fail  | window not yet elapsed             |
// | 3  | exactly A + 24h                              |  pass  | window elapsed (>=)                |
// | 4  | finalizableAt == A + DEFAULT_DELAY           |  true  | getter matches                     |
// | 5  | delay override 2d: at A + 24h                |  fail  | longer window not yet elapsed      |
// | 6  | delay override 2d: at A + 2d                 |  pass  | overridden window elapsed          |
// | 7  | override back to 0 restores default          |  pass  | 0 == DEFAULT_DELAY                 |
// | 10 | window enlarged after acceptance              |  fail  | delay not shortened retroactively  |
// | 11 | window shrunk after acceptance               |  pass  | delay not extended, lot not stranded |
// | 12 | window set absurdly large                    |  pass  | no underflow in finalizableAt      |
// | 13 | two lots accepted under different windows    |  true  | each keeps its own basis           |
//
// Config/authorization
// | #  | case                                    | expect                            |
// |----|-----------------------------------------|-----------------------------------|
// | 8  | setDelayOverride zero dealManager        | revert InvalidDealManager         |
// | 9  | setDelayOverride by non-owner            | revert (not owner)                |
// | 14 | override >= settlement window            | revert DelayExceedsSettlementWindow |
// | 15 | override 0 when default >= window        | revert DelayExceedsSettlementWindow |
// ─────────────────────────────────────────────────────────────────────────────

contract TimeSettlementPeriodConditionTest is SecondaryConditionIntegrationBase {
    TimeSettlementPeriodCondition internal timing;
    uint256 internal constant A = 100 days; // acceptance timestamp
    uint256 internal constant WINDOW = 7 days;

    bytes32 internal offerId;
    bytes32 internal agreementId;

    function setUp() public {
        _setUpIntegration();
        timing = new TimeSettlementPeriodCondition();
        dm.setSettlementWindow(WINDOW);
        // Accept at A so the real escrow stamps acceptedAt = A, expiry = A + WINDOW.
        vm.warp(A);
        (offerId, agreementId) = _postAndAcceptSell();
    }

    function _check() internal view returns (bool) {
        return timing.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // 1
    function test_Posting_Silent_Passes() public view {
        assertTrue(timing.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
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
        assertEq(timing.finalizableAt(IDealManager(address(dm)), agreementId), A + timing.DEFAULT_DELAY());
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

    // 10 — enlarging the window must not slide the reconstructed acceptance backwards, erasing the delay
    function test_WindowEnlargedAfterAcceptance_DelayUnchanged() public {
        uint256 expected = timing.finalizableAt(IDealManager(address(dm)), agreementId);
        dm.setSettlementWindow(WINDOW + 2 days);
        assertEq(timing.finalizableAt(IDealManager(address(dm)), agreementId), expected);
        vm.warp(A + timing.DEFAULT_DELAY() - 1);
        assertFalse(_check());
        vm.warp(A + timing.DEFAULT_DELAY());
        assertTrue(_check());
    }

    // 11 — shrinking the window must not push the delay past the lot's expiry, stranding it
    function test_WindowShrunkAfterAcceptance_DelayUnchanged() public {
        uint256 expected = timing.finalizableAt(IDealManager(address(dm)), agreementId);
        dm.setSettlementWindow(2 days);
        assertEq(timing.finalizableAt(IDealManager(address(dm)), agreementId), expected);
        vm.warp(A + timing.DEFAULT_DELAY());
        assertTrue(_check());
    }

    // 12 — a window above the acceptance timestamp must not underflow the reconstruction
    function test_WindowLargerThanExpiry_NoUnderflow() public {
        dm.setSettlementWindow(A + WINDOW + 1 days);
        assertEq(timing.finalizableAt(IDealManager(address(dm)), agreementId), A + timing.DEFAULT_DELAY());
    }

    // 13 — two lots accepted at different times keep their own acceptedAt basis
    function test_LotsAcceptedUnderDifferentWindows_KeepOwnBasis() public {
        uint256 secondTokenId = _newSellerCert();
        uint256 secondAcceptedAt = A + 3 days;
        dm.setSettlementWindow(2 days);
        vm.warp(secondAcceptedAt);
        (, bytes32 secondId) = _postAndAcceptSellToken(secondTokenId, uint256(keccak256("secondLot")));

        assertEq(timing.finalizableAt(IDealManager(address(dm)), agreementId), A + timing.DEFAULT_DELAY());
        assertEq(
            timing.finalizableAt(IDealManager(address(dm)), secondId),
            secondAcceptedAt + timing.DEFAULT_DELAY()
        );
    }

    // 14
    function test_SetDelayOverride_AtOrAboveWindow_Reverts() public {
        vm.expectRevert(TimeSettlementPeriodCondition.DelayExceedsSettlementWindow.selector);
        timing.setDelayOverride(address(dm), WINDOW);
    }

    // 15
    function test_SetDelayOverride_ZeroWithDefaultAboveWindow_Reverts() public {
        dm.setSettlementWindow(1 hours);
        vm.expectRevert(TimeSettlementPeriodCondition.DelayExceedsSettlementWindow.selector);
        timing.setDelayOverride(address(dm), 0);
    }
}
