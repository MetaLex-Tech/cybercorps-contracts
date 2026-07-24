// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {
    ATTR_BO_COUNT,
    ATTR_INVESTOR_JURISDICTION,
    ATTR_REGULATORY_JURISDICTION,
    ATTR_US_STATE,
    CategoryKind,
    Credential
} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {HolderCapCondition} from "../../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// HolderCapCondition — ICA §3(c)(1)/§3(c)(1)(C)/§3(c)(7) holder limits at transfer time.
//
// Real integration (see SecondaryConditionIntegrationBase): each scenario posts + accepts a real sell offer,
// so checkCondition reads a genuine Offer + SecondaryEscrow. Acceptance materializes the escrow (counterparty
// = buyer) with NO transfer — that happens at finalize — so the printer's §3(c)(1)(A) look-through tally is
// still the pre-transfer count the condition reads, derived from each holder's badge beneficial-owner count /
// U.S. classification. The condition is deliberately NOT wired as a pathway threshold, so acceptance always
// succeeds and the test asserts checkCondition's boolean directly.
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
// |  9 | blockUsInvestors, non-U.S. buyer                |  pass  | floor only bites U.S. buyers          |
// | 10 | usResidentOnlyCount, non-U.S. buyer             |  pass  | non-U.S. acquirer not counted         |
// | 11 | usResidentOnlyCount, fresh U.S. buyer at cap    |  fail  | only U.S. residents counted, breaches |
//
// Config/authorization
// | # | case                              | expect              |
// |---|-----------------------------------|---------------------|
// |12 | initialize zero badge             | revert InvalidBadge |
// |13 | updateConfig by stranger          | revert (not admin)  |
// |14 | updateBadge by stranger           | revert (not admin)  |
//
// Operational staleness: a re-credential that changes an existing holder's BO count does not reach the
// printer's cached tally until a keeper resync (15).
// ─────────────────────────────────────────────────────────────────────────────

contract HolderCapConditionTest is SecondaryConditionIntegrationBase {
    HolderCapCondition internal holderCap;
    address internal incumbent = makeAddr("incumbent");
    bytes32 internal constant CAT_ACCREDITED = keccak256("cat.accredited");

    // Mirror of LeXcheXBadge.CredentialAttributesUpdated for expectEmit.
    event CredentialAttributesUpdated(uint256 indexed tokenId, bytes2 usState, uint32 beneficialOwnerCount);

    function setUp() public {
        _setUpIntegration();
        _createCategory(
            CAT_ACCREDITED,
            CategoryKind.ACCREDITED_INVESTOR,
            address(0),
            ATTR_INVESTOR_JURISDICTION | ATTR_REGULATORY_JURISDICTION | ATTR_US_STATE | ATTR_BO_COUNT
        );
        holderCap = HolderCapCondition(
            _proxy(
                address(new HolderCapCondition()),
                abi.encodeCall(
                    HolderCapCondition.initialize,
                    (address(auth), address(badge), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false)
                )
            )
        );
        _credential(buyer, "US", 0);
    }

    /// @dev Issues an accredited credential; the newest valid one governs the reads, so a later call in a
    /// test supersedes the setUp default (jurisdiction / beneficial-owner count).
    function _credential(address to, string memory jurisdiction, uint32 boCount) internal {
        Credential memory c;
        c.investorName = "Inv";
        c.investorType = "Fund";
        c.investorJurisdiction = jurisdiction;
        c.beneficialOwnerCount = boCount;
        _mintCred(to, CAT_ACCREDITED, c);
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
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        _seedHolder("KY", 499); // tally 500, but cap 0 => no numeric cap
        assertTrue(_check());
    }

    // 8
    function test_BlockUsInvestors_UsBuyer_Fails() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        assertFalse(_check());
    }

    // 9
    function test_BlockUsInvestors_NonUsBuyer_Passes() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        _credentialBuyer("KY", 0);
        assertTrue(_check());
    }

    // 10
    function test_UsResidentOnlyCount_NonUsBuyer_NotCounted_Passes() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        _credentialBuyer("KY", 0);
        // Even with a "full" U.S. tally, a non-U.S. acquirer does not add to the U.S.-resident count.
        _seedHolder("US", 1);
        assertTrue(_check());
    }

    // 11
    function test_UsResidentOnlyCount_UsBuyerBreaches_Fails() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        // The printer's U.S.-resident look-through tally already stands at the cap (= 1). A fresh U.S.
        // buyer would make 2 > cap 1.
        _seedHolder("US", 1);
        assertFalse(_check());
    }

    // ── Config / authorization ──────────────────────────────────────────────────

    // 12
    function test_Initialize_ZeroBadge_Reverts() public {
        HolderCapCondition impl = new HolderCapCondition();
        vm.expectRevert(HolderCapCondition.InvalidBadge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(
                HolderCapCondition.initialize,
                (address(auth), address(0), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false)
            )
        );
    }

    // 13
    function test_UpdateConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }

    // 14
    function test_UpdateBadge_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.updateBadge(address(badge));
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
        uint256 credId = badge.getCredentialByOwner(incumbent);

        // A single posted+accepted offer, evaluated before and after the keeper resync (a second postOffer on
        // the same cert would revert on the still-reserved units, so we re-check the same settlement).
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();

        // Admin re-credentials the incumbent: BO count 90 -> 99. The badge emits the attribute update, but
        // nothing pokes the printer.
        vm.expectEmit(true, false, false, true, address(badge));
        emit CredentialAttributesUpdated(credId, bytes2(0), 99);
        badge.updateAttributes(credId, bytes2(0), 99);

        // The badge now reports 99, yet the printer's cached tally is still the pre-update snapshot (91).
        assertEq(badge.getBeneficialOwnerCount(incumbent), 99, "badge reflects the re-credential");
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
}
