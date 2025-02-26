
pragma solidity 0.8.28;

import "./libs/auth.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./CyberCorpCertificate.sol";

contract IssuanceManager is BorgAuthACL {
    // Custom errors
    error CompanyDetailsNotSet();
    error SignatureURIRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    
    UpgradeableBeacon public beacon;
    uint256 private _tokenIdCounter;
    // Company details
    string public companyName;
    string public companyJurisdiction;
    string public companyContactDetails;
    string public defaultDisputeResolution;
    string public defaultLegend;

    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap, uint256 discount);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CompanyDetailsUpdated(string companyName, string jurisdiction);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI);

    constructor(address initialImplementation, BorgAuth _auth) BorgAuthACL(_auth) {
        beacon = new UpgradeableBeacon(initialImplementation, address(this));
        _tokenIdCounter = 1;
    }
    
    // Set company details
    function setCompanyDetails(
        string calldata _companyName,
        string calldata _companyJurisdiction,
        string calldata _companyContactDetails,
        string calldata _defaultDisputeResolution,
        string calldata _defaultLegend
    ) external onlyAdmin {
        companyName = _companyName;
        companyJurisdiction = _companyJurisdiction;
        companyContactDetails = _companyContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
        
        emit CompanyDetailsUpdated(_companyName, _companyJurisdiction);
    }

    function issue(
        address investor,
        string calldata investorName,
        uint256 amount,
        uint256 cap,
        uint256 discount,
        string calldata safeTextURI,
        bool transferable,
        string calldata legend
    ) public onlyOwner returns (uint256 tokenId) {
        if (bytes(companyName).length == 0) revert CompanyDetailsNotSet();
        tokenId = _tokenIdCounter++;
        
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(CyberCorpsCertificate.initialize.selector)
        );
        
        // Create certificate details
        CyberCorpsCertificate.CertificateDetails memory details = CyberCorpsCertificate.CertificateDetails({
            issuerName: companyName,
            investorName: investorName,
            securityType: "SAFE",
            purchaseAmount: amount,
            postMoneyValuationCap: cap,
            safeTextURI: safeTextURI,
            transferable: transferable,
            legend: legend,
            governingJurisdiction: companyJurisdiction,
            contactDetails: companyContactDetails,
            disputeResolutionMethod: defaultDisputeResolution,
            issuerSignatureURI: "",
            endorsementSigners: new address[](0),
            endorsementSignatureURIs: new string[](0),
            endorsementTimestamps: new uint256[](0)
        });

        CyberCorpsCertificate(address(proxy)).safeMint(investor, tokenId, details);


        emit CertificateCreated(tokenId, investor, amount, cap, discount);
        return tokenId;
    }
    
    // Add issuer signature to an certificate
    function signCertificate(uint256 tokenId, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCorpsCertificate certificate = getCertificateContract(tokenId);
        certificate.addIssuerSignature(tokenId, signatureURI);
        
        emit CertificateSigned(tokenId, signatureURI);
    }
    
    // Add endorsement for secondary market transfer
    function endorseCertificate(uint256 tokenId, address endorser, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCorpsCertificate certificate = getCertificateContract(tokenId);
        certificate.addEndorsement(tokenId, endorser, signatureURI);
        
        emit CertificateEndorsed(tokenId, endorser, signatureURI);
    }
    
    // Helper function to get the certificate contract
    function getCertificateContract(uint256 tokenId) internal view returns (CyberCorpsCertificate) {
        // This is a simplified approach - in a real implementation, you'd need to track
        // the proxy address for each token ID
        return CyberCorpsCertificate(address(beacon));
    }

    //placeholder function, do not edit
    function convert(uint256 tokenId, address convertTo, uint256 stockAmount) external onlyOwner {
        // Get certificate details
        CyberCorpsCertificate certificate = getCertificateContract(tokenId);
        CyberCorpsCertificate.CertificateDetails memory details = certificate.getCertificateDetails(tokenId);
        
        // Verify it's a SAFE
        if (keccak256(bytes(details.securityType)) != keccak256(bytes("SAFE"))) revert NotSAFEToken();
        
        // Get the proxy address for this token
        address proxyAddress = UpgradeableBeacon(beacon).implementation();
        if (proxyAddress == address(0)) revert TokenProxyNotFound();
        
        // Burn the SAFE token
        CyberCorpsCertificate(proxyAddress).burn(tokenId);
        
        // Issue a new stock token
        uint256 newTokenId = 0;

        emit Converted(tokenId, newTokenId);
    }
    

    function upgradeImplementation(address _newImplementation) external onlyAdmin {
        UpgradeableBeacon(beacon).upgradeTo(_newImplementation);
    }

    function getBeaconImplementation() external view returns (address) {
        return UpgradeableBeacon(beacon).implementation();
    }
}
