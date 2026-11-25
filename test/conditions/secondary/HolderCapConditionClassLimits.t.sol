// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_ACCREDITED} from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {HolderCapCondition} from "../../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {HolderLimitTracker} from "../../../src/HolderLimitTracker.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

/// @dev Reverts on every call: stands in for a tracker that must never be read.
contract RevertEverything {
    fallback() external {
        revert("must not be read");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HolderCapCondition — section 12(g) limits read from the HolderLimitTracker.
//
// Real integration: each scenario posts and accepts a real sell offer on the printer of
// SecondaryConditionIntegrationBase, which reports to a real tracker. The seller holds the offered lot
// (weight 1, not accredited). The buyer is fresh and not accredited unless a test says otherwise.
//
// |  # | case                                                         | expect |
// |----|--------------------------------------------------------------|:------:|
// | C1 | class limits, condition has no tracker                       |  fail  |
// | C2 | class limits, printer does not report to the trusted tracker |  fail  |
// | C3 | class limits, book not yet backfilled, then backfilled       | fail, then pass |
// | C4 | non-accredited cap: lands on it / breaches it                | pass / fail |
// | C5 | accredited buyer at a full non-accredited cap                |  pass  |
// | C6 | existing holder at a full non-accredited cap                 |  pass  |
// | C7 | plan exclusion lets a fresh buyer under a full total cap     |  pass  |
// | C8 | plan-only holder buying is a new holder for the counts       | pass / fail |
// | C9 | plan-only holder whose credential lapsed keeps its booking   |  pass  |
// | C10| no class limits: the tracker is never read                   |  pass  |
// | S1-S8 | every setter path to usResidentOnlyCount + excludePlanOnly | revert |
// ─────────────────────────────────────────────────────────────────────────────
contract HolderCapConditionClassLimitsTest is SecondaryConditionIntegrationBase {
    HolderCapCondition internal holderCap;
    HolderLimitTracker internal tracker;
    address internal classX = makeAddr("class X");

    function setUp() public {
        _setUpIntegration();
        holderCap = HolderCapCondition(
            _proxy(address(new HolderCapCondition()), abi.encodeCall(HolderCapCondition.initialize, (address(auth))))
        );
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        tracker = _newTracker();
        holderCap.setHolderTracker(address(tracker));
        _attach(tracker);
    }

    function _newTracker() internal returns (HolderLimitTracker) {
        return HolderLimitTracker(
            _proxy(address(new HolderLimitTracker()), abi.encodeCall(HolderLimitTracker.initialize, (address(auth))))
        );
    }

    function _attach(HolderLimitTracker t) internal {
        LedgerEntryToken(address(printer)).setHolderTracker(address(t));
        t.backfill(address(printer), 100);
    }

    bytes32 internal offerId;
    bytes32 internal settlementId;

    /// @dev Posts and accepts the sell offer once per test; later calls check the same offer again against the
    /// state at that time (the condition reads the counts live).
    function _check() internal returns (bool) {
        if (offerId == bytes32(0)) (offerId, settlementId) = _postAndAcceptSell();
        return holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    function _accredit(address to, uint64 expiry) internal returns (uint256) {
        Credential memory c;
        c.expiryDate = expiry;
        return _mintCred(to, K_ACCREDITED, c);
    }

    /// @dev `n` more holders, none accredited; each adds weight 1.
    function _seed(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _makeHolder(makeAddr(string.concat("holder ", vm.toString(i))));
        }
    }

    /// @dev A holder whose only lot has the plan label.
    function _planHolder(address who) internal returns (uint256 tokenId) {
        tokenId = _makeHolder(who);
        tracker.setPlanSecurity(address(printer), tokenId, true);
    }

    // ── Readiness (T4) ─────────────────────────────────────────────────────────────────────────────

    // C1
    function test_ClassLimits_NoTrackerInCondition_Fails() public {
        holderCap.setHolderTracker(address(0));
        holderCap.setClassLimits(address(corp), address(0), 50, false);
        assertFalse(_check());
    }

    // C2
    function test_ClassLimits_PrinterReportsElsewhere_Fails() public {
        holderCap.setClassLimits(address(corp), address(0), 50, false);
        _attach(_newTracker()); // ready, but not the tracker the condition trusts
        assertFalse(_check());
        LedgerEntryToken(address(printer)).setHolderTracker(address(0));
        assertFalse(_check());
    }

    // C3
    function test_ClassLimits_BookNotBackfilled_FailsUntilItIs() public {
        holderCap.setClassLimits(address(corp), address(0), 50, false);
        LedgerEntryToken(address(printer)).setHolderTracker(address(tracker)); // a new generation, not backfilled
        assertFalse(tracker.isReady(address(printer)));
        assertFalse(_check());
        tracker.backfill(address(printer), 100);
        assertTrue(_check());
    }

    // ── Non-accredited cap ─────────────────────────────────────────────────────────────────────────

    // C4
    function test_NonAccreditedCap_LandsOnCap_Passes() public {
        _seed(3); // seller + 3 = 4 not accredited; the buyer makes 5
        holderCap.setClassLimits(address(corp), address(0), 5, false);
        assertEq(tracker.counts(address(printer)).nonAccredited, 4);
        assertTrue(_check());
    }

    function test_NonAccreditedCap_Breaches_Fails() public {
        _seed(4); // 5, and the buyer makes 6
        holderCap.setClassLimits(address(corp), address(0), 5, false);
        assertFalse(_check());
    }

    // C5
    function test_NonAccreditedCap_AccreditedBuyer_Passes() public {
        _seed(4);
        holderCap.setClassLimits(address(corp), address(0), 5, false);
        _accredit(buyer, uint64(block.timestamp + 365 days));
        assertTrue(_check());
    }

    // C6
    function test_NonAccreditedCap_ExistingHolder_Passes() public {
        _seed(3);
        _makeHolder(buyer); // 5 not accredited
        holderCap.setClassLimits(address(corp), address(0), 5, false);
        assertTrue(_check());
    }

    // ── Plan exclusion ─────────────────────────────────────────────────────────────────────────────

    // C7
    function test_PlanExclusion_TotalCapLeavesPlanHoldersOut() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 3, false, false);
        _planHolder(makeAddr("employee 1"));
        _planHolder(makeAddr("employee 2")); // seller + 2 = 3: a fresh buyer breaches the total cap
        assertFalse(_check());
        holderCap.setClassLimits(address(corp), address(0), 0, true);
        assertEq(tracker.counts(address(printer)).totalExcludingPlan, 1);
        assertTrue(_check());
    }

    // C8
    function test_PlanExclusion_PlanOnlyBuyerCountsAsNewHolder() public {
        _planHolder(buyer); // left out of the counts today
        holderCap.setClassLimits(address(corp), address(0), 1, true);
        // Not accredited, excluding plan: the seller only (1). The buyer comes back in: 1 + 1 > 1
        assertEq(tracker.counts(address(printer)).nonAccreditedExcludingPlan, 1);
        assertFalse(_check());
        holderCap.setClassLimits(address(corp), address(0), 2, true);
        assertTrue(_check());
    }

    // C9 — review finding #6 of PR #209: the buyer is read under the booking rule of the book
    function test_PlanExclusion_LapsedBookedBuyerStaysAccredited() public {
        _accredit(buyer, uint64(block.timestamp + 1 hours));
        _planHolder(buyer); // booked accredited while valid
        holderCap.setClassLimits(address(corp), address(0), 1, true); // the seller fills the cap
        vm.warp(block.timestamp + 2 hours);
        (, bool stillValid) = badge.getMostRecentValidWith(buyer, K_ACCREDITED);
        assertFalse(stillValid, "the credential lapsed");
        assertTrue(tracker.isAccredited(address(printer), buyer), "the booking stands");
        assertTrue(_check(), "the buyer does not use a place for holders who are not accredited");
    }

    // ── No class limits (T5) ───────────────────────────────────────────────────────────────────────

    // C10
    function test_NoClassLimits_TrackerNeverRead() public {
        holderCap.setHolderTracker(address(new RevertEverything()));
        assertTrue(_check());
        holderCap.setClassLimits(address(corp), address(0), 0, false); // set, but no limit and no exclusion
        assertTrue(_check());
    }

    // ── Setter conflicts (T6) ──────────────────────────────────────────────────────────────────────

    // S1 — review finding #1 of PR #209
    function test_Conflict_SpvUsOnlyAfterPrinterPlanExclusion_Reverts() public {
        holderCap.setClassLimits(address(corp), classX, 0, true); // class X uses the SPV policy
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
    }

    // S2
    function test_Conflict_PrinterPlanExclusionUnderSpvUsOnly_Reverts() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setClassLimits(address(corp), classX, 0, true);
    }

    // S3
    function test_Conflict_SpvPlanExclusionOverPrinterUsOnly_Reverts() public {
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setClassLimits(address(corp), address(0), 0, true);
    }

    // S4
    function test_Conflict_RemovePrinterConfig_Reverts() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        holderCap.setClassLimits(address(corp), classX, 0, true);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.removePrinterConfig(address(corp), classX);
    }

    // S5
    function test_Conflict_RemoveClassLimits_Reverts() public {
        holderCap.setClassLimits(address(corp), address(0), 0, true);
        holderCap.setClassLimits(address(corp), classX, 0, false);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.removeClassLimits(address(corp), classX);
    }

    // S6
    function test_Conflict_PrinterUsOnlyOverOwnPlanExclusion_Reverts() public {
        holderCap.setClassLimits(address(corp), classX, 0, true);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
    }

    // S7 — the counts follow removal: once class X no longer inherits, the SPV may count U.S. residents only
    function test_Conflict_CountsFollowRemoval() public {
        holderCap.setClassLimits(address(corp), classX, 0, true);
        holderCap.removeClassLimits(address(corp), classX);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);

        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        holderCap.removePrinterConfig(address(corp), classX);
        holderCap.setClassLimits(address(corp), address(0), 0, true);
    }

    // S8 — a printer with both settings of its own inherits neither
    function test_Conflict_PrinterWithBothOwnSettings_DoesNotBlockSpv() public {
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        holderCap.setClassLimits(address(corp), classX, 0, true);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
    }

    // ── Access and layout ──────────────────────────────────────────────────────────────────────────

    function test_SetHolderTracker_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.setHolderTracker(address(0));
    }

    function test_ClassLimitSetters_NonAdmin_Revert() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        holderCap.setClassLimits(address(corp), address(0), 1, false);
        vm.expectRevert();
        holderCap.removeClassLimits(address(corp), address(0));
        vm.stopPrank();
        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.setClassLimits(address(0), address(0), 1, false);
    }

    function test_StorageLayout_AppendedMembers() public {
        bytes32 base = keccak256("metalex.condition.secondary.holder-cap.storage.v1");
        holderCap.setClassLimits(address(corp), classX, 321, true);
        bytes32 inner = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 2)));
        bytes32 slot = keccak256(abi.encode(classX, inner));
        assertEq(uint256(vm.load(address(holderCap), slot)), 321, "classLimits at P+2");
        assertEq(address(uint160(uint256(vm.load(address(holderCap), bytes32(uint256(base) + 3))))), address(tracker), "tracker at P+3");
        bytes32 countSlot = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 4)));
        assertEq(uint256(vm.load(address(holderCap), countSlot)), 1, "planExclusionOnSpvConfig at P+4");
        holderCap.removeClassLimits(address(corp), classX);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        countSlot = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 5)));
        assertEq(uint256(vm.load(address(holderCap), countSlot)), 1, "usOnlyOnSpvLimits at P+5");
    }
}
