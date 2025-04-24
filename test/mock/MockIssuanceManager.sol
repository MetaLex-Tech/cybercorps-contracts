/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "../../src/libs/auth.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../../src/interfaces/ICyberCertPrinter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./MockIssuanceManagerStorage.sol";

/// @title IssuanceManager
/// @notice Manages the issuance and lifecycle of digital certificates representing securities and more
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract MockIssuanceManager is Initializable, UUPSUpgradeable, BorgAuthACL {
    using IssuanceManagerStorage for IssuanceManagerStorage.IssuanceManagerData;
 
    // IssuanceManager errors
    error CompanyDetailsNotSet();
    error SignatureURIRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    error NotUpgradeFactory();
    
    event CertPrinterCreated(address indexed certificate, address indexed corp, string[] ledger, string name, string ticker, SecurityClass securityType, SecuritySeries securitySeries, string certificateUri);
    event CertificateCreated(uint256 indexed tokenId, address indexed certificate, uint256 amount, uint256 cap, CertificateDetails details);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CompanyDetailsUpdated(string companyName, string jurisdiction);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the IssuanceManager contract
    /// @param _auth Address of the BorgAuth contract
    /// @param _CORP Address of the CyberCorp contract
    /// @param _CyberCertPrinterImplementation Implementation address for CyberCertPrinter
    /// @param _uriBuilder Address of the json URI builder contract for certificate metadata
    function initialize(
        address _auth,
        address _CORP,
        address _CyberCertPrinterImplementation,
        address _uriBuilder,
        address _upgradeFactory
    ) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        
        IssuanceManagerStorage.setCORP(_CORP);
        IssuanceManagerStorage.setUriBuilder(_uriBuilder);
        
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            _CyberCertPrinterImplementation,
            address(this)
        );
        IssuanceManagerStorage.setCyberCertPrinterBeacon(beacon);
        IssuanceManagerStorage.setUpgradeFactory(_upgradeFactory);
    }

    modifier onlyUpgradeFactory() {
        if (msg.sender != IssuanceManagerStorage.getUpgradeFactory()) revert NotUpgradeFactory();
        _;
    }
    
    /// @notice Creates a new certificate printer contract
    /// @dev Only callable by owner
    /// @param _ledger Array of default restrictive ledgers for a certificate
    /// @param _name Name of the certificate
    /// @param _ticker Trading symbol
    /// @param _certificateUri URI containing certificate metadata
    /// @param _securityType Type of security being represented
    /// @param _securitySeries Series of the security
    /// @return address Address of the new certificate printer contract
    function createCertPrinter(string[] memory _ledger, string memory _name, string memory _ticker, string memory _certificateUri, SecurityClass _securityType, SecuritySeries _securitySeries) public onlyOwner returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(IssuanceManagerStorage.getPrinters().length, address(this)));
        address newCert = Create2.deploy(0, salt, _getBytecode());
        IssuanceManagerStorage.addPrinter(newCert);
        ICyberCertPrinter(newCert).initialize(_ledger, _name, _ticker, _certificateUri, address(this), _securityType, _securitySeries);
        emit CertPrinterCreated(newCert, IssuanceManagerStorage.getCORP(), _ledger, _name, _ticker, _securityType, _securitySeries, _certificateUri);
        return newCert;
    }

    /// @notice Creates a new certificate
    /// @dev Only callable by owner
    /// @param certAddress Address of the certificate printer contract
    /// @param to Recipient of the certificate
    /// @param _details Certificate details
    /// @return uint256 ID of the new certificate
    function createCert(address certAddress, address to, CertificateDetails memory _details) public onlyOwner returns (uint256) {
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        uint256 tokenId = cert.totalSupply();
        uint256 id = cert.safeMint(tokenId, to, _details);
        emit CertificateCreated(tokenId, certAddress, _details.investmentAmount, _details.issuerUSDValuationAtTimeofInvestment, _details);
        return id;
    }

    /// @notice Assigns an existing certificate to a new investor
    /// @dev Only callable by owner
    /// @param certAddress Address of the certificate printer contract
    /// @param from Current owner of the certificate
    /// @param tokenId ID of the certificate
    /// @param investor New owner of the certificate
    /// @param _details Updated certificate details
    function assignCert(address certAddress, address from, uint256 tokenId, address investor, CertificateDetails memory _details) public onlyOwner {
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        cert.assignCert(from, tokenId, investor, _details);
    }

    /// @notice Creates and assigns a new certificate in one transaction
    /// @dev Only callable by owner, requires company details to be set
    /// @param certAddress Address of the certificate printer contract
    /// @param investor Recipient of the certificate
    /// @param _details Certificate details
    /// @return tokenId ID of the new certificate
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
    
    /// @notice Adds an issuer's signature to a certificate
    /// @dev Only callable by admin, requires valid signature URI
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param signatureURI URI containing the signature data
    function signCertificate(address certAddress, uint256 tokenId, string calldata signatureURI) external onlyAdmin {
        if (bytes(signatureURI).length == 0) revert SignatureURIRequired();
        
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addIssuerSignature(tokenId, signatureURI);
    }
    
    /// @notice Adds an endorsement for secondary market transfer
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param endorser Address of the endorser
    /// @param signature Endorsement signature
    /// @param agreementId ID of the associated agreement
    function endorseCertificate(address certAddress, uint256 tokenId, address endorser, bytes memory signature, bytes32 agreementId) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        Endorsement memory newEndorsement = Endorsement(endorser, block.timestamp, signature, address(0), agreementId, address(0), "");
        certificate.addEndorsement(tokenId, newEndorsement);
    }

    /// @notice Updates the details of an existing certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param _details Updated certificate details
    function updateCertificateDetails(address certAddress, uint256 tokenId, CertificateDetails memory _details) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.updateCertificateDetails(tokenId, _details);
    }

    /// @notice Voids a certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate to void
    function voidCertificate(address certAddress, uint256 tokenId) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.voidCert(tokenId);
    }
    
    /// @notice Sets the global transferability status for a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param transferable Whether certificates should be transferable
    function setGlobalTransferable(address certAddress, bool transferable) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalTransferable(transferable);
    }

    /// @notice Upgrades the implementation of the certificate printer
    /// @dev Only callable by upgrader role
    /// @param _newImplementation Address of the new implementation
    function upgradeBeaconImplementation(address _newImplementation) external onlyUpgradeFactory {
        IssuanceManagerStorage.updateBeaconImplementation(_newImplementation);
    }

    /// @notice Gets the current implementation address of the certificate printer
    /// @return address Current implementation address
    function getBeaconImplementation() external view returns (address) {
        return IssuanceManagerStorage.getCyberCertPrinterBeacon().implementation();
    }

    /// @notice Gets the bytecode for creating new certificate printer proxies
    /// @dev Internal function used by createCertPrinter
    /// @return bytecode The proxy contract creation bytecode
    function _getBytecode() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(IssuanceManagerStorage.getCyberCertPrinterBeacon(), ""));
    }

    /// @notice Gets the company name from the CyberCorp contract
    /// @return string The company name
    function companyName() external view returns (string memory) {
        return ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPName();
    }

    /// @notice Gets the company jurisdiction from the CyberCorp contract
    /// @return string The company jurisdiction
    function companyJurisdiction() external view returns (string memory) {
        return ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPJurisdiction();
    }

    /// @notice Gets the CyberCorp contract address
    /// @return address The CyberCorp contract address
    function CORP() external view returns (address) {
        return IssuanceManagerStorage.getCORP();
    }

    /// @notice Gets the URI builder contract address
    /// @return address The URI builder contract address
    function uriBuilder() external view returns (address) {
        return IssuanceManagerStorage.getUriBuilder();
    }

    /// @notice Gets the certificate printer beacon contract
    /// @return UpgradeableBeacon The beacon contract
    function CyberCertPrinterBeacon() external view returns (UpgradeableBeacon) {
        return IssuanceManagerStorage.getCyberCertPrinterBeacon();
    }

    /// @notice Gets a certificate printer address by index
    /// @param index Index in the printers array
    /// @return address The certificate printer contract address
    function printers(uint256 index) external view returns (address) {
        return IssuanceManagerStorage.getPrinters()[index];
    }

    /// @notice Sets the URI builder contract address
    /// @dev Only callable by owner
    /// @param _uriBuilder New URI builder contract address
    function setUriBuilder(address _uriBuilder) external onlyOwner {
        IssuanceManagerStorage.setUriBuilder(_uriBuilder);
    }

    /// @notice Sets a restriction hook for a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param _id ID of the certificate
    /// @param _hookAddress Address of the restriction hook contract
    function setRestrictionHook(address certAddress, uint256 _id, address _hookAddress) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setRestrictionHook(_id, _hookAddress);
    }

    /// @notice Sets a global restriction hook for a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param hookAddress Address of the restriction hook contract
    function setGlobalRestrictionHook(address certAddress, address hookAddress) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalRestrictionHook(hookAddress);
    }

    /// @notice Adds a default legend to a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param newLegend Text of the new legend
    function addDefaultLegend(address certAddress, string memory newLegend) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addDefaultLegend(newLegend);
    }

    /// @notice Removes a default legend from a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param index Index of the legend to remove
    function removeDefaultLegendAt(address certAddress, uint256 index) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeDefaultLegendAt(index);
    }

    /// @notice Adds a legend to a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param newLegend Text of the new legend
    function addCertLegend(address certAddress, uint256 tokenId, string memory newLegend) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addCertLegend(tokenId, newLegend);
    }

    /// @notice Removes a legend from a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param index Index of the legend to remove
    function removeCertLegendAt(address certAddress, uint256 tokenId, uint256 index) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeCertLegendAt(tokenId, index);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Only callable by addresses with the upgrader role
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyUpgradeFactory {}

    function getUpgradeFactory() public view returns (address) {
        return IssuanceManagerStorage.getUpgradeFactory();
    }

    function shouldBeFalse() public view returns (bool) {
        return IssuanceManagerStorage.shouldBeFalse();
    }
}
