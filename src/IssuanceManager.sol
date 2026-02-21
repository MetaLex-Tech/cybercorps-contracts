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

import "./libs/auth.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/utils/Create2.sol";
import "openzeppelin-contracts/utils/Address.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/ICyberScrip.sol";

import "./interfaces/ICertificateConverter.sol";
import "./interfaces/IIssuanceManagerFactory.sol";
import "./storage/IssuanceManagerStorage.sol";

/// @title IssuanceManager
/// @notice Manages the issuance and lifecycle of digital certificates representing securities and more
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract IssuanceManager is Initializable, BorgAuthACL, UUPSUpgradeable {
    using IssuanceManagerStorage for IssuanceManagerStorage.IssuanceManagerData;

    string public constant DEPLOY_VERSION = "3"; // For version-tracking on all deployment and future upgrades

    // IssuanceManager errors
    error CompanyDetailsNotSet();
    error SignatureURIRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    error NotUpgradeFactory();
    error ScripifiedCertNotAllowed();
    error ConditionCheckFailed();
    error NotRefImplementation();
    error InvalidScripRatio();
    error ScripRatioRemainder();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    event ScripifiedCert(
        address indexed certAddress,
        uint256 indexed id,
        address indexed scripifiedCert,
        uint256 amount
    );

    event CertPrinterCreated(
        address indexed certificate,
        address indexed corp,
        string[] ledger,
        string name,
        string ticker,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string certificateUri
    );
    event CertificateCreated(
        uint256 indexed tokenId,
        address indexed certificate,
        uint256 amount,
        uint256 cap,
        CertificateDetails details,
        string tokenURI
    );
    event CompanyDetailsUpdated(string companyName, string jurisdiction);
    event CertPrinterBeaconImplementationUpgraded(address implementation);
    event ScripBeaconImplementationUpgraded(address implementation);
    event ScripToCertMinimumSet(address indexed certAddress, uint256 minimum);
    event ScripifyWhitelistEnabledSet(address indexed certAddress, bool enabled);
    event ScripifyWhitelistUpdated(
        address indexed certAddress,
        uint256 indexed id,
        bool isWhitelisted
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the IssuanceManager contract
    /// @param _auth Address of the BorgAuth contract
    /// @param _CORP Address of the CyberCorp contract
    /// @param _uriBuilder Address of the json URI builder contract for certificate metadata
    /// @param _upgradeFactory Address of the factory (for upgrading purposes)
    function initialize(
        address _auth,
        address _CORP,
        address _uriBuilder,
        address _upgradeFactory
    ) external initializer {
        __BorgAuthACL_init(_auth);

        // Create beacons for CyberCertPrinter and CyberScrip
        // Unlike IssuanceManager which is individually upgradeable, CyberCertPrinter and CyberScrip deployments are
        // beacon proxies because they are managed by the same company owner and are expected to
        // share the same implementation or upgraded to a new version all at the same time.
        // Maintenance-wise, since IssuanceManager itself is upgradeable, we don't need to worry about beacon ownership transfers

        address cyberCertPrinterRefImpl = IIssuanceManagerFactory(
            _upgradeFactory
        ).getCyberCertPrinterRefImplementation();
        UpgradeableBeacon beaconCertPrinter = new UpgradeableBeacon(
            cyberCertPrinterRefImpl,
            address(this)
        );
        emit CertPrinterBeaconImplementationUpgraded(cyberCertPrinterRefImpl);

        address cyberScripRefImpl = IIssuanceManagerFactory(_upgradeFactory)
            .getCyberScripRefImplementation();
        UpgradeableBeacon beaconScrip = new UpgradeableBeacon(
            cyberScripRefImpl,
            address(this)
        );
        emit ScripBeaconImplementationUpgraded(cyberScripRefImpl);

        IssuanceManagerStorage.setCORP(_CORP);
        IssuanceManagerStorage.setUriBuilder(_uriBuilder);
        IssuanceManagerStorage.setCyberCertPrinterBeacon(beaconCertPrinter);
        IssuanceManagerStorage.setUpgradeFactory(_upgradeFactory);
        IssuanceManagerStorage.setCyberScripBeacon(beaconScrip);
    }

    modifier onlyUpgradeFactory() {
        // Allow explicitly configured upgrade factory OR contract owner
        if (msg.sender != IssuanceManagerStorage.getUpgradeFactory()) {
            // Check owner via BorgAuth
            try AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender) {
                _;
                return;
            } catch {
                revert NotUpgradeFactory();
            }
        }
        _;
    }

    /// @dev Restricts execution to contract itself or AUTH.OWNER_ROLE callers
    modifier onlyOwnerOrSelf() {
        if (msg.sender != address(this)) {
            AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        }
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
    function createCertPrinter(
        string[] memory _ledger,
        string memory _name,
        string memory _ticker,
        string memory _certificateUri,
        SecurityClass _securityType,
        SecuritySeries _securitySeries,
        address _extension
    ) public onlyOwner returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                IssuanceManagerStorage.getPrinters().length,
                address(this)
            )
        );
        address newCert = Create2.deploy(0, salt, _getBytecodeCertPrinter());
        IssuanceManagerStorage.addPrinter(newCert);
        ICyberCertPrinter(newCert).initialize(
            _ledger,
            _name,
            _ticker,
            _certificateUri,
            address(this),
            _securityType,
            _securitySeries,
            _extension
        );
        emit CertPrinterCreated(
            newCert,
            IssuanceManagerStorage.getCORP(),
            _ledger,
            _name,
            _ticker,
            _securityType,
            _securitySeries,
            _certificateUri
        );
        return newCert;
    }

    /// @notice Creates a new certificate
    /// @dev Only callable by owner
    /// @param certAddress Address of the certificate printer contract
    /// @param to Recipient of the certificate
    /// @param _details Certificate details
    /// @return uint256 ID of the new certificate
    function createCert(
        address certAddress,
        address to,
        CertificateDetails memory _details
    ) public onlyOwner returns (uint256) {
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        uint256 tokenId = cert.totalSupply();
        uint256 id = cert.safeMint(tokenId, to, _details);
        string memory tokenURI = cert.tokenURI(tokenId);
        emit CertificateCreated(
            tokenId,
            certAddress,
            _details.investmentAmountUSD,
            _details.issuerUSDValuationAtTimeOfInvestment,
            _details,
            tokenURI
        );
        return id;
    }

    /// @notice Assigns an existing certificate to a new investor
    /// @dev Only callable by owner
    /// @param certAddress Address of the certificate printer contract
    /// @param from Current owner of the certificate
    /// @param tokenId ID of the certificate
    /// @param investor New owner of the certificate
    /// @param _details Updated certificate details
    function assignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory _details
    ) public onlyOwner {
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
    ) public onlyOwnerOrSelf returns (uint256 tokenId) {
        if (
            bytes(ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPName())
                .length == 0
        ) revert CompanyDetailsNotSet();
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        tokenId = cert.totalSupply();

        cert.safeMintAndAssign(investor, tokenId, _details);
        string memory tokenURI = cert.tokenURI(tokenId);
        emit CertificateCreated(
            tokenId,
            certAddress,
            _details.investmentAmountUSD,
            _details.issuerUSDValuationAtTimeOfInvestment,
            _details,
            tokenURI
        );
        return tokenId;
    }

    /// @notice Adds an issuer's signature to a certificate
    /// @dev Only callable by admin, requires valid signature URI
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param signatureURI URI containing the signature data
    function signCertificate(
        address certAddress,
        uint256 tokenId,
        string calldata signatureURI
    ) external onlyAdmin {
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
    function endorseCertificate(
        address certAddress,
        uint256 tokenId,
        address endorser,
        bytes memory signature,
        bytes32 agreementId
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        Endorsement memory newEndorsement = Endorsement(
            endorser,
            block.timestamp,
            signature,
            address(0),
            agreementId,
            address(0),
            ""
        );
        certificate.addEndorsement(tokenId, newEndorsement);
    }

   /* /// @notice Updates the details of an existing certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param _details Updated certificate details
    function updateCertificateDetails(
        address certAddress,
        uint256 tokenId,
        CertificateDetails memory _details
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.updateCertificateDetails(tokenId, _details);
    }*/

    /// @notice Voids a certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate to void
    function voidCertificate(
        address certAddress,
        uint256 tokenId
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.voidCert(tokenId);
    }

    /// @notice Sets the global transferability status for a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param transferable Whether certificates should be transferable
    function setGlobalTransferable(
        address certAddress,
        bool transferable
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalTransferable(transferable);
    }

    /// @notice Upgrades the implementation of the certificate printer
    /// @dev Only callable by company owner, only upgradeable to the current reference implementation
    /// @param _newImplementation Address of the new implementation
    function upgradeCertPrinterBeaconImplementation(
        address _newImplementation
    ) external onlyOwner {
        if (
            IIssuanceManagerFactory(IssuanceManagerStorage.getUpgradeFactory())
                .getCyberCertPrinterRefImplementation() != _newImplementation
        ) {
            revert NotRefImplementation();
        }
        IssuanceManagerStorage.upgradeCertPrinterBeaconImplementation(
            _newImplementation
        );
        emit CertPrinterBeaconImplementationUpgraded(_newImplementation);
    }

    /// @notice Gets the current implementation address of the certificate printer
    /// @return address Current implementation address
    function getCertPrinterBeaconImplementation()
        external
        view
        returns (address)
    {
        return
            IssuanceManagerStorage.getCyberCertPrinterBeacon().implementation();
    }

    /// @notice Upgrades the implementation of the scrip
    /// @dev Only callable by company owner, only upgradeable to the current reference implementation
    /// @param _newImplementation Address of the new implementation
    function upgradeScripBeaconImplementation(
        address _newImplementation
    ) external onlyOwner {
        if (
            IIssuanceManagerFactory(IssuanceManagerStorage.getUpgradeFactory())
                .getCyberScripRefImplementation() != _newImplementation
        ) {
            revert NotRefImplementation();
        }
        IssuanceManagerStorage.updateScripBeaconImplementation(
            _newImplementation
        );
        emit ScripBeaconImplementationUpgraded(_newImplementation);
    }

    function getScripBeaconImplementation() external view returns (address) {
        return IssuanceManagerStorage.getCyberScripBeacon().implementation();
    }

    /// @notice Gets the bytecode for creating new certificate printer proxies
    /// @dev Internal function used by createCertPrinter
    /// @return bytecode The proxy contract creation bytecode
    function _getBytecodeCertPrinter()
        private
        view
        returns (bytes memory bytecode)
    {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            sourceCodeBytes,
            abi.encode(IssuanceManagerStorage.getCyberCertPrinterBeacon(), "")
        );
    }

    function _getBytecodeScrip() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            sourceCodeBytes,
            abi.encode(IssuanceManagerStorage.getCyberScripBeacon(), "")
        );
    }

    /// @notice Gets the company name from the CyberCorp contract
    /// @return string The company name
    function companyName() external view returns (string memory) {
        return ICyberCorp(IssuanceManagerStorage.getCORP()).cyberCORPName();
    }

    /// @notice Gets the company jurisdiction from the CyberCorp contract
    /// @return string The company jurisdiction
    function companyJurisdiction() external view returns (string memory) {
        return
            ICyberCorp(IssuanceManagerStorage.getCORP())
                .cyberCORPJurisdiction();
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
    function cyberCertPrinterBeacon()
        external
        view
        returns (UpgradeableBeacon)
    {
        return IssuanceManagerStorage.getCyberCertPrinterBeacon();
    }

    /// @notice Gets the scrip beacon contract
    /// @return UpgradeableBeacon The beacon contract
    function cyberScripBeacon() external view returns (UpgradeableBeacon) {
        return IssuanceManagerStorage.getCyberScripBeacon();
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

    function setScripRatio(
        address certAddress,
        uint256 numerator,
        uint256 denominator
    ) external onlyOwner {
        if (numerator == 0 || denominator == 0) revert InvalidScripRatio();
        IssuanceManagerStorage.setScripRatio(certAddress, numerator, denominator);
    }

    function getScripRatio(
        address certAddress
    ) external view returns (uint256 numerator, uint256 denominator) {
        IssuanceManagerStorage.ScripRatio storage ratio = IssuanceManagerStorage
            .getScripRatio(certAddress);
        numerator = ratio.numerator;
        denominator = ratio.denominator;
        if (numerator == 0 || denominator == 0) {
            return (1, 1);
        }
    }

    /// @notice Sets a restriction hook for a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param _id ID of the certificate
    /// @param _hookAddress Address of the restriction hook contract
    function setRestrictionHook(
        address certAddress,
        uint256 _id,
        address _hookAddress
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setRestrictionHook(_id, _hookAddress);
    }

    /// @notice Sets a global restriction hook for a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param hookAddress Address of the restriction hook contract
    function setGlobalRestrictionHook(
        address certAddress,
        address hookAddress
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setGlobalRestrictionHook(hookAddress);
    }

    function setTokenTransferable(
        address certAddress,
        uint256 tokenId,
        bool value
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.setTokenTransferable(tokenId, value);
    }

    /// @notice Sets the minimum scrip amount required to convert back into certs
    /// @dev Only callable by owner; set to 0 to disable the minimum
    /// @param certAddress Address of the certificate printer contract
    /// @param minimum Minimum amount required for scrip-to-cert conversion
    function setScripToCertMinimum(
        address certAddress,
        uint256 minimum
    ) external onlyOwner {
        IssuanceManagerStorage.setScripToCertMinimum(certAddress, minimum);
        emit ScripToCertMinimumSet(certAddress, minimum);
    }

    function setScripifyWhitelistEnabled(
        address certAddress,
        bool enabled
    ) external onlyOwner {
        IssuanceManagerStorage.setScripifyWhitelistEnabled(certAddress, enabled);
        emit ScripifyWhitelistEnabledSet(certAddress, enabled);
    }

    function addScripifyWhitelistIds(
        address certAddress,
        uint256[] memory ids
    ) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            IssuanceManagerStorage.setScripifyWhitelisted(
                certAddress,
                ids[i],
                true
            );
            emit ScripifyWhitelistUpdated(certAddress, ids[i], true);
        }
    }

    function removeScripifyWhitelistIds(
        address certAddress,
        uint256[] memory ids
    ) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            IssuanceManagerStorage.setScripifyWhitelisted(
                certAddress,
                ids[i],
                false
            );
            emit ScripifyWhitelistUpdated(certAddress, ids[i], false);
        }
    }

    /// @notice Adds a default legend to a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param newLegend Text of the new legend
    function addDefaultLegend(
        address certAddress,
        string memory newLegend
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addDefaultLegend(newLegend);
    }

    /// @notice Removes a default legend from a certificate contract
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param index Index of the legend to remove
    function removeDefaultLegendAt(
        address certAddress,
        uint256 index
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeDefaultLegendAt(index);
    }

    /// @notice Adds a legend to a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param newLegend Text of the new legend
    function addCertLegend(
        address certAddress,
        uint256 tokenId,
        string memory newLegend
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.addCertLegend(tokenId, newLegend);
    }

    /// @notice Removes a legend from a specific certificate
    /// @dev Only callable by admin
    /// @param certAddress Address of the certificate printer contract
    /// @param tokenId ID of the certificate
    /// @param index Index of the legend to remove
    function removeCertLegendAt(
        address certAddress,
        uint256 tokenId,
        uint256 index
    ) external onlyAdmin {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        certificate.removeCertLegendAt(tokenId, index);
    }

    //deploy matching erc20 contract for a cert
    function deployCyberScrip(
        address certAddress,
        ITransferRestrictionHook[] memory typeRestrictionHooks,
        ICondition[] memory certToScripConditions,
        ICondition[] memory scripToCertConditions,
        uint256 scripToCertMinimum,
        uint256 scripRatioNumerator,
        uint256 scripRatioDenominator,
        uint256[] memory scripifyWhitelistIds,
        bool scripifyWhitelistEnabled,
        bool enableForceTransfer,
        bool enableForceBurn,
        bool enableFreeze
    ) onlyOwner external returns (address) {
        if (scripRatioNumerator == 0 || scripRatioDenominator == 0) {
            revert InvalidScripRatio();
        }
        bytes32 salt = keccak256(abi.encodePacked(certAddress, address(this)));
        address newScrip = Create2.deploy(0, salt, _getBytecodeScrip());
        ICyberScrip(newScrip).initialize(
            address(AUTH),
            certAddress,
            address(this),
            string(
                abi.encodePacked("scrip", ICyberCertPrinter(certAddress).name())
            ),
            string(
                abi.encodePacked(
                    "scrip",
                    ICyberCertPrinter(certAddress).symbol()
                )
            ),
            typeRestrictionHooks,
            enableForceTransfer,
            enableForceBurn,
            enableFreeze
        );
        IssuanceManagerStorage.setScripifiedCert(certAddress, newScrip);
        IssuanceManagerStorage.setCertToScripConditions(
            certAddress,
            certToScripConditions
        );
        IssuanceManagerStorage.setScripToCertConditions(
            certAddress,
            scripToCertConditions
        );
        IssuanceManagerStorage.setScripToCertMinimum(
            certAddress,
            scripToCertMinimum
        );
        IssuanceManagerStorage.setScripRatio(
            certAddress,
            scripRatioNumerator,
            scripRatioDenominator
        );
        emit ScripToCertMinimumSet(certAddress, scripToCertMinimum);
        IssuanceManagerStorage.setScripifyWhitelistEnabled(
            certAddress,
            scripifyWhitelistEnabled
        );
        emit ScripifyWhitelistEnabledSet(certAddress, scripifyWhitelistEnabled);
        for (uint256 i = 0; i < scripifyWhitelistIds.length; i++) {
            IssuanceManagerStorage.setScripifyWhitelisted(
                certAddress,
                scripifyWhitelistIds[i],
                true
            );
            emit ScripifyWhitelistUpdated(
                certAddress,
                scripifyWhitelistIds[i],
                true
            );
        }
        return newScrip;
    }

    function setScripRestrictionHooks(
        address certAddress,
        ITransferRestrictionHook[] memory hooks
    ) external onlyAdmin {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).setRestrictionHook(hooks);
    }

    function disableScripForceTransfer(address certAddress) external onlyOwner {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).disableForceTransfer();
    }

    function disableScripForceBurn(address certAddress) external onlyOwner {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).disableForceBurn();
    }

    function disableScripFreeze(address certAddress) external onlyOwner {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).disableFreeze();
    }

    function setScripFrozen(
        address certAddress,
        address account,
        bool isFrozen
    ) external onlyAdmin {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).setFrozen(account, isFrozen);
    }

    function forceScripTransfer(
        address certAddress,
        address from,
        address to,
        uint256 amount
    ) external onlyAdmin {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).forceTransfer(from, to, amount);
    }

    function forceScripBurn(
        address certAddress,
        address account,
        uint256 amount
    ) external onlyAdmin {
        address scripifiedCert = _getScripForCert(certAddress);
        ICyberScrip(scripifiedCert).forceBurn(account, amount);
    }

    /// @notice Convert a certificate into scrip tokens, partially or fully
    /// @param certAddress Address of the certificate printer contract
    /// @param id ID of the certificate to convert
    /// @param amount Number of units to convert into scrip
    function scripifyCert(
        address certAddress,
        uint256 id,
        uint256 amount,
        address target
    ) external {
        IssuanceManagerStorage.executeScripifyCert(
            certAddress,
            id,
            amount,
            target,
            msg.sender
        );
    }

    function getUpgradeFactory() public view returns (address) {
        return IssuanceManagerStorage.getUpgradeFactory();
    }

    function getScripToCertMinimum(address certAddress) external view returns (uint256) {
        return IssuanceManagerStorage.getScripToCertMinimum(certAddress);
    }

    function getScripifyWhitelistEnabled(
        address certAddress
    ) external view returns (bool) {
        return IssuanceManagerStorage.getScripifyWhitelistEnabled(certAddress);
    }

    function isScripifyWhitelisted(
        address certAddress,
        uint256 id
    ) external view returns (bool) {
        return IssuanceManagerStorage.isScripifyWhitelisted(certAddress, id);
    }

    function convertScripToCert(address certAddress, uint256 amount) external {
        IssuanceManagerStorage.executeConvertScripToCert(
            certAddress,
            amount,
            msg.sender,
            this.convertScripToCert.selector
        );
    }

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        if (
            IIssuanceManagerFactory(IssuanceManagerStorage.getUpgradeFactory())
                .getRefImplementation() != newImplementation
        ) {
            revert NotRefImplementation();
        }
    }

    function _getScripForCert(address certAddress) private view returns (address) {
        address scripifiedCert = IssuanceManagerStorage.getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();
        return scripifiedCert;
    }

}
