// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice Optional interface implemented by share certificate extensions.
/// @dev Keeps the printer independent from the large ShareCertData ABI while
///      still allowing it to make SeriesTerms authoritative at class level.
interface IShareClassTermsExtension {
    function getSeriesTermsData(
        bytes calldata extensionData
    ) external view returns (bytes memory termsData, uint256 authorizedShares);
}
