pragma solidity 0.8.28;

import "./libs/auth.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./CyberCertPrinter.sol";
import "./interfaces/ICyberCorp.sol";

contract IssuanceManager is BorgAuthACL {
    // Custom errors
    error CompanyDetailsNotSet();
    error SignatureURIRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    
    UpgradeableBeacon public beacon;
    uint256 private _tokenIdCounter;
    address public CORP;

    // Mapping to track proxy addresses for each token ID
    mapping(uint256 => address) private _proxyAddresses;

    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CompanyDetailsUpdated(string companyName, string jurisdiction);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI);

    constructor(address _CORP, BorgAuth _auth) BorgAuthACL(_auth) {
        CORP = _CORP;
        _tokenIdCounter = 1;
    }
    
    function createCert(address initialImplementation) public onlyOwner returns (uint256 tokenId) {
        beacon = new UpgradeableBeacon(initialImplementation, address(this));
    }


    function issue(
        address investor,
        CyberCertPrinter.CertificateDetails memory _details
    ) public onlyOwner returns (uint256 tokenId) {
        if (bytes(ICyberCorp(CORP).companyName()).length == 0) revert CompanyDetailsNotSet();
        tokenId = _tokenIdCounter++;
        
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(CyberCertPrinter.initialize.selector)
        );

        CyberCertPrinter(address(proxy)).safeMintAndAssign(investor, tokenId, _details);

        // Store the proxy address for this token ID
        _proxyAddresses[tokenId] = address(proxy);

        emit CertificateCreated(tokenId, investor, _details.investmentAmount, _details.issuerUSDValuationAtTimeofInvestment);
        return tokenId;
    }
    
    // Add issuer signature to an certificate
    function signCertificate(uint256 tokenId, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCertPrinter certificate = getCertificateContract(tokenId);
        certificate.addIssuerSignature(tokenId, signatureURI);
        
        emit CertificateSigned(tokenId, signatureURI);
    }
    
    // Add endorsement for secondary market transfer
    function endorseCertificate(uint256 tokenId, address endorser, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCertPrinter certificate = getCertificateContract(tokenId);
        certificate.addEndorsement(tokenId, endorser, signatureURI);
        
        emit CertificateEndorsed(tokenId, endorser, signatureURI);
    }
    
    // Helper function to get the certificate contract
    function getCertificateContract(uint256 tokenId) internal view returns (CyberCertPrinter) {
        address proxyAddress = _proxyAddresses[tokenId];
        if (proxyAddress == address(0)) revert TokenProxyNotFound();
        return CyberCertPrinter(proxyAddress);
    }

    //placeholder function, do not edit
    function convert(uint256 tokenId, address convertTo, uint256 stockAmount) external onlyOwner {
        // Get certificate details
        CyberCertPrinter certificate = getCertificateContract(tokenId);
        CyberCertPrinter.CertificateDetails memory details = certificate.getCertificateDetails(tokenId);
        
        // Verify it's a SAFE
       // if (details. != SecurityClass.SAFE) revert NotSAFEToken();
        
        // Get the proxy address for this token
        address proxyAddress = UpgradeableBeacon(beacon).implementation();
        if (proxyAddress == address(0)) revert TokenProxyNotFound();
        
        // Burn the SAFE token
        CyberCertPrinter(proxyAddress).burn(tokenId);
        
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
