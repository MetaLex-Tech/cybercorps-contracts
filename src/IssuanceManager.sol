pragma solidity 0.8.28;

import "./libs/auth.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./storage/IssuanceManagerStorage.sol";


contract IssuanceManager is Initializable, UUPSUpgradeable, BorgAuthACL {
    using IssuanceManagerStorage for IssuanceManagerStorage.IssuanceManagerData;

    // Custom errors
    error CompanyDetailsNotSet();
    error SignatureURIRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    
    event CertPrinterCreated(address indexed certificate, address indexed corp, string[] ledger, string name, string ticker, SecurityClass securityType, SecuritySeries securitySeries, string certificateUri);
    event CertificateCreated(uint256 indexed tokenId, address indexed certificate, uint256 amount, uint256 cap, CertificateDetails details);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CompanyDetailsUpdated(string companyName, string jurisdiction);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    /// @notice Initializer function that sets up the contract
    /// @param _auth Address of the BorgAuth contract
    /// @param _CORP Address of the CyberCorp contract
    /// @param _CyberCertPrinterImplementation Implementation address for CyberCertPrinter
    function initialize(
        address _auth,
        address _CORP,
        address _CyberCertPrinterImplementation,
        address _uriBuilder
    ) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        
        // Set storage values
        IssuanceManagerStorage.setCORP(_CORP);
        IssuanceManagerStorage.setUriBuilder(_uriBuilder);
        
        // Create beacon with implementation
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            _CyberCertPrinterImplementation,
            address(this)
        );
        IssuanceManagerStorage.setCyberCertPrinterBeacon(beacon);
    }
    
    function createCertPrinter(string[] memory _ledger, string memory _name, string memory _ticker, string memory _certificateUri, SecurityClass _securityType, SecuritySeries _securitySeries) public onlyOwner returns (address) {
        //add new proxy to a set CyberCertPrinter deployement
        bytes32 salt = keccak256(abi.encodePacked(IssuanceManagerStorage.getPrinters().length, address(this)));
        address newCert = Create2.deploy(0, salt, _getBytecode());
        IssuanceManagerStorage.addPrinter(newCert);
        ICyberCertPrinter(newCert).initialize(_ledger, _name, _ticker, _certificateUri, address(this), _securityType, _securitySeries);
        emit CertPrinterCreated(newCert, IssuanceManagerStorage.getCORP(), _ledger, _name, _ticker, _securityType, _securitySeries, _certificateUri);
        return newCert;
    }


    function createCert(address certAddress, address to, CertificateDetails memory _details) public onlyOwner returns (uint256) {
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        uint256 tokenId = cert.totalSupply();
        uint256 id = cert.safeMint(tokenId, to, _details);
        emit CertificateCreated(tokenId, certAddress, _details.investmentAmount, _details.issuerUSDValuationAtTimeofInvestment, _details);
        return id;
    }

    function assignCert(address certAddress, address from, uint256 tokenId, address investor, CertificateDetails memory _details) public onlyOwner {
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        cert.assignCert(from, tokenId, investor, _details);
    }

    function createCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory _details
    ) public onlyOwner returns (uint256 tokenId) {
        if (bytes(ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPName()).length == 0) revert CompanyDetailsNotSet();
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        tokenId = cert.totalSupply();
    
        cert.safeMintAndAssign(investor, tokenId, _details);
        emit CertificateCreated(tokenId, certAddress, _details.investmentAmount, _details.issuerUSDValuationAtTimeofInvestment, _details);
        return tokenId;
    }
    
    // Add issuer signature to an certificate
    function signCertificate(address certAddress, uint256 tokenId, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addIssuerSignature(tokenId, signatureURI);
    }
    
    // Add endorsement for secondary market transfer
    function endorseCertificate(address certAddress, uint256 tokenId, address endorser, bytes memory signature, bytes32 agreementId) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        Endorsement memory newEndorsement = Endorsement(endorser, block.timestamp, signature, address(0), agreementId, address(0), "");
        certificate.addEndorsement(tokenId, newEndorsement);
    }

    function voidCertificate(address certAddress, uint256 tokenId) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.voidCert(tokenId);
    }
    
    function setGlobalTransferable(address certAddress, bool transferable) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalTransferable(transferable);
    }

    function upgradeImplementation(address _newImplementation) external onlyAdmin {
        IssuanceManagerStorage.updateBeaconImplementation(_newImplementation);
    }

    function getBeaconImplementation() external view returns (address) {
        return IssuanceManagerStorage.getCyberCertPrinterBeacon().implementation();
    }

    function _getBytecode() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(IssuanceManagerStorage.getCyberCertPrinterBeacon(), ""));
    }

    function companyName() external view returns (string memory) {
        return ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPName();
    }

    function companyJurisdiction() external view returns (string memory) {
        return ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPJurisdiction();
    }

    // Public getters for storage variables
    function CORP() external view returns (address) {
        return IssuanceManagerStorage.getCORP();
    }

    function uriBuilder() external view returns (address) {
        return IssuanceManagerStorage.getUriBuilder();
    }

    function CyberCertPrinterBeacon() external view returns (UpgradeableBeacon) {
        return IssuanceManagerStorage.getCyberCertPrinterBeacon();
    }

    function printers(uint256 index) external view returns (address) {
        return IssuanceManagerStorage.getPrinters()[index];
    }

    /// @notice Function that authorizes an upgrade to a new implementation
    /// @dev Only callable by owner due to onlyOwner modifier inherited from BorgAuthACL
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
