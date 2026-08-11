// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  EligibilityCondition - both parties must be admin-cleared to trade
/// @author MetaLeX Labs, Inc.
/// @notice Shared singleton, configured per SPV. Catch-all threshold condition backing offchain eligibility
/// review (KYC/AML, tax forms, ERISA, and any other credentialing gate). The SPV's admin toggles a clearance
/// flag per party; the underlying evidence stays offchain. Fails on any party that SPV has not cleared.
contract EligibilityCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidAccount();
    error InvalidSpv();

    event ClearanceUpdated(address indexed spv, address indexed account, bool cleared);

    struct EligibilityStorage {
        mapping(address => mapping(address => bool)) cleared;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.eligibility.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 1 = 49)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Clears a party for one SPV; only that SPV's own BorgAuth admin
    function setClearance(address spv, address account, bool _cleared) external {
        if (spv == address(0)) revert InvalidSpv();
        if (account == address(0)) revert InvalidAccount();
        _requireAuthAdmin(spv);
        _eligibilityStorage().cleared[spv][account] = _cleared;
        emit ClearanceUpdated(spv, account, _cleared);
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
        EligibilityStorage storage $ = _eligibilityStorage();
        if (seller != address(0) && !$.cleared[offer.spvAddress][seller]) return false;
        if (buyer != address(0) && !$.cleared[offer.spvAddress][buyer]) return false;
        return true;
    }

    /// @notice Whether `account` is cleared to trade under `spv`
    function cleared(address spv, address account) public view returns (bool) {
        return _eligibilityStorage().cleared[spv][account];
    }

    function _eligibilityStorage() private pure returns (EligibilityStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
