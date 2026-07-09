// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {ICyberCertPrinter} from "../../../interfaces/ICyberCertPrinter.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HolderCapCondition - ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits at transfer time
/// @author MetaLeX Labs, Inc.
/// @notice Per-SPV deployment. Reads the onchain holder count from the SPV's ownership ledger (the
/// offer's cert printer) at acceptance/finalization — not offer time — to avoid stale-count races, and
/// the acquirer's entity-beneficial-owner-count credential attribute from LeXcheXBadge (§4.1.3A).
/// If the acquirer is an entity that triggers §3(c)(1)(A) look-through (determined offchain during
/// credentialing; reflected by a non-zero credentialed beneficial-owner count), the entity's credentialed
/// count is added instead of counting it as one holder. A buyer who already holds interests in the SPV
/// (position increase, not new holder) does not implicate the cap.
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

        bool buyerIsUS = _isUSBuyer(buyer);
        if (blockUsInvestors && buyerIsUS) return false;

        if (cap == 0) return true;

        ICyberCertPrinter printer = ICyberCertPrinter(offer.certPrinter);

        // Position increase, not a new holder: the cap is not implicated
        if (printer.balanceOfLegalOwner(buyer) > 0) return true;

        // Touche Remnant: a non-U.S. acquirer does not add to the U.S.-resident-only count
        if (usResidentOnlyCount && !buyerIsUS) return true;

        uint256 currentCount = usResidentOnlyCount
            ? _usResidentHolderCount(printer)
            : printer.holderCount(); // TODO review: does it report look-through holder count?

        // §3(c)(1)(A) look-through: a credentialed entity BO count flows through instead of 1
        uint32 boCount = badge.getBeneficialOwnerCount(buyer);
        uint256 addition = boCount > 0 ? boCount : 1;

        return currentCount + addition <= cap;
    }

    /// @dev Counts unique legal owners whose credential marks them U.S.-resident. O(n²) over the token
    /// set, acceptable at holder-cap scale (n ≤ 250 by construction).
    // TODO review: could be too expensive
    function _usResidentHolderCount(ICyberCertPrinter printer) internal view returns (uint256 count) {
        uint256 supply = printer.totalSupply();
        address[] memory seen = new address[](supply);
        uint256 seenLen;
        for (uint256 i = 0; i < supply; i++) {
            address holder = printer.legalOwnerOf(printer.tokenByIndex(i));
            if (holder == address(0)) continue;
            bool duplicate = false;
            for (uint256 j = 0; j < seenLen; j++) {
                if (seen[j] == holder) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;
            seen[seenLen++] = holder;
            if (_isUSBuyer(holder)) count++;
        }
    }

    function _isUSBuyer(address account) internal view returns (bool) {
        bytes32 h = keccak256(bytes(badge.getInvestorJurisdiction(account)));
        return h == keccak256("US") || h == keccak256("USA") || h == keccak256("United States");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
