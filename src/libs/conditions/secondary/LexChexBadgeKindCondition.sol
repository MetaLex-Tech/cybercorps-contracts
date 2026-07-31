// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  LexChexBadgeKindCondition - parameterizable investor-status gate on the LeXcheXBadge layer
/// @author MetaLeX Labs, Inc.
/// @notice The secondary-trading successor of LexChexCondition: one primitive, deployed per
/// parameterization (spec §B), configured with the required status fact-key (a K_* value from
/// ILexChexBadge):
///  - AccreditedInvestorCondition: kindKey = K_ACCREDITED, buyer only — required for §4(a)(7) trades
///    and typically by operating agreements generally
///  - QualifiedPurchaserCondition: kindKey = K_QP, buyer + seller — §3(c)(7) funds only
///  - QualifiedInstitutionalBuyerCondition: kindKey = K_QIB, buyer only — Rule 144A pathway only
///  - NonUSPersonCondition: kindKey = K_NON_US, buyer only — Reg S pathway only. The attested fact, never
///    the buyer's recorded country, so a holder can clear the gate without disclosing a jurisdiction
///  - SpvWhitelistCondition: kindKey = K_SPV_WHITELIST — admission to the SPV the offer belongs to
///  - SyndicateCondition: kindKey = K_SYNDICATE — a seat in that SPV's issuer circle (§4.1.3A)
///
/// The first four are statuses, which follow the party anywhere. The last two are entitlements granted per
/// SPV, so they only count for the SPV the offer belongs to.
contract LexChexBadgeKindCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidBadge();
    error InvalidKindKey();

    event BadgeUpdated(address badge);
    event ParametersUpdated(uint256 kindKey, bool checkSeller);

    ILexChexBadge public badge;
    uint256 public kindKey;
    bool public checkSeller;

    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        uint256 _kindKey,
        bool _checkSeller
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
        _setParameters(_kindKey, _checkSeller);
    }

    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function updateParameters(uint256 _kindKey, bool _checkSeller) external onlyAdmin {
        _setParameters(_kindKey, _checkSeller);
    }

    function _setParameters(uint256 _kindKey, bool _checkSeller) internal {
        if (!_isGateable(_kindKey)) revert InvalidKindKey();
        kindKey = _kindKey;
        checkSeller = _checkSeller;
        emit ParametersUpdated(_kindKey, _checkSeller);
    }

    /// @dev Keys this gate can enforce: one or more status facts, or exactly one entitlement. The rest are
    /// wiring slips —
    ///  - empty: matches every credential, so the gate becomes "holds any badge"
    ///  - a value key: asks if a fact was recorded, not if the party qualifies
    ///  - an undefined bit: matches nothing, so every trade is blocked
    ///  - status and entitlement mixed: no one credential answers both
    function _isGateable(uint256 _kindKey) private pure returns (bool) {
        uint256 scoped = _kindKey & SCOPED_KEYS;
        if (scoped == 0) return _kindKey != 0 && (_kindKey & ~STATUS_KEYS) == 0;
        return scoped == _kindKey && (_kindKey & (_kindKey - 1)) == 0;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        if (buyer != address(0) && !_holds(buyer, offer.spvAddress)) {
            return false;
        }
        if (checkSeller && seller != address(0) && !_holds(seller, offer.spvAddress)) {
            return false;
        }
        return true;
    }

    /// @dev A status follows the party anywhere. An entitlement is granted per SPV, so it only counts for the
    /// SPV this offer belongs to.
    function _holds(address party, address spv) private view returns (bool) {
        uint256 key = kindKey;
        if ((key & SCOPED_KEYS) != 0) return badge.hasValidScopedCredentialOf(party, key, spv);
        return badge.hasValidCredentialOf(party, key);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
