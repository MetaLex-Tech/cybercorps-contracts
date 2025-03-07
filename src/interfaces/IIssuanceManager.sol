// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "./ICyberCorp.sol";
import "./ITransferRestrictionHook.sol";

//Adapter interface for custom auth roles. Allows extensibility for different auth protocols i.e. hats.
interface IIssuanceManager is IERC721, IERC721Enumerable, IERC721Metadata {
    // Structs
    struct CertificateDetails {
        string investorName;
        string signingOfficerName;
        string signingOfficerTitle;
        uint256 investmentAmount;
        uint256 issuerUSDValuationAtTimeofInvestment;
        uint256 unitsRepresented;
        bool transferable;
        string legalDetails;
        string issuerSignatureURI;
    }

    struct Endorsement {
        address endorser;
        string signatureURI;
        uint256 timestamp;
    }

    // Events
    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI);
    event HookStatusChanged(bool enabled);
    event WhitelistUpdated(address indexed account, bool whitelisted);

    // Issuance Manager Functions
    function initialize(
        address _auth,
        address _CORP,
        address _CyberCertPrinterImplementation
    ) external;

    function createCertPrinter(
        address initialImplementation,
        string memory _ledger,
        string memory _name,
        string memory _ticker
    ) external returns (address);

    function createCert(
        address certAddress,
        uint256 tokenId,
        address to
    ) external returns (uint256);

    function assignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory _details
    ) external;

    function createCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory _details
    ) external returns (uint256 tokenId);

    function signCertificate(
        address certAddress,
        uint256 tokenId,
        string calldata signatureURI
    ) external;

    function endorseCertificate(
        address certAddress,
        uint256 tokenId,
        address endorser,
        string calldata signatureURI
    ) external;

    function convert(
        address certAddress,
        uint256 tokenId,
        address convertTo,
        uint256 stockAmount
    ) external;

    function upgradeImplementation(
        address _newImplementation
    ) external;

    function getBeaconImplementation() external view returns (address);

    // Certificate Details Functions
    function getCertificateDetails(
        uint256 tokenId
    ) external view returns (CertificateDetails memory);

    function getEndorsementHistory(
        uint256 tokenId,
        uint256 index
    ) external view returns (
        address endorser,
        string memory signatureURI,
        uint256 timestamp
    );

    // Transfer Hook Functions
    function setRestrictionHook(
        uint256 _id,
        address _hookAddress
    ) external;

    function setGlobalRestrictionHook(
        address hookAddress
    ) external;

    function restrictionHooksById(
        uint256 tokenId
    ) external view returns (ITransferRestrictionHook);

    function globalRestrictionHook() external view returns (ITransferRestrictionHook);

    // Beacon Functions
    function CyberCertPrinterBeacon() external view returns (address);
    function CORP() external view returns (address);
    function certifications(uint256) external view returns (address);
    function companyName() external view returns (string memory);
    function companyJurisdiction() external view returns (string memory);
}