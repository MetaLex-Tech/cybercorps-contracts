// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {FUND_INTEREST_EXTENSION_TYPE} from "../../../storage/extensions/FundInterestExtension.sol";
import {
    ICertificateExtension,
    IFundInterestExtension
} from "../../../storage/extensions/ICertificateExtension.sol";
import {ILedgerEntryToken} from "../../../interfaces/ILedgerEntryToken.sol";
import {Offer, OfferSide} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  HoldingPeriodCondition - Rule 144 holding-period verification
/// @author MetaLeX Labs, Inc.
/// @notice Shared (generic) threshold condition, attached per exemption pathway (Rule 144). Reads
/// acquisitionDate and tackedFromAcquisitionDate from the seller certificate's FundInterestExtension
/// data (§12B.3). Where Rule 144(d)(3) tacking is asserted (non-zero tackedFromAcquisitionDate), the
/// earlier of the two dates applies; otherwise acquisitionDate alone. Fails if the required hold
/// (one year for non-reporting issuers) has not elapsed.
contract HoldingPeriodCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidHoldingPeriod();

    event HoldingPeriodUpdated(uint256 holdingPeriod);

    struct HoldingPeriodStorage {
        uint256 holdingPeriod;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.holding-period.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 1 = 49)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, uint256 _holdingPeriod) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_holdingPeriod == 0) revert InvalidHoldingPeriod();
        _holdingPeriodStorage().holdingPeriod = _holdingPeriod;
        emit HoldingPeriodUpdated(_holdingPeriod);
    }

    function updateHoldingPeriod(uint256 _holdingPeriod) external onlyAdmin {
        if (_holdingPeriod == 0) revert InvalidHoldingPeriod();
        _holdingPeriodStorage().holdingPeriod = _holdingPeriod;
        emit HoldingPeriodUpdated(_holdingPeriod);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);

        // A buy offer at posting has no seller (and no token) yet: the hold is verified at acceptance
        if (agreementId == bytes32(0) && offer.side == OfferSide.BUY) return true;

        (,, uint256 sellerTokenId) = _resolveParties(dealManager, offer, agreementId);

        ILedgerEntryToken cert = ILedgerEntryToken(offer.certPrinter);
        // Base acquisitionTimestamp; no record = fail closed.
        uint64 anchor = cert.acquisitionTimestamp(sellerTokenId);
        if (anchor == 0) return false;

        // Rule 144(d)(3) tacking anchor (extension) governs where present and earlier. Read through the
        // printer's extension so the payload is decoded at that printer's own version, not a hardcoded layout.
        bytes memory extensionData = cert.getCertificateDetails(sellerTokenId).extensionData;
        address ext = cert.getExtension(sellerTokenId);
        if (
            extensionData.length != 0 &&
            ext != address(0) &&
            ICertificateExtension(ext).supportsExtensionType(FUND_INTEREST_EXTENSION_TYPE)
        ) {
            uint64 tackedFrom = IFundInterestExtension(ext).tackedFromAcquisitionDate(extensionData);
            if (tackedFrom != 0 && tackedFrom < anchor) anchor = tackedFrom;
        }

        // Never configured. A zero hold is not a real Rule 144 setting, so it means unset, not "no wait".
        uint256 period = _holdingPeriodStorage().holdingPeriod;
        if (period == 0) return false;

        return block.timestamp >= uint256(anchor) + period;
    }

    /// @notice Required hold in seconds
    function holdingPeriod() public view returns (uint256) {
        return _holdingPeriodStorage().holdingPeriod;
    }

    function _holdingPeriodStorage() private pure returns (HoldingPeriodStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
