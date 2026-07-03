// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {FundInterestData} from "../../../storage/extensions/FundInterestExtension.sol";
import {ICyberCertPrinter} from "../../../interfaces/ICyberCertPrinter.sol";
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

    /// @notice Required hold in seconds (default 365 days: Rule 144(d) for non-reporting issuers)
    uint256 public holdingPeriod;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, uint256 _holdingPeriod) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_holdingPeriod == 0) revert InvalidHoldingPeriod();
        holdingPeriod = _holdingPeriod;
        emit HoldingPeriodUpdated(_holdingPeriod);
    }

    function updateHoldingPeriod(uint256 _holdingPeriod) external onlyAdmin {
        if (_holdingPeriod == 0) revert InvalidHoldingPeriod();
        holdingPeriod = _holdingPeriod;
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

        bytes memory extensionData =
            ICyberCertPrinter(offer.certPrinter).getCertificateDetails(sellerTokenId).extensionData;
        // No fund-interest record = the holding period cannot be verified: fail closed
        if (extensionData.length == 0) return false;

        FundInterestData memory data = abi.decode(extensionData, (FundInterestData));
        uint64 anchor = data.acquisitionDate;
        if (data.tackedFromAcquisitionDate != 0 && data.tackedFromAcquisitionDate < anchor) {
            anchor = data.tackedFromAcquisitionDate;
        }
        if (anchor == 0) return false;

        return block.timestamp >= uint256(anchor) + holdingPeriod;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
