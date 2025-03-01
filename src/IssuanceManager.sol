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
    address[] public certifications;

    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CompanyDetailsUpdated(string companyName, string jurisdiction);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI);

    constructor(address _CORP, BorgAuth _auth) BorgAuthACL(_auth) {
        CORP = _CORP;
        _tokenIdCounter = 1;
    }
    
    function createCertPrinter(address initialImplementation, string memory _ledger, string memory _name, string memory _ticker) public onlyOwner returns (address) {
        //add new proxy to a set CyberCertPrinter deployement
        address newCert = address(new CyberCertPrinter(_ledger, _name, _ticker));
        certifications.push(newCert);
        return newCert;
    }

    function createCert(address certAddress, uint256 tokenId) public onlyOwner returns (uint256) {
        CyberCertPrinter cert = CyberCertPrinter(certAddress);
        uint256 id = cert.safeMint(tokenId);
        return id;
    }

    function assignCert(address certAddress, uint256 tokenId, address investor, CyberCertPrinter.CertificateDetails memory _details) public onlyOwner {
        CyberCertPrinter cert = CyberCertPrinter(certAddress);
        cert.assignCert(tokenId, investor, _details);
    }

    function createCertAndAssign(
        address certAddress,
        address investor,
        CyberCertPrinter.CertificateDetails memory _details
    ) public onlyOwner returns (uint256 tokenId) {
        if (bytes(ICyberCorp(CORP).companyName()).length == 0) revert CompanyDetailsNotSet();
        CyberCertPrinter cert = CyberCertPrinter(certAddress);
        tokenId = cert.totalSupply();
        
        /*BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(CyberCertPrinter.initialize.selector)
        );*/

        cert.safeMintAndAssign(investor, tokenId, _details);
        emit CertificateCreated(tokenId, investor, _details.investmentAmount, _details.issuerUSDValuationAtTimeofInvestment);
        return tokenId;
    }
    
    // Add issuer signature to an certificate
    function signCertificate(address certAddress, uint256 tokenId, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCertPrinter certificate = CyberCertPrinter(certAddress);
        certificate.addIssuerSignature(tokenId, signatureURI);
        
        emit CertificateSigned(tokenId, signatureURI);
    }
    
    // Add endorsement for secondary market transfer
    function endorseCertificate(address certAddress, uint256 tokenId, address endorser, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        CyberCertPrinter certificate = CyberCertPrinter(certAddress);
        certificate.addEndorsement(tokenId, endorser, signatureURI);
        
        emit CertificateEndorsed(tokenId, endorser, signatureURI);
    }
    

    //placeholder function, do not edit
    function convert(address certAddress, uint256 tokenId, address convertTo, uint256 stockAmount) external onlyOwner {
        // Get certificate details
        CyberCertPrinter certificate = CyberCertPrinter(certAddress);
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
