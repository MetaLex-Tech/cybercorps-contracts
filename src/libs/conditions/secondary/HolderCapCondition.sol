// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {LookThroughPolicy} from "../../policies/LookThroughPolicy.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {ILedgerEntryTokenHolderLimits} from "../../../interfaces/ILedgerEntryTokenHolderLimits.sol";
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

    /// @notice Section 12(g) limits that sit beside an SpvConfig (appended for C2 and C4). One struct for the
    /// company (printer key `address(0)`) and one for each LET contract; the LET contract's struct, when set,
    /// replaces the company's for sales of that printer.
    struct ClassLimits {
        uint256 nonAccreditedCap;    // limit on holders who are not accredited; 0 = no such limit
        bool excludePlanOnly;        // leave holders whose every live lot has the plan label out of the counts
        bool configured;             // set by setClassLimits; tells "not set" from "set to no limit"
    }

    error InvalidSpv();
    error InvalidPrinter();
    /// @notice `usResidentOnlyCount` and `excludePlanOnly` cannot apply to the same sales: the printer has no
    /// total of U.S. holders with the plan-only holders left out.
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

    /// @dev Upgrade notes: the shared proxy keeps this struct at the fixed STORAGE_POSITION (ERC-7201-style
    /// namespace, not linear slots). Members may only be appended; never move, rename or retype one.
    ///   slot P + 0: configs          (deployed layout)
    ///   slot P + 1: printerConfigs   (appended for per-class caps)
    ///   slot P + 2: classLimits      (appended for the limit on holders who are not accredited and the plan label)
    struct HolderCapStorage {
        mapping(address => SpvConfig) configs;
        /// @dev spv => LET contract (printer) => policy. Keyed by the SPV first, so only that SPV's admin can
        /// write a policy that the SPV's own sales read.
        mapping(address => mapping(address => SpvConfig)) printerConfigs;
        /// @dev spv => LET contract (printer), or address(0) for the SPV itself => section 12(g) limits.
        mapping(address => mapping(address => ClassLimits)) classLimits;
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
        // A printer with no limits of its own uses the SPV's, together with this SPV policy
        if (_usResidentOnlyCount && _holderCapStorage().classLimits[spv][address(0)].excludePlanOnly) {
            revert UsResidentCountWithPlanExclusion();
        }
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
        if (_usResidentOnlyCount && _effectiveClassLimits(spv, printer).excludePlanOnly) {
            revert UsResidentCountWithPlanExclusion();
        }
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

    /// @notice Sets the section 12(g) limits for an SPV (`printer == address(0)`) or for one of its LET
    /// contracts; only the SPV's own BorgAuth admin. A LET contract's limits replace the SPV's for its sales.
    /// @param nonAccreditedCap Limit on holders who are not accredited; 0 = no such limit.
    /// @param excludePlanOnly Leave plan-only holders out of the total cap and of the limit above.
    function setClassLimits(address spv, address printer, uint256 nonAccreditedCap, bool excludePlanOnly) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        if (excludePlanOnly) {
            // The SPV policy that the same sales use: the printer's own if set, else the SPV's. For the SPV key,
            // the SPV policy. A printer policy that falls back to these SPV limits is checked at its own setter
            // and, if set before them, refused in checkCondition.
            HolderCapStorage storage $ = _holderCapStorage();
            SpvConfig storage config = $.printerConfigs[spv][printer];
            if (printer == address(0) || !config.configured) config = $.configs[spv];
            if (config.usResidentOnlyCount) revert UsResidentCountWithPlanExclusion();
        }
        _holderCapStorage().classLimits[spv][printer] =
            ClassLimits({nonAccreditedCap: nonAccreditedCap, excludePlanOnly: excludePlanOnly, configured: true});
        emit ClassLimitsUpdated(spv, printer, nonAccreditedCap, excludePlanOnly);
    }

    /// @notice Removes the section 12(g) limits of an SPV or of one of its LET contracts; only the SPV's own
    /// BorgAuth admin.
    function removeClassLimits(address spv, address printer) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        HolderCapStorage storage $ = _holderCapStorage();
        delete $.classLimits[spv][printer];
        // The printer falls back to the SPV's limits; refuse if that pairs them with a U.S.-only count
        if (printer != address(0) && $.printerConfigs[spv][printer].usResidentOnlyCount
            && $.classLimits[spv][address(0)].excludePlanOnly) revert UsResidentCountWithPlanExclusion();
        emit ClassLimitsRemoved(spv, printer);
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

        // Section 12(g) limits (C2/C4). An SPV that sets none, or sets them with no limit and the exclusion
        // off, continues below exactly as before and never calls a read that an older printer lacks.
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

        return currentCount + _addition(badge, buyer) <= config.cap;
    }

    /// @dev The buyer's place in a count. A credentialed entity BO count flows through instead of 1.
    /// `_validate` rejects an asserted count of zero, so a zero read means no look-through credential — a
    /// single holder.
    function _addition(ILexChexBadge badge, address buyer) private view returns (uint256) {
        return _addition(badge, buyer, 1);
    }

    /// @dev As above for a buyer that the printer already books at `bookedWeight`: with no credentialed count
    /// the printer keeps that weight (a withdrawn or lapsed count is unknown, not lower), so the check adds it.
    function _addition(ILexChexBadge badge, address buyer, uint256 bookedWeight) private view returns (uint256) {
        uint32 boCount;
        if (address(badge) != address(0)) (boCount,) = badge.getEffectiveBeneficialOwnerCount(buyer);
        return boCount > 0 ? boCount : bookedWeight;
    }

    /// @dev The steps after the no-U.S. floor when section 12(g) limits apply to the sale. Every printer read
    /// that C2/C4 added goes through `_read`, so a LET contract without them refuses the sale instead of
    /// reverting or passing.
    function _checkWithClassLimits(
        SpvConfig storage config,
        ClassLimits memory limits,
        ILedgerEntryToken printer,
        ILexChexBadge badge,
        address buyer,
        bool buyerIsUS
    ) private view returns (bool) {
        // No printer total matches this pair; setClassLimits / setConfig / setPrinterConfig refuse it.
        if (limits.excludePlanOnly && config.usResidentOnlyCount) return false;

        // Capability probe: a LET contract from before C2/C4 has none of the new reads.
        (bool ok, uint256 nonAccredited) = _read(printer, abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCount, ()));
        if (!ok) return false;

        // A buyer who already holds is a larger position, not a new holder. With the plan exclusion on, a
        // plan-only holder is left out of the count today, so buying a lot that has no label adds them.
        // A plan-only holder enters the counts at the weight the printer already books for it, unless its
        // registry gives a fresh count. A buyer who holds nothing is booked as 1 by the printer.
        bool newHolder = !printer.isLegalHolder(buyer);
        uint256 bookedWeight = 1;
        if (!newHolder && limits.excludePlanOnly) {
            (ok, bookedWeight) = _read(printer, abi.encodeCall(ILedgerEntryTokenHolderLimits.planOnlyHolderWeight, (buyer)));
            if (!ok) return false;
            newHolder = bookedWeight != 0;
        }
        if (!newHolder) return true;

        uint256 addition = _addition(badge, buyer, bookedWeight);

        // The total cap, as in checkCondition, on the count with plan-only holders left out when that is on
        if (config.cap != 0 && !(config.usResidentOnlyCount && !buyerIsUS)) {
            uint256 currentCount;
            if (config.usResidentOnlyCount) {
                currentCount = printer.usLookThroughHolderCount();
            } else if (limits.excludePlanOnly) {
                (ok, currentCount) = _read(printer, abi.encodeCall(ILedgerEntryTokenHolderLimits.lookThroughHolderCountExcludingPlan, ()));
                if (!ok) return false;
            } else {
                currentCount = printer.lookThroughHolderCount();
            }
            if (currentCount + addition > config.cap) return false;
        }

        // The limit on holders who are not accredited. An accredited buyer does not use a place. The buyer's
        // status is read through the printer: its registry and the company's mark, the rule its tally uses.
        if (limits.nonAccreditedCap != 0) {
            uint256 accredited;
            (ok, accredited) = _read(printer, abi.encodeCall(ILedgerEntryTokenHolderLimits.isAccredited, (buyer)));
            if (!ok) return false;
            if (accredited == 0) {
                if (limits.excludePlanOnly) {
                    (ok, nonAccredited) = _read(
                        printer, abi.encodeCall(ILedgerEntryTokenHolderLimits.nonAccreditedLookThroughHolderCountExcludingPlan, ())
                    );
                    if (!ok) return false;
                }
                if (nonAccredited + addition > limits.nonAccreditedCap) return false;
            }
        }
        return true;
    }

    /// @dev A static call through the printer's forwarder `holderLimits(bytes)` that cannot revert the
    /// condition: the one-word answer of `data`, or false when the printer does not answer with a well-formed
    /// `bytes` of at least one word (an older implementation has no forwarder and reverts). A bool reads 0 or 1.
    function _read(ILedgerEntryToken printer, bytes memory data) private view returns (bool ok, uint256 value) {
        bytes memory ret;
        (ok, ret) = address(printer).staticcall(abi.encodeCall(ILedgerEntryToken.holderLimits, (data)));
        // `bytes` encoding: word 0 = offset 0x20, word 1 = length, then the inner answer
        if (!ok || ret.length < 96) return (false, 0);
        uint256 offset;
        uint256 length;
        assembly ("memory-safe") {
            offset := mload(add(ret, 0x20))
            length := mload(add(ret, 0x40))
            value := mload(add(ret, 0x60))
        }
        if (offset != 0x20 || length < 32 || length > ret.length - 64) return (false, 0);
    }

    /// @dev The section 12(g) limits that sales of `printer` use: the printer's own if set, else the SPV's.
    function _effectiveClassLimits(address spv, address printer) private view returns (ClassLimits memory limits) {
        HolderCapStorage storage $ = _holderCapStorage();
        limits = $.classLimits[spv][printer];
        if (!limits.configured) limits = $.classLimits[spv][address(0)];
    }

    /// @notice The section 12(g) limits stored for an SPV (`printer == address(0)`) or for one of its LET
    /// contracts; `configured == false` means not set (a LET contract then uses the SPV's).
    function classLimits(address spv, address printer) public view returns (ClassLimits memory) {
        return _holderCapStorage().classLimits[spv][printer];
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

    function _holderCapStorage() private pure returns (HolderCapStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
