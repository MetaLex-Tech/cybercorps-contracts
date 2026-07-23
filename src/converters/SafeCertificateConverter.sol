
pragma solidity 0.8.28;

import "../interfaces/ICertificateConverter.sol";
import "../interfaces/ILedgerEntryToken.sol";
import "../RoundManager.sol";

/// @title SafeCertificateConverter
/// @notice Computes conversion plan for certificates based on RoundManager data
contract SafeCertificateConverter is ICertificateConverter {
    error InvalidRoundConfig();
    error MathError();

    /// @inheritdoc ICertificateConverter
    function computeConversion(
        address roundManager,
        bytes32 roundId,
        address certPrinter,
        uint256 tokenId
    ) external view override returns (ConversionPlan memory plan) {
        // Read source cert details
       /* ILedgerEntryToken source = ILedgerEntryToken(certPrinter);
        CertificateDetails memory src = source.getCertificateDetails(tokenId);

        // Pull round info from RoundManager via primitive getters
        RoundManager rm = RoundManager(roundManager);
        if (!rm.roundExists(roundId)) revert InvalidRoundConfig();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 cCapUsed
        ) = rm.getCapTableSnapshotFields(roundId);

        (uint8 mode, uint8 priceDecimals, uint8 shareDecimals) = rm.getRoundingPolicyFields(roundId);
        (uint256 roundPrice, uint8 roundPriceDecimals) = rm.getRoundPriceInfo(roundId);
        (SecurityClass cls, SecuritySeries series) = rm.getPrimarySecurity(roundId);

        if (cCapUsed == 0 || roundPrice == 0) revert InvalidRoundConfig();
        if (src.investmentAmountUSD == 0 || src.issuerUSDValuationAtTimeOfInvestment == 0) revert InvalidRoundConfig();

        // Compute SAFE price: SAFE_Price = PMVC / CCap, normalized to roundPriceDecimals
        uint256 pmvc = src.issuerUSDValuationAtTimeOfInvestment;
        uint256 pa = src.investmentAmountUSD;
        uint256 safePrice = (pmvc * (10 ** uint256(roundPriceDecimals))) / cCapUsed;
        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice;

        // Compute shares = PA / priceBasis with decimals and rounding policy
        // We scale numerator by (priceDecimals + shareDecimals), then divide by priceBasis and de-scale by priceDecimals
        // Use roundPriceDecimals for price scaling to align with priceBasis units
        uint256 numerator = pa * (10 ** (uint256(roundPriceDecimals) + uint256(shareDecimals)));
        uint256 raw = numerator / priceBasis;
        uint256 denom = (10 ** uint256(roundPriceDecimals));
        uint256 shares;
        if (mode == 0) {
            // Floor
            shares = raw / denom;
        } else if (mode == 1) {
            // Ceil
            shares = (raw + denom - 1) / denom;
        } else {
            // Round half up
            shares = (raw + denom / 2) / denom;
        }
        if (shares == 0) revert MathError();

        // Fill plan
        plan.shares = shares;
        plan.priceBasis = priceBasis;
        plan.targetClass = cls;
        plan.targetSeries = series;
        plan.legalDetails = "Converted from SAFE";*/
    }
}


