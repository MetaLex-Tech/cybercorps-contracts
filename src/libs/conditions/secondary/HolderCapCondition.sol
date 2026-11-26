// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {LookThroughPolicy} from "../../policies/LookThroughPolicy.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {IHolderLimitTracker} from "../../../interfaces/IHolderLimitTracker.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HolderCapCondition - ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits at transfer time
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV, with an optional override per LET contract (class) of that SPV.
/// Counts holders at acceptance/finalization — not offer time — to avoid
/// stale-count races. Look-through applies to both sides on one basis: each existing holder already
/// contributes its credentialed beneficial-owner count in the printer's tally, and the acquirer's
/// credentialed count is added on top instead of counting it as one holder.
///
/// Offshore SPVs may also refuse U.S. money outright (`blockUsInvestors`) or count only U.S. holders
/// toward the cap (`usResidentOnlyCount`, Touche Remnant). Both read the acquirer's classification from
/// LookThroughPolicy, which resolves an unknown acquirer as U.S. — so missing evidence never slips a gate.
///
/// | classification | `blockUsInvestors` | `usResidentOnlyCount` |
/// |----------------|--------------------|-----------------------|
/// | US             | BLOCK              | counted               |
/// | non-US         | pass               | not counted           |
///
/// Count added for an acquirer who is not already a holder (`cap` ≠ 0):
///
/// | `K_BO_COUNT` | addition |
/// |--------------|----------|
/// | 0            | +1       |
/// | >0           | +count   |
///
/// An acquirer already holding live interests is a position increase, not a new holder, and skips the
/// count — but not the `blockUsInvestors` floor, which an existing U.S. holder still fails.
///
/// The credential registry is the printer's own (`lookThroughBadge`), never a separate wiring here: a printer
/// keeps one badge for life, and reading it there is what stops the buyer and the holders already counted
/// from being classified against different registries.
///
/// Section 12(g) limits (`setClassLimits`): a cap on holders of record and a cap on holders of record who are not
/// accredited, with the option to leave holders of plan securities only (Rule 12g5-1(a)(8)) out of both. Section
/// 12(g) counts holders of record: each legal owner is one holder and there is no look-through, so these limits
/// never use the look-through tally or `K_BO_COUNT`. They sit beside the Investment Company Act cap above and do
/// not change it: that cap always counts every holder on the printer's look-through tally, plan-only holders
/// included. The section 12(g) counts are kept outside the printer by the HolderLimitTracker that MetaLeX trusts
/// here (`setHolderTracker`). A sale under these limits passes only when the printer reports to that tracker and
/// the tracker's book of it is complete (`isReady`); otherwise it fails. An SPV that sets no such limit never
/// reads the tracker.
contract HolderCapCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    /// @notice The ICA exception the SPV relies on (informational for the indexer/UI; the cap value and
    /// counting mode below drive the enforcement)
    enum IcaException {
        SECTION_3C1,    // 100-holder cap
        SECTION_3C1C,   // 250-holder cap (qualifying venture funds)
        SECTION_3C7,    // no numeric cap beyond the QP requirement (cap = 0)
        NONE            // no Investment Company Act exception, e.g. an operating company (cap = 0)
    }

    struct SpvConfig {
        IcaException icaException;   // which exception the SPV relies on (informational)
        uint256 cap;                 // holder cap (100 / 250); 0 = no numeric cap (§3(c)(7))
        bool usResidentOnlyCount;    // Touche Remnant: only U.S.-resident holders count toward the cap
        bool blockUsInvestors;       // offshore no-U.S.-investor floor
        bool configured;             // cap 0 is a real setting, so it cannot double as "unset"
    }

    /// @notice Section 12(g) limits that sit beside an SpvConfig, in holders of record (each legal owner counts
    /// once). One struct for the SPV (printer key `address(0)`) and one for each LET contract; the LET contract's
    /// struct, when set, replaces the SPV's for sales of that printer.
    struct ClassLimits {
        uint256 totalCap;            // limit on holders of record (e.g. 2,000); 0 = no such limit
        uint256 nonAccreditedCap;    // limit on holders of record who are not accredited (e.g. 500); 0 = none
        bool excludePlanOnly;        // leave plan-only holders out of the two limits above (never the ICA cap)
        bool configured;             // set by setClassLimits; tells "not set" from "set to no limit"
    }

    error InvalidSpv();
    error InvalidPrinter();

    event ConfigUpdated(
        address indexed spv,
        IcaException icaException,
        uint256 cap,
        bool usResidentOnlyCount,
        bool blockUsInvestors
    );

    /// @notice A per-printer (per-class) policy for one LET contract of an SPV. It replaces the SPV policy for
    /// sales of that printer only.
    event PrinterConfigUpdated(
        address indexed spv,
        address indexed printer,
        IcaException icaException,
        uint256 cap,
        bool usResidentOnlyCount,
        bool blockUsInvestors
    );

    /// @notice The per-printer policy is removed; sales of that printer use the SPV policy again.
    event PrinterConfigRemoved(address indexed spv, address indexed printer);

    /// @notice Section 12(g) limits set for an SPV (`printer == address(0)`) or for one of its LET contracts.
    event ClassLimitsUpdated(
        address indexed spv, address indexed printer, uint256 totalCap, uint256 nonAccreditedCap, bool excludePlanOnly
    );

    /// @notice The section 12(g) limits of a LET contract (or of the SPV) are removed. A LET contract then uses
    /// the SPV's; the SPV then has none.
    event ClassLimitsRemoved(address indexed spv, address indexed printer);

    /// @notice The HolderLimitTracker whose counts the section 12(g) limits read.
    event HolderTrackerUpdated(address indexed tracker);

    /// @dev Upgrade notes: the shared proxy keeps this struct at the fixed STORAGE_POSITION (ERC-7201-style
    /// namespace, not linear slots). Members may only be appended; never move, rename or retype one.
    ///   slot P + 0: configs          (deployed layout)
    ///   slot P + 1: printerConfigs   (appended for per-class caps)
    ///   slot P + 2: classLimits      (appended for the section 12(g) limits, as are the members below)
    ///   slot P + 3: holderTracker
    struct HolderCapStorage {
        mapping(address => SpvConfig) configs;
        /// @dev spv => LET contract (printer) => policy. Keyed by the SPV first, so only that SPV's admin can
        /// write a policy that the SPV's own sales read.
        mapping(address => mapping(address => SpvConfig)) printerConfigs;
        /// @dev spv => LET contract (printer), or address(0) for the SPV itself => section 12(g) limits.
        mapping(address => mapping(address => ClassLimits)) classLimits;
        /// @dev The HolderLimitTracker trusted for the counts; set by the owner (MetaLeX).
        address holderTracker;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.holder-cap.storage.v1");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Sets an SPV's holder-limit policy; only the SPV's own BorgAuth admin
    function setConfig(
        address spv,
        IcaException _icaException,
        uint256 _cap,
        bool _usResidentOnlyCount,
        bool _blockUsInvestors
    ) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _holderCapStorage().configs[spv] = SpvConfig({
            icaException: _icaException,
            cap: _cap,
            usResidentOnlyCount: _usResidentOnlyCount,
            blockUsInvestors: _blockUsInvestors,
            configured: true
        });
        emit ConfigUpdated(spv, _icaException, _cap, _usResidentOnlyCount, _blockUsInvestors);
    }

    /// @notice Sets a holder-limit policy for one LET contract (class) of an SPV; only the SPV's own BorgAuth
    /// admin. Sales of that printer use this policy instead of the SPV policy from `setConfig`.
    function setPrinterConfig(
        address spv,
        address printer,
        IcaException _icaException,
        uint256 _cap,
        bool _usResidentOnlyCount,
        bool _blockUsInvestors
    ) external {
        if (spv == address(0)) revert InvalidSpv();
        if (printer == address(0)) revert InvalidPrinter();
        _requireAuthAdmin(spv);
        _holderCapStorage().printerConfigs[spv][printer] = SpvConfig({
            icaException: _icaException,
            cap: _cap,
            usResidentOnlyCount: _usResidentOnlyCount,
            blockUsInvestors: _blockUsInvestors,
            configured: true
        });
        emit PrinterConfigUpdated(spv, printer, _icaException, _cap, _usResidentOnlyCount, _blockUsInvestors);
    }

    /// @notice Removes the per-printer policy, so sales of that printer use the SPV policy again; only the SPV's
    /// own BorgAuth admin. Removing a policy that is not set changes nothing but still emits the event.
    function removePrinterConfig(address spv, address printer) external {
        if (spv == address(0)) revert InvalidSpv();
        if (printer == address(0)) revert InvalidPrinter();
        _requireAuthAdmin(spv);
        delete _holderCapStorage().printerConfigs[spv][printer];
        emit PrinterConfigRemoved(spv, printer);
    }

    /// @notice Sets the section 12(g) limits of an SPV (`printer == address(0)`) or of one of its LET contracts;
    /// only the SPV's own BorgAuth admin. The limits of a LET contract replace the SPV's for its sales. Both caps
    /// count holders of record (each legal owner once); neither changes the Investment Company Act cap.
    /// @param totalCap Limit on holders of record; 0 = no limit.
    /// @param nonAccreditedCap Limit on holders of record who are not accredited; 0 = no limit.
    /// @param excludePlanOnly Leave plan-only holders out of the two caps above.
    function setClassLimits(
        address spv,
        address printer,
        uint256 totalCap,
        uint256 nonAccreditedCap,
        bool excludePlanOnly
    ) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _holderCapStorage().classLimits[spv][printer] = ClassLimits({
            totalCap: totalCap,
            nonAccreditedCap: nonAccreditedCap,
            excludePlanOnly: excludePlanOnly,
            configured: true
        });
        emit ClassLimitsUpdated(spv, printer, totalCap, nonAccreditedCap, excludePlanOnly);
    }

    /// @notice Removes the section 12(g) limits of an SPV or of one of its LET contracts; only the SPV's own
    /// BorgAuth admin. A LET contract then uses the SPV's limits.
    function removeClassLimits(address spv, address printer) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        delete _holderCapStorage().classLimits[spv][printer];
        emit ClassLimitsRemoved(spv, printer);
    }

    /// @notice Sets the HolderLimitTracker whose counts the section 12(g) limits read; only the owner. Zero:
    /// none, and every sale under those limits fails.
    function setHolderTracker(address tracker) external onlyOwner {
        _holderCapStorage().holderTracker = tracker;
        emit HolderTrackerUpdated(tracker);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        // The class's own policy if one is set, else the SPV policy. `offer.spvAddress` is the DealManager's
        // own corp, so a policy written under another SPV's key is never read here.
        HolderCapStorage storage $ = _holderCapStorage();
        SpvConfig storage config = $.printerConfigs[offer.spvAddress][offer.certPrinter];
        if (!config.configured) config = $.configs[offer.spvAddress];

        // Attached but never configured. §3(c)(1) still caps the SPV, and a zero cap is a real §3(c)(7)
        // setting rather than an absence, so nothing passes until the GP states which applies.
        if (!config.configured) return false;

        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No acquirer yet (posting context) — the cap is evaluated at acceptance and finalization
        if (buyer == address(0)) return true;

        // The buyer is read off the printer's own badge, the same one its holder tally was built from, so the
        // two sides of the count can never come from different registries.
        ILedgerEntryToken printer = ILedgerEntryToken(offer.certPrinter);
        ILexChexBadge badge = ILexChexBadge(printer.lookThroughBadge());

        // The no-U.S.-investor floor is absolute — it precedes the cap and applies even to an existing holder
        (bool buyerIsUS,) = LookThroughPolicy.isUSInvestor(badge, buyer);
        if (config.blockUsInvestors && buyerIsUS) return false;

        // The Investment Company Act cap, on the printer's look-through tally. Section 12(g) settings never
        // change it.
        if (!_withinIcaCap(config, printer, badge, buyer, buyerIsUS)) return false;

        // Section 12(g) limits, in holders of record. An SPV that sets no cap there never reads the tracker.
        ClassLimits memory limits = _effectiveClassLimits(offer.spvAddress, offer.certPrinter);
        if (limits.totalCap == 0 && limits.nonAccreditedCap == 0) return true;
        return _withinClassLimits(limits, printer, buyer);
    }

    /// @dev The Investment Company Act cap. Note threshold conditions are checked BEFORE the transaction
    /// happens, so the holder counts we get from `LedgerEntryToken` are BEFORE the buyer bought it.
    function _withinIcaCap(
        SpvConfig storage config,
        ILedgerEntryToken printer,
        ILexChexBadge badge,
        address buyer,
        bool buyerIsUS
    ) private view returns (bool) {
        if (config.cap == 0) return true;

        // Position increase, not a new holder: the cap is not implicated. Uses the live-holder tally, so a
        // holder who fully sold out (and re-enters) is correctly treated as new rather than bypassing the cap.
        if (printer.isLegalHolder(buyer)) return true;

        // Touche Remnant: a non-U.S. acquirer does not add to the U.S.-resident-only count
        if (config.usResidentOnlyCount && !buyerIsUS) return true;

        // Base is the printer's maintained O(1) look-through tally (both counts share the look-through basis).
        uint256 currentCount = config.usResidentOnlyCount
            ? printer.usLookThroughHolderCount()
            : printer.lookThroughHolderCount();

        return currentCount + _addition(badge, buyer) <= config.cap;
    }

    /// @dev The buyer's place in the look-through tally: a credentialed entity BO count, else one. `_validate`
    /// rejects an asserted count of zero, so a zero read means no look-through credential.
    function _addition(ILexChexBadge badge, address buyer) private view returns (uint256) {
        uint32 boCount;
        if (address(badge) != address(0)) (boCount,) = badge.getEffectiveBeneficialOwnerCount(buyer);
        return boCount > 0 ? boCount : 1;
    }

    /// @dev The section 12(g) limits, in holders of record: a new legal owner adds exactly one, whatever its
    /// beneficial owners. The counts come from the trusted tracker; a printer that does not report to it, or
    /// whose book there is not complete, fails the sale.
    function _withinClassLimits(ClassLimits memory limits, ILedgerEntryToken printer, address buyer)
        private
        view
        returns (bool)
    {
        IHolderLimitTracker tracker = IHolderLimitTracker(_holderCapStorage().holderTracker);
        if (address(tracker) == address(0) || !tracker.isReady(address(printer))) return false;

        // A buyer who already holds is a larger position, not a new holder. With the plan exclusion on, a
        // plan-only holder is left out of the counts today; the lot it buys carries no label in its hands (a
        // label holds only for the owner it was set for), so the purchase brings it into the counts.
        if (
            printer.isLegalHolder(buyer)
                && !(limits.excludePlanOnly && tracker.isPlanOnlyHolder(address(printer), buyer))
        ) return true;

        IHolderLimitTracker.Counts memory c = tracker.counts(address(printer));

        if (limits.totalCap != 0) {
            uint256 holders = limits.excludePlanOnly ? c.totalExcludingPlan : c.total;
            if (holders + 1 > limits.totalCap) return false;
        }

        // An accredited buyer does not use a place. The buyer is read through the tracker, under the rule its
        // book uses (registry, booking and company mark).
        if (limits.nonAccreditedCap != 0 && !tracker.isAccredited(address(printer), buyer)) {
            uint256 nonAccredited = limits.excludePlanOnly ? c.nonAccreditedExcludingPlan : c.nonAccredited;
            if (nonAccredited + 1 > limits.nonAccreditedCap) return false;
        }
        return true;
    }

    /// @dev The section 12(g) limits that sales of `printer` use: the printer's own if set, else the SPV's.
    function _effectiveClassLimits(address spv, address printer) private view returns (ClassLimits memory limits) {
        HolderCapStorage storage $ = _holderCapStorage();
        limits = $.classLimits[spv][printer];
        if (!limits.configured) limits = $.classLimits[spv][address(0)];
    }

    /// @notice An SPV's holder-limit configuration
    function configs(address spv) public view returns (SpvConfig memory) {
        return _holderCapStorage().configs[spv];
    }

    /// @notice The per-printer (per-class) policy of an SPV; `configured == false` means the printer uses the SPV
    /// policy from `configs(spv)`
    function printerConfigs(address spv, address printer) public view returns (SpvConfig memory) {
        return _holderCapStorage().printerConfigs[spv][printer];
    }

    /// @notice The section 12(g) limits stored for an SPV (`printer == address(0)`) or for one of its LET
    /// contracts; `configured == false` means not set (a LET contract then uses the SPV's).
    function classLimits(address spv, address printer) public view returns (ClassLimits memory) {
        return _holderCapStorage().classLimits[spv][printer];
    }

    /// @notice The HolderLimitTracker whose counts the section 12(g) limits read.
    function holderTracker() public view returns (address) {
        return _holderCapStorage().holderTracker;
    }

    function _holderCapStorage() private pure returns (HolderCapStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
