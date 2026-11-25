// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title  IHolderLimitTracker - section 12(g) holder counts of LET contracts, kept outside the LET contract
/// @notice One shared tracker keeps, for each LET contract (printer) that points at it, the section 12(g)
/// counts that HolderCapCondition needs: holders of record, holders who are not accredited, and both with the
/// holders of plan securities only (Rule 12g5-1(a)(8)) left out. Section 12(g) counts holders of record, so
/// each legal owner with a live lot counts as one holder; there is no look-through to beneficial owners. The
/// printer reports each change of a lot through `onLotChange`; everything else is computed here from the
/// printer's public reads and the accreditation credentials in its registry (`lookThroughBadge`).
interface IHolderLimitTracker {
    /// @notice The counts of one printer, in holders of record: each legal owner with a live lot counts once.
    struct Counts {
        uint256 total;                       // legal owners with a live lot
        uint256 nonAccredited;               // total less the holders booked accredited
        uint256 totalExcludingPlan;          // total less the plan-only holders
        uint256 nonAccreditedExcludingPlan;  // nonAccredited less the plan-only holders who are not accredited
    }

    /// @notice A holder's record in the current book of a printer.
    struct HolderRecord {
        uint32 liveLots;      // live lots counted for the holder
        uint32 planLots;      // of those, lots with the plan label in force
        bool counted;         // in the totals (the holder has a live lot)
        bool accredited;      // booked accredited
        bool planOnly;        // every live lot has the plan label
        uint256 credentialId; // the credential the accredited booking relies on
    }

    /// @notice The printer does not report to this tracker.
    error NotAttached();
    /// @notice The lot has no legal owner, so no label can be set for one.
    error NoLegalOwner();

    event Attached(address indexed printer, uint64 indexed generation, bool ready);
    event Detached(address indexed printer, uint64 indexed generation);
    event Backfilled(address indexed printer, uint64 indexed generation, uint256 cursor, bool ready);
    event PlanSecuritySet(address indexed printer, uint256 indexed tokenId, address indexed owner, bool value);
    event NotAccreditedMarkSet(address indexed printer, address indexed account, bool marked);

    // ── Called by a printer ────────────────────────────────────────────────────────────────────────

    /// @notice The printer (msg.sender) now reports here: start a new, empty book (a new generation) and record
    /// its supply. The book is ready at once when the supply is zero; otherwise after `backfill` covers it.
    function onAttach() external;

    /// @notice The printer (msg.sender) no longer reports here. Its book stops being ready.
    function onDetach() external;

    /// @notice The printer (msg.sender) reports a lot after a change of its legal owner or status: the legal
    /// owner now (zero when none) and whether the lot is live (has an owner and is not void). Applied to the
    /// book of the printer's current generation; ignored when the printer is not attached.
    function onLotChange(uint256 tokenId, address owner, bool live) external;

    // ── Any caller: recompute from the printer and its registry ───────────────────────────────────────

    /// @notice Count `count` more tokens of the printer's supply, in index order, from the backfill cursor.
    /// The target is the supply at attach; every token minted later is reported by the printer. The book is
    /// ready when the cursor reaches the target. Reverts unless the printer reports here.
    function backfill(address printer, uint256 count) external;

    /// @notice Re-read one lot from the printer (legal owner and void status) and apply it.
    function syncLot(address printer, uint256 tokenId) external;

    /// @notice Re-read a holder's accreditation from the registry.
    function syncHolder(address printer, address owner) external;

    function syncHolders(address printer, address[] calldata owners) external;

    // ── Printer admin (its issuance manager, or an admin of that manager's AUTH) ───────────────────────

    /// @notice Set or clear the plan-security label of a lot for its current legal owner. The label is in
    /// force only while that address is the legal owner; any change of legal owner clears it.
    function setPlanSecurity(address printer, uint256 tokenId, bool value) external;

    /// @notice Mark `account` as not accredited for this printer, or remove the mark. A marked account is
    /// never booked accredited. The mark is kept across generations.
    function setNotAccreditedMark(address printer, address account, bool marked) external;

    // ── Views ──────────────────────────────────────────────────────────────────────────────────────

    /// @notice True when the printer reports here and the book of its current generation covers its supply.
    function isReady(address printer) external view returns (bool);

    /// @notice True when the printer reports here (attached and not detached since).
    function isAttached(address printer) external view returns (bool);

    /// @notice The counts of the printer's current book; zero when the printer is not attached.
    function counts(address printer) external view returns (Counts memory);

    /// @notice Whether `account` counts as accredited for this printer under the booking rule: no company
    /// mark, and either a valid accredited credential now or a booking whose credential was not voided.
    function isAccredited(address printer, address account) external view returns (bool);

    /// @notice True when `owner` is a holder whose every live lot has the plan label in force.
    function isPlanOnlyHolder(address printer, address owner) external view returns (bool);

    function isPlanSecurity(address printer, uint256 tokenId) external view returns (bool);

    function notAccreditedMark(address printer, address account) external view returns (bool);

    function holderRecord(address printer, address owner) external view returns (HolderRecord memory);

    /// @notice Backfill progress of the printer's current book.
    function backfillState(address printer)
        external
        view
        returns (bool attached, uint64 generation, bool started, uint256 cursor, uint256 target, bool ready);
}
