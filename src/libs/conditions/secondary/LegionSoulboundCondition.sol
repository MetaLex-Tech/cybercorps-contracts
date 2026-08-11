// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "./BadgeScopedCondition.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  LegionSoulboundCondition - issuer-specific credential category/tier gate
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV. Gates on an issuer's own credential label — syndicate
/// circles, non-accredited tiers — which generic credentials do not capture. Each SPV names the label its
/// parties must hold and whether the seller is checked too. An SPV whose operator runs its own LeXcheXBadge
/// layer is pointed at it through the per-SPV badge override.
contract LegionSoulboundCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BadgeScopedCondition {
    struct SpvConfig {
        bytes32 requiredCategoryId;  // issuer label the party must hold; zero = not configured
        bool applyToSeller;
    }

    error InvalidSpv();
    error InvalidCategory();

    event ConfigUpdated(address indexed spv, bytes32 requiredCategoryId, bool applyToSeller);

    struct LegionSoulboundStorage {
        mapping(address => SpvConfig) configs;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.legion-soulbound.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 1 = 49)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _defaultBadge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __BadgeScopedCondition_init(_defaultBadge);
    }

    /// @notice Sets an SPV's circle requirement; only the SPV's own BorgAuth admin
    function setConfig(address spv, bytes32 _requiredCategoryId, bool _applyToSeller) external {
        if (spv == address(0)) revert InvalidSpv();
        if (_requiredCategoryId == bytes32(0)) revert InvalidCategory();
        _requireAuthAdmin(spv);
        _legionStorage().configs[spv] = SpvConfig({requiredCategoryId: _requiredCategoryId, applyToSeller: _applyToSeller});
        emit ConfigUpdated(spv, _requiredCategoryId, _applyToSeller);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        SpvConfig storage config = _legionStorage().configs[offer.spvAddress];

        // Attached but never configured. There is no circle to be a member of, and silence is not a finding
        // that none applies, so nothing passes until the GP names one.
        if (config.requiredCategoryId == bytes32(0)) return false;

        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);
        ILexChexBadge badge = badgeFor(offer.spvAddress);

        if (buyer != address(0) && !badge.hasValidCredential(buyer, config.requiredCategoryId)) {
            return false;
        }
        if (config.applyToSeller && seller != address(0) && !badge.hasValidCredential(seller, config.requiredCategoryId)) {
            return false;
        }
        return true;
    }

    /// @notice An SPV's circle requirement
    function configs(address spv) public view returns (SpvConfig memory) {
        return _legionStorage().configs[spv];
    }

    function _legionStorage() private pure returns (LegionSoulboundStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
