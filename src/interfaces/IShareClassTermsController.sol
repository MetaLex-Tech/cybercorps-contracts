// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IShareClassTermsController {
    function configureClassTerms(address certPrinter, bytes calldata extensionData) external;

    function amendClassTerms(address certPrinter, bytes calldata extensionData) external;

    function accountNewIssuance(
        address certPrinter,
        bytes calldata extensionData,
        uint256 units,
        bool increasesIssuedUnits
    ) external;

    function accountCertificateUpdate(
        address certPrinter,
        uint256 tokenId,
        bytes calldata extensionData,
        uint256 activeUnits,
        bool changesIssuedUnits
    ) external;

    function releaseCertificateUnits(address certPrinter, uint256 tokenId) external;

    function restoreCertificateUnits(address certPrinter, uint256 tokenId) external;

    function releaseScripUnits(address certPrinter, uint256 units) external;

    function getClassTerms(address certPrinter)
        external
        view
        returns (
            bytes memory termsData,
            bytes32 termsHash,
            uint256 authorizedShares,
            uint256 issuedUnits,
            bool configured
        );
}
