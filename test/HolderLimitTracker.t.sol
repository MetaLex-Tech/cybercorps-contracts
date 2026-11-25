// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {LedgerEntryTokenStorage} from "../src/storage/LedgerEntryTokenStorage.sol";
import {HolderLimitTracker} from "../src/HolderLimitTracker.sol";
import {IHolderLimitTracker} from "../src/interfaces/IHolderLimitTracker.sol";
import {CertificateDetails, ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {K_ACCREDITED, K_BO_COUNT, K_INVESTOR_TYPE, InvestorType} from "../src/interfaces/ILexChexBadge.sol";
import {MockCyberCorp, MockIssuanceManager, MockUriBuilder} from "./CyberCertPrinterTest.t.sol";

/// @dev Adds a burn: the printer has no burn entry point, so this runs the library's burn bookkeeping.
contract TrackerPrinterHarness is LedgerEntryToken {
    function debugBurn(uint256 t) external {
        LedgerEntryTokenStorage.recordBurnLegalOwner(t);
        _burn(t);
    }
}

/// @dev A tracker that accepts the attach and then refuses every lot change, and uses all its gas when told
/// it is detached: the printer must still be able to leave it.
contract HostileTracker {
    function onAttach() external {}

    function onLotChange(uint256, address, bool) external pure {
        revert("hostile");
    }

    function onDetach() external view {
        uint256 i;
        while (gasleft() > 0) i++;
    }
}

/// @dev A registry that answers every read with malformed data.
contract MalformedBadge {
    function getEffectiveBeneficialOwnerCount(address) external pure returns (uint256, uint256) {
        return (uint256(1) << 40, 0); // more than a uint32
    }

    function getMostRecentValidWith(address, uint256) external pure returns (uint256, uint256) {
        return (7, 2); // a `found` word that is not a bool
    }

    function getCredential(uint256) external pure returns (bytes memory) {
        return hex"deadbeef"; // not a Credential
    }
}

/// @dev A registry that first answers a valid accredited credential, then nothing valid and a malformed
/// credential record, so the void check of a booked holder reads malformed data.
contract SwitchableBadge {
    bool public broken;

    function breakIt() external {
        broken = true;
    }

    function getEffectiveBeneficialOwnerCount(address) external pure returns (uint32, uint64) {
        return (0, 0);
    }

    function getMostRecentValidWith(address, uint256) external view returns (uint256, bool) {
        return broken ? (0, false) : (5, true);
    }

    function getCredential(uint256) external pure returns (bytes memory) {
        return hex"deadbeef";
    }
}

/// @dev A minimal printer that drives the tracker directly, for registry answers that a real printer's own
/// tally would refuse first.
contract FakePrinter {
    address public lookThroughBadge;

    constructor(address badge) {
        lookThroughBadge = badge;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function attach(IHolderLimitTracker tracker) external {
        tracker.onAttach();
    }

    function report(IHolderLimitTracker tracker, uint256 tokenId, address owner, bool live) external {
        tracker.onLotChange(tokenId, owner, live);
    }
}

contract HolderLimitTrackerTest is Test {
    TrackerPrinterHarness internal printer;
    MockIssuanceManager internal issuanceManager;
    LeXcheXBadge internal badge;
    HolderLimitTracker internal tracker;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal stranger = makeAddr("stranger");

    address[] internal holders;
    uint256[] internal tokens;

    function setUp() public {
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        issuanceManager = new MockIssuanceManager(address(corp), address(new MockUriBuilder()));
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
        printer = TrackerPrinterHarness(address(new ERC1967Proxy(address(new TrackerPrinterHarness()), initData)));
        vm.prank(address(issuanceManager));
        printer.setGlobalLegalTransferable(true);

        BorgAuth badgeAuth = new BorgAuth(address(this));
        badge = LeXcheXBadge(
            address(new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth)))))
        );
        vm.prank(address(issuanceManager));
        printer.setLookThroughBadge(address(badge));

        BorgAuth trackerAuth = new BorgAuth(address(this));
        tracker = HolderLimitTracker(
            address(
                new ERC1967Proxy(
                    address(new HolderLimitTracker()), abi.encodeCall(HolderLimitTracker.initialize, (address(trackerAuth)))
                )
            )
        );

        holders.push(alice);
        holders.push(bob);
        holders.push(carol);
        holders.push(dave);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

    function _details() internal pure returns (CertificateDetails memory) {
        return CertificateDetails("Officer", "CEO", 1_000, 10_000, 100, "", "");
    }

    function _attach() internal {
        vm.prank(address(issuanceManager));
        printer.setHolderTracker(address(tracker));
    }

    function _detach() internal {
        vm.prank(address(issuanceManager));
        printer.setHolderTracker(address(0));
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

    function _label(uint256 id, bool value) internal {
        vm.prank(address(issuanceManager));
        tracker.setPlanSecurity(address(printer), id, value);
    }

    function _mark(address h, bool value) internal {
        vm.prank(address(issuanceManager));
        tracker.setNotAccreditedMark(address(printer), h, value);
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

    function _counts() internal view returns (IHolderLimitTracker.Counts memory) {
        return tracker.counts(address(printer));
    }

    function _rec(address h) internal view returns (IHolderLimitTracker.HolderRecord memory) {
        return tracker.holderRecord(address(printer), h);
    }

    function _live(uint256 id) internal view returns (bool) {
        return !printer.isVoided(id);
    }

    /// @dev T1 and T2: each holder's live lots and plan-only state match the printer and the labels; every total
    /// is the number of holders of record in that state (each legal owner with a live lot once); and the total
    /// never exceeds the printer's look-through tally, which counts an entity as its beneficial owners.
    function _checkBook() internal view {
        uint256 total;
        uint256 accredited;
        uint256 planOnly;
        uint256 planOnlyAccredited;
        uint256 owners;
        for (uint256 i = 0; i < holders.length; i++) {
            address h = holders[i];
            uint32 live;
            uint32 planned;
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 id = tokens[j];
                if (printer.legalOwnerOf(id) != h || !_live(id)) continue;
                live++;
                if (tracker.isPlanSecurity(address(printer), id)) planned++;
            }
            IHolderLimitTracker.HolderRecord memory r = _rec(h);
            assertEq(r.liveLots, live, "live lots");
            assertEq(r.planLots, planned, "plan lots");
            assertEq(r.planOnly, live > 0 && planned == live, "plan-only");
            assertEq(r.counted, live > 0, "counted iff live");
            if (live > 0) owners++;
            if (!r.counted) continue;
            total += 1;
            if (r.accredited) accredited += 1;
            if (r.planOnly) planOnly += 1;
            if (r.accredited && r.planOnly) planOnlyAccredited += 1;
        }
        IHolderLimitTracker.Counts memory c = _counts();
        assertEq(c.total, total, "total");
        assertEq(c.nonAccredited, total - accredited, "non-accredited");
        assertEq(c.totalExcludingPlan, total - planOnly, "excluding plan");
        assertEq(c.nonAccreditedExcludingPlan, (total - accredited) - (planOnly - planOnlyAccredited), "non-accredited excluding plan");
        assertEq(c.total, owners, "one per legal owner with a live lot");
        assertLe(c.total, printer.lookThroughHolderCount(), "never above the look-through tally");
    }

    // ── Opt-in and attach ──────────────────────────────────────────────────────────────────────────

    function test_NoTracker_PrinterMakesNoCall() public {
        vm.expectCall(address(tracker), abi.encodeWithSelector(IHolderLimitTracker.onLotChange.selector), 0);
        _mint(1, alice);
        _assign(1, bob);
        _void(1);
        _unvoid(1);
        assertFalse(tracker.isAttached(address(printer)));
        assertFalse(tracker.isReady(address(printer)));
        assertEq(_counts().total, 0);
    }

    function test_Attach_EmptyPrinter_ReadyAtOnce() public {
        _attach();
        assertTrue(tracker.isAttached(address(printer)));
        assertTrue(tracker.isReady(address(printer)));
        _mint(1, alice);
        _mint(2, bob);
        assertEq(_counts().total, 2);
        assertEq(_counts().nonAccredited, 2);
        _checkBook();
    }

    function test_Attach_WithHolders_ReadyAfterBackfillInBatches() public {
        _mint(1, alice);
        _mint(2, bob);
        _mint(3, bob);
        _attach();
        assertFalse(tracker.isReady(address(printer)), "holders from before the attach are not counted yet");

        tracker.backfill(address(printer), 1);
        (,,, uint256 cursor, uint256 target, bool ready) = tracker.backfillState(address(printer));
        assertEq(cursor, 1);
        assertEq(target, 3);
        assertFalse(ready);

        // A change during the backfill reaches the book through the printer; the backfill re-reads it later
        _mint(4, carol);
        tracker.backfill(address(printer), 10);
        assertTrue(tracker.isReady(address(printer)));
        assertEq(_rec(bob).liveLots, 2);
        _checkBook();
    }

    function test_SyncAndBackfill_NotAttached_Revert() public {
        _mint(1, alice);
        vm.expectRevert(IHolderLimitTracker.NotAttached.selector);
        tracker.backfill(address(printer), 1);
        vm.expectRevert(IHolderLimitTracker.NotAttached.selector);
        tracker.syncLot(address(printer), 1);
        vm.expectRevert(IHolderLimitTracker.NotAttached.selector);
        tracker.syncHolder(address(printer), alice);
    }

    // ── Lot paths (T2) ─────────────────────────────────────────────────────────────────────────────

    function test_EveryLotPath_KeepsTheBook() public {
        _attach();
        _mint(1, alice);
        _checkBook();
        _mint(2, alice);
        _checkBook();
        _assign(1, bob); // sale
        _checkBook();
        _void(2); // alice's last live lot
        assertEq(_rec(alice).liveLots, 0);
        _checkBook();
        _unvoid(2);
        _checkBook();
        printer.debugBurn(1); // bob's only lot
        tokens[0] = tokens[1];
        tokens.pop();
        assertFalse(_rec(bob).counted);
        _checkBook();
    }

    /// Section 12(g) counts holders of record: an entity with 5 beneficial owners is one holder here, while the
    /// printer's Investment Company Act look-through tally counts it as 5.
    function test_Entity_CountsAsOneHolderOfRecord() public {
        _attach();
        _entity(alice, 5);
        _mint(1, alice);
        _mint(2, alice);
        _mint(3, bob);
        assertTrue(_rec(alice).counted);
        assertEq(_counts().total, 2, "alice and bob, one each");
        assertEq(_counts().nonAccredited, 2);
        assertEq(printer.lookThroughHolderCount(), 6, "the look-through tally is unchanged");
        _checkBook();
        // A later credential with more beneficial owners changes nothing here
        _entity(alice, 40);
        tracker.syncHolder(address(printer), alice);
        assertEq(_counts().total, 2);
        _checkBook();
    }

    // ── Accreditation ──────────────────────────────────────────────────────────────────────────────

    function test_Accredited_BookedAtChange() public {
        _attach();
        uint256 id = _accredit(alice);
        _mint(1, alice);
        _mint(2, bob);
        assertTrue(_rec(alice).accredited);
        assertEq(_rec(alice).credentialId, id);
        assertEq(_counts().nonAccredited, 1, "only bob");
        assertTrue(tracker.isAccredited(address(printer), alice));
        assertFalse(tracker.isAccredited(address(printer), bob));
        _checkBook();
    }

    function test_Accredited_LapseKeepsBooking() public {
        _attach();
        _accredit(alice, uint64(block.timestamp + 1 days));
        _mint(1, alice);
        vm.warp(block.timestamp + 2 days);
        tracker.syncHolder(address(printer), alice);
        assertTrue(_rec(alice).accredited, "a lapse does not remove the booking");
        assertTrue(tracker.isAccredited(address(printer), alice), "the buyer rule follows the booking");
        assertEq(_counts().nonAccredited, 0);
    }

    function test_Accredited_VoidEndsBookingAtNextSync() public {
        _attach();
        uint256 id = _accredit(alice);
        _mint(1, alice);
        badge.void(id, "withdrawn");
        assertTrue(_rec(alice).accredited, "pull: not yet synced");
        assertFalse(tracker.isAccredited(address(printer), alice), "the buyer rule reads the void at once");
        tracker.syncHolder(address(printer), alice);
        assertFalse(_rec(alice).accredited);
        assertEq(_rec(alice).credentialId, 0);
        assertEq(_counts().nonAccredited, 1);
    }

    function test_Accredited_SupersededCredentialMovesBooking() public {
        _attach();
        uint256 first = _accredit(alice);
        _mint(1, alice);
        Credential memory c;
        c.asserts = K_ACCREDITED;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        uint256 second = badge.supersede(first, c, "renewed");
        tracker.syncHolder(address(printer), alice);
        assertTrue(_rec(alice).accredited);
        assertEq(_rec(alice).credentialId, second);
    }

    function test_Mark_OverridesRegistryAndPersistsAcrossReattach() public {
        _attach();
        _accredit(alice);
        _mint(1, alice);
        _mark(alice, true);
        assertFalse(_rec(alice).accredited);
        assertFalse(tracker.isAccredited(address(printer), alice));
        assertEq(_counts().nonAccredited, 1);

        _detach();
        _attach();
        tracker.backfill(address(printer), 10);
        assertTrue(tracker.notAccreditedMark(address(printer), alice), "the mark is kept across generations");
        assertFalse(_rec(alice).accredited);

        _mark(alice, false);
        assertTrue(_rec(alice).accredited, "removing the mark books the holder again");
        _checkBook();
    }

    // ── Plan label ─────────────────────────────────────────────────────────────────────────────────

    function test_PlanLabel_PlanOnlyNeedsEveryLiveLot() public {
        _attach();
        _mint(1, alice);
        _mint(2, alice);
        _mint(3, bob);
        _label(1, true);
        assertFalse(_rec(alice).planOnly);
        assertEq(_counts().totalExcludingPlan, 2);
        _label(2, true);
        assertTrue(_rec(alice).planOnly);
        assertTrue(tracker.isPlanOnlyHolder(address(printer), alice));
        assertFalse(tracker.isPlanOnlyHolder(address(printer), bob));
        assertEq(_counts().totalExcludingPlan, 1);
        assertEq(_counts().nonAccreditedExcludingPlan, 1);
        _checkBook();
        _label(2, false);
        assertFalse(_rec(alice).planOnly);
        _checkBook();
    }

    function test_PlanLabel_SaleClearsAndBuyBackDoesNotRevive() public {
        _attach();
        _mint(1, alice);
        _label(1, true);
        assertTrue(tracker.isPlanSecurity(address(printer), 1));
        _assign(1, bob);
        assertFalse(tracker.isPlanSecurity(address(printer), 1));
        assertFalse(_rec(bob).planOnly);
        _assign(1, alice);
        assertFalse(tracker.isPlanSecurity(address(printer), 1), "a buy-back does not revive the label");
        assertFalse(_rec(alice).planOnly);
        _checkBook();
    }

    function test_PlanLabel_VoidedLotLeavesAndReturnsWithLabel() public {
        _attach();
        _mint(1, alice);
        _mint(2, alice);
        _label(1, true);
        _void(2);
        assertTrue(_rec(alice).planOnly, "the only live lot has the label");
        _unvoid(2);
        assertFalse(_rec(alice).planOnly);
        _checkBook();
    }

    function test_PlanLabel_NoLegalOwner_Reverts() public {
        _attach();
        vm.prank(address(issuanceManager));
        vm.expectRevert(IHolderLimitTracker.NoLegalOwner.selector);
        tracker.setPlanSecurity(address(printer), 99, true);
    }

    function test_AdminSetters_RefuseNonAdmin() public {
        _attach();
        _mint(1, alice);
        vm.startPrank(stranger);
        vm.expectRevert();
        tracker.setPlanSecurity(address(printer), 1, true);
        vm.expectRevert();
        tracker.setNotAccreditedMark(address(printer), alice, true);
        vm.stopPrank();
        // An admin of the issuance manager's AUTH (its owner here) may set both
        tracker.setPlanSecurity(address(printer), 1, true);
        tracker.setNotAccreditedMark(address(printer), alice, true);
        assertTrue(tracker.isPlanSecurity(address(printer), 1));
    }

    // ── Detach, re-attach, a hostile tracker (T8, T10) ─────────────────────────────────────────────

    function test_DetachAndReattach_StartsANewBook() public {
        _attach();
        _mint(1, alice);
        _label(1, true);
        _detach();
        assertFalse(tracker.isAttached(address(printer)));
        assertFalse(tracker.isReady(address(printer)));
        assertEq(_counts().total, 0);

        vm.expectCall(address(tracker), abi.encodeWithSelector(IHolderLimitTracker.onLotChange.selector), 0);
        _assign(1, bob);

        _attach();
        (, uint64 generation,,,, bool ready) = tracker.backfillState(address(printer));
        assertEq(generation, 2);
        assertFalse(ready);
        tracker.backfill(address(printer), 10);
        assertFalse(tracker.isPlanSecurity(address(printer), 1), "labels do not carry over");
        assertEq(_rec(bob).liveLots, 1);
        _checkBook();
    }

    function test_HostileTracker_BlocksChangesUntilAdminLeavesIt() public {
        HostileTracker hostile = new HostileTracker();
        vm.prank(address(issuanceManager));
        printer.setHolderTracker(address(hostile));

        vm.prank(address(issuanceManager));
        vm.expectRevert(bytes("hostile"));
        printer.safeMint(1, alice, _details());

        // Its onDetach uses all the gas it is given; the switch still succeeds
        vm.prank(address(issuanceManager));
        printer.setHolderTracker(address(0));
        _mint(1, alice);
        assertEq(printer.lookThroughHolderCount(), 1);
    }

    function test_SetHolderTracker_NonAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        printer.setHolderTracker(address(tracker));
    }

    // ── Who writes a book (T3) ─────────────────────────────────────────────────────────────────────

    function test_Writes_KeyedBySender() public {
        _attach();
        _mint(1, alice);
        IHolderLimitTracker.Counts memory before = _counts();

        // Not attached: ignored
        vm.prank(stranger);
        tracker.onLotChange(1, bob, true);
        // Attached as itself: writes only its own book
        vm.startPrank(stranger);
        tracker.onAttach();
        tracker.onLotChange(1, bob, true);
        tracker.onDetach();
        vm.stopPrank();

        assertEq(_counts().total, before.total);
        assertEq(_rec(bob).liveLots, 0);
        assertTrue(tracker.isAttached(address(printer)), "another sender cannot detach the printer");
        _checkBook();
    }

    // ── Registry answers (T7) ──────────────────────────────────────────────────────────────────────

    function test_MalformedRegistry_NeverRevertsASync() public {
        FakePrinter fake = new FakePrinter(address(new MalformedBadge()));
        fake.attach(tracker);
        fake.report(tracker, 1, alice, true);
        IHolderLimitTracker.HolderRecord memory r = tracker.holderRecord(address(fake), alice);
        assertTrue(r.counted, "counted as one holder of record");
        assertFalse(r.accredited, "a malformed found word reads as not found");
        assertFalse(tracker.isAccredited(address(fake), alice));
        assertEq(tracker.counts(address(fake)).nonAccredited, 1);
    }

    function test_MalformedCredentialRecord_ReadsVoided() public {
        SwitchableBadge sb = new SwitchableBadge();
        FakePrinter fake = new FakePrinter(address(sb));
        fake.attach(tracker);
        fake.report(tracker, 1, alice, true);
        assertTrue(tracker.holderRecord(address(fake), alice).accredited);
        assertEq(tracker.holderRecord(address(fake), alice).credentialId, 5);

        sb.breakIt();
        assertFalse(tracker.isAccredited(address(fake), alice), "a record that cannot be decoded reads voided");
        tracker.syncHolder(address(fake), alice);
        assertFalse(tracker.holderRecord(address(fake), alice).accredited);
        assertEq(tracker.counts(address(fake)).nonAccredited, 1);
    }

    function test_RevertingRegistry_NeverRevertsASync() public {
        FakePrinter fake = new FakePrinter(address(new HostileTracker())); // no registry functions: every read fails
        fake.attach(tracker);
        fake.report(tracker, 1, alice, true);
        assertTrue(tracker.holderRecord(address(fake), alice).counted);
        assertEq(tracker.counts(address(fake)).nonAccredited, 1);
    }

    // ── Gas (reported, not asserted) ───────────────────────────────────────────────────────────────

    function _gasMintAndSale(uint256 firstId) internal returns (uint256 mintGas, uint256 saleGas) {
        address from = makeAddr(string.concat("seller ", vm.toString(firstId)));
        address to = makeAddr(string.concat("buyer ", vm.toString(firstId)));
        _accredit(to);
        vm.startPrank(address(issuanceManager));
        uint256 g = gasleft();
        printer.safeMint(firstId, from, _details());
        mintGas = g - gasleft();
        g = gasleft();
        printer.assignCert(from, firstId, to, _details(), "");
        saleGas = g - gasleft();
        vm.stopPrank();
    }

    function test_Gas_WithAndWithoutTracker() public {
        _mint(100, carol); // a printer that already has a holder
        uint256 snap = vm.snapshotState();
        (uint256 mintOff, uint256 saleOff) = _gasMintAndSale(1);
        vm.revertToState(snap);
        _attach();
        tracker.backfill(address(printer), 10);
        (uint256 mintOn, uint256 saleOn) = _gasMintAndSale(1);
        emit log_named_uint("mint, no tracker", mintOff);
        emit log_named_uint("mint, tracker", mintOn);
        emit log_named_uint("change of legal owner, no tracker", saleOff);
        emit log_named_uint("change of legal owner, tracker", saleOn);
    }

    // ── Fuzz (T1, T2) ──────────────────────────────────────────────────────────────────────────────

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_RandomOperations_KeepTheBook(uint256 seed) public {
        _attach();
        uint256[] memory credentials = new uint256[](holders.length);
        uint256 nextId = 1;
        for (uint256 step = 0; step < 40; step++) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            uint256 op = r % 10;
            address h = holders[(r >> 8) % holders.length];
            if (op == 0 || tokens.length == 0) {
                _mint(nextId++, h);
            } else {
                uint256 id = tokens[(r >> 16) % tokens.length];
                bool live = _live(id);
                if (op == 1 && live && printer.legalOwnerOf(id) != h) _assign(id, h);
                else if (op == 2 && live) _void(id);
                else if (op == 3 && !live) _unvoid(id);
                else if (op == 4) _label(id, (r >> 24) % 2 == 0);
                else if (op == 5) _mark(h, (r >> 24) % 2 == 0);
                else if (op == 6) credentials[(r >> 8) % holders.length] = _accredit(h);
                else if (op == 9) {
                    _entity(h, uint32(2 + (r >> 24) % 30)); // look-through only; the book must not change
                    tracker.syncHolder(address(printer), h);
                }
                else if (op == 7) {
                    uint256 c = credentials[(r >> 8) % holders.length];
                    if (c != 0 && badge.isValid(c)) badge.void(c, "fuzz");
                    tracker.syncHolder(address(printer), h);
                } else {
                    vm.prank(stranger);
                    tracker.syncLot(address(printer), id); // anyone; must not move the book from the truth
                }
            }
            _checkBook();
        }
    }
}
