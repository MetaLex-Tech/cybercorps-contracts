// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {CategoryKind} from "../../../creds/storage/lexchexBadgeStorage.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  LexChexBadgeKindCondition - parameterizable investor-status gate on the LeXcheXBadge layer
/// @author MetaLeX Labs, Inc.
/// @notice The secondary-trading successor of LexChexCondition: one primitive, deployed per
/// parameterization (spec §B):
///  - AccreditedInvestorCondition: kind = ACCREDITED_INVESTOR, buyer only — required for §4(a)(7) trades
///    and typically by operating agreements generally
///  - QualifiedPurchaserCondition: kind = QUALIFIED_PURCHASER, buyer + seller — §3(c)(7) funds only
///  - QualifiedInstitutionalBuyerCondition: kind = QIB, buyer only — Rule 144A pathway only
/// An optional investorType filter narrows within the kind (e.g. accredited / QP / QIB subtype strings).
contract LexChexBadgeKindCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidBadge();

    event BadgeUpdated(address badge);
    event ParametersUpdated(CategoryKind kind, string investorTypeFilter, bool checkSeller);

    ILexChexBadge public badge;
    CategoryKind public kind;
    string public investorTypeFilter;
    bool public checkSeller;

    uint256[46] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        CategoryKind _kind,
        string memory _investorTypeFilter,
        bool _checkSeller
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        kind = _kind;
        investorTypeFilter = _investorTypeFilter;
        checkSeller = _checkSeller;
        emit BadgeUpdated(_badge);
        emit ParametersUpdated(_kind, _investorTypeFilter, _checkSeller);
    }

    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function updateParameters(
        CategoryKind _kind,
        string memory _investorTypeFilter,
        bool _checkSeller
    ) external onlyAdmin {
        kind = _kind;
        investorTypeFilter = _investorTypeFilter;
        checkSeller = _checkSeller;
        emit ParametersUpdated(_kind, _investorTypeFilter, _checkSeller);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        if (buyer != address(0) && !badge.hasValidCredentialOfKind(buyer, kind, investorTypeFilter)) {
            return false;
        }
        if (checkSeller && seller != address(0) && !badge.hasValidCredentialOfKind(seller, kind, investorTypeFilter)) {
            return false;
        }
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
