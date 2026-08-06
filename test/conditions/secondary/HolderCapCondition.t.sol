// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_BO_COUNT, K_INVESTOR_JURISDICTION, K_INVESTOR_TYPE, InvestorType}
    from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {ILedgerEntryToken} from "../../../src/interfaces/ILedgerEntryToken.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {LeXcheXBadge} from "../../../src/creds/lexchexBadge.sol";
import {SecurityClass, SecuritySeries} from "../../../src/CyberCorpConstants.sol";
import {HolderCapCondition} from "../../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// HolderCapCondition — ICA §3(c)(1)/§3(c)(1)(C)/§3(c)(7) holder limits at transfer time.
//
// Real integration (see SecondaryConditionIntegrationBase): each scenario posts + accepts a real sell offer.
// Acceptance materializes the escrow with NO transfer — that happens at finalize — so the printer's tally is
// still the pre-transfer count the condition reads. The condition is deliberately NOT wired as a pathway
// threshold, so acceptance always succeeds and the test asserts checkCondition's boolean directly.
//
// The seller holds the offered cert, so it already contributes weight 1 to the tally; seeded incumbents make
// up the rest, hence `_seedHolder(bo)` targets `count - 1`.
//
// Scenario × outcome (default deployment: §3(c)(1), cap = 100)
// |  # | scenario                                        | expect | rationale                             |
// |----|-------------------------------------------------|:------:|---------------------------------------|
// |  1 | posting (no acquirer)                           |  pass  | cap evaluated later                   |
// |  2 | fresh U.S. buyer, count 99 (+1 = 100)           |  pass  | lands exactly on the cap              |
// |  3 | fresh U.S. buyer, count 100 (+1 = 101)          |  fail  | would breach the cap                  |
// |  4 | existing holder (isLegalHolder), count 100      |  pass  | position increase, not a new holder   |
// |  5 | entity look-through boCount 5, count 95 (=100)  |  pass  | 5 BOs flow through, lands on cap      |
// |  6 | entity look-through boCount 5, count 96 (=101)  |  fail  | look-through breaches the cap         |
// |  7 | §3(c)(7) (cap 0), fresh buyer, count 500        |  pass  | no numeric cap                        |
// |  8 | blockUsInvestors, U.S. buyer                    |  fail  | offshore no-U.S.-investor floor       |
// | 8a | blockUsInvestors, existing U.S. holder          |  fail  | floor precedes the position-increase  |
// |  9 | blockUsInvestors, non-U.S. buyer                |  pass  | floor only bites U.S. buyers          |
// | 10 | usResidentOnlyCount, non-U.S. buyer             |  pass  | non-U.S. acquirer not counted         |
// | 11 | usResidentOnlyCount, fresh U.S. buyer at cap    |  fail  | only U.S. residents counted, breaches |
//
// The credential registry is the printer's own, so there is no badge wiring here to get wrong.
//
// Config/authorization
// | # | case                              | expect              |
// |---|-----------------------------------|---------------------|
// |12 | updateConfig by stranger          | revert (not admin)  |
//
// Operational staleness: a re-credential that changes an existing holder's BO count does not reach the
// printer's cached tally until a keeper resync (15).
// ─────────────────────────────────────────────────────────────────────────────

