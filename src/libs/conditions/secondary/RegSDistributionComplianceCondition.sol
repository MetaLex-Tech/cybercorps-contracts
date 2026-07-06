// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {FundInterestData} from "../../../storage/extensions/FundInterestExtension.sol";
import {ICyberCertPrinter} from "../../../interfaces/ICyberCertPrinter.sol";
import {Offer, OfferSide} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  RegSDistributionComplianceCondition - Regulation S distribution compliance period
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition for the Reg S pathway. The applicable compliance period is a
/// function of the SPV's domicile and Reg S issuer category (1/2/3) — determined by counsel and encoded
/// here at configuration by the SPV's admin (e.g. one year for Category 3 U.S. equity). Fails if the
/// period has not elapsed since the interest's acquisitionDate (FundInterestExtension data, §12B.3).
contract RegSDistributionComplianceCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    struct RegSConfig {
        uint8 issuerCategory;       // Reg S issuer category 1 / 2 / 3 (informational)
        uint64 compliancePeriod;    // seconds; the encoded distribution compliance period
        bool configured;
    }

    error InvalidSpv();
    error InvalidCategory();

    event RegSConfigUpdated(address indexed spv, uint8 issuerCategory, uint64 compliancePeriod);

    /// @notice Per-SPV (cyberCORP address) Reg S parameterization
    mapping(address => RegSConfig) public regSConfigs;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Encodes an SPV's Reg S category and compliance period; only the SPV's own BorgAuth admin
    function setRegSConfig(address spv, uint8 issuerCategory, uint64 compliancePeriod) external {
        if (spv == address(0)) revert InvalidSpv();
        if (issuerCategory == 0 || issuerCategory > 3) revert InvalidCategory();
        _requireAuthAdmin(spv);
        regSConfigs[spv] = RegSConfig({
            issuerCategory: issuerCategory,
            compliancePeriod: compliancePeriod,
            configured: true
        });
        emit RegSConfigUpdated(spv, issuerCategory, compliancePeriod);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);

        // A Reg S resale from an unconfigured SPV fails closed
        RegSConfig memory config = regSConfigs[offer.spvAddress];
        if (!config.configured) return false;

        // A bid at posting has no seller (and no token) yet: the period is verified at acceptance
        if (agreementId == bytes32(0) && offer.side == OfferSide.BUY) return true;

        (,, uint256 sellerTokenId) = _resolveParties(dealManager, offer, agreementId);

        bytes memory extensionData =
            ICyberCertPrinter(offer.certPrinter).getCertificateDetails(sellerTokenId).extensionData;
        if (extensionData.length == 0) return false;

        FundInterestData memory data = abi.decode(extensionData, (FundInterestData));
        if (data.acquisitionDate == 0) return false;

        return block.timestamp >= uint256(data.acquisitionDate) + config.compliancePeriod;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
