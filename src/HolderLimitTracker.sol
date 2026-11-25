// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BorgAuth, BorgAuthACL} from "./libs/auth.sol";
import {IHolderLimitTracker} from "./interfaces/IHolderLimitTracker.sol";
import {ILedgerEntryToken} from "./interfaces/ILedgerEntryToken.sol";
import {IIssuanceManager} from "./interfaces/IIssuanceManager.sol";
import {ILexChexBadge, K_ACCREDITED} from "./interfaces/ILexChexBadge.sol";
import {Credential} from "./creds/storage/lexchexBadgeStorage.sol";

/// @title  HolderLimitTracker - section 12(g) holder counts of LET contracts, kept outside the LET contract
/// @author MetaLeX Labs, Inc.
/// @notice A shared singleton. A LET contract (printer) opts in by pointing `holderTracker` at it; the printer
/// then reports every change of a lot's legal owner or void status here (`onLotChange`). From those reports
/// and the printer's credential registry the tracker keeps, per printer:
///  - each holder's live lots, accredited booking and plan-only state;
///  - the totals behind `counts`, which HolderCapCondition reads for its section 12(g) limits: holders of
///    record, holders who are not accredited, and leaving plan-only holders out (Rule 12g5-1(a)(8)).
///
/// Holders of record: section 12(g) counts each legal owner once. An entity is one holder however many
/// beneficial owners it has; there is no look-through (owner decision, 2026-11-25). The printer's own
/// look-through tally, which the Investment Company Act cap uses, is separate and unchanged.
///
/// Who can write what:
///  - A printer writes only its own book: `onAttach`, `onDetach` and `onLotChange` are keyed by msg.sender.
///    Another contract calling them writes a book that no sale reads.
///  - Any caller can backfill or resync. Those paths re-read the printer and the registry and can only move a
///    book to the state those reads give.
///  - The plan label and the company mark are set by the printer's admin: its issuance manager, or an admin
///    of that manager's AUTH (the rule of LedgerEntryTokenStorage.requireManagerOrAdmin).
///
/// Books: each `onAttach` starts a new, empty book (a new generation), because the tracker cannot see the
/// changes made while the printer pointed elsewhere. The book records the supply at attach; it is ready once a
/// backfill has covered those tokens, since every later change reaches it through `onLotChange`. `onDetach`
/// stops the book being ready. The company marks are kept across generations; the plan labels are not, so after a re-attach
/// they must be set again (until then the holders are counted, the safe direction).
///
/// Accreditation: a holder is booked accredited when the registry has a valid credential with
/// `K_ACCREDITED` for it, from any issuer and with any scope, at a sync. A lapse keeps the booking (the owner's
/// decision: the evidence from the time of the purchase stands); a void of the credential the booking relies
/// on ends it at the next sync, unless another valid one exists; the company mark ends it at once.
///
/// A registry that answers malformed data never reverts a sync: it reads as not accredited and
/// voided, which can only raise the counts of holders who are not accredited.
contract HolderLimitTracker is IHolderLimitTracker, UUPSUpgradeable, BorgAuthACL {
    /// @dev One holder, packed in one slot. `counted` is true exactly when the holder is in the totals.
    struct Holder {
        uint32 liveLots;
        uint32 planLots;
        bool counted;
        bool accredited;
        bool planOnly;
    }

    /// @dev One generation of a printer's counts. Every total is the number of counted holders with the
    /// matching state: total = all; accredited = booked accredited; planOnly = plan-only;
    /// planOnlyAccredited = both.
    struct Book {
        bool started;                            // `target` is fixed
        bool ready;                              // the backfill covered `target`
        uint256 cursor;                          // next token index for backfill
        uint256 target;                          // supply at attach (or at the first backfill call)
        uint256 total;
        uint256 accredited;
        uint256 planOnly;
        uint256 planOnlyAccredited;
        mapping(uint256 => address) lotHolder;   // the holder a lot is counted under; 0 = not counted
        mapping(uint256 => bool) lotPlan;        // the lot is counted as a plan lot of lotHolder
        mapping(uint256 => address) planLabel;   // the legal owner the plan label was set for
        mapping(address => Holder) holders;
        mapping(address => uint256) credentialId; // the credential an accredited booking relies on
    }

    /// @dev Upgrade notes: ERC-7201-style namespace; members may only be appended.
    struct TrackerStorage {
        mapping(address => mapping(uint64 => Book)) books;               // printer => generation => book
        mapping(address => mapping(address => bool)) notAccreditedMark;  // printer => account => mark
        mapping(address => uint64) generation;                           // printer => current generation
        mapping(address => bool) attached;                               // printer => it reports here now
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.holder-limit-tracker.storage.v1");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    // ── Called by a printer ────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IHolderLimitTracker
    function onAttach() external {
        TrackerStorage storage $ = _storage();
        uint64 gen = ++$.generation[msg.sender];
        $.attached[msg.sender] = true;
        Book storage b = $.books[msg.sender][gen];
        (bool ok, uint256 supply) = _readUint(msg.sender, abi.encodeWithSignature("totalSupply()"));
        if (ok) {
            b.started = true;
            b.target = supply;
            b.ready = supply == 0;
        }
        emit Attached(msg.sender, gen, b.ready);
    }

    /// @inheritdoc IHolderLimitTracker
    function onDetach() external {
        TrackerStorage storage $ = _storage();
        $.attached[msg.sender] = false;
        emit Detached(msg.sender, $.generation[msg.sender]);
    }

    /// @inheritdoc IHolderLimitTracker
    function onLotChange(uint256 tokenId, address owner, bool live) external {
        (bool attached, uint64 gen) = _generation(msg.sender);
        if (!attached) return;
        _applyLot(msg.sender, _storage().books[msg.sender][gen], tokenId, owner, live);
    }

    // ── Any caller ─────────────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IHolderLimitTracker
    function backfill(address printer, uint256 count) external {
        (Book storage b, uint64 gen) = _attachedBook(printer);
        ILedgerEntryToken p = ILedgerEntryToken(printer);
        if (!b.started) {
            b.started = true;
            b.target = p.totalSupply();
        }
        uint256 i = b.cursor;
        uint256 end = i + count;
        if (end > b.target) end = b.target;
        for (; i < end; i++) {
            uint256 tokenId = p.tokenByIndex(i);
            (address owner, bool live) = _readLot(printer, tokenId);
            _applyLot(printer, b, tokenId, owner, live);
        }
        b.cursor = end;
        if (end == b.target) b.ready = true;
        emit Backfilled(printer, gen, end, b.ready);
    }

    /// @inheritdoc IHolderLimitTracker
    function syncLot(address printer, uint256 tokenId) external {
        (Book storage b,) = _attachedBook(printer);
        (address owner, bool live) = _readLot(printer, tokenId);
        _applyLot(printer, b, tokenId, owner, live);
    }

    /// @inheritdoc IHolderLimitTracker
    function syncHolder(address printer, address owner) external {
        (Book storage b,) = _attachedBook(printer);
        _syncHolder(printer, b, owner);
    }

    /// @inheritdoc IHolderLimitTracker
    function syncHolders(address printer, address[] calldata owners) external {
        (Book storage b,) = _attachedBook(printer);
        for (uint256 i = 0; i < owners.length; i++) {
            _syncHolder(printer, b, owners[i]);
        }
    }

    // ── Printer admin ──────────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IHolderLimitTracker
    function setPlanSecurity(address printer, uint256 tokenId, bool value) external {
        _requirePrinterAdmin(printer);
        (Book storage b,) = _attachedBook(printer);
        (address owner, bool live) = _readLot(printer, tokenId);
        if (owner == address(0)) revert NoLegalOwner();
        b.planLabel[tokenId] = value ? owner : address(0);
        emit PlanSecuritySet(printer, tokenId, owner, value);
        _applyLot(printer, b, tokenId, owner, live);
    }

    /// @inheritdoc IHolderLimitTracker
    function setNotAccreditedMark(address printer, address account, bool marked) external {
        _requirePrinterAdmin(printer);
        _storage().notAccreditedMark[printer][account] = marked;
        emit NotAccreditedMarkSet(printer, account, marked);
        // The mark is kept for a later attach too; the current book, if any, follows it now
        (bool attached, uint64 gen) = _generation(printer);
        if (attached) _syncHolder(printer, _storage().books[printer][gen], account);
    }

    // ── Views ──────────────────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IHolderLimitTracker
    function isReady(address printer) external view returns (bool) {
        (bool attached, uint64 gen) = _generation(printer);
        return attached && _storage().books[printer][gen].ready;
    }

    /// @inheritdoc IHolderLimitTracker
    function counts(address printer) external view returns (Counts memory c) {
        (bool attached, uint64 gen) = _generation(printer);
        if (!attached) return c;
        Book storage b = _storage().books[printer][gen];
        // Each subtrahend is a subset of its minuend while the totals are kept; `_sub` reads a defect high
        c.total = b.total;
        c.nonAccredited = _sub(b.total, b.accredited);
        c.totalExcludingPlan = _sub(b.total, b.planOnly);
        c.nonAccreditedExcludingPlan = _sub(c.nonAccredited, _sub(b.planOnly, b.planOnlyAccredited));
    }

    /// @inheritdoc IHolderLimitTracker
    function isAccredited(address printer, address account) external view returns (bool) {
        if (_storage().notAccreditedMark[printer][account]) return false;
        address badge = _badgeOf(printer);
        (bool found,) = _accreditedCredential(badge, account);
        if (found) return true;
        (bool attached, uint64 gen) = _generation(printer);
        if (!attached) return false;
        Book storage b = _storage().books[printer][gen];
        Holder storage h = b.holders[account];
        return h.counted && h.accredited && !_isVoided(badge, b.credentialId[account]);
    }

    /// @inheritdoc IHolderLimitTracker
    function isPlanOnlyHolder(address printer, address owner) external view returns (bool) {
        (bool attached, uint64 gen) = _generation(printer);
        if (!attached) return false;
        Holder storage h = _storage().books[printer][gen].holders[owner];
        return h.counted && h.planOnly;
    }

    /// @inheritdoc IHolderLimitTracker
    function isPlanSecurity(address printer, uint256 tokenId) external view returns (bool) {
        (bool attached, uint64 gen) = _generation(printer);
        if (!attached) return false;
        address label = _storage().books[printer][gen].planLabel[tokenId];
        if (label == address(0)) return false;
        (address owner,) = _readLot(printer, tokenId);
        return owner == label;
    }

    /// @inheritdoc IHolderLimitTracker
    function notAccreditedMark(address printer, address account) external view returns (bool) {
        return _storage().notAccreditedMark[printer][account];
    }

    /// @inheritdoc IHolderLimitTracker
    function holderRecord(address printer, address owner) external view returns (HolderRecord memory r) {
        (bool attached, uint64 gen) = _generation(printer);
        if (!attached) return r;
        Book storage b = _storage().books[printer][gen];
        Holder storage h = b.holders[owner];
        r = HolderRecord({
            liveLots: h.liveLots,
            planLots: h.planLots,
            counted: h.counted,
            accredited: h.accredited,
            planOnly: h.planOnly,
            credentialId: b.credentialId[owner]
        });
    }

    /// @inheritdoc IHolderLimitTracker
    function isAttached(address printer) external view returns (bool) {
        return _storage().attached[printer];
    }

    /// @inheritdoc IHolderLimitTracker
    function backfillState(address printer)
        external
        view
        returns (bool attached, uint64 generation, bool started, uint256 cursor, uint256 target, bool ready)
    {
        (attached, generation) = _generation(printer);
        Book storage b = _storage().books[printer][generation];
        return (attached, generation, b.started, b.cursor, b.target, attached && b.ready);
    }

    /// @notice Decodes a `Credential` returned by the registry and reports whether it is voided. External so
    /// that `_isVoided` can catch a decoding failure of malformed data; it reads only its argument.
    function decodeVoided(bytes calldata ret) external pure returns (bool) {
        Credential memory c = abi.decode(ret, (Credential));
        return bytes(c.voided).length > 0;
    }

    // ── Internals ──────────────────────────────────────────────────────────────────────────────────

    /// @dev Apply one lot's state: the holder it counts under (its owner when live), whether the plan label is
    /// in force, then resync the holders it touches. A label set for another owner is cleared first: the
    /// exclusion was for the person who received the lot, so a sale and a later buy-back do not revive it.
    function _applyLot(address printer, Book storage b, uint256 tokenId, address owner, bool live) private {
        address label = b.planLabel[tokenId];
        if (label != address(0) && label != owner) {
            delete b.planLabel[tokenId];
            label = address(0);
            emit PlanSecuritySet(printer, tokenId, owner, false);
        }
        address holder = (live && owner != address(0)) ? owner : address(0);
        bool plan = holder != address(0) && label == holder;

        address prevHolder = b.lotHolder[tokenId];
        bool prevPlan = b.lotPlan[tokenId];
        if (prevHolder != holder || prevPlan != plan) {
            if (prevHolder != address(0)) {
                Holder storage p = b.holders[prevHolder];
                p.liveLots -= 1;
                if (prevPlan) p.planLots -= 1;
            }
            if (holder != address(0)) {
                Holder storage n = b.holders[holder];
                n.liveLots += 1;
                if (plan) n.planLots += 1;
            }
            b.lotHolder[tokenId] = holder;
            b.lotPlan[tokenId] = plan;
            if (prevHolder != address(0) && prevHolder != holder) _syncHolder(printer, b, prevHolder);
        }
        // Like the printer's own tally, a lot that joins or stays with a holder re-reads the registry
        if (holder != address(0)) _syncHolder(printer, b, holder);
    }

    /// @dev Remove the holder from the totals, recompute its booking and plan-only state, and add it back as one
    /// holder of record. A holder with no live lot leaves the totals and its record is cleared; its company
    /// mark stays.
    function _syncHolder(address printer, Book storage b, address owner) private {
        Holder storage h = b.holders[owner];
        bool wasCounted = h.counted;
        if (wasCounted) {
            b.total -= 1;
            if (h.accredited) b.accredited -= 1;
            if (h.planOnly) b.planOnly -= 1;
            if (h.accredited && h.planOnly) b.planOnlyAccredited -= 1;
        }
        if (h.liveLots == 0) {
            delete b.holders[owner];
            delete b.credentialId[owner];
            return;
        }

        bool booked = _decideBooking(printer, b, _badgeOf(printer), owner, wasCounted && h.accredited);
        bool planOnly = h.planLots == h.liveLots;

        h.counted = true;
        h.accredited = booked;
        h.planOnly = planOnly;
        b.total += 1;
        if (booked) b.accredited += 1;
        if (planOnly) b.planOnly += 1;
        if (booked && planOnly) b.planOnlyAccredited += 1;
    }

    /// @dev The booking of a live holder: the company mark ends it; a valid credential books it (and is the
    /// one it relies on); else a booking stays unless the credential it relies on was voided.
    function _decideBooking(address printer, Book storage b, address badge, address owner, bool booked)
        private
        returns (bool)
    {
        if (_storage().notAccreditedMark[printer][owner]) {
            delete b.credentialId[owner];
            return false;
        }
        (bool found, uint256 credentialId) = _accreditedCredential(badge, owner);
        if (found) {
            b.credentialId[owner] = credentialId;
            return true;
        }
        if (booked && !_isVoided(badge, b.credentialId[owner])) return true;
        delete b.credentialId[owner];
        return false;
    }

    /// @dev Whether the printer reports here now, and the generation of its current book.
    function _generation(address printer) private view returns (bool attached, uint64 gen) {
        TrackerStorage storage $ = _storage();
        return ($.attached[printer], $.generation[printer]);
    }

    function _attachedBook(address printer) private view returns (Book storage b, uint64 gen) {
        bool attached;
        (attached, gen) = _generation(printer);
        if (!attached) revert NotAttached();
        b = _storage().books[printer][gen];
    }

    /// @dev The legal owner of a lot and whether it is live, read from the printer. A token that does not exist
    /// (or that the printer cannot answer for) reads as no owner and not live.
    function _readLot(address printer, uint256 tokenId) private view returns (address owner, bool live) {
        (bool ok, uint256 word) = _readUint(printer, abi.encodeCall(ILedgerEntryToken.legalOwnerOf, (tokenId)));
        if (!ok || word > type(uint160).max || word == 0) return (address(0), false);
        owner = address(uint160(word));
        uint256 voided;
        (ok, voided) = _readUint(printer, abi.encodeCall(ILedgerEntryToken.isVoided, (tokenId)));
        live = ok && voided == 0;
    }

    function _badgeOf(address printer) private view returns (address) {
        (bool ok, uint256 word) = _readUint(printer, abi.encodeCall(ILedgerEntryToken.lookThroughBadge, ()));
        return (ok && word <= type(uint160).max) ? address(uint160(word)) : address(0);
    }

    /// @dev The most recent valid credential with `K_ACCREDITED` for `owner`, through the two-argument
    /// overload (no issuer, scope or hook filter). A `found` word other than 1 reads as not found.
    function _accreditedCredential(address badge, address owner) private view returns (bool found, uint256 id) {
        if (badge == address(0)) return (false, 0);
        (bool ok, bytes memory ret) = badge.staticcall(
            abi.encodeWithSignature("getMostRecentValidWith(address,uint256)", owner, K_ACCREDITED)
        );
        if (!ok || ret.length < 64) return (false, 0);
        uint256 foundWord;
        (id, foundWord) = abi.decode(ret, (uint256, uint256));
        found = foundWord == 1;
        if (!found) id = 0;
    }

    /// @dev Whether the issuer or an admin voided the credential (a voided credential keeps a non-empty reason).
    /// A lapse is not a void. No registry, or one that cannot answer or answers malformed data, reads voided.
    function _isVoided(address badge, uint256 credentialId) private view returns (bool) {
        if (badge == address(0)) return true;
        (bool ok, bytes memory ret) =
            badge.staticcall(abi.encodeCall(ILexChexBadge.getCredential, (credentialId)));
        if (!ok) return true;
        try this.decodeVoided(ret) returns (bool voided) {
            return voided;
        } catch {
            return true;
        }
    }

    /// @dev A static call that returns the first word of the answer, or ok = false when the call fails or the
    /// answer is shorter than one word.
    function _readUint(address target, bytes memory data) private view returns (bool ok, uint256 word) {
        bytes memory ret;
        (ok, ret) = target.staticcall(data);
        if (!ok || ret.length < 32) return (false, 0);
        word = abi.decode(ret, (uint256));
    }

    function _requirePrinterAdmin(address printer) private view {
        address manager = ILedgerEntryToken(printer).issuanceManager();
        if (msg.sender == manager) return;
        BorgAuth auth = BorgAuth(IIssuanceManager(manager).AUTH());
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
    }

    function _sub(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function _storage() private pure returns (TrackerStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
