// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_ACCREDITED, K_BO_COUNT, K_INVESTOR_JURISDICTION, K_INVESTOR_TYPE, InvestorType}
    from "../../../src/interfaces/ILexChexBadge.sol";
import {ILedgerEntryTokenHolderLimits} from "../../../src/interfaces/ILedgerEntryTokenHolderLimits.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {ILedgerEntryToken} from "../../../src/interfaces/ILedgerEntryToken.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {LeXcheXBadge} from "../../../src/creds/lexchexBadge.sol";
import {SecurityClass, SecuritySeries} from "../../../src/CyberCorpConstants.sol";
import {HolderCapCondition} from "../../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {BorgAuth} from "../../../src/libs/auth.sol";
import {SecondaryConditionIntegrationBase, SpvFixture} from "./SecondaryConditionIntegration.sol";

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
// Per-printer (per-class) policy: `printerConfigs[spv][printer]` replaces `configs[spv]` for sales of that
// printer only. A printer with no policy of its own falls back to the SPV policy.
// |  # | case                                                   | expect                         |
// |----|--------------------------------------------------------|--------------------------------|
// | P1 | two classes of one SPV, different caps                 | each sale reads its own cap    |
// | P2 | class with no policy of its own                        | SPV policy applies             |
// | P3 | class policy removed                                   | SPV policy applies again       |
// | P4 | class policy only, no SPV policy                       | class policy applies           |
// | P5 | neither policy for the printer of the sale             | fail (not configured)          |
// | P6 | another SPV's admin writes under its own key           | not read by this SPV's sales   |
// | P7 | set/remove by non-admin, zero SPV, zero printer        | revert                         |
// | P8 | raw slots: `configs` at P+0, `printerConfigs` at P+1   | deployed layout kept           |
//
// Section 12(g) limits (C2, C4): `classLimits[spv][printer]` (printer 0 = the SPV) holds a limit on holders
// who are not accredited and the plan-only exclusion. Read through the printer's `holderLimits` forwarder.
// | #  | case                                                               | expect                          |
// |----|--------------------------------------------------------------------|---------------------------------|
// | N1 | cap 2, 2 non-accredited holders: new non-accredited buyer           | fail                            |
// | N2 | same, accredited buyer / existing holder                            | pass                            |
// | N3 | holder's credential voided: count 2 before resync, 3 after          | fail after (known limit before) |
// | N4 | company mark on an accredited buyer                                 | counted, fail                   |
// | N5 | printer without the forwarder (older LET), limits set / not set     | fail / as C1                    |
// | N6 | malformed forwarder answer                                          | fail                            |
// | N7 | non-admin setters; another SPV's key                                | revert; not read                |
// | N8 | limits configured with no limit and exclusion off                   | as C1, no new read              |
// | N9 | LET contract limits override the SPV's; removed -> SPV's again      | per printer                     |
// | N10| second cap with total cap 0                                         | applies                         |
// | L1 | plan-only incumbent, exclusion on / off                             | left out / counted              |
// | L2 | incumbent with one labelled and one unlabelled lot                  | counted once                    |
// | L3 | plan-only buyer, exclusion on                                       | uses a place                    |
// | L4 | usResidentOnlyCount with the exclusion                              | refused by setters; fail        |
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

    // ── Per-printer (per-class) policy ──────────────────────────────────────────

    /// @dev A second class of the same SPV: an unwired printer from the SPV's IssuanceManager, with the seller
    /// holding one cert. An unwired printer counts every holder as one U.S. holder, so its tally is 1.
    function _postAndAcceptOnSecondClass() internal returns (address bare, bytes32 offerId, bytes32 settlementId) {
        bare = _unwiredPrinter();
        uint256 sellerCert = im.createCertAndAssign(bare, seller, _certDetails(UNITS));
        offerId = _postSellOn(bare, sellerCert);
        settlementId = _acceptSell(offerId);
    }

    function _checkOffer(HolderCapCondition c, bytes32 offerId, bytes32 settlementId) internal view returns (bool) {
        return c.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    // P1 — two LET contracts of one SPV with different caps: each sale is checked against its own cap. The SPV
    // policy (cap 100) would pass both sales, so every refusal below comes from a class policy.
    function test_PrinterConfig_TwoClasses_EachSaleUsesOwnCap() public {
        _seedHolder("KY", 9); // class A tally: seller(1) + 9 = 10
        (bytes32 offerA, bytes32 settlementA) = _postAndAcceptSell();
        (address classB, bytes32 offerB, bytes32 settlementB) = _postAndAcceptOnSecondClass(); // class B tally 1
        assertEq(printer.lookThroughHolderCount(), 10);
        assertEq(ILedgerEntryToken(classB).lookThroughHolderCount(), 1);

        // A cap 11 (10 + 1 fits), B cap 1 (1 + 1 does not)
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 11, false, false);
        holderCap.setPrinterConfig(address(corp), classB, HolderCapCondition.IcaException.SECTION_3C1, 1, false, false);
        assertTrue(_checkOffer(holderCap, offerA, settlementA), "class A: 10 + 1 <= 11");
        assertFalse(_checkOffer(holderCap, offerB, settlementB), "class B: 1 + 1 > 1");

        // Reversed: A cap 10 (10 + 1 does not fit), B cap 2 (1 + 1 fits)
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 10, false, false);
        holderCap.setPrinterConfig(address(corp), classB, HolderCapCondition.IcaException.SECTION_3C1, 2, false, false);
        assertFalse(_checkOffer(holderCap, offerA, settlementA), "class A: 10 + 1 > 10");
        assertTrue(_checkOffer(holderCap, offerB, settlementB), "class B: 1 + 1 <= 2");

        // The SPV policy is unchanged by the class policies
        HolderCapCondition.SpvConfig memory spvCfg = holderCap.configs(address(corp));
        assertEq(spvCfg.cap, 100);
        assertTrue(spvCfg.configured);
    }

    // P1b — a class policy carries all of its fields, not only the cap: the no-U.S. floor of class B does not
    // reach class A.
    function test_PrinterConfig_BlockUsInvestors_OnlyOnItsClass() public {
        (bytes32 offerA, bytes32 settlementA) = _postAndAcceptSell();
        (address classB, bytes32 offerB, bytes32 settlementB) = _postAndAcceptOnSecondClass();
        holderCap.setPrinterConfig(address(corp), classB, HolderCapCondition.IcaException.SECTION_3C7, 0, false, true);
        assertTrue(_checkOffer(holderCap, offerA, settlementA), "class A uses the SPV policy (no floor)");
        assertFalse(_checkOffer(holderCap, offerB, settlementB), "class B refuses the U.S. buyer");
    }

    // P2 — a printer with no policy of its own uses the SPV policy (behaviour before this change)
    function test_PrinterConfig_UnsetPrinter_UsesSpvConfig() public {
        (address classB,,) = _postAndAcceptOnSecondClass();
        holderCap.setPrinterConfig(address(corp), classB, HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        assertFalse(holderCap.printerConfigs(address(corp), address(printer)).configured);

        _seedHolder("KY", 99); // class A tally 100; SPV cap 100; buyer +1 = 101
        assertFalse(_check(), "class A falls back to the SPV cap of 100");
    }

    // P3 — after the class policy is removed, the SPV policy applies again
    function test_PrinterConfig_Removed_FallsBackToSpvConfig() public {
        _seedHolder("KY", 99); // tally 100
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "SPV cap 100 refuses 101");

        vm.expectEmit(true, true, false, true, address(holderCap));
        emit HolderCapCondition.PrinterConfigUpdated(
            address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1C, 250, false, false
        );
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1C, 250, false, false);
        HolderCapCondition.SpvConfig memory cfg = holderCap.printerConfigs(address(corp), address(printer));
        assertTrue(cfg.configured);
        assertEq(cfg.cap, 250);
        assertEq(uint8(cfg.icaException), uint8(HolderCapCondition.IcaException.SECTION_3C1C));
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "class cap 250 admits 101");

        vm.expectEmit(true, true, false, true, address(holderCap));
        emit HolderCapCondition.PrinterConfigRemoved(address(corp), address(printer));
        holderCap.removePrinterConfig(address(corp), address(printer));
        cfg = holderCap.printerConfigs(address(corp), address(printer));
        assertFalse(cfg.configured);
        assertEq(cfg.cap, 0);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "SPV cap 100 applies again");
    }

    // P4 + P5 — on a condition with no SPV policy, a sale passes only when its own printer has a policy
    function test_PrinterConfig_NoSpvConfig_OnlyConfiguredClassPasses() public {
        HolderCapCondition fresh = HolderCapCondition(
            _proxy(address(new HolderCapCondition()), abi.encodeCall(HolderCapCondition.initialize, (address(auth))))
        );
        (bytes32 offerA, bytes32 settlementA) = _postAndAcceptSell();
        (address classB, bytes32 offerB, bytes32 settlementB) = _postAndAcceptOnSecondClass();

        // Neither policy: refused (existing behaviour)
        assertFalse(_checkOffer(fresh, offerA, settlementA), "neither policy");
        assertFalse(_checkOffer(fresh, offerB, settlementB), "neither policy");

        // A class B policy does not configure class A
        fresh.setPrinterConfig(address(corp), classB, HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        assertTrue(_checkOffer(fresh, offerB, settlementB), "class B has its own policy");
        assertFalse(_checkOffer(fresh, offerA, settlementA), "class A still has neither policy");

        // Removing the only policy returns class B to "not configured"
        fresh.removePrinterConfig(address(corp), classB);
        assertFalse(_checkOffer(fresh, offerB, settlementB), "class B has neither policy again");
    }

    // P6 — a policy is read as [offer.spvAddress][offer.certPrinter]. Another SPV's admin can write a policy for
    // this SPV's printer, but only under its own SPV key, which this SPV's sales never read.
    function test_PrinterConfig_OtherSpvKey_NotRead() public {
        BorgAuth otherAuth = new BorgAuth(stranger);
        SpvFixture otherSpv = new SpvFixture(address(otherAuth));

        _seedHolder("KY", 99); // tally 100; SPV cap 100
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();

        vm.prank(stranger);
        holderCap.setPrinterConfig(address(otherSpv), address(printer), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        assertTrue(holderCap.printerConfigs(address(otherSpv), address(printer)).configured);
        assertFalse(holderCap.printerConfigs(address(corp), address(printer)).configured);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "corp's sale still reads corp's cap of 100");
    }

    // P7 — authorization and input checks
    function test_SetPrinterConfig_ByNonAdmin_Reverts() public {
        uint256 adminRole = auth.ADMIN_ROLE(); // read before the prank, which the next call consumes
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger));
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }

    function test_RemovePrinterConfig_ByNonAdmin_Reverts() public {
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        uint256 adminRole = auth.ADMIN_ROLE(); // read before the prank, which the next call consumes
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger));
        holderCap.removePrinterConfig(address(corp), address(printer));
        assertTrue(holderCap.printerConfigs(address(corp), address(printer)).configured, "policy is still set");
    }

    function test_SetPrinterConfig_ZeroSpv_Reverts() public {
        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.setPrinterConfig(address(0), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
    }

    function test_SetPrinterConfig_ZeroPrinter_Reverts() public {
        vm.expectRevert(HolderCapCondition.InvalidPrinter.selector);
        holderCap.setPrinterConfig(address(corp), address(0), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
    }

    function test_RemovePrinterConfig_ZeroSpv_Reverts() public {
        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.removePrinterConfig(address(0), address(printer));
    }

    function test_RemovePrinterConfig_ZeroPrinter_Reverts() public {
        vm.expectRevert(HolderCapCondition.InvalidPrinter.selector);
        holderCap.removePrinterConfig(address(corp), address(0));
    }

    // P8 — storage layout. The shared proxy already holds `configs` data at the namespaced position P, so that
    // member must stay at P + 0 (the slot formula of the deployed implementation); the new mapping is at P + 1.
    // SpvConfig: slot 0 = icaException, slot 1 = cap, slot 2 = the three packed bools.
    function test_StorageLayout_ConfigsKeptAtNamespaceBase() public {
        bytes32 base = keccak256("metalex.condition.secondary.holder-cap.storage.v1");
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1C, 123, false, false);
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 77, false, false);

        bytes32 spvCfgSlot = keccak256(abi.encode(address(corp), base));
        assertEq(uint256(vm.load(address(holderCap), bytes32(uint256(spvCfgSlot) + 1))), 123, "configs[spv].cap at P+0");

        bytes32 inner = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 1)));
        bytes32 printerCfgSlot = keccak256(abi.encode(address(printer), inner));
        assertEq(
            uint256(vm.load(address(holderCap), bytes32(uint256(printerCfgSlot) + 1))), 77, "printerConfigs[spv][printer].cap at P+1"
        );
    }

    function test_SetConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }

    // ── Section 12(g) limits (C2, C4) ───────────────────────────────────────────────────────────────

    function _accredited(address to) internal returns (uint256) {
        Credential memory c;
        return _mintCred(to, K_ACCREDITED, c);
    }

    function _limits(uint256 nonAccreditedCap, bool excludePlanOnly) internal {
        holderCap.setClassLimits(address(corp), address(0), nonAccreditedCap, excludePlanOnly);
    }

    function _hl(bytes memory data) internal returns (bytes memory) {
        return LedgerEntryToken(address(printer)).holderLimits(data);
    }

    function _nonAccredited() internal returns (uint256) {
        return abi.decode(_hl(abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCount, ())), (uint256));
    }

    function _label(uint256 tokenId) internal {
        _hl(abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (tokenId, true)));
    }

    // N1 + N2
    function test_NonAccreditedCap_RefusesNewNonAccreditedBuyer() public {
        _makeHolder(incumbent); // seller(1) + incumbent(1), neither accredited
        assertEq(_nonAccredited(), 2);
        _limits(2, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "2 + 1 > 2");

        // The buyer's status is read live: an accredited buyer does not use a place
        _accredited(buyer);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "accredited buyer");
    }

    function test_NonAccreditedCap_ExistingHolderBuysMore() public {
        _makeHolder(incumbent);
        _makeHolder(buyer); // count 3, above the limit; the buyer already holds
        _limits(2, false);
        assertTrue(_check(), "a larger position, not a new holder");
    }

    // N3 — revoke before expiry
    function test_NonAccreditedCap_VoidedCredential_CountsAfterResync() public {
        address accHolder = makeAddr("accHolder");
        uint256 cred = _accredited(accHolder);
        _makeHolder(accHolder);
        _makeHolder(incumbent);
        assertEq(printer.lookThroughHolderCount(), 3);
        assertEq(_nonAccredited(), 2);
        _limits(2, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "2 + 1 > 2");

        badge.void(cred, "revoked");
        assertEq(_nonAccredited(), 2, "known limit: the count is too low until a resync");
        _limits(3, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "known limit: 2 + 1 <= 3 before the resync");

        vm.prank(stranger);
        LedgerEntryToken(address(printer)).resyncHolder(accHolder);
        assertEq(_nonAccredited(), 3);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "3 + 1 > 3 after the resync");
        _limits(2, false);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "3 + 1 > 2");
    }

    // N4 — a marked buyer is a buyer who is not accredited
    function test_NonAccreditedCap_MarkedBuyerIsCounted() public {
        _makeHolder(incumbent);
        _accredited(buyer);
        _limits(2, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "accredited buyer");
        _hl(abi.encodeCall(ILedgerEntryTokenHolderLimits.setNotAccreditedMark, (buyer, true)));
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "the marked buyer counts against the limit");
    }

    // N5 — an older printer has no forwarder: refused when limits apply, as C1 when they do not
    function test_OldPrinter_RefusedOnlyWhenLimitsApply() public {
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        vm.mockCallRevert(address(printer), abi.encodeWithSelector(ILedgerEntryToken.holderLimits.selector), "");
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "no limits: as C1");

        _limits(50, false);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "second cap on an older printer: refused");
        _limits(0, true);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "plan setting on an older printer: refused");

        // N8 — configured, but no limit and the exclusion off: no new read, as C1
        _limits(0, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "nothing applies: as C1");
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 1, false, false);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "C1 cap still refuses 1 + 1 > 1");

        holderCap.removeClassLimits(address(corp), address(0));
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "limits removed: as C1");
    }

    // N6 — an answer that is not a well-formed `bytes` of at least one word is refused, not trusted
    function test_MalformedForwarderAnswer_Refused() public {
        _limits(50, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_checkOffer(holderCap, offerId, settlementId));

        bytes memory sel = abi.encodeWithSelector(ILedgerEntryToken.holderLimits.selector);
        vm.mockCall(address(printer), sel, abi.encode(uint256(0))); // one raw word, not `bytes`
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "raw word");
        vm.mockCall(address(printer), sel, abi.encode(bytes(""))); // empty `bytes`
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "empty answer");
        vm.mockCall(address(printer), sel, abi.encodePacked(uint256(0x40), uint256(32), uint256(0))); // bad offset
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "bad offset");
        vm.mockCall(address(printer), sel, abi.encodePacked(uint256(0x20), uint256(64), uint256(0))); // short
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "length past the data");
        vm.clearMockedCalls();
        assertTrue(_checkOffer(holderCap, offerId, settlementId));
    }

    // N7
    function test_SetClassLimits_ByNonAdmin_Reverts() public {
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger));
        holderCap.setClassLimits(address(corp), address(0), 1, false);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger));
        holderCap.setClassLimits(address(corp), address(printer), 1, true);
        _limits(1, false);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger));
        holderCap.removeClassLimits(address(corp), address(0));
        assertTrue(holderCap.classLimits(address(corp), address(0)).configured);

        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.setClassLimits(address(0), address(printer), 1, false);
        vm.expectRevert(HolderCapCondition.InvalidSpv.selector);
        holderCap.removeClassLimits(address(0), address(printer));
    }

    function test_ClassLimits_OtherSpvKey_NotRead() public {
        BorgAuth otherAuth = new BorgAuth(stranger);
        SpvFixture otherSpv = new SpvFixture(address(otherAuth));
        vm.startPrank(stranger);
        holderCap.setClassLimits(address(otherSpv), address(printer), 1, false);
        holderCap.setClassLimits(address(otherSpv), address(0), 1, false);
        vm.stopPrank();
        assertFalse(holderCap.classLimits(address(corp), address(printer)).configured);
        assertTrue(_check(), "corp's sale does not read another SPV's limits (1 + 1 would be > 1)");
    }

    // N9 — a printer's limits replace the SPV's; removing them falls back
    function test_ClassLimits_PrinterOverridesSpv() public {
        _makeHolder(incumbent); // non-accredited count 2
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        _limits(2, false);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "SPV limit 2");

        vm.expectEmit(true, true, false, true, address(holderCap));
        emit HolderCapCondition.ClassLimitsUpdated(address(corp), address(printer), 10, false);
        holderCap.setClassLimits(address(corp), address(printer), 10, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "printer limit 10");
        holderCap.setClassLimits(address(corp), address(printer), 0, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "printer: no limit, replaces the SPV's 2");

        vm.expectEmit(true, true, false, true, address(holderCap));
        emit HolderCapCondition.ClassLimitsRemoved(address(corp), address(printer));
        holderCap.removeClassLimits(address(corp), address(printer));
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "SPV limit 2 again");

        // A second class without its own limits uses the SPV's
        (, bytes32 offerB, bytes32 settlementB) = _postAndAcceptOnSecondClass(); // class B: seller only
        _limits(1, false);
        assertFalse(_checkOffer(holderCap, offerB, settlementB), "class B: 1 + 1 > 1 (SPV's)");
    }

    // N10 — the second cap applies with no total cap
    function test_NonAccreditedCap_AppliesWithoutTotalCap() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        _makeHolder(incumbent);
        _limits(2, false);
        assertFalse(_check(), "total cap 0, second cap 2: 2 + 1 > 2");
    }

    function test_ClassLimits_BlockUsInvestorsStillFirst() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        _accredited(buyer);
        _limits(100, false);
        assertFalse(_check(), "the no-U.S. floor precedes the limits");
    }

    // The entity look-through weight flows into the second cap, as into the total
    function test_NonAccreditedCap_EntityBuyerUsesItsWeight() public {
        _credentialBuyer("US", 3);
        _limits(3, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "seller(1) + buyer(3) > 3");
        _limits(4, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId));
    }

    // L1
    function test_PlanExclusion_PlanOnlyIncumbentLeftOut() public {
        uint256 lot = _makeHolder(incumbent);
        _label(lot);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 2, false, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "exclusion off: 2 + 1 > 2");
        _limits(0, true);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "exclusion on: 1 + 1 <= 2");

        // The same for the second cap
        _limits(1, true);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "non-accredited, excl. plan: 1 + 1 > 1");
        _limits(2, true);
        assertTrue(_checkOffer(holderCap, offerId, settlementId));
        _limits(2, false);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "exclusion off: non-accredited 2 + 1 > 2");
    }

    // L2
    function test_PlanExclusion_OneLabelledOneNot_CountedOnce() public {
        uint256 lot = _makeHolder(incumbent);
        _makeHolder(incumbent);
        _label(lot);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 2, false, false);
        _limits(0, true);
        assertEq(printer.lookThroughHolderCount(), 2);
        assertFalse(_check(), "incumbent still counts once: 2 + 1 > 2");
    }

    // L3 — a buyer who holds only plan securities is a new holder for the count when the exclusion is on
    function test_PlanExclusion_PlanOnlyBuyerUsesAPlace() public {
        uint256 lot = _makeHolder(buyer);
        _label(lot);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 2, false, false);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "exclusion off: an existing holder");
        _limits(0, true);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "exclusion on: seller(1) + buyer(1) <= 2");
        _makeHolder(incumbent);
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "exclusion on: 2 + 1 > 2, the buyer uses a place");
        _limits(0, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId), "exclusion off: still a larger position");
    }

    // L4 — no printer total matches a U.S.-only count with the exclusion
    function test_PlanExclusion_WithUsResidentCount_Refused() public {
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        _limits(0, true);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setClassLimits(address(corp), address(printer), 0, true);
        _limits(5, false); // a second cap alone is fine with the U.S.-only count

        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);
        _limits(0, true);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);

        // A printer with its own limits (exclusion off) may use a U.S.-only count; removing those limits
        // would pair it with the SPV's exclusion, so the removal is refused
        holderCap.setClassLimits(address(corp), address(printer), 0, false);
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        vm.expectRevert(HolderCapCondition.UsResidentCountWithPlanExclusion.selector);
        holderCap.removeClassLimits(address(corp), address(printer));
    }

    // L4 — the pair that no setter sees: a printer policy with a U.S.-only count set first, then the SPV's
    // exclusion. checkCondition refuses those sales.
    function test_PlanExclusion_UncatchablePair_RefusedInCheck() public {
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        holderCap.setPrinterConfig(address(corp), address(printer), HolderCapCondition.IcaException.SECTION_3C1, 100, true, false);
        assertTrue(_checkOffer(holderCap, offerId, settlementId));
        _limits(0, true); // the SPV policy has no U.S.-only count, so this setter allows it
        assertFalse(_checkOffer(holderCap, offerId, settlementId), "the printer pairs both: refused");
    }

    // Storage layout: classLimits at P + 2; ClassLimits: slot 0 = cap, slot 1 = the two packed bools.
    function test_StorageLayout_ClassLimitsAtP2() public {
        bytes32 base = keccak256("metalex.condition.secondary.holder-cap.storage.v1");
        holderCap.setClassLimits(address(corp), address(printer), 499, true);
        bytes32 inner = keccak256(abi.encode(address(corp), bytes32(uint256(base) + 2)));
        bytes32 slot = keccak256(abi.encode(address(printer), inner));
        assertEq(uint256(vm.load(address(holderCap), slot)), 499, "classLimits[spv][printer].nonAccreditedCap at P+2");
        assertEq(uint256(vm.load(address(holderCap), bytes32(uint256(slot) + 1))), 0x0101, "excludePlanOnly + configured");
        // configs and printerConfigs are where they were
        HolderCapCondition.SpvConfig memory cfg = holderCap.configs(address(corp));
        assertEq(cfg.cap, 100);
    }
}
