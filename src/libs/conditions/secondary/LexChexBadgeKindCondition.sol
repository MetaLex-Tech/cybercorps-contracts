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

    /// @dev _kindKey is validated first
    function _setParameters(uint256 _kindKey, bool _checkSeller) internal {
        if (_kindKey == 0 || (_kindKey & ~ALL_KEYS) != 0) revert InvalidKindKey();
        kindKey = _kindKey;
        checkSeller = _checkSeller;
        emit ParametersUpdated(_kindKey, _checkSeller);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        if (buyer != address(0) && !badge.hasValidCredentialOf(buyer, kindKey)) {
            return false;
        }
        if (checkSeller && seller != address(0) && !badge.hasValidCredentialOf(seller, kindKey)) {
            return false;
        }
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
