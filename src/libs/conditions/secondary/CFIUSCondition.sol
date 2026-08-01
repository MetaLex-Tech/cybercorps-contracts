// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "./BadgeScopedCondition.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";
import {USJurisdictionPolicy} from "../../policies/USJurisdictionPolicy.sol";

/// @title  CFIUSCondition - FIRRMA gating for CFIUS-sensitive SPVs
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV. Only SPVs that do not satisfy the FIRRMA investment fund
/// exception (31 CFR §800.307) set `tidUsBusiness`; the rest stay dormant and pass. A foreign acquirer, or
/// one from a jurisdiction the GP treats as a blocked affiliation, cannot take the interest until the GP
/// records a manual clearance for that SPV.
///
/// An SPV the GP has recorded as dormant (not a TID U.S. business), no acquirer yet, or a recorded
/// clearance passes ahead of the table. An SPV with no determination on record at all blocks.
///
/// | `K_INVESTOR_JURISDICTION` | policy    |
/// |---------------------------|-----------|
/// | EMPTY                     | CLEARANCE |
/// | US                        | PASS      |
/// | non-US                    | CLEARANCE |
///
/// A U.S. acquirer still needs clearance if its physical or its look-through jurisdiction is on the GP's
/// blocked list: CFIUS cares about who controls it, not where it is registered.
contract CFIUSCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BadgeScopedCondition {
    struct SpvConfig {
        bool tidUsBusiness;              // the SPV's CFIUS sensitivity determination
        string[] blockedJurisdictions;   // jurisdictions the GP treats as a blocked affiliation
        bool configured;                 // dormant and unconfigured are different answers, so record which
    }

    error InvalidSpv();
    error InvalidBuyer();

    event TidUsBusinessUpdated(address indexed spv, bool tidUsBusiness);
    event BlockedJurisdictionsUpdated(address indexed spv, string[] jurisdictions);
    event CfiusClearanceUpdated(address indexed spv, address indexed buyer, bool cleared, address indexed approver);

    struct CFIUSStorage {
        mapping(address => SpvConfig) configs;
        mapping(address => mapping(address => bool)) cfiusCleared;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.cfius.storage.v1");

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

    /// @notice Records the SPV's TID U.S. business determination, and with it that the GP has made one at
    /// all; only the SPV's own BorgAuth admin. False is the finding that the FIRRMA fund exception applies.
    function setTidUsBusiness(address spv, bool _tidUsBusiness) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        SpvConfig storage config = _cfiusStorage().configs[spv];
        config.tidUsBusiness = _tidUsBusiness;
        config.configured = true;
        emit TidUsBusinessUpdated(spv, _tidUsBusiness);
    }

    /// @notice Replaces the SPV's blocked-affiliation list; only the SPV's own BorgAuth admin
    function setBlockedJurisdictions(address spv, string[] memory _blockedJurisdictions) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _cfiusStorage().configs[spv].blockedJurisdictions = _blockedJurisdictions;
        emit BlockedJurisdictionsUpdated(spv, _blockedJurisdictions);
    }

    /// @notice Records the outcome of the GP's manual review for a buyer; only the SPV's own BorgAuth admin.
    /// A clearance answers for this SPV alone — another SPV's review is its own to make.
    function setCfiusClearance(address spv, address buyer, bool cleared) external {
        if (spv == address(0)) revert InvalidSpv();
        if (buyer == address(0)) revert InvalidBuyer();
        _requireAuthAdmin(spv);
        _cfiusStorage().cfiusCleared[spv][buyer] = cleared;
        emit CfiusClearanceUpdated(spv, buyer, cleared, msg.sender);
    }

    function tidUsBusiness(address spv) external view returns (bool) {
        return _cfiusStorage().configs[spv].tidUsBusiness;
    }

    function blockedJurisdictions(address spv) external view returns (string[] memory) {
        return _cfiusStorage().configs[spv].blockedJurisdictions;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        CFIUSStorage storage $ = _cfiusStorage();
        SpvConfig storage config = $.configs[offer.spvAddress];

        // Attached but the GP has recorded no determination. Attaching the condition is itself a statement
        // that CFIUS reaches this SPV, so silence is not the fund exception — nothing passes until they say.
        if (!config.configured) return false;
        if (!config.tidUsBusiness) return true;

        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No buyer yet (posting context) — nothing to gate
        if (buyer == address(0)) return true;

        // A recorded clearance attestation satisfies the condition regardless of nationality
        if ($.cfiusCleared[offer.spvAddress][buyer]) return true;

        // Foreign acquirers require clearance, and an unestablished jurisdiction is empty — not U.S. — so it
        // falls the same way (fail closed for CFIUS)
        ILexChexBadge badge = badgeFor(offer.spvAddress);
        string memory jurisdiction = badge.getInvestorJurisdiction(buyer);
        if (!USJurisdictionPolicy.isUS(jurisdiction)) return false;

        // A U.S. acquirer can still be foreign-controlled, and CFIUS cares about control. So the blocked list
        // is matched against the look-through jurisdiction too, not just where the buyer is registered.
        if (_isBlocked(config, jurisdiction)) return false;
        return !_isBlocked(config, badge.getLookThroughJurisdiction(buyer));
    }

    function _isBlocked(SpvConfig storage config, string memory jurisdiction) private view returns (bool) {
        if (bytes(jurisdiction).length == 0) return false;
        bytes32 j = keccak256(bytes(jurisdiction));
        for (uint256 i = 0; i < config.blockedJurisdictions.length; i++) {
            if (keccak256(bytes(config.blockedJurisdictions[i])) == j) return true;
        }
        return false;
    }

    /// @notice Whether the GP has cleared `buyer` for `spv`
    function cfiusCleared(address spv, address buyer) public view returns (bool) {
        return _cfiusStorage().cfiusCleared[spv][buyer];
    }

    function _cfiusStorage() private pure returns (CFIUSStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
