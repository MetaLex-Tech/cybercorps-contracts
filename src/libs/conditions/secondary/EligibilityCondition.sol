// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  EligibilityCondition - both parties must be admin-cleared to trade
/// @author MetaLeX Labs, Inc.
/// @notice Catch-all threshold condition backing offchain eligibility review (KYC/AML, tax forms,
/// ERISA, and any other credentialing gate). The credentialing-layer admin toggles a per-account
/// clearance flag; the underlying evidence stays offchain. Fails on any party that is not cleared.
contract EligibilityCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidAccount();

    event ClearanceUpdated(address indexed account, bool cleared);

    mapping(address => bool) public cleared;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function setClearance(address account, bool _cleared) external onlyAdmin {
        if (account == address(0)) revert InvalidAccount();
        cleared[account] = _cleared;
        emit ClearanceUpdated(account, _cleared);
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
        if (seller != address(0) && !cleared[seller]) return false;
        if (buyer != address(0) && !cleared[buyer]) return false;
        return true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
