// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_ACCREDITED, K_BO_COUNT, K_INVESTOR_JURISDICTION, K_INVESTOR_TYPE, InvestorType}
    from "../../../src/interfaces/ILexChexBadge.sol";
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
// HolderCapCondition — section 12(g) limits in holders of record, read from the HolderLimitTracker.
//
// Real integration: each scenario posts and accepts a real sell offer on the printer of
// SecondaryConditionIntegrationBase, which reports to a real tracker. The seller holds the offered lot (one
// holder, not accredited). The buyer is fresh and not accredited unless a test says otherwise. Setup gives the
// SPV an Investment Company Act cap of 100 (`setConfig`).
//
// |  # | case                                                              | expect |
// |----|-------------------------------------------------------------------|:------:|
// | C1 | class limits, condition has no tracker                            |  fail  |
// | C2 | class limits, printer does not report to the trusted tracker      |  fail  |
// | C3 | class limits, book not yet backfilled, then backfilled            | fail, then pass |
// | C4 | non-accredited cap: lands on it / breaches it                     | pass / fail |
// | C5 | accredited buyer at a full non-accredited cap                     |  pass  |
// | C6 | existing holder at a full non-accredited cap                      |  pass  |
// | R1 | total cap: lands on it / breaches it                              | pass / fail |
// | R2 | an entity holder is one holder of record under the total cap      |  pass  |
// | R3 | an entity buyer adds one holder of record                         |  pass  |
// | R4 | the ICA cap still counts an entity's beneficial owners            |  fail  |
// | R5 | both 12(g) caps apply to the same sale                            |  fail  |
// | P1 | plan exclusion never lowers the ICA count (review regression)     |  fail  |
// | P2 | plan exclusion leaves plan-only holders out of the total cap      | fail, then pass |
// | P3 | plan-only holder buying is a new holder for the counts            | fail / pass |
// | P4 | plan-only holder whose credential lapsed keeps its booking        |  pass  |
// | N1 | no 12(g) cap set (or the exclusion alone): tracker never read     |  pass  |
// | N2 | an operating company: IcaException.NONE, ICA cap 0, 12(g) caps     | pass / fail |
// | N3 | U.S.-only ICA count and plan exclusion may now be combined        | pass / fail |
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
        _icaCap(100);
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

    function _icaCap(uint256 cap) internal {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, cap, false, false);
    }

    /// @dev The SPV's section 12(g) limits: total cap, non-accredited cap, plan exclusion.
    function _limits(uint256 totalCap, uint256 nonAccreditedCap, bool excludePlanOnly) internal {
        holderCap.setClassLimits(address(corp), address(0), totalCap, nonAccreditedCap, excludePlanOnly);
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

    /// @dev An entity credential whose look-through count is `boCount` beneficial owners.
    function _entity(address to, uint32 boCount) internal {
        Credential memory c;
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "US";
        c.beneficialOwnerCount = boCount;
        _mintCred(to, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_BO_COUNT, c);
    }

    /// @dev `n` more holders, none accredited.
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
        _limits(0, 50, false);
        assertFalse(_check());
    }

    // C2
    function test_ClassLimits_PrinterReportsElsewhere_Fails() public {
        _limits(0, 50, false);
        _attach(_newTracker()); // ready, but not the tracker the condition trusts
        assertFalse(_check());
        LedgerEntryToken(address(printer)).setHolderTracker(address(0));
        assertFalse(_check());
    }

    // C3
    function test_ClassLimits_BookNotBackfilled_FailsUntilItIs() public {
        _limits(50, 0, false);
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
        _limits(0, 5, false);
        assertEq(tracker.counts(address(printer)).nonAccredited, 4);
        assertTrue(_check());
    }

    function test_NonAccreditedCap_Breaches_Fails() public {
        _seed(4); // 5, and the buyer makes 6
        _limits(0, 5, false);
        assertFalse(_check());
    }

    // C5
    function test_NonAccreditedCap_AccreditedBuyer_Passes() public {
        _seed(4);
        _limits(0, 5, false);
        _accredit(buyer, uint64(block.timestamp + 365 days));
        assertTrue(_check());
    }

    // C6
    function test_NonAccreditedCap_ExistingHolder_Passes() public {
        _seed(3);
        _makeHolder(buyer); // 5 not accredited
        _limits(0, 5, false);
        assertTrue(_check());
    }

    // ── Holders of record (total cap) ──────────────────────────────────────────────────────────────

    // R1
    function test_TotalCap_LandsOnCap_Passes() public {
        _seed(2); // seller + 2 = 3; the buyer makes 4
        _limits(4, 0, false);
        assertTrue(_check());
    }

    function test_TotalCap_Breaches_Fails() public {
        _seed(3); // 4, and the buyer makes 5
        _limits(4, 0, false);
        assertFalse(_check());
    }

    // R2 — section 12(g) has no look-through: an entity with 25 beneficial owners is one holder of record
    function test_TotalCap_EntityHolderIsOneHolderOfRecord() public {
        address fund = makeAddr("fund with 25 partners");
        _entity(fund, 25);
        _makeHolder(fund);
        assertEq(printer.lookThroughHolderCount(), 26, "the ICA tally looks through");
        assertEq(tracker.counts(address(printer)).total, 2, "the 12(g) count does not");
        _limits(3, 3, false); // seller + fund + buyer = 3
        assertTrue(_check());
    }

    // R3 — a buyer that is an entity adds one holder of record, not its beneficial owners
    function test_TotalCap_EntityBuyerAddsOne() public {
        _entity(buyer, 25);
        _limits(2, 2, false); // seller + buyer = 2
        assertTrue(_check());
    }

    // R4 — the ICA cap still looks through: the same entity holder fills a cap of 26 there
    function test_IcaCap_StillCountsBeneficialOwners() public {
        address fund = makeAddr("fund with 25 partners");
        _entity(fund, 25);
        _makeHolder(fund);
        _icaCap(26); // seller (1) + fund (25) = 26: no room for a new holder
        _limits(2000, 500, false); // far from the 12(g) caps
        assertFalse(_check());
        _icaCap(27);
        assertTrue(_check());
    }

    // R5 — both 12(g) caps apply to the same sale
    function test_BothCaps_EachCanRefuse() public {
        _seed(2); // 3 holders, none accredited
        _limits(4, 3, false); // total has room (3 + 1 <= 4); non-accredited does not (3 + 1 > 3)
        assertFalse(_check());
        _limits(3, 4, false); // now the total cap refuses
        assertFalse(_check());
        _limits(4, 4, false);
        assertTrue(_check());
    }

    // ── Plan exclusion ─────────────────────────────────────────────────────────────────────────────

    // P1 — review regression: the plan exclusion is a section 12(g) rule (Rule 12g5-1(a)(8)); it must never
    // lower the Investment Company Act count (whose exclusion is the narrower Rule 3c-5)
    function test_PlanExclusion_NeverLowersIcaCount() public {
        _icaCap(3);
        _planHolder(makeAddr("employee 1"));
        _planHolder(makeAddr("employee 2")); // seller + 2 = 3 on the ICA tally: a new holder breaches it
        assertFalse(_check());
        _limits(2000, 500, true);
        assertEq(tracker.counts(address(printer)).totalExcludingPlan, 1);
        assertFalse(_check(), "the plan exclusion does not touch the ICA cap");
    }

    // P2
    function test_PlanExclusion_TotalCapLeavesPlanHoldersOut() public {
        _planHolder(makeAddr("employee 1"));
        _planHolder(makeAddr("employee 2")); // 3 holders of record, 1 excluding plan-only
        _limits(2, 0, false);
        assertFalse(_check());
        _limits(2, 0, true);
        assertTrue(_check());
    }

    // P3
    function test_PlanExclusion_PlanOnlyBuyerCountsAsNewHolder() public {
        _planHolder(buyer); // left out of the counts today
        _limits(0, 1, true);
        // Not accredited, excluding plan: the seller only (1). The buyer comes back in: 1 + 1 > 1
        assertEq(tracker.counts(address(printer)).nonAccreditedExcludingPlan, 1);
        assertFalse(_check());
        _limits(0, 2, true);
        assertTrue(_check());
    }

    // P4 — review finding #6 of PR #209: the buyer is read under the booking rule of the book
    function test_PlanExclusion_LapsedBookedBuyerStaysAccredited() public {
        _accredit(buyer, uint64(block.timestamp + 1 hours));
        _planHolder(buyer); // booked accredited while valid
        _limits(0, 1, true); // the seller fills the cap
        vm.warp(block.timestamp + 2 hours);
        (, bool stillValid) = badge.getMostRecentValidWith(buyer, K_ACCREDITED);
        assertFalse(stillValid, "the credential lapsed");
        assertTrue(tracker.isAccredited(address(printer), buyer), "the booking stands");
        assertTrue(_check(), "the buyer does not use a place for holders who are not accredited");
    }

    // ── No 12(g) cap (T5), operating companies, combinations ───────────────────────────────────────

    // N1
    function test_NoClassLimits_TrackerNeverRead() public {
        holderCap.setHolderTracker(address(new RevertEverything()));
        assertTrue(_check());
        _limits(0, 0, false); // set, but no cap
        assertTrue(_check());
        _limits(0, 0, true); // the exclusion alone changes no count that is checked
        assertTrue(_check());
    }

    // N2 — an operating company relies on no ICA exception and uses only the section 12(g) caps
    function test_OperatingCompany_NoneLabelAndRecordHolderCaps() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.NONE, 0, false, false);
        assertEq(uint8(holderCap.configs(address(corp)).icaException), uint8(HolderCapCondition.IcaException.NONE));
        _seed(1); // 2 holders
        _limits(3, 0, false);
        assertTrue(_check());
        _limits(2, 0, false);
        assertFalse(_check());
    }

    // N3 — the plan exclusion no longer touches the ICA count, so a U.S.-only ICA count and the plan exclusion
    // may apply to the same sales, at the SPV and the printer level
    function test_UsOnlyIcaCountWithPlanExclusion_Allowed() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        _limits(0, 1, true);
        holderCap.setPrinterConfig(address(corp), classX, HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        holderCap.setClassLimits(address(corp), classX, 0, 1, true);
        assertFalse(_check(), "seller + buyer > 1 not accredited");
        _limits(0, 2, true);
        assertTrue(_check());
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
        holderCap.setClassLimits(address(corp), address(0), 1, 1, false);
        vm.expectRevert();
        holderCap.removeClassLimits(address(corp), address(0));
        vm.stopPrank();
        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.setClassLimits(address(0), address(0), 1, 1, false);
    }

    function test_ClassLimits_SetAndRemove() public {
        holderCap.setClassLimits(address(corp), classX, 2000, 500, true);
        HolderCapCondition.ClassLimits memory l = holderCap.classLimits(address(corp), classX);
        assertEq(l.totalCap, 2000);
        assertEq(l.nonAccreditedCap, 500);
        assertTrue(l.excludePlanOnly);
        assertTrue(l.configured);
        holderCap.removeClassLimits(address(corp), classX);
        assertFalse(holderCap.classLimits(address(corp), classX).configured);
    }

    function test_StorageLayout_AppendedMembers() public {
        bytes32 base = keccak256("metalex.condition.secondary.holder-cap.storage.v1");
        holderCap.setClassLimits(address(corp), classX, 2000, 500, true);
        bytes32 inner = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 2)));
        bytes32 slot = keccak256(abi.encode(classX, inner));
        assertEq(uint256(vm.load(address(holderCap), slot)), 2000, "classLimits at P+2: totalCap");
        assertEq(uint256(vm.load(address(holderCap), bytes32(uint256(slot) + 1))), 500, "nonAccreditedCap");
        assertEq(address(uint160(uint256(vm.load(address(holderCap), bytes32(uint256(base) + 3))))), address(tracker), "tracker at P+3");
    }
}
