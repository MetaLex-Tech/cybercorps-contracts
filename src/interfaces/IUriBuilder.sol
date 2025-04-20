pragma solidity 0.8.28;

import "../CyberCorpConstants.sol";
import {CertificateDetails, Endorsement, OwnerDetails} from "../storage/CyberCertPrinterStorage.sol";

interface IUriBuilder {
    function buildCertificateUri(
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        SecurityClass securityClass,
        SecuritySeries securitySeries,
        string memory certificateUri,
        string[] memory certLegend,
        CertificateDetails memory details,
        Endorsement[] memory endorsements,
        OwnerDetails memory owner,
        string[] memory globalFields,
        string[] memory globalValues,
        uint256 tokenId,
        address contractAddress
    ) external view returns (string memory);
}
