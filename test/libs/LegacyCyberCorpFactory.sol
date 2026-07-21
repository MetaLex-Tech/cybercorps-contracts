// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CompanyOfficer, SecurityClass, SecuritySeries} from "../../src/CyberCorpConstants.sol";
import {CertificateDetails} from "../../src/storage/CyberCertPrinterStorage.sol";
import {RoundType} from "../../src/libs/RoundLib.sol";

/// @dev Certificate tuple used by factory and round-manager implementations deployed before series data.
struct LegacyCyberCertData {
    string name;
    string symbol;
    string uri;
    SecurityClass securityClass;
    SecuritySeries securitySeries;
    address extension;
    string[] defaultLegend;
}

/// @dev Test-only ABI for historical CyberCorpFactory implementations.
interface ILegacyCyberCorpFactory {
    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address companyPayable,
        CompanyOfficer memory officer,
        LegacyCyberCertData[] memory certData,
        bytes32 templateId,
        string[] memory globalValues,
        address[] memory parties,
        uint256 paymentAmount,
        string[][] memory partyValues,
        bytes memory signature,
        CertificateDetails[] memory details,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (
        address cyberCorpAddress,
        address authAddress,
        address issuanceManagerAddress,
        address dealManagerAddress,
        address roundManagerAddress,
        address[] memory certPrinterAddress,
        bytes32 id,
        uint256[] memory certIds
    );

    function deployCyberCorpAndCreateRound(
        uint256 salt,
        SecuritySeries seriesType,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address companyPayable,
        CompanyOfficer memory officer,
        string[] memory legalDetails,
        bytes[] memory extensionData,
        LegacyCyberCertData[] memory certData,
        bytes32 templateId,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature,
        RoundType roundType,
        address[] memory conditions,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 startTime,
        uint256 endTime,
        bool publicRound,
        bool allowTimedOffers,
        bool restrictEndTimeReduction
    ) external returns (
        address cyberCorpAddress,
        address authAddress,
        address issuanceManagerAddress,
        address dealManagerAddress,
        address roundManagerAddress,
        bytes32 roundId
    );
}
