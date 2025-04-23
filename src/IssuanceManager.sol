/*    .o.                                                                                         
     .888.                                                                                        
    .8"888.                                                                                       
   .8' `888.                                                                                      
  .88ooo8888.                                                                                     
 .8'     `888.                                                                                    
o88o     o8888o                                                                                   
                                                                                                  
                                                                                                  
                                                                                                  
ooo        ooooo               .             oooo                                                 
`88.       .888'             .o8             `888                                                 
 888b     d'888   .ooooo.  .o888oo  .oooo.    888   .ooooo.  oooo    ooo                          
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888  d88' `88b  `88b..8P'                           
 8  `888'   888  888ooo888   888    .oP"888   888  888ooo888    Y888'                             
 8    Y     888  888    .o   888 . d8(  888   888  888    .o  .o8"'88b                            
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888o `Y8bod8P' o88'   888o                          
                                                                                                  
                                                                                                  
                                                                                                  
  .oooooo.                .o8                            .oooooo.                                 
 d8P'  `Y8b              "888                           d8P'  `Y8b                                
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.  
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b 
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
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

    function updateCertificateDetails(address certAddress, uint256 tokenId, CertificateDetails memory _details) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.updateCertificateDetails(tokenId, _details);
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

    //set uirBuilder
    function setUriBuilder(address _uriBuilder) external onlyOwner {
        IssuanceManagerStorage.setUriBuilder(_uriBuilder);
    }

    // Functions to manage CyberCertPrinter settings
    function setRestrictionHook(address certAddress, uint256 _id, address _hookAddress) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setRestrictionHook(_id, _hookAddress);
    }

    function setGlobalRestrictionHook(address certAddress, address hookAddress) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalRestrictionHook(hookAddress);
    }

    function addDefaultLegend(address certAddress, string memory newLegend) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addDefaultLegend(newLegend);
    }

    function removeDefaultLegendAt(address certAddress, uint256 index) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeDefaultLegendAt(index);
    }

    function addCertLegend(address certAddress, uint256 tokenId, string memory newLegend) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addCertLegend(tokenId, newLegend);
    }

    function removeCertLegendAt(address certAddress, uint256 tokenId, uint256 index) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeCertLegendAt(tokenId, index);
    }

    /// @notice Function that authorizes an upgrade to a new implementation
    /// @dev Only callable by owner due to onlyOwner modifier inherited from BorgAuthACL
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
