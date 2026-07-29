// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  CFIUSCondition - FIRRMA gating for CFIUS-sensitive SPVs
/// @author MetaLeX Labs, Inc.
/// @notice Per-SPV deployment, and only for SPVs that do not satisfy the FIRRMA investment fund
/// exception (31 CFR §800.307) — most SPVs never deploy it. Blocks transfers to non-U.S. persons or
/// persons from blocked jurisdictions pending manual GP review and a CFIUS clearance attestation
/// recorded here by the SPV's admin.
contract CFIUSCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidBadge();
    error InvalidBuyer();

    event BadgeUpdated(address badge);
    event TidUsBusinessUpdated(bool tidUsBusiness);
    event BlockedJurisdictionsUpdated(string[] jurisdictions);
    event CfiusClearanceUpdated(address indexed buyer, bool cleared, address indexed approver);

    ILexChexBadge public badge;
    /// @notice The SPV's CFIUS sensitivity flag: TID U.S. business determination. When false the
    /// condition is dormant (always passes).
    bool public tidUsBusiness;
    /// @notice Jurisdictions (country codes matching badge credential jurisdiction strings) that always
    /// require clearance regardless of non-U.S.-person analysis
    string[] public blockedJurisdictions;

    /// @notice GP-recorded CFIUS clearance attestations, per buyer
    mapping(address => bool) public cfiusCleared;

    uint256[45] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        bool _tidUsBusiness,
        string[] memory _blockedJurisdictions
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        tidUsBusiness = _tidUsBusiness;
        blockedJurisdictions = _blockedJurisdictions;
        emit BadgeUpdated(_badge);
        emit TidUsBusinessUpdated(_tidUsBusiness);
        emit BlockedJurisdictionsUpdated(_blockedJurisdictions);
    }

    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function setTidUsBusiness(bool _tidUsBusiness) external onlyAdmin {
        tidUsBusiness = _tidUsBusiness;
        emit TidUsBusinessUpdated(_tidUsBusiness);
    }

    // TODO:
    // - legion will add the regions
    // - potentially zkpassport
    // - ideally handle/aggregated by LexChexBadge
    function setBlockedJurisdictions(string[] memory _blockedJurisdictions) external onlyAdmin {
        blockedJurisdictions = _blockedJurisdictions;
        emit BlockedJurisdictionsUpdated(_blockedJurisdictions);
    }

    /// @notice Records the outcome of the GP's manual review / CFIUS clearance for a buyer
    function setCfiusClearance(address buyer, bool cleared) external onlyAdmin {
        if (buyer == address(0)) revert InvalidBuyer();
        cfiusCleared[buyer] = cleared;
        emit CfiusClearanceUpdated(buyer, cleared, msg.sender);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        if (!tidUsBusiness) return true;

        Offer memory offer = dealManager.getOffer(offerId);
        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No buyer yet (posting context) — nothing to gate
        if (buyer == address(0)) return true;

        // A recorded clearance attestation satisfies the condition regardless of nationality
        if (cfiusCleared[buyer]) return true;

        // Non-U.S. persons require clearance; US-ness now routes through the single physical-jurisdiction fact
        // (no separate non-U.S.-person credential to disagree with it). An unestablished jurisdiction reads as
        // empty, which is not U.S., so the buyer is treated as requiring clearance (fail closed for CFIUS). The
        // U.S.-string test is the badge's canonical one, shared to avoid drift.
        string memory jurisdiction = badge.getInvestorJurisdiction(buyer);
        if (!badge.isUSJurisdiction(jurisdiction)) return false;

        // A U.S. buyer whose credential jurisdiction matches a blocked-affiliation entry still needs clearance
        bytes32 j = keccak256(bytes(jurisdiction));
        for (uint256 i = 0; i < blockedJurisdictions.length; i++) {
            if (keccak256(bytes(blockedJurisdictions[i])) == j) return false;
        }
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
