// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {LedgerEntryTokenStorage} from "../src/storage/LedgerEntryTokenStorage.sol";
import {LedgerEntryTokenHolderLimits} from "../src/storage/LedgerEntryTokenHolderLimits.sol";
import {ILedgerEntryTokenHolderLimits} from "../src/interfaces/ILedgerEntryTokenHolderLimits.sol";
import {CertificateDetails, ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {K_ACCREDITED, K_BO_COUNT, K_INVESTOR_TYPE, InvestorType} from "../src/interfaces/ILexChexBadge.sol";
import {MockCyberCorp, MockIssuanceManager, MockUriBuilder} from "./CyberCertPrinterTest.t.sol";

/// @dev Adds read-only debug views of the tally and the section 12(g) records, a burn (the printer has no
/// burn entry point; this runs the library's burn bookkeeping), and a wipe of the new storage that recreates
/// a printer upgraded with holders booked before LedgerEntryTokenHolderLimits existed.
contract HolderLimitsHarness is LedgerEntryToken {
    function debugHolder(address o) external view returns (uint32 liveLots, uint32 weight) {
        LedgerEntryTokenStorage.HolderAcct storage a = LedgerEntryTokenStorage.cyberCertStorage().holderAcct[o];
        return (a.liveLots, a.weight);
    }

    function debugLimit(address o) external view returns (LedgerEntryTokenStorage.HolderLimitAcct memory) {
        return LedgerEntryTokenStorage.cyberCertStorage().holderLimitAcct[o];
    }

    function debugLiveCounted(uint256 t) external view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().liveCounted[t];
    }

    function debugLabelOwner(uint256 t) external view returns (address) {
        return LedgerEntryTokenStorage.cyberCertStorage().planLot[t].labelOwner;
    }

    function debugLegalOwner(uint256 t) external view returns (address) {
        return LedgerEntryTokenStorage.cyberCertStorage().owners[t].ownerAddress;
    }

    function debugBurn(uint256 t) external {
        LedgerEntryTokenStorage.recordBurnLegalOwner(t);
        _burn(t);
    }

    /// @dev Every member that this change appended reads zero again, as on a printer upgraded with holders.
    function debugWipeHolderLimits(address[] calldata holders, uint256[] calldata tokens) external {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        for (uint256 i = 0; i < holders.length; i++) {
            delete s.holderLimitAcct[holders[i]];
            delete s.accreditedCredentialId[holders[i]];
            delete s.notAccreditedMark[holders[i]];
        }
        for (uint256 i = 0; i < tokens.length; i++) delete s.planLot[tokens[i]];
        s.accreditedLookThroughHolderCount = 0;
        s.planOnlyLookThroughHolderCount = 0;
        s.planOnlyAccreditedLookThroughHolderCount = 0;
    }
}

