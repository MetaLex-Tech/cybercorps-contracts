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
/// Section 12(g) limits (`setClassLimits`): a cap on holders who are not accredited, and leaving holders of plan
/// securities only (Rule 12g5-1(a)(8)) out of the counts. Those counts are kept outside the printer by the
/// HolderLimitTracker that MetaLeX trusts here (`setHolderTracker`). A sale under these limits passes only when
/// the printer reports to that tracker and the tracker's book of it is complete (`isReady`); otherwise it
/// fails. An SPV that sets no such limit never reads the tracker.
contract HolderCapCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    /// @notice The ICA exception the SPV relies on (informational for the indexer/UI; the cap value and
    /// counting mode below drive the enforcement)
    enum IcaException {
        SECTION_3C1,    // 100-holder cap
        SECTION_3C1C,   // 250-holder cap (qualifying venture funds)
        SECTION_3C7     // no numeric cap beyond the QP requirement (cap = 0)
    }

    struct SpvConfig {
        IcaException icaException;   // which exception the SPV relies on (informational)
        uint256 cap;                 // holder cap (100 / 250); 0 = no numeric cap (§3(c)(7))
        bool usResidentOnlyCount;    // Touche Remnant: only U.S.-resident holders count toward the cap
        bool blockUsInvestors;       // offshore no-U.S.-investor floor
        bool configured;             // cap 0 is a real setting, so it cannot double as "unset"
    }

    /// @notice Section 12(g) limits that sit beside an SpvConfig. One struct for the SPV (printer key
    /// `address(0)`) and one for each LET contract; the LET contract's struct, when set, replaces the SPV's for
    /// sales of that printer.
    struct ClassLimits {
        uint256 nonAccreditedCap;    // limit on holders who are not accredited; 0 = no such limit
        bool excludePlanOnly;        // leave holders whose every live lot has the plan label out of the counts
        bool configured;             // set by setClassLimits; tells "not set" from "set to no limit"
    }

    error InvalidSpv();
    error InvalidPrinter();
    /// @notice `usResidentOnlyCount` and `excludePlanOnly` cannot apply to the same sales: there is no total of
    /// U.S. holders with the plan-only holders left out.
    error UsResidentCountWithPlanExclusion();

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
        address indexed spv, address indexed printer, uint256 nonAccreditedCap, bool excludePlanOnly
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
    ///   slot P + 4: planExclusionOnSpvConfig
    ///   slot P + 5: usOnlyOnSpvLimits
    struct HolderCapStorage {
        mapping(address => SpvConfig) configs;
        /// @dev spv => LET contract (printer) => policy. Keyed by the SPV first, so only that SPV's admin can
        /// write a policy that the SPV's own sales read.
        mapping(address => mapping(address => SpvConfig)) printerConfigs;
        /// @dev spv => LET contract (printer), or address(0) for the SPV itself => section 12(g) limits.
        mapping(address => mapping(address => ClassLimits)) classLimits;
        /// @dev The HolderLimitTracker trusted for the counts; set by the owner (MetaLeX).
        address holderTracker;
        /// @dev spv => number of its printers with their own limits that exclude plan-only holders and no
        /// policy of their own (their sales use the SPV policy).
        mapping(address => uint256) planExclusionOnSpvConfig;
        /// @dev spv => number of its printers with their own policy that counts U.S. residents only and no
        /// limits of their own (their sales use the SPV limits).
        mapping(address => uint256) usOnlyOnSpvLimits;
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
        _requireNoSpvConflict(spv);
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
        (bool wasA, bool wasB) = _inheritance(spv, printer);
        _holderCapStorage().printerConfigs[spv][printer] = SpvConfig({
            icaException: _icaException,
            cap: _cap,
            usResidentOnlyCount: _usResidentOnlyCount,
            blockUsInvestors: _blockUsInvestors,
            configured: true
        });
        _afterPrinterChange(spv, printer, wasA, wasB);
        emit PrinterConfigUpdated(spv, printer, _icaException, _cap, _usResidentOnlyCount, _blockUsInvestors);
    }

    /// @notice Removes the per-printer policy, so sales of that printer use the SPV policy again; only the SPV's
    /// own BorgAuth admin. Removing a policy that is not set changes nothing but still emits the event.
    function removePrinterConfig(address spv, address printer) external {
        if (spv == address(0)) revert InvalidSpv();
        if (printer == address(0)) revert InvalidPrinter();
        _requireAuthAdmin(spv);
        (bool wasA, bool wasB) = _inheritance(spv, printer);
        delete _holderCapStorage().printerConfigs[spv][printer];
        _afterPrinterChange(spv, printer, wasA, wasB);
        emit PrinterConfigRemoved(spv, printer);
    }

    /// @notice Sets the section 12(g) limits of an SPV (`printer == address(0)`) or of one of its LET contracts;
    /// only the SPV's own BorgAuth admin. The limits of a LET contract replace the SPV's for its sales.
    /// @param nonAccreditedCap Limit on holders who are not accredited (look-through basis); 0 = no limit.
    /// @param excludePlanOnly Leave plan-only holders out of the total cap and of the limit above.
    function setClassLimits(address spv, address printer, uint256 nonAccreditedCap, bool excludePlanOnly) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        (bool wasA, bool wasB) = _inheritance(spv, printer);
        _holderCapStorage().classLimits[spv][printer] =
            ClassLimits({nonAccreditedCap: nonAccreditedCap, excludePlanOnly: excludePlanOnly, configured: true});
        if (printer == address(0)) _requireNoSpvConflict(spv);
        else _afterPrinterChange(spv, printer, wasA, wasB);
        emit ClassLimitsUpdated(spv, printer, nonAccreditedCap, excludePlanOnly);
    }

    /// @notice Removes the section 12(g) limits of an SPV or of one of its LET contracts; only the SPV's own
    /// BorgAuth admin. A LET contract then uses the SPV's limits.
    function removeClassLimits(address spv, address printer) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        (bool wasA, bool wasB) = _inheritance(spv, printer);
        delete _holderCapStorage().classLimits[spv][printer];
        if (printer != address(0)) _afterPrinterChange(spv, printer, wasA, wasB);
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

        // Section 12(g) limits. An SPV that sets none, or sets them with no limit and the exclusion off,
        // continues below exactly as before and never reads the tracker.
        ClassLimits memory limits = _effectiveClassLimits(offer.spvAddress, offer.certPrinter);
        if (limits.nonAccreditedCap != 0 || limits.excludePlanOnly) {
            return _checkWithClassLimits(config, limits, printer, badge, buyer, buyerIsUS);
        }

        if (config.cap == 0) return true;

        // Note threshold conditions are checked BEFORE the transaction happens, so we need to consider the fact
        // that the holder counts we get from `LedgerEntryToken` are BEFORE the buyer bought it

        // Early termination: Position increase, not a new holder: the cap is not implicated. Uses the live-holder tally, so a
        // holder who fully sold out (and re-enters) is correctly treated as new rather than bypassing the cap.
        if (printer.isLegalHolder(buyer)) return true;

        // Early termination: Touche Remnant: a non-U.S. acquirer does not add to the U.S.-resident-only count
        if (config.usResidentOnlyCount && !buyerIsUS) return true;

        // Base is the printer's maintained O(1) look-through tally (both counts share the look-through basis).
        uint256 currentCount = config.usResidentOnlyCount
            ? printer.usLookThroughHolderCount()
            : printer.lookThroughHolderCount();

        return currentCount + _addition(badge, buyer, 1) <= config.cap;
    }

    /// @dev The buyer's place in a count. A credentialed entity BO count flows through instead of
    /// `bookedWeight`. `_validate` rejects an asserted count of zero, so a zero read means no look-through
    /// credential: a new holder (1), or a holder already booked at `bookedWeight` (a withdrawn or lapsed count
    /// is unknown, not lower).
    function _addition(ILexChexBadge badge, address buyer, uint256 bookedWeight) private view returns (uint256) {
        uint32 boCount;
        if (address(badge) != address(0)) (boCount,) = badge.getEffectiveBeneficialOwnerCount(buyer);
        return boCount > 0 ? boCount : bookedWeight;
    }

    /// @dev The steps after the no-U.S. floor when section 12(g) limits apply to the sale. The counts come
    /// from the trusted tracker; a printer that does not report to it, or whose book there is not complete,
    /// fails the sale.
    function _checkWithClassLimits(
        SpvConfig storage config,
        ClassLimits memory limits,
        ILedgerEntryToken printer,
        ILexChexBadge badge,
        address buyer,
        bool buyerIsUS
    ) private view returns (bool) {
        // No count matches this pair; the setters refuse it, so this only guards against an unforeseen path.
        if (limits.excludePlanOnly && config.usResidentOnlyCount) return false;

        IHolderLimitTracker tracker = IHolderLimitTracker(_holderCapStorage().holderTracker);
        if (address(tracker) == address(0) || !tracker.isReady(address(printer))) return false;
        IHolderLimitTracker.Counts memory c = tracker.counts(address(printer));

        // A buyer who already holds is a larger position, not a new holder. With the plan exclusion on, a
        // plan-only holder is left out of the counts today, so buying a lot that has no label adds them at the
        // weight the tracker books for them (unless the registry gives a fresh count).
        bool newHolder = !printer.isLegalHolder(buyer);
        uint256 bookedWeight = 1;
        if (!newHolder && limits.excludePlanOnly) {
            bookedWeight = tracker.planOnlyHolderWeight(address(printer), buyer);
            newHolder = bookedWeight != 0;
        }
        if (!newHolder) return true;

        uint256 addition = _addition(badge, buyer, bookedWeight);

        // The total cap, on the count with plan-only holders left out when that is on
        if (config.cap != 0 && !(config.usResidentOnlyCount && !buyerIsUS)) {
            uint256 currentCount;
            if (config.usResidentOnlyCount) currentCount = printer.usLookThroughHolderCount();
            else if (limits.excludePlanOnly) currentCount = c.totalExcludingPlan;
            else currentCount = printer.lookThroughHolderCount();
            if (currentCount + addition > config.cap) return false;
        }

        // The limit on holders who are not accredited. An accredited buyer does not use a place. The buyer is
        // read through the tracker, under the rule its book uses (registry, booking and company mark).
        if (limits.nonAccreditedCap != 0 && !tracker.isAccredited(address(printer), buyer)) {
            uint256 nonAccredited = limits.excludePlanOnly ? c.nonAccreditedExcludingPlan : c.nonAccredited;
            if (nonAccredited + addition > limits.nonAccreditedCap) return false;
        }
        return true;
    }

    /// @dev The section 12(g) limits that sales of `printer` use: the printer's own if set, else the SPV's.
    function _effectiveClassLimits(address spv, address printer) private view returns (ClassLimits memory limits) {
        HolderCapStorage storage $ = _holderCapStorage();
        limits = $.classLimits[spv][printer];
        if (!limits.configured) limits = $.classLimits[spv][address(0)];
    }

    /// @dev The SPV policy that sales of `printer` use: the printer's own if set, else the SPV's.
    function _effectiveConfig(address spv, address printer) private view returns (SpvConfig storage config) {
        HolderCapStorage storage $ = _holderCapStorage();
        config = $.printerConfigs[spv][printer];
        if (!config.configured) config = $.configs[spv];
    }

    /// @dev Which SPV-level setting a printer inherits in a way the conflict check must follow:
    /// `a` = it has limits of its own that exclude plan-only holders and uses the SPV policy;
    /// `b` = it has a policy of its own that counts U.S. residents only and uses the SPV limits.
    function _inheritance(address spv, address printer) private view returns (bool a, bool b) {
        if (printer == address(0)) return (false, false);
        HolderCapStorage storage $ = _holderCapStorage();
        SpvConfig storage config = $.printerConfigs[spv][printer];
        ClassLimits storage limits = $.classLimits[spv][printer];
        a = limits.configured && limits.excludePlanOnly && !config.configured;
        b = config.configured && config.usResidentOnlyCount && !limits.configured;
    }

    /// @dev After a change of a printer's own policy or limits: keep the two counts of printers that inherit an
    /// SPV-level setting, and refuse the change if the printer's sales would pair a U.S.-only count with the
    /// plan exclusion.
    function _afterPrinterChange(address spv, address printer, bool wasA, bool wasB) private {
        HolderCapStorage storage $ = _holderCapStorage();
        (bool a, bool b) = _inheritance(spv, printer);
        if (a != wasA) {
            if (a) $.planExclusionOnSpvConfig[spv] += 1;
            else $.planExclusionOnSpvConfig[spv] -= 1;
        }
        if (b != wasB) {
            if (b) $.usOnlyOnSpvLimits[spv] += 1;
            else $.usOnlyOnSpvLimits[spv] -= 1;
        }
        if (_effectiveConfig(spv, printer).usResidentOnlyCount && _effectiveClassLimits(spv, printer).excludePlanOnly) {
            revert UsResidentCountWithPlanExclusion();
        }
    }

    /// @dev After a change of the SPV policy or the SPV limits: refuse it if the sales of any printer would pair
    /// a U.S.-only count with the plan exclusion. Printers with neither setting of their own use both SPV
    /// settings; the two counts cover the printers that inherit only one of them.
    function _requireNoSpvConflict(address spv) private view {
        HolderCapStorage storage $ = _holderCapStorage();
        bool usOnly = $.configs[spv].usResidentOnlyCount;
        bool exclude = $.classLimits[spv][address(0)].excludePlanOnly;
        if (
            (usOnly && exclude) || (usOnly && $.planExclusionOnSpvConfig[spv] != 0)
                || (exclude && $.usOnlyOnSpvLimits[spv] != 0)
        ) revert UsResidentCountWithPlanExclusion();
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
