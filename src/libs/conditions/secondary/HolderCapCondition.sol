// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {LookThroughPolicy} from "../../policies/LookThroughPolicy.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HolderCapCondition - ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits at transfer time
/// @author MetaLeX Labs, Inc.
/// @notice Per-SPV deployment. Counts holders at acceptance/finalization — not offer time — to avoid
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
contract HolderCapCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    /// @notice The ICA exception the SPV relies on (informational for the indexer/UI; the cap value and
    /// counting mode below drive the enforcement)
    enum IcaException {
        SECTION_3C1,    // 100-holder cap
        SECTION_3C1C,   // 250-holder cap (qualifying venture funds)
        SECTION_3C7     // no numeric cap beyond the QP requirement (cap = 0)
    }

    error InvalidBadge();

    event ConfigUpdated(
        IcaException icaException,
        uint256 cap,
        bool usResidentOnlyCount,
        bool blockUsInvestors
    );
    event BadgeUpdated(address badge);

    ILexChexBadge public badge;
    IcaException public icaException;
    /// @notice Holder cap (100 / 250); 0 = no numeric cap (§3(c)(7))
    uint256 public cap;
    /// @notice Touche Remnant counting for non-U.S. SPVs: only U.S.-resident holders count toward the cap
    bool public usResidentOnlyCount;
    /// @notice Optional no-U.S.-investor floor for offshore SPVs: block U.S. acquirers entirely
    bool public blockUsInvestors;

    uint256[45] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        IcaException _icaException,
        uint256 _cap,
        bool _usResidentOnlyCount,
        bool _blockUsInvestors
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        icaException = _icaException;
        cap = _cap;
        usResidentOnlyCount = _usResidentOnlyCount;
        blockUsInvestors = _blockUsInvestors;
        emit BadgeUpdated(_badge);
        emit ConfigUpdated(_icaException, _cap, _usResidentOnlyCount, _blockUsInvestors);
    }

    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function updateConfig(
        IcaException _icaException,
        uint256 _cap,
        bool _usResidentOnlyCount,
        bool _blockUsInvestors
    ) external onlyAdmin {
        icaException = _icaException;
        cap = _cap;
        usResidentOnlyCount = _usResidentOnlyCount;
        blockUsInvestors = _blockUsInvestors;
        emit ConfigUpdated(_icaException, _cap, _usResidentOnlyCount, _blockUsInvestors);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No acquirer yet (posting context) — the cap is evaluated at acceptance and finalization
        if (buyer == address(0)) return true;

        // The no-U.S.-investor floor is absolute — it precedes the cap and applies even to an existing holder
        bool buyerIsUS = LookThroughPolicy.isUSInvestor(badge, buyer);
        if (blockUsInvestors && buyerIsUS) return false;

        if (cap == 0) return true;

        ILedgerEntryToken printer = ILedgerEntryToken(offer.certPrinter);

        // Note threshold conditions are checked BEFORE the transaction happens, so we need to consider the fact
        // that the holder counts we get from `LedgerEntryToken` are BEFORE the buyer bought it

        // Early termination: Position increase, not a new holder: the cap is not implicated. Uses the live-holder tally, so a
        // holder who fully sold out (and re-enters) is correctly treated as new rather than bypassing the cap.
        if (printer.isLegalHolder(buyer)) return true;

        // Early termination: Touche Remnant: a non-U.S. acquirer does not add to the U.S.-resident-only count
        if (usResidentOnlyCount && !buyerIsUS) return true;

        // Base is the printer's maintained O(1) look-through tally (both counts share the look-through basis).
        uint256 currentCount = usResidentOnlyCount
            ? printer.usLookThroughHolderCount()
            : printer.lookThroughHolderCount();

        // A credentialed entity BO count flows through instead of 1. `_validate` rejects an asserted count of
        // zero, so a zero read means no look-through credential — a single holder.
        uint32 boCount = badge.getBeneficialOwnerCount(buyer);
        uint256 addition = boCount > 0 ? boCount : 1;

        return currentCount + addition <= cap;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
