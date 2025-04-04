//make an interface for the CyberCorpPrinter
pragma solidity 0.8.28;

import "./IIssuanceManager.sol";
import "../CyberCorpConstants.sol";

    struct Endorsement {
        address endorser;
        uint256 timestamp;
        bytes signatureHash;
        address registry;  //optional
        bytes32 agreementId; //optional
        address endorsee;
        string endorseeName;
    }

interface ICyberCertPrinter {
    function initialize(string memory _ledger, string memory name, string memory ticker, string memory _certificateUri, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external;
    function updateIssuanceManager(address _issuanceManager) external;
    function updateLedger(string memory _ledger) external;
    function setRestrictionHook(uint256 _id, address _hookAddress) external;
    function setGlobalRestrictionHook(address hookAddress) external;
    function safeMint(uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256);
    function setGlobalTransferable(bool _transferable) external;
    function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails memory details) external returns (uint256);
    function assignCert(address from, uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256);
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external;
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) external;
    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external;
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external;
    function burn(uint256 tokenId) external;
    function voidCert(uint256 tokenId) external;
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory);
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        address endorser,
        string memory endorseeName,
        address registry,
        bytes32 agreementId,
        uint256 timestamp,
        bytes memory signatureHash,
        address endorsee
    );
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
}
