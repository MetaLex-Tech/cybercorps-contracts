// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HolderCapCondition - ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits at transfer time
/// @author MetaLeX Labs, Inc.
/// @notice Per-SPV deployment. Reads the cert printer's maintained O(1) §3(c)(1)(A) look-through holder
/// tally at acceptance/finalization — not offer time — to avoid stale-count races, plus the acquirer's
/// entity-beneficial-owner-count credential attribute from LeXcheXBadge (§4.1.3A). Look-through applies to
/// both sides on one basis: each existing holder already contributes its credentialed beneficial-owner
/// count in the printer's tally, and the incoming acquirer's credentialed count (non-zero for a
/// look-through entity, determined offchain during credentialing) is added on top instead of counting it
/// as one holder. A buyer who already holds live interests in the SPV (position increase, not new holder)
/// does not implicate the cap.
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

        // isUSLookThroughInvestor resolves an unknown holder conservatively as U.S., so an unknown buyer is both blocked
        // (when blockUsInvestors) and counted (when usResidentOnlyCount) rather than slipping through.
        bool buyerIsUS = badge.isUSLookThroughInvestor(buyer);
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

        // §3(c)(1)(A) look-through for the incoming buyer (not yet a holder at check time): a credentialed
        // entity BO count flows through instead of 1. No look-through credential (count 0) → single holder.
        uint32 boCount = badge.getBeneficialOwnerCount(buyer);
        uint256 addition = boCount > 0 ? boCount : 1;

        return currentCount + addition <= cap;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
