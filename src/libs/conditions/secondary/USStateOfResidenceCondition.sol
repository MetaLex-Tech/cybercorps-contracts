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

/// @title  USStateOfResidenceCondition - blue-sky state gating for U.S. acceptors (§6.9, Addendum D)
/// @author MetaLeX Labs, Inc.
/// @notice Shared deployment with per-SPV configuration: a blocked-states list keyed by SPV, adjustable
/// by the GP via a setter gated on the SPV's own BorgAuth admin. New York defaults onto the list for any
/// SPV without Martin Act registration; typical additions are Alabama, Kentucky, Virginia for SPVs
/// expecting only §4(a)(1½)/Rule 144 trades. Reads the state-of-residence (individuals) or
/// state-of-organization (entities) attribute on the acquirer's credential (§4.1.3A).
///
/// | `K_INVESTOR_JURISDICTION` ↓ / `K_US_STATE` → | EMPTY | unblocked | blocked |
/// |----------------------------------------------|-------|-----------|---------|
/// | EMPTY                                        | BLOCK | BLOCK     | BLOCK   |
/// | US                                           | BLOCK | PASS      | BLOCK   |
/// | non-US                                       | PASS  | PASS      | BLOCK   |
///
/// A non-U.S. acquirer carrying no state is out of blue-sky reach and passes. One carrying a blocked state
/// is contradictory evidence — the blue-sky exposure is the side to believe, so it blocks.
contract USStateOfResidenceCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BadgeScopedCondition {
    error InvalidSpv();

    event StateBlocked(address indexed spv, bytes2 state, bool blocked);
    event MartinActRegistrationUpdated(address indexed spv, bool registered);

    bytes2 public constant NEW_YORK = "NY";

    struct USStateStorage {
        mapping(address => mapping(bytes2 => bool)) blockedStates;
        mapping(address => bool) martinActRegistered;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.us-state-of-residence.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 2 = 48)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _badge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __BadgeScopedCondition_init(_badge);
    }

    /// @notice Adds/removes a state on an SPV's blocked list; only the SPV's own BorgAuth admin (the GP)
    function setStateBlocked(address spv, bytes2 state, bool blocked) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _usStateStorage().blockedStates[spv][state] = blocked;
        emit StateBlocked(spv, state, blocked);
    }

    /// @notice Records the SPV's Martin Act registration status; unregistered SPVs block NY by default
    function setMartinActRegistered(address spv, bool registered) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _usStateStorage().martinActRegistered[spv] = registered;
        emit MartinActRegistrationUpdated(spv, registered);
    }

    /// @notice Effective block status for a state, including the NY Martin Act default
    function isStateBlocked(address spv, bytes2 state) public view returns (bool) {
        USStateStorage storage $ = _usStateStorage();
        if ($.blockedStates[spv][state]) return true;
        if (state == NEW_YORK && !$.martinActRegistered[spv]) return true;
        return false;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No acquirer yet (posting context) — nothing to gate
        if (buyer == address(0)) return true;

        // An acquirer with no recorded jurisdiction has not shown whether blue sky reaches the trade
        ILexChexBadge badge = badgeFor(offer.spvAddress);
        string memory jurisdiction = badge.getInvestorJurisdiction(buyer);
        if (bytes(jurisdiction).length == 0) return false;

        // No state recorded: a non-U.S. acquirer is out of blue-sky reach, but a U.S. one blocks rather than
        // passing silently — nothing forces the credential to carry a state, so passing would leave the
        // screen opt-in by the credentialed party
        bytes2 state = badge.getUsState(buyer);
        if (state == bytes2(0)) return !USJurisdictionPolicy.isUS(jurisdiction);

        // A recorded blocked state blocks whatever the jurisdiction says: a foreign domicile alongside a
        // blocked state is contradictory evidence, and the blue-sky exposure is the side to believe
        return !isStateBlocked(offer.spvAddress, state);
    }

    /// @notice Whether an SPV blocks a state outright
    function blockedStates(address spv, bytes2 state) public view returns (bool) {
        return _usStateStorage().blockedStates[spv][state];
    }

    /// @notice Whether an SPV is registered under NY Martin Act Article 23-A
    function martinActRegistered(address spv) public view returns (bool) {
        return _usStateStorage().martinActRegistered[spv];
    }

    function _usStateStorage() private pure returns (USStateStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
