
pragma solidity 0.8.28;

import "../CyberCorpConstants.sol";

interface ICertificateConverter {
    struct ConversionPlan {
        // Computed economics
        uint256 shares;              // units to represent on new cert
        uint256 priceBasis;          // min(roundPrice, SAFE_Price) or other basis
        // Target metadata
        SecurityClass targetClass;
        SecuritySeries targetSeries;
        string legalDetails;         // appended to new cert legal details
    }

    /// @notice Compute conversion plan for a given certificate
    /// @param roundManager Address of RoundManager for the corp
    /// @param roundId Equity Financing round identifier
    /// @param certPrinter Source certificate printer
    /// @param tokenId Source certificate token id
    /// @return plan Conversion plan (shares, price basis, target class/series, legal details)
    function computeConversion(
        address roundManager,
        bytes32 roundId,
        address certPrinter,
        uint256 tokenId
    ) external view returns (ConversionPlan memory plan);
}


