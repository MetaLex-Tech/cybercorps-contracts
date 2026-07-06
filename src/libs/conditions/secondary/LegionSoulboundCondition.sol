// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  LegionSoulboundCondition - issuer-specific credential category/tier gate
/// @author MetaLeX Labs, Inc.
/// @notice Thin condition querying an operator's custom credentialing layer (a LeXcheXBadge deployment)
/// for issuer-specific gating not captured by generic credentials — syndicate-circle restrictions,
/// non-accredited-tier requirements. Configured with the required category and whether the check
/// applies to buyer only or buyer and seller.
contract LegionSoulboundCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidBadge();
    error InvalidCategory();

    event ConfigUpdated(address badge, bytes32 requiredCategoryId, bool applyToSeller);

    ILexChexBadge public badge;
    bytes32 public requiredCategoryId;
    bool public applyToSeller;

    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        bytes32 _requiredCategoryId,
        bool _applyToSeller
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        _setConfig(_badge, _requiredCategoryId, _applyToSeller);
    }

    function updateConfig(address _badge, bytes32 _requiredCategoryId, bool _applyToSeller) external onlyAdmin {
        _setConfig(_badge, _requiredCategoryId, _applyToSeller);
    }

    function _setConfig(address _badge, bytes32 _requiredCategoryId, bool _applyToSeller) internal {
        if (_badge == address(0)) revert InvalidBadge();
        if (_requiredCategoryId == bytes32(0)) revert InvalidCategory();
        badge = ILexChexBadge(_badge);
        requiredCategoryId = _requiredCategoryId;
        applyToSeller = _applyToSeller;
        emit ConfigUpdated(_badge, _requiredCategoryId, _applyToSeller);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        if (buyer != address(0) && !badge.hasValidCredential(buyer, requiredCategoryId)) {
            return false;
        }
        if (applyToSeller && seller != address(0) && !badge.hasValidCredential(seller, requiredCategoryId)) {
            return false;
        }
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
