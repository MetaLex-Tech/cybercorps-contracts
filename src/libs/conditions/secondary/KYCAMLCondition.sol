// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {CategoryKind} from "../../../creds/storage/lexchexBadgeStorage.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  KYCAMLCondition - both parties must hold valid, unexpired KYC/AML badges
/// @author MetaLeX Labs, Inc.
/// @notice Shared (singleton) threshold condition. Reads the LeXcheXBadge credentialing layer for both
/// seller and buyer and fails on any expired, voided, or absent badge. Refresh cadence is a
/// credentialing-layer policy (category defaultValidityDuration), not condition logic.
contract KYCAMLCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidBadge();

    event BadgeUpdated(address badge);

    ILexChexBadge public badge;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _badge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // Unknown parties (posting context) short-circuit; known parties enforce.
        if (seller != address(0) && !badge.hasValidCredentialOfKind(seller, CategoryKind.KYC_AML, "")) {
            return false;
        }
        if (buyer != address(0) && !badge.hasValidCredentialOfKind(buyer, CategoryKind.KYC_AML, "")) {
            return false;
        }
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
