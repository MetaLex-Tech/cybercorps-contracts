// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "./BadgeScopedCondition.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Credential} from "../../../creds/storage/lexchexBadgeStorage.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @notice Legion's membership ladder, stored in `Credential.data`. The badge never learns what the bytes
/// mean. Stands in for whatever ladder a real issuer runs.
enum LegionTier {
    NONE,
    PROSPECT,
    MEMBER,
    LEAD
}

/// @title  LegionSoulboundCondition - issuer circle gate: seat plus rank
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV. Wants a seat in one issuer's circle and a minimum rank on
/// its ladder — "MEMBER or better", not just "in the circle". For membership alone, name the lowest rung.
/// An SPV running its own badge layer is pointed at it through the per-SPV override.
/// @dev A qualifying credential carries both keys on one record: K_SYNDICATE scoped to this SPV (the seat)
/// and K_DATA (the rank). A rank is a value, not a flag — two of them contradict — so the badge resolves the
/// holder's current seat with getMostRecentValidWith, and the rank on THAT one is compared to the bar. A
/// holder demoted by a newer seat reads as demoted even if the old seat was never voided.
contract LegionSoulboundCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BadgeScopedCondition {
    /// @notice What a qualifying credential must assert, on one record.
    uint256 private constant SEAT_AND_RANK = K_SYNDICATE | K_DATA;

    struct SpvConfig {
        LegionTier minTier;  // lowest rank that clears the gate; NONE = not configured
        bool applyToSeller;
    }

    error InvalidSpv();
    error InvalidTier();

    event ConfigUpdated(address indexed spv, LegionTier minTier, bool applyToSeller);
    event IssuersUpdated(address[] issuers);

    struct LegionSoulboundStorage {
        mapping(address => SpvConfig) configs;
        address[] issuers; // tier credentials must come from one of these; empty accepts any issuer
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.legion-soulbound.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 2 = 48)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _defaultBadge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __BadgeScopedCondition_init(_defaultBadge);
    }

    /// @notice Sets an SPV's tier requirement; only the SPV's own BorgAuth admin
    function setConfig(address spv, LegionTier _minTier, bool _applyToSeller) external {
        if (spv == address(0)) revert InvalidSpv();
        if (_minTier == LegionTier.NONE) revert InvalidTier();
        _requireAuthAdmin(spv);
        _legionStorage().configs[spv] = SpvConfig({minTier: _minTier, applyToSeller: _applyToSeller});
        emit ConfigUpdated(spv, _minTier, _applyToSeller);
    }

    /// @notice Whose seats count; empty accepts any issuer's.
    function updateIssuers(address[] calldata _issuers) external onlyAdmin {
        _legionStorage().issuers = _issuers;
        emit IssuersUpdated(_issuers);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        SpvConfig storage config = _legionStorage().configs[offer.spvAddress];

        // Never configured: no rank to have reached, so nothing passes until the GP names one.
        if (config.minTier == LegionTier.NONE) return false;

        (address seller, address buyer,) = _resolveParties(dealManager, offer, agreementId);
        ILexChexBadge badge = badgeFor(offer.spvAddress);

        if (buyer != address(0) && !_holds(badge, buyer, offer.spvAddress, config.minTier)) {
            return false;
        }
        if (config.applyToSeller && seller != address(0) && !_holds(badge, seller, offer.spvAddress, config.minTier)) {
            return false;
        }
        return true;
    }

    /// @notice How a rank goes into `Credential.data`. Issuers mint through it so both sides agree.
    function encodeTier(LegionTier tier) public pure returns (bytes memory) {
        return abi.encode(uint256(tier));
    }

    /// @notice An SPV's tier requirement
    function configs(address spv) public view returns (SpvConfig memory) {
        return _legionStorage().configs[spv];
    }

    /// @notice Issuers whose tier credentials this gate accepts; empty means any.
    function issuers() public view returns (address[] memory) {
        return _legionStorage().issuers;
    }

    /// @dev The party's current rank in this SPV's circle, tested against the bar. `scope` keeps seats from
    /// other SPVs out.
    /// A rank the gate cannot read is no rank, so an unreadable newest seat blocks rather than letting an
    /// older one answer in its place.
    function _holds(ILexChexBadge badge, address party, address spv, LegionTier required)
        private
        view
        returns (bool)
    {
        (uint256 tokenId, bool found) =
            badge.getMostRecentValidWith(party, SEAT_AND_RANK, _legionStorage().issuers, spv, address(0), "");
        if (!found) return false;
        return _tierOf(badge.getCredential(tokenId).data) >= uint256(required);
    }

    /// @dev The rank in a payload; 0 when it is not one this gate wrote.
    function _tierOf(bytes memory data) private pure returns (uint256) {
        if (data.length != 32) return 0;
        uint256 tier = abi.decode(data, (uint256));
        return tier > uint256(type(LegionTier).max) ? 0 : tier;
    }

    function _legionStorage() private pure returns (LegionSoulboundStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