contract HolderCapConditionTest is SecondaryConditionIntegrationBase {
    HolderCapCondition internal holderCap;
    address internal incumbent = makeAddr("incumbent");

    function setUp() public {
        _setUpIntegration();
        holderCap = HolderCapCondition(
            _proxy(
                address(new HolderCapCondition()),
                abi.encodeCall(HolderCapCondition.initialize, (address(auth)))
            )
        );
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        _credential(buyer, "US", 0);
    }

    /// @dev Issues an accredited credential; the newest valid one governs the reads, so a later call in a
    /// test supersedes the setUp default (jurisdiction / beneficial-owner count).
    function _credential(address to, string memory jurisdiction, uint32 boCount) internal returns (uint256) {
        Credential memory c;
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = jurisdiction;
        c.beneficialOwnerCount = boCount;
        // A value key may only be asserted with a non-empty value, so K_BO_COUNT is only added when non-zero.
        uint256 asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        if (boCount > 0) asserts |= K_BO_COUNT;
        return _mintCred(to, asserts, c);
    }

    function _credentialBuyer(string memory jurisdiction, uint32 boCount) internal {
        _credential(buyer, jurisdiction, boCount);
    }

    /// @dev Seeds one pre-existing incumbent holder credentialed with `boCount` (and U.S. status), so the
    /// printer's look-through tally stands at seller-weight (1) + boCount before the buyer is evaluated.
    function _seedHolder(string memory jurisdiction, uint32 boCount) internal {
        _credential(incumbent, jurisdiction, boCount);
        _makeHolder(incumbent);
    }

    function _check() internal returns (bool) {
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        return holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    // ── Cap scenarios ───────────────────────────────────────────────────────────

    // 1
    function test_Posting_NoAcquirer_Passes() public {
        bytes32 offerId = _postSell();
        assertTrue(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 2
    function test_FreshUsBuyer_LandsOnCap_Passes() public {
        _seedHolder("KY", 98); // seller(1) + 98 = tally 99
        assertTrue(_check());
    }

    // 3
    function test_FreshUsBuyer_BreachesCap_Fails() public {
        _seedHolder("KY", 99); // tally 100; buyer +1 = 101
        assertFalse(_check());
    }

    // 4
    function test_ExistingHolder_PositionIncrease_Passes() public {
        _seedHolder("KY", 98);
        _makeHolder(buyer); // buyer already holds (position increase, not a new holder); tally = 100
        assertTrue(_check());
    }

    // 5
    function test_EntityLookThrough_LandsOnCap_Passes() public {
        _seedHolder("KY", 94); // seller(1) + 94 = tally 95
        _credentialBuyer("US", 5); // buyer's 5 BOs flow through: 95 + 5 = 100
        assertTrue(_check());
    }

    // 6
    function test_EntityLookThrough_BreachesCap_Fails() public {
        _seedHolder("KY", 95); // tally 96
        _credentialBuyer("US", 5); // 96 + 5 = 101
        assertFalse(_check());
    }

    // 7
    function test_Section3c7_NoNumericCap_Passes() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        _seedHolder("KY", 499); // tally 500, but cap 0 => no numeric cap
        assertTrue(_check());
    }

    // 8
    function test_BlockUsInvestors_UsBuyer_Fails() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        assertFalse(_check());
    }

    // 8a — the floor is absolute: it precedes the position-increase short-circuit, so an existing U.S.
    // holder cannot add to a position an offshore SPV would refuse them today.
    function test_BlockUsInvestors_ExistingUsHolder_Fails() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        _makeHolder(buyer);
        assertFalse(_check());
    }

    // 9
    function test_BlockUsInvestors_NonUsBuyer_Passes() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        _credentialBuyer("KY", 0);
        assertTrue(_check());
    }

    // 10
    function test_UsResidentOnlyCount_NonUsBuyer_NotCounted_Passes() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        _credentialBuyer("KY", 0);
        // Even with a "full" U.S. tally, a non-U.S. acquirer does not add to the U.S.-resident count.
        _seedHolder("US", 1);
        assertTrue(_check());
    }

    // 11
    function test_UsResidentOnlyCount_UsBuyerBreaches_Fails() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        // The printer's U.S.-resident look-through tally already stands at the cap (= 1). A fresh U.S.
        // buyer would make 2 > cap 1.
        _seedHolder("US", 1);
        assertFalse(_check());
    }

    // ── Config / authorization ──────────────────────────────────────────────────

    // 12
    function test_UpdateConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }

    // ── Operational staleness ────────────────────────────────────────────────────
    // The printer's look-through tally is a cached per-holder snapshot sampled at the holder's last LET op.
    // A badge-side re-credential (updateAttributes/recertify) does NOT call back into the printer, so an
    // existing holder's new beneficial-owner count is invisible to the cap check until a keeper calls
    // resyncHolder / resyncHolders (or that holder does another counted LET op). Until then the base is stale
    // and the cap can fail open. This test demonstrates the gap and that resync closes it.

    // 15
    function test_StaleLookThroughTally_ResyncReconciles() public {
        _seedHolder("KY", 90); // seller(1) + 90 = tally 91

        // A single posted+accepted offer, evaluated before and after the keeper resync (a second postOffer on
        // the same cert would revert on the still-reserved units, so we re-check the same settlement).
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();

        // Admin re-credentials the incumbent: BO count 90 -> 99 by minting a superseding credential (the newest
        // valid one governs the reads). Nothing pokes the printer.
        _credential(incumbent, "KY", 99);

        // The badge now reports 99, yet the printer's cached tally is still the pre-update snapshot (91).
        (uint32 recredentialed,) = badge.getEffectiveBeneficialOwnerCount(incumbent);
        assertEq(recredentialed, 99, "badge reflects the re-credential");
        assertEq(printer.lookThroughHolderCount(), 91, "printer tally is stale until a resync");

        // Fail-open: the stale base (91) + fresh U.S. buyer (+1) = 92 <= 100 is admitted, even though the true
        // count is now seller(1) + incumbent(99) + buyer(1) = 101 > cap 100 and should be blocked.
        assertTrue(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "stale tally lets a breaching trade pass"
        );

        // Keeper reconciles the incumbent's contribution to the current badge value (resyncHolders is the
        // batch variant). No event is emitted — the reconcile is silent and permissionless.
        LedgerEntryToken(address(printer)).resyncHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 100, "resync folds the new BO count into the tally");

        // With the reconciled base the same trade is correctly blocked.
        assertFalse(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "resynced tally blocks the breaching trade"
        );
    }

    // ── Audit findings ──────────────────────────────────────────────────────────

    /// @dev A printer straight from the factory — no look-through badge wired.
    function _unwiredPrinter() internal returns (address) {
        return im.createCertPrinter(
            new string[](0), "Bare", "BARE", "ipfs://bare",
            SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0), bytes("")
        );
    }

    // H1 — with no badge wired, every holder is unknown. Unknown counts as one U.S. holder, so the
    // U.S.-only subtotal tracks the population instead of sitting at zero and never filling the cap.
    function test_Audit_H1_UnwiredPrinterCountsHoldersAsUs() public {
        address bare = _unwiredPrinter();
        assertEq(LedgerEntryToken(bare).lookThroughBadge(), address(0), "printer starts unwired");

        for (uint256 i = 0; i < 5; i++) {
            address h = makeAddr(string.concat("usHolder", vm.toString(i)));
            _credential(h, "US", 10);
            im.createCertAndAssign(bare, h, _certDetails(1));
        }

        assertEq(ILedgerEntryToken(bare).lookThroughHolderCount(), 5, "one holder each, no look-through");
        assertEq(ILedgerEntryToken(bare).usLookThroughHolderCount(), 5, "unknown holders read U.S.");
    }

    // H2 — withdrawing an attestation says nothing about how many owners a holder has, so it must not shrink
    // the tally. Only a fresh one revises the weight. resyncHolder is open to anyone, so this matters.
    function test_Audit_H2_VoidingBoCredential_DoesNotFreeCapHeadroom() public {
        uint256 boCred = _credential(incumbent, "KY", 90);
        _makeHolder(incumbent); // seller(1) + incumbent(90) = 91
        assertEq(printer.lookThroughHolderCount(), 91);

        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 91, false, false);
        assertFalse(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "91 + 1 > cap 91 is correctly blocked"
        );

        // The admin withdraws the attestation, meaning to tighten.
        badge.void(boCred, "attestation withdrawn");
        (uint32 afterVoid,) = badge.getEffectiveBeneficialOwnerCount(incumbent);
        assertEq(uint256(afterVoid), 0, "badge reports the fact unestablished");

        vm.prank(stranger);
        LedgerEntryToken(address(printer)).resyncHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 91, "revocation did not shrink the tally");
        assertFalse(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "the blocked trade stays blocked"
        );

        // A fresh attestation still lowers the weight: the holder is not frozen, just not guessed at.
        _credential(incumbent, "KY", 10);
        LedgerEntryToken(address(printer)).resyncHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 11, "a new attestation does revise the weight");
        assertTrue(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    // H2b — expiry needs no admin action at all, so it must not shrink the tally either.
    function test_Audit_H2b_ExpiredBoCredential_DoesNotFreeCapHeadroom() public {
        Credential memory c;
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "KY";
        c.beneficialOwnerCount = 90;
        c.expiryDate = uint64(block.timestamp + 1 days);
        _mintCred(incumbent, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_BO_COUNT, c);
        _makeHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 91);

        vm.warp(block.timestamp + 2 days);
        vm.prank(stranger);
        LedgerEntryToken(address(printer)).resyncHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 91, "a lapsed attestation did not shrink the tally");
    }

    // H2c — the flip side of H2: a recert to individual is a fresh fact, not a withdrawal, so it must revise
    // the weight down. The badge answers 1 for an individual, so the resync sees a real count rather than the
    // zero it would read from the retired K_BO_COUNT alone, and the freed cap room is genuine.
    function test_Audit_H2c_IndividualRecert_ReleasesStaleEntityWeight() public {
        uint256 entityCred = _credential(incumbent, "KY", 90);
        _makeHolder(incumbent); // seller(1) + incumbent(90) = 91
        assertEq(printer.lookThroughHolderCount(), 91);

        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 91, false, false);
        assertFalse(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "91 + 1 > cap 91 is correctly blocked"
        );

        // The incumbent turns out to be a natural person, not an entity.
        Credential memory asIndividual;
        asIndividual.investorType = InvestorType.INDIVIDUAL;
        asIndividual.investorJurisdiction = "KY";
        asIndividual.asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        asIndividual.expiryDate = uint64(block.timestamp + 3650 days);
        badge.supersede(entityCred, asIndividual, "recertified as individual");
        (uint32 asIndividualCount,) = badge.getEffectiveBeneficialOwnerCount(incumbent);
        assertEq(asIndividualCount, 1, "an individual is one beneficial owner");

        vm.prank(stranger);
        LedgerEntryToken(address(printer)).resyncHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 2, "seller(1) + incumbent(1); the stale 90 is released");
        assertTrue(
            holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "the trade the stale weight was blocking now passes"
        );
    }

    // M1 — the condition reads the printer's own badge, so there is no second wiring to drift. Credentials
    // minted only on the badge the printer uses are the ones that count.
    function test_Audit_M1_BadgeComesFromThePrinter() public {
        LeXcheXBadge other = LeXcheXBadge(
            _proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth))))
        );
        address bare = _unwiredPrinter();
        LedgerEntryToken(bare).setLookThroughBadge(address(other));
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);

        // The buyer is U.S. on the base badge but foreign on the one this printer uses, and the printer's
        // answer is the one that governs — so the no-U.S. floor lets them through.
        (string memory baseJurisdiction,) = badge.getInvestorJurisdiction(buyer);
        assertEq(baseJurisdiction, "US");
        Credential memory foreign;
        foreign.investorType = InvestorType.ENTITY;
        foreign.investorJurisdiction = "KY";
        other.mint(buyer, _withExpiry(foreign, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION));

        uint256 sellerCert = im.createCertAndAssign(bare, seller, _certDetails(UNITS));
        bytes32 offerId = _postSellOn(bare, sellerCert);
        bytes32 settlementId = _acceptSell(offerId);
        assertTrue(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    // An unwired printer knows nothing about anyone, so the buyer counts as one U.S. holder — the same
    // reading its tally gives every existing holder.
    function test_Audit_M1b_UnwiredPrinterCountsBuyerAsOneUsHolder() public {
        address bare = _unwiredPrinter();
        uint256 sellerCert = im.createCertAndAssign(bare, seller, _certDetails(UNITS));
        bytes32 offerId = _postSellOn(bare, sellerCert);
        bytes32 settlementId = _acceptSell(offerId);

        // seller(1) + buyer(1) = 2, so a cap of 2 fits and a cap of 1 does not.
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 2, false, false);
        assertTrue(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 1, false, false);
        assertFalse(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));

        // And an unknown buyer reads U.S., so the no-U.S. floor refuses them.
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, true);
        assertFalse(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    /// @dev Stamps a far expiry so a credential can be minted onto another badge directly.
    function _withExpiry(Credential memory c, uint256 asserts) internal view returns (Credential memory) {
        c.asserts = asserts;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        return c;
    }

    // Attached but never configured: a zero cap is a real §3(c)(7) setting, so it cannot stand in for
    // "nobody set this". Nothing passes until the GP states which exception applies.
    function test_Audit_UnconfiguredSpv_Blocks() public {
        HolderCapCondition fresh = HolderCapCondition(
            _proxy(address(new HolderCapCondition()), abi.encodeCall(HolderCapCondition.initialize, (address(auth))))
        );
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(fresh.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));

        // §3(c)(7) with no numeric cap is a configuration, and it passes.
        fresh.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        assertTrue(fresh.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    function test_SetConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }
}