contract LedgerEntryTokenHolderLimitsTest is Test {
    HolderLimitsHarness internal printer;
    MockIssuanceManager internal issuanceManager;
    LeXcheXBadge internal badge;
    BorgAuth internal badgeAuth;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal erin = makeAddr("erin");
    address internal stranger = makeAddr("stranger");

    address[] internal holders;
    uint256[] internal tokens;

    function setUp() public {
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        issuanceManager = new MockIssuanceManager(address(corp), address(new MockUriBuilder()));
        HolderLimitsHarness implementation = new HolderLimitsHarness();
        bytes memory initData = abi.encodeCall(
            LedgerEntryToken.initialize,
            (
                new string[](0),
                "Mock Cert",
                "MCERT",
                "ipfs://certificate",
                address(issuanceManager),
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );
        printer = HolderLimitsHarness(address(new ERC1967Proxy(address(implementation), initData)));
        vm.prank(address(issuanceManager));
        printer.setGlobalLegalTransferable(true);

        badgeAuth = new BorgAuth(address(this));
        badge = LeXcheXBadge(
            address(new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth)))))
        );

        holders.push(alice);
        holders.push(bob);
        holders.push(carol);
        holders.push(dave);
        holders.push(erin);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

    function _details() internal pure returns (CertificateDetails memory) {
        return CertificateDetails("Officer", "CEO", 1_000, 10_000, 100, "", "");
    }

    function _wire() internal {
        vm.prank(address(issuanceManager));
        printer.setLookThroughBadge(address(badge));
    }

    function _mint(uint256 id, address to) internal {
        vm.prank(address(issuanceManager));
        printer.safeMint(id, to, _details());
        tokens.push(id);
    }

    function _assign(uint256 id, address to) internal {
        address from = printer.legalOwnerOf(id);
        vm.prank(address(issuanceManager));
        printer.assignCert(from, id, to, _details(), "");
    }

    function _void(uint256 id) internal {
        vm.prank(address(issuanceManager));
        printer.voidCert(id);
    }

    function _unvoid(uint256 id) internal {
        vm.prank(address(issuanceManager));
        printer.unvoidCert(id);
    }

    function _accredit(address h, uint64 expiry) internal returns (uint256) {
        Credential memory c;
        c.asserts = K_ACCREDITED;
        c.expiryDate = expiry;
        return badge.mint(h, c);
    }

    function _accredit(address h) internal returns (uint256) {
        return _accredit(h, uint64(block.timestamp + 3650 days));
    }

    function _entity(address h, uint32 bo) internal returns (uint256) {
        Credential memory c;
        c.asserts = K_INVESTOR_TYPE | K_BO_COUNT;
        c.investorType = InvestorType.ENTITY;
        c.beneficialOwnerCount = bo;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        return badge.mint(h, c);
    }

    /// @dev A write through the forwarder as `who`.
    function _hl(address who, bytes memory data) internal returns (bytes memory) {
        vm.prank(who);
        return printer.holderLimits(data);
    }

    /// @dev A read through the forwarder in a static call, as the holder cap condition does it.
    function _read(bytes memory data) internal view returns (bytes memory) {
        (bool ok, bytes memory ret) =
            address(printer).staticcall(abi.encodeCall(ILedgerEntryToken.holderLimits, (data)));
        require(ok, "static read failed");
        return abi.decode(ret, (bytes));
    }

    function _uint(bytes memory data) internal view returns (uint256) {
        return abi.decode(_read(data), (uint256));
    }

    function _bool(bytes memory data) internal view returns (bool) {
        return abi.decode(_read(data), (bool));
    }

    function _nonAccredited() internal view returns (uint256) {
        return _uint(abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCount, ()));
    }

    function _allExclPlan() internal view returns (uint256) {
        return _uint(abi.encodeCall(ILedgerEntryTokenHolderLimits.lookThroughHolderCountExcludingPlan, ()));
    }

    function _nonAccreditedExclPlan() internal view returns (uint256) {
        return _uint(abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCountExcludingPlan, ()));
    }

    function _planOnly(address h) internal view returns (bool) {
        return _bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.isPlanOnlyHolder, (h)));
    }

    function _isLabelled(uint256 id) internal view returns (bool) {
        return _bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.isPlanSecurity, (id)));
    }

    function _booked(address h) internal view returns (bool accredited) {
        (accredited,,) = abi.decode(
            _read(abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitAccount, (h))), (bool, uint32, uint256)
        );
    }

    function _label(uint256 id, bool value) internal {
        _hl(address(issuanceManager), abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (id, value)));
    }

    function _mark(address h, bool value) internal {
        _hl(address(issuanceManager), abi.encodeCall(ILedgerEntryTokenHolderLimits.setNotAccreditedMark, (h, value)));
    }

    function _syncHolder(address who, address h) internal {
        _hl(who, abi.encodeCall(ILedgerEntryTokenHolderLimits.syncHolder, (h)));
    }

    /// @dev The invariant: each total equals the sum over the holder accounts, and each account agrees with
    /// the printer's own records (lots, weight, labels, marks).
    function _checkSums() internal view {
        uint256 lt;
        uint256 acc;
        uint256 plan;
        uint256 planAcc;
        for (uint256 i = 0; i < holders.length; i++) {
            address h = holders[i];
            (uint32 liveLots, uint32 weight) = printer.debugHolder(h);
            LedgerEntryTokenStorage.HolderLimitAcct memory r = printer.debugLimit(h);
            uint32 expectedPlanLots;
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 t = tokens[j];
                address owner = printer.debugLegalOwner(t);
                if (owner == h && printer.debugLiveCounted(t) && printer.debugLabelOwner(t) == h) expectedPlanLots++;
            }
            assertEq(r.planLots, expectedPlanLots, "planLots matches the labelled live lots");
            bool planOnly = liveLots > 0 && r.planLots == liveLots;
            if (liveLots == 0) assertFalse(r.accredited, "no booking without a live lot");
            if (printer.debugLimit(h).accredited) {
                assertFalse(
                    _bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.notAccreditedMark, (h))), "a marked holder is never booked"
                );
            }
            uint32 w = liveLots > 0 ? weight : 0;
            assertEq(r.accreditedWeight, r.accredited ? w : 0, "accredited contribution");
            assertEq(r.planOnlyWeight, planOnly ? w : 0, "plan-only contribution");
            assertEq(r.planOnlyAccreditedWeight, (planOnly && r.accredited) ? w : 0, "plan-only accredited contribution");
            assertEq(_planOnly(h), planOnly, "isPlanOnlyHolder read");
            lt += w;
            acc += r.accreditedWeight;
            plan += r.planOnlyWeight;
            planAcc += r.planOnlyAccreditedWeight;
        }
        assertEq(printer.lookThroughHolderCount(), lt, "existing total = sum of weights");
        (uint256 tAcc, uint256 tPlan, uint256 tPlanAcc) = abi.decode(
            _read(abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitTotals, ())), (uint256, uint256, uint256)
        );
        assertEq(tAcc, acc, "accredited total = sum");
        assertEq(tPlan, plan, "plan-only total = sum");
        assertEq(tPlanAcc, planAcc, "plan-only accredited total = sum");
        assertEq(_nonAccredited(), lt - acc, "count of holders who are not accredited");
        assertEq(_allExclPlan(), lt - plan, "count with plan-only holders left out");
        assertEq(_nonAccreditedExclPlan(), lt - acc - (plan - planAcc), "count of non-accredited, plan-only left out");
    }

    // ── C2: holders who are not accredited ──────────────────────────────────────────────────────────

    // No registry wired (the state of every live printer today): every holder counts as not accredited, even
    // one that has a valid accredited credential on a badge.
    function test_NoRegistry_EveryHolderCountsAsNotAccredited() public {
        _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        _mint(3, carol);
        assertEq(printer.lookThroughHolderCount(), 3);
        assertEq(_nonAccredited(), 3);
        assertFalse(_bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.isAccredited, (alice))), "no registry: not accredited");
        _checkSums();
    }

    function test_FirstLot_BooksAccredited() public {
        _wire();
        uint256 cred = _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_nonAccredited(), 1);
        (bool accredited,, uint256 credentialId) = abi.decode(
            _read(abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitAccount, (alice))), (bool, uint32, uint256)
        );
        assertTrue(accredited);
        assertEq(credentialId, cred);
        _checkSums();
    }

    // A credential issued after the first lot is read at the next lot and at a resync by anyone.
    function test_LaterLotAndResync_BookAccredited() public {
        _wire();
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_nonAccredited(), 2);
        _accredit(alice);
        _mint(3, alice);
        assertEq(_nonAccredited(), 1, "booked at the next lot");
        _accredit(bob);
        vm.prank(stranger);
        printer.resyncHolder(bob);
        assertEq(_nonAccredited(), 0, "booked at a resync");
        _checkSums();
    }

    // The accredited total follows the booked holder's weight at a resync.
    function test_AccreditedTotal_FollowsWeight() public {
        _wire();
        _entity(alice, 5);
        _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        assertEq(printer.lookThroughHolderCount(), 6);
        assertEq(_nonAccredited(), 1);
        _entity(alice, 9);
        printer.resyncHolder(alice);
        assertEq(printer.lookThroughHolderCount(), 10);
        assertEq(_nonAccredited(), 1, "the accredited total moved with the weight");
        _checkSums();
    }

    // A lapse does not remove the booking: not after a resync, not after one more lot. A holder who leaves
    // and comes back is read again as a new holder.
    function test_Lapse_KeepsBooking_UntilTheHolderLeaves() public {
        _wire();
        _accredit(alice, uint64(block.timestamp + 1 days));
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_nonAccredited(), 1);

        vm.warp(block.timestamp + 2 days);
        assertFalse(_bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.isAccredited, (alice))), "credential lapsed");
        printer.resyncHolder(alice);
        assertEq(_nonAccredited(), 1, "still booked after a resync");
        _mint(3, alice);
        assertEq(_nonAccredited(), 1, "still booked after one more lot");
        _checkSums();

        // Alice sells both lots, then buys again: a new holder, read again, so not accredited now
        _assign(1, bob);
        _assign(3, bob);
        assertFalse(printer.isLegalHolder(alice));
        assertFalse(_booked(alice));
        _assign(1, alice);
        assertFalse(_booked(alice), "re-entry reads the badge again");
        assertEq(_nonAccredited(), 2);
        _checkSums();
    }

    // Revoked before expiry: the booking ends at the next resync. Before the resync the count is too low by
    // the holder's weight; that is the known limit (the badge does not call the printer).
    function test_Void_RemovesBooking_AtResync() public {
        _wire();
        uint256 cred = _accredit(carol);
        _mint(1, alice);
        _mint(2, bob);
        _mint(3, carol);
        assertEq(_nonAccredited(), 2);

        badge.void(cred, "revoked");
        assertEq(_nonAccredited(), 2, "known limit: unchanged until a resync");
        vm.prank(stranger);
        printer.resyncHolder(carol);
        assertEq(_nonAccredited(), 3);
        assertFalse(_booked(carol));
        _checkSums();
    }

    // A superseded credential with a new valid accredited credential keeps the booking and moves the stored id.
    function test_Supersede_WithValidAccredited_KeepsBooking() public {
        _wire();
        uint256 cred = _accredit(carol);
        _mint(1, carol);
        Credential memory c;
        c.asserts = K_ACCREDITED;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        uint256 fresh = badge.supersede(cred, c, "re-verified");
        printer.resyncHolder(carol);
        (bool accredited,, uint256 credentialId) = abi.decode(
            _read(abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitAccount, (carol))), (bool, uint32, uint256)
        );
        assertTrue(accredited);
        assertEq(credentialId, fresh);
        assertEq(_nonAccredited(), 0);

        // And voiding the new one, with no other valid credential, ends it
        badge.void(fresh, "revoked");
        printer.resyncHolder(carol);
        assertEq(_nonAccredited(), 1);
        _checkSums();
    }

    // A credential that lapsed is not revoked: voiding a different, unrelated credential changes nothing.
    function test_LapsedThenOtherCredentialVoided_KeepsBooking() public {
        _wire();
        _accredit(carol, uint64(block.timestamp + 1 days));
        _mint(1, carol);
        uint256 other = _entity(carol, 1);
        vm.warp(block.timestamp + 2 days);
        badge.void(other, "unrelated");
        printer.resyncHolder(carol);
        assertTrue(_booked(carol));
    }

    // Company mark: removes the booking at once; no resync by the holder or another account puts it back; it
    // stays after the holder leaves and returns; removing it books the holder again.
    function test_CompanyMark_SurvivesResyncAndExit() public {
        _wire();
        _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_nonAccredited(), 1);

        vm.expectEmit(true, false, false, true, address(printer));
        emit ILedgerEntryToken.NotAccreditedMarkSet(alice, true);
        _mark(alice, true);
        assertEq(_nonAccredited(), 2, "the mark removes the booking in the same call");
        assertFalse(_bool(abi.encodeCall(ILedgerEntryTokenHolderLimits.isAccredited, (alice))), "a marked buyer is not accredited");

        vm.prank(alice);
        printer.resyncHolder(alice);
        _syncHolder(alice, alice);
        _syncHolder(stranger, alice);
        vm.prank(stranger);
        printer.resyncHolder(alice);
        assertEq(_nonAccredited(), 2, "no resync puts the booking back");

        _assign(1, bob); // alice leaves
        _assign(1, alice); // and returns
        assertEq(_nonAccredited(), 2, "the mark stays after the holder leaves");
        _checkSums();

        _mark(alice, false);
        assertEq(_nonAccredited(), 1, "removing the mark books the holder again");
        printer.resyncHolder(alice);
        assertEq(_nonAccredited(), 1, "and a resync keeps it");
        _checkSums();
    }

    // A printer upgraded with holders: the new members read zero, so each holder counts as not accredited and
    // none as plan-only; the existing totals do not change. A resync lowers the count to the true number.
    function test_UpgradedWithHolders_CountsEachAsNotAccredited() public {
        _wire();
        _accredit(alice);
        _accredit(bob);
        _mint(1, alice);
        _mint(2, bob);
        _mint(3, carol);
        _label(3, true);
        uint256 lt = printer.lookThroughHolderCount();
        uint256 us = printer.usLookThroughHolderCount();

        printer.debugWipeHolderLimits(holders, tokens);
        assertEq(_nonAccredited(), 3, "each holder counts as not accredited");
        assertEq(_allExclPlan(), 3, "none is plan-only");
        assertEq(printer.lookThroughHolderCount(), lt);
        assertEq(printer.usLookThroughHolderCount(), us);
        _checkSums();

        printer.resyncHolder(alice);
        printer.resyncHolder(bob);
        assertEq(_nonAccredited(), 1, "the resync lowers it to the true number");
        // Every operation on an old account is safe: void, unvoid, owner change, label
        _void(2);
        _unvoid(2);
        _assign(3, alice);
        _label(1, true);
        _checkSums();
    }

    // MTLX1-18 case for the new total: a registry wired after the holders exist. The backfill reads it.
    function test_RegistryWiredLate_BackfillBooksHolders() public {
        _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_nonAccredited(), 2);
        _wire();
        assertEq(_nonAccredited(), 2, "nothing changes until a read");
        printer.backfillLookThroughTally(0, 10);
        assertEq(_nonAccredited(), 1);
        _checkSums();
    }

    // Unwiring the registry: a booked holder's booking ends at the next resync (the void cannot be read).
    function test_RegistryUnwired_BookingEndsAtResync() public {
        _wire();
        _accredit(alice);
        _mint(1, alice);
        assertEq(_nonAccredited(), 0);
        vm.prank(address(issuanceManager));
        printer.setLookThroughBadge(address(0));
        printer.resyncHolder(alice);
        assertEq(_nonAccredited(), 1);
        _checkSums();
    }

    // Void, unvoid, burn and a legal-owner change keep each total equal to the sum.
    function test_VoidUnvoidBurnTransfer_KeepSums() public {
        _wire();
        _accredit(alice);
        _entity(bob, 4);
        _mint(1, alice);
        _mint(2, alice);
        _mint(3, bob);
        _label(2, true);
        _checkSums();
        _void(1);
        _checkSums();
        assertTrue(_planOnly(alice), "the one live lot left is labelled");
        _unvoid(1);
        _checkSums();
        _assign(3, carol);
        _checkSums();
        printer.debugBurn(2);
        _checkSums();
        printer.debugBurn(1);
        _checkSums();
        assertFalse(printer.isLegalHolder(alice));
        assertEq(_nonAccredited(), 1);
    }

    // MTLX1-16 case for the new totals: voiding an id with no token still reverts and leaves nothing behind.
    function test_VoidNonexistent_LeavesNoTrace() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
        printer.voidCert(7);
        _mint(7, alice);
        assertEq(_nonAccredited(), 1);
        _checkSums();
    }

    // ── C4: plan label ──────────────────────────────────────────────────────────────────────────────

    function test_PlanLabel_LabelledOnlyHolderIsLeftOut() public {
        _mint(1, alice);
        _mint(2, bob);
        vm.expectEmit(true, false, false, true, address(printer));
        emit ILedgerEntryToken.PlanSecuritySet(1, true);
        _label(1, true);
        assertTrue(_isLabelled(1));
        assertTrue(_planOnly(alice));
        assertEq(printer.lookThroughHolderCount(), 2, "the full count still has alice");
        assertEq(_allExclPlan(), 1);
        assertEq(_nonAccreditedExclPlan(), 1);
        _checkSums();

        _label(1, false);
        assertFalse(_planOnly(alice));
        assertEq(_allExclPlan(), 2);
        _checkSums();
    }

    function test_PlanLabel_OneLabelledOneNot_CountsOnce() public {
        _mint(1, alice);
        _mint(2, alice);
        _label(1, true);
        assertFalse(_planOnly(alice));
        assertEq(_allExclPlan(), 1);
        _label(2, true);
        assertTrue(_planOnly(alice));
        assertEq(_allExclPlan(), 0);
        _checkSums();
    }

    // The holder sells the labelled lot: the label ends, the buyer counts, and the seller leaves the count when
    // no live lot remains.
    function test_PlanLabel_SaleRemovesLabel() public {
        _mint(1, alice);
        _label(1, true);
        assertEq(_allExclPlan(), 0);
        vm.expectEmit(true, false, false, true, address(printer));
        emit ILedgerEntryToken.PlanSecuritySet(1, false);
        _assign(1, bob);
        assertFalse(_isLabelled(1));
        assertFalse(printer.isLegalHolder(alice));
        assertFalse(_planOnly(bob));
        assertEq(_allExclPlan(), 1, "the buyer counts");
        _checkSums();
    }

    // The same through a secondary-trade reissue (a new lot minted from the seller's lot).
    function test_PlanLabel_ReissueToBuyerHasNoLabel() public {
        _mint(1, alice);
        _label(1, true);
        vm.prank(address(issuanceManager));
        printer.safeMintFromAndAssign(1, bob, bob, 2, _details(), "Bob");
        tokens.push(2);
        _void(1);
        assertFalse(_isLabelled(2));
        assertEq(_allExclPlan(), 1);
        _checkSums();
    }

    // A labelled lot sold and bought back does not get its label back.
    function test_PlanLabel_DoesNotRevive() public {
        _mint(1, alice);
        _label(1, true);
        _assign(1, bob);
        _assign(1, alice);
        assertFalse(_isLabelled(1), "no label after the buy-back");
        assertEq(printer.debugLabelOwner(1), address(0), "the record is deleted");
        assertFalse(_planOnly(alice));
        _checkSums();
        // An explicit sync changes nothing
        _hl(stranger, abi.encodeCall(ILedgerEntryTokenHolderLimits.syncLot, (1)));
        assertFalse(_isLabelled(1));
    }

    // A label on a void lot only counts once the lot is live again.
    function test_PlanLabel_OnVoidLot_CountsAtUnvoid() public {
        _mint(1, alice);
        _mint(2, alice);
        _void(2);
        _label(2, true);
        assertFalse(_planOnly(alice), "lot 1 is live and has no label");
        _label(1, true);
        assertTrue(_planOnly(alice));
        _unvoid(2);
        assertTrue(_planOnly(alice));
        _label(2, false);
        assertFalse(_planOnly(alice));
        _checkSums();
    }

    function test_PlanLabel_AccreditedPlanOnly() public {
        _wire();
        _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        _label(1, true);
        assertEq(_nonAccredited(), 1);
        assertEq(_allExclPlan(), 1);
        assertEq(_nonAccreditedExclPlan(), 1, "alice is accredited and plan-only: subtracted once");
        _checkSums();
    }

    // ── Setters: authorization ───────────────────────────────────────────────────────────────────────

    function test_Setters_RefuseNonAdmin_AllowManagerAndAdmin() public {
        _mint(1, alice);
        uint256 adminRole = issuanceManager.auth().ADMIN_ROLE();
        bytes memory refused = abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, stranger);

        vm.prank(stranger);
        vm.expectRevert(refused);
        printer.holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (1, true)));
        vm.prank(stranger);
        vm.expectRevert(refused);
        printer.holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.setNotAccreditedMark, (alice, true)));
        assertFalse(_isLabelled(1));

        // The holder itself is not an admin either
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, alice));
        printer.holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (1, true)));

        // An admin of the issuance manager's AUTH (the test contract owns it)
        printer.holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (1, true)));
        assertTrue(_isLabelled(1));
        _label(1, false); // the issuance manager
        assertFalse(_isLabelled(1));
    }

    function test_SetPlanSecurity_NonexistentToken_Reverts() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
        printer.holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (9, true)));
    }

    // ── Forwarder ────────────────────────────────────────────────────────────────────────────────────

    function _snapshotState() internal view returns (bytes32) {
        (uint256 a, uint256 b, uint256 c) = abi.decode(
            _read(abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitTotals, ())), (uint256, uint256, uint256)
        );
        return keccak256(
            abi.encode(
                printer.lookThroughHolderCount(),
                printer.usLookThroughHolderCount(),
                printer.usTallyExpiry(),
                printer.isLegalHolder(alice),
                printer.isLegalHolder(bob),
                printer.issuanceManager(),
                printer.issueTimestamp(1),
                printer.unitsReserved(1),
                a,
                b,
                c
            )
        );
    }

    function test_Forwarder_UnknownSelectorAndGarbage_Revert() public {
        _mint(1, alice);
        bytes32 before = _snapshotState();

        vm.expectRevert();
        printer.holderLimits(abi.encodeWithSignature("doesNotExist(uint256)", 1));
        vm.expectRevert();
        printer.holderLimits(hex"deadbeef00");
        vm.expectRevert();
        printer.holderLimits(hex"");
        vm.expectRevert();
        printer.holderLimits(hex"01");
        // Right selector, too-short arguments
        vm.expectRevert();
        printer.holderLimits(abi.encodePacked(ILedgerEntryTokenHolderLimits.syncLot.selector, uint8(1)));
        assertEq(_snapshotState(), before);
    }

    function test_Forwarder_BubblesRevertReasonUnchanged() public {
        _mint(1, alice);
        vm.prank(stranger);
        (bool ok, bytes memory ret) = address(printer).call(
            abi.encodeCall(
                ILedgerEntryToken.holderLimits,
                (abi.encodeCall(ILedgerEntryTokenHolderLimits.setNotAccreditedMark, (alice, true)))
            )
        );
        assertFalse(ok);
        assertEq(
            ret,
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, issuanceManager.auth().ADMIN_ROLE(), stranger)
        );
    }

    // The forwarder reaches LedgerEntryTokenHolderLimits only. Selectors of LedgerEntryTokenStorage functions
    // (which carry no access check of their own) find nothing there and revert, changing nothing.
    function test_Forwarder_CannotReachStorageLibrary() public {
        _mint(1, alice);
        bytes32 before = _snapshotState();
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSelector(LedgerEntryTokenStorage.setIssuanceManager.selector, stranger);
        calls[1] = abi.encodeWithSelector(LedgerEntryTokenStorage.setIssueTimestamp.selector, uint256(1), uint64(5));
        calls[2] = abi.encodeWithSelector(LedgerEntryTokenStorage.increaseUnitsReserved.selector, uint256(1), uint256(5));
        calls[3] = abi.encodeWithSelector(LedgerEntryTokenStorage.recordVoidLegalOwner.selector, uint256(1));
        calls[4] = abi.encodeWithSelector(LedgerEntryTokenStorage.recordBurnLegalOwner.selector, uint256(1));
        calls[5] = abi.encodeWithSelector(LedgerEntryTokenStorage.recordMint.selector, uint256(2), stranger, _details());
        calls[6] = abi.encodeWithSelector(LedgerEntryTokenStorage.setExtension.selector, stranger);
        calls[7] = abi.encodeWithSelector(LedgerEntryTokenStorage.resyncHolder.selector, alice);
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(stranger);
            vm.expectRevert();
            printer.holderLimits(calls[i]);
        }
        assertEq(_snapshotState(), before);
        assertEq(printer.issuanceManager(), address(issuanceManager));
    }

    // A sync needs no static context; a view through a static call works; a write in a static call fails.
    function test_Forwarder_StaticCallOfSyncFails() public {
        _mint(1, alice);
        (bool ok,) = address(printer).staticcall{gas: 1_000_000}(
            abi.encodeCall(ILedgerEntryToken.holderLimits, (abi.encodeCall(ILedgerEntryTokenHolderLimits.syncHolder, (alice))))
        );
        assertFalse(ok, "a sync writes, so a static call of it fails");
        assertEq(_nonAccredited(), 1);
    }

    // Calling the library directly (not through a printer) cannot write: Solidity's library call guard.
    function test_Library_DirectCallOfWriteReverts() public {
        address lib = address(LedgerEntryTokenHolderLimits);
        (bool ok,) = lib.call(abi.encodeCall(ILedgerEntryTokenHolderLimits.syncHolder, (alice)));
        assertFalse(ok);
    }

    // ── Any-caller safety: fuzzed sequence ──────────────────────────────────────────────────────────

    struct Before {
        uint256 lt;
        uint256 us;
        uint64 expiry;
        bytes32 legalHolders;
    }

    function _baseReads() internal view returns (Before memory b) {
        b.lt = printer.lookThroughHolderCount();
        b.us = printer.usLookThroughHolderCount();
        b.expiry = printer.usTallyExpiry();
        bool[] memory lh = new bool[](holders.length);
        for (uint256 i = 0; i < holders.length; i++) lh[i] = printer.isLegalHolder(holders[i]);
        b.legalHolders = keccak256(abi.encode(lh));
    }

    function _sameBase(Before memory a, Before memory b) internal pure {
        assertEq(a.lt, b.lt, "lookThroughHolderCount unchanged by a forwarder call");
        assertEq(a.us, b.us, "usLookThroughHolderCount unchanged by a forwarder call");
        assertEq(a.expiry, b.expiry, "usTallyExpiry unchanged by a forwarder call");
        assertEq(a.legalHolders, b.legalHolders, "isLegalHolder unchanged by a forwarder call");
    }

    uint256[] internal creds;

    /// @dev One unprivileged forwarder call with fuzzed arguments.
    function _randomForwarderCall(uint256 seed) internal {
        address caller = address(uint160(uint256(keccak256(abi.encode(seed, "caller")))));
        if (caller == address(issuanceManager) || caller == address(this)) caller = stranger;
        address anyAddr = (seed >> 8) % 3 == 0
            ? holders[(seed >> 16) % holders.length]
            : address(uint160(uint256(keccak256(abi.encode(seed, "addr")))));
        uint256 anyId = (seed >> 24) % 3 == 0 ? (seed >> 32) % 8 : uint256(keccak256(abi.encode(seed, "id")));
        uint256 kind = (seed >> 40) % 14;
        bytes memory data;
        bool expectAdminRevert;
        if (kind == 0) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.syncHolder, (anyAddr));
        else if (kind == 1) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.syncLot, (anyId));
        else if (kind == 2) {
            data = abi.encodeCall(ILedgerEntryTokenHolderLimits.setPlanSecurity, (anyId, seed & 1 == 1));
            expectAdminRevert = true;
        } else if (kind == 3) {
            data = abi.encodeCall(ILedgerEntryTokenHolderLimits.setNotAccreditedMark, (anyAddr, seed & 1 == 1));
            expectAdminRevert = true;
        } else if (kind == 4) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCount, ());
        else if (kind == 5) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.lookThroughHolderCountExcludingPlan, ());
        else if (kind == 6) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCountExcludingPlan, ());
        else if (kind == 7) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitTotals, ());
        else if (kind == 8) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.isAccredited, (anyAddr));
        else if (kind == 9) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.isPlanOnlyHolder, (anyAddr));
        else if (kind == 10) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.isPlanSecurity, (anyId));
        else if (kind == 11) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.notAccreditedMark, (anyAddr));
        else if (kind == 12) data = abi.encodeCall(ILedgerEntryTokenHolderLimits.holderLimitAccount, (anyAddr));
        else data = abi.encodePacked(bytes4(uint32(seed >> 48)), keccak256(abi.encode(seed))); // garbage

        Before memory b = _baseReads();
        vm.prank(caller);
        (bool ok, bytes memory ret) = address(printer).call(abi.encodeCall(ILedgerEntryToken.holderLimits, (data)));
        if (expectAdminRevert) {
            assertFalse(ok, "an unprivileged setter call reverts");
            assertEq(bytes4(ret), BorgAuth.BorgAuth_NotAuthorized.selector);
        }
        _sameBase(b, _baseReads());
    }

    function _step(uint256 op) internal {
        uint256 action = op % 12;
        address h = holders[(op >> 8) % holders.length];
        uint256 id = 1 + ((op >> 16) % 6);
        bool exists = printer.debugLegalOwner(id) != address(0) || _minted(id);
        if (action == 0) {
            if (!_minted(id)) _mint(id, h);
        } else if (action == 1) {
            if (exists && !printer.isVoided(id) && printer.legalOwnerOf(id) != h) _assign(id, h);
        } else if (action == 2) {
            if (exists) _void(id);
        } else if (action == 3) {
            if (exists) _unvoid(id);
        } else if (action == 4) {
            if (exists && printer.legalOwnerOf(id) != address(0)) _label(id, (op >> 24) & 1 == 1);
        } else if (action == 5) {
            _mark(h, (op >> 24) & 1 == 1);
        } else if (action == 6) {
            creds.push(_accredit(h, uint64(block.timestamp + 1 + ((op >> 32) % 30 days))));
        } else if (action == 7) {
            if (creds.length > 0) {
                uint256 c = creds[(op >> 32) % creds.length];
                if (bytes(badge.getCredential(c).voided).length == 0) badge.void(c, "revoked");
            }
        } else if (action == 8) {
            printer.resyncHolder(h);
        } else if (action == 9) {
            vm.warp(block.timestamp + ((op >> 32) % 20 days));
        } else if (action == 10) {
            if ((op >> 24) & 1 == 1) _entity(h, uint32(1 + ((op >> 32) % 9)));
            else printer.backfillLookThroughTally(0, 10);
        } else {
            _randomForwarderCall(uint256(keccak256(abi.encode(op))));
        }
    }

    function _minted(uint256 id) internal view returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) if (tokens[i] == id) return true;
        return false;
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_AnyCaller_SequenceKeepsSums(uint256[24] memory ops, bool wired) public {
        if (wired) _wire();
        for (uint256 i = 0; i < ops.length; i++) {
            _step(ops[i]);
            // An unprivileged forwarder call after every step, too
            _randomForwarderCall(uint256(keccak256(abi.encode(ops[i], i))));
            _checkSums();
        }
    }

    /// @dev Fuzzed forwarder calls only, on a populated printer: nothing a stranger sends moves the existing
    /// reads, and the sums hold.
    function testFuzz_AnyCaller_ForwarderOnly(uint256[16] memory seeds) public {
        _wire();
        _accredit(alice);
        _entity(bob, 3);
        _mint(1, alice);
        _mint(2, bob);
        _mint(3, carol);
        _label(3, true);
        for (uint256 i = 0; i < seeds.length; i++) {
            _randomForwarderCall(seeds[i]);
            _checkSums();
        }
    }
}
