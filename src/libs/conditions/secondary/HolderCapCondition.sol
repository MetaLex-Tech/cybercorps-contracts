// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {LookThroughPolicy} from "../../policies/LookThroughPolicy.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HolderCapCondition - ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits at transfer time
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV. Counts holders at acceptance/finalization — not offer time — to avoid
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

    error InvalidSpv();

    event ConfigUpdated(
        address indexed spv,
        IcaException icaException,
        uint256 cap,
        bool usResidentOnlyCount,
        bool blockUsInvestors
    );

    struct HolderCapStorage {
        mapping(address => SpvConfig) configs;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.holder-cap.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 1 = 49)

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

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        SpvConfig storage config = _holderCapStorage().configs[offer.spvAddress];

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
        bool buyerIsUS = LookThroughPolicy.isUSInvestor(badge, buyer);
        if (config.blockUsInvestors && buyerIsUS) return false;

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

        // A credentialed entity BO count flows through instead of 1. `_validate` rejects an asserted count of
        // zero, so a zero read means no look-through credential — a single holder.
        uint32 boCount = address(badge) == address(0) ? 0 : badge.getBeneficialOwnerCount(buyer);
        uint256 addition = boCount > 0 ? boCount : 1;

        return currentCount + addition <= config.cap;
    }

    /// @notice An SPV's holder-limit configuration
    function configs(address spv) public view returns (SpvConfig memory) {
        return _holderCapStorage().configs[spv];
    }

    function _holderCapStorage() private pure returns (HolderCapStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
