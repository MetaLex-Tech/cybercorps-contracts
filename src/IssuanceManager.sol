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
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ITransferRestrictionHook.sol";

import "./interfaces/ICertificateConverter.sol";
import "./interfaces/IIssuanceManagerFactory.sol";
import "./storage/IssuanceManagerStorage.sol";

/// @title IssuanceManager
/// @notice Manages the issuance and lifecycle of digital certificates representing securities and more
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract IssuanceManager is Initializable, BorgAuthACL, UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "4.1"; // For version-tracking on all deployment and future upgrades

    // IssuanceManager errors
    error CompanyDetailsNotSet();
    error SignatureRequired();
    error TokenProxyNotFound();
    error NotSAFEToken();
    error NotUpgradeFactory();
    error ScripifiedCertNotAllowed();
    error ConditionCheckFailed();
    error NotRefImplementation();
    error InvalidScripRatio();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    error RecertificationApprovalRequired();
    error InvalidInvestor();
    error InvalidInvestorName();
    event ScripifiedCert(
        address indexed certAddress,
        uint256 indexed id,
        address indexed scripifiedCert,
        uint256 amount,
        uint256 newUnitsRepresented,
        uint256 newCertNominalShares,
        uint256 newTotalAssetsWad,
        uint256 newTotalNominalShares
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
        CertificateDetails details
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
    event CyberScripDeployed(
        address indexed certPrinterAddress,
        address indexed cyberScripAddress,
        uint256 scripRatioNumerator,
        uint256 scripRatioDenominator,
        bool enableForceTransfer,
        bool enableForceBurn,
        bool enableFreeze
    );
    event RecertificationApprovalSet(
        address indexed certAddress,
        address indexed investor,
        string investorName
    );
    event RecertificationApprovalCleared(
        address indexed certAddress,
        address indexed investor
    );
    event ScripRecertified(
        address indexed certAddress,
        address indexed user,
        uint256 indexed certId,
        uint256 scripAmount,
        uint256 newUnitsRepresented,
        uint256 newCertNominalShares,
        uint256 newTotalAssetsWad,
        uint256 newTotalNominalShares
    );
    event ScripAddedToExistingCert(
        address indexed certAddress,
        address indexed user,
        uint256 indexed certId,
        uint256 scripsAdded,
        uint256 newUnitsRepresented,
        uint256 newUnitsScripified
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
        // Delegated to IssuanceManagerStorage to keep this contract under the EIP-170 size limit.
        IssuanceManagerStorage.executeInitialize(
            _upgradeFactory,
            _CORP,
            _uriBuilder
        );
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

    /// @dev Restricts execution to contract itself or AUTH.OWNER_ROLE callers. Body in a shared private helper
    /// (not inlined per call site) to keep this contract under the EIP-170 size limit.
    function _requireOwnerOrSelf() private view {
        if (msg.sender != address(this)) {
            AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        }
    }

    modifier onlyOwnerOrSelf() {
        _requireOwnerOrSelf();
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
        return
            IssuanceManagerStorage.executeCreateCertPrinter(
            _ledger,
            _name,
            _ticker,
            _certificateUri,
            _securityType,
            _securitySeries,
            _extension
        );
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
        return IssuanceManagerStorage.executeCreateCert(certAddress, to, _details);
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
        IssuanceManagerStorage.executeAssignCert(
            certAddress,
            from,
            tokenId,
            investor,
            _details
        );
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
        return
            createCertAndAssignWithName(
                certAddress,
                investor,
                _details,
                "",
                bytes(""),
                block.timestamp
            );
    }

    function createCertAndAssignWithName(
        address certAddress,
        address investor,
        CertificateDetails memory _details,
        string memory investorName,
        bytes memory endorsementSignature,
        uint256 timestamp
    ) public onlyOwnerOrSelf returns (uint256 tokenId) {
        return
            IssuanceManagerStorage.executeCreateCertAndAssign(
                certAddress,
                investor,
                _details,
                investorName,
                endorsementSignature,
                timestamp
            );
    }

    /// @notice Creates, assigns, signs, and endorses a new certificate in one transaction
    /// @dev Only callable by owner/self, requires company details to be set
    /// @param certAddress Address of the certificate printer contract
    /// @param investor Recipient of the certificate
    /// @param _details Certificate details
    /// @param endorsementSignature Signature hash to store in endorsement and cert signatures
    /// @param registry Optional source registry associated with endorsement
    /// @param agreementId Optional agreement id associated with endorsement
    /// @param investorName Human-readable investor name stored in endorsement
    /// @return tokenId ID of the new certificate
    function createCertSignAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory _details,
        bytes memory endorsementSignature,
        address registry,
        bytes32 agreementId,
        string memory investorName
    ) public onlyOwnerOrSelf returns (uint256 tokenId) {
        return
            IssuanceManagerStorage.executeCreateCertSignAndAssign(
                certAddress,
                investor,
                _details,
                endorsementSignature,
                registry,
                agreementId,
                investorName
            );
    }

    /// @notice Effectuates the secondary-trade ownership change at finalization (spec §7.4A / §7.5)
    /// @dev Gated on OWNER_ROLE, which the SPV's DealManager holds. dealMetadata is the abi-encoded tuple
    /// produced by DealManager.finalizeSecondaryTradeAgreement; see IssuanceManagerStorage.executeSecondaryTransfer.
    function secondaryTransfer(bytes calldata dealMetadata) external onlyOwner {
        IssuanceManagerStorage.executeSecondaryTransfer(dealMetadata);
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

    /// @notice Whether `printer` is a certificate printer this IssuanceManager created and still tracks
    /// @dev Authoritative membership check against the registry; a self-reporting printer cannot forge it
    function isPrinter(address printer) external view returns (bool) {
        return IssuanceManagerStorage.isPrinter(printer);
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
        IssuanceManagerStorage.executeSetScripRatio(
            certAddress,
            numerator,
            denominator
        );
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

    /// @notice Sets the minimum scrip amount required to convert back into certs
    /// @dev Only callable by owner; set to 0 to disable the minimum
    /// @param certAddress Address of the certificate printer contract
    /// @param minimum Minimum amount required for scrip-to-cert conversion
    function setScripToCertMinimum(
        address certAddress,
        uint256 minimum
    ) external onlyOwner {
        IssuanceManagerStorage.executeSetScripToCertMinimum(
            certAddress,
            minimum
        );
    }

    function setScripifyWhitelistEnabled(
        address certAddress,
        bool enabled
    ) external onlyOwner {
        IssuanceManagerStorage.executeSetScripifyWhitelistEnabled(
            certAddress,
            enabled
        );
    }

    function addScripifyWhitelistIds(
        address certAddress,
        uint256[] memory ids
    ) external onlyOwner {
        IssuanceManagerStorage.executeSetScripifyWhitelistIds(
            certAddress,
            ids,
            true
        );
    }

    function removeScripifyWhitelistIds(
        address certAddress,
        uint256[] memory ids
    ) external onlyOwner {
        IssuanceManagerStorage.executeSetScripifyWhitelistIds(
            certAddress,
            ids,
            false
        );
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
        return
            IssuanceManagerStorage.executeDeployCyberScrip(
                certAddress,
                address(AUTH),
                typeRestrictionHooks,
                certToScripConditions,
                scripToCertConditions,
                scripToCertMinimum,
                scripRatioNumerator,
                scripRatioDenominator,
                scripifyWhitelistIds,
                scripifyWhitelistEnabled,
                enableForceTransfer,
                enableForceBurn,
                enableFreeze
            );
    }

    function setScripRestrictionHooks(
        address certAddress,
        ITransferRestrictionHook[] memory hooks
    ) external onlyAdmin {
        IssuanceManagerStorage.executeSetScripRestrictionHooks(
            certAddress,
            hooks
        );
    }

    function disableScripForceTransfer(address certAddress) external onlyOwner {
        IssuanceManagerStorage.executeDisableScripForceTransfer(certAddress);
    }

    function disableScripForceBurn(address certAddress) external onlyOwner {
        IssuanceManagerStorage.executeDisableScripForceBurn(certAddress);
    }

    function disableScripFreeze(address certAddress) external onlyOwner {
        IssuanceManagerStorage.executeDisableScripFreeze(certAddress);
    }

    function setScripFrozen(
        address certAddress,
        address account,
        bool isFrozen
    ) external onlyAdmin {
        IssuanceManagerStorage.executeSetScripFrozen(
            certAddress,
            account,
            isFrozen
        );
    }

    function forceScripTransfer(
        address certAddress,
        address from,
        address to,
        uint256 amount
    ) external onlyAdmin {
        IssuanceManagerStorage.executeForceScripTransfer(
            certAddress,
            from,
            to,
            amount
        );
    }

    function forceScripBurn(
        address certAddress,
        address account,
        uint256 amount
    ) external onlyAdmin {
        IssuanceManagerStorage.executeForceScripBurn(
            certAddress,
            account,
            amount
        );
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

    function setRecertificationApproval(
        address certAddress,
        address investor,
        string calldata investorName,
        CertificateDetails calldata details,
        bytes calldata officerSignature
    ) external onlyAdmin {
        IssuanceManagerStorage.executeSetRecertificationApproval(
            certAddress,
            investor,
            investorName,
            details,
            officerSignature
        );
    }

    function clearRecertificationApproval(
        address certAddress,
        address investor
    ) external onlyAdmin {
        IssuanceManagerStorage.executeClearRecertificationApproval(
            certAddress,
            investor
        );
    }

    function getRecertificationApproval(
        address certAddress,
        address investor
    )
        external
        view
        returns (
            bool approved,
            string memory investorName,
            CertificateDetails memory details,
            bytes memory officerSignature,
            uint256 endorsementTimestamp
        )
    {
        return
            IssuanceManagerStorage.getRecertificationApprovalData(
                certAddress,
                investor
            );
    }

    function getScripifyWhitelistEnabled(
        address certAddress
    ) external view returns (bool) {
        return IssuanceManagerStorage.getScripifyWhitelistEnabled(certAddress);
    }

    function getCertScripifiedStatus(
        address certAddress,
        uint256 id
    )
        external
        view
        returns (bool isScripified, uint256 scripifiedUnits, uint256 maxUnitsRepresented)
    {
        return IssuanceManagerStorage.getCertScripifiedStatus(certAddress, id);
    }

    /// @notice `totalTrackedScrip` is CyberScrip `totalSupply`. Second value is vault price per
    ///         nominal share: `totalAssetsWad * 1e27 / totalNominalShares` (ray), or 0 if empty.
    function getScripPoolTotals(
        address certAddress
    )
        external
        view
        returns (uint256 totalTrackedScrip, uint256 pricePerShareRay)
    {
        return IssuanceManagerStorage.getScripPoolTotals(certAddress);
    }

    /// @notice Underlying units (wad) and total nominal shares in the scripified-units vault.
    function getCertScripUnitVault(address certAddress)
        external
        view
        returns (uint256 totalAssetsWad, uint256 totalNominalShares)
    {
        return IssuanceManagerStorage.getCertScripUnitVault(certAddress);
    }

    function getScripPoolAmountById(
        address certAddress,
        uint256 id
    ) external view returns (uint256) {
        return IssuanceManagerStorage.getScripPoolAmountById(certAddress, id);
    }

    function getScripPoolSharesById(
        address certAddress,
        uint256 id
    ) external view returns (uint256) {
        return IssuanceManagerStorage.getScripPoolSharesById(certAddress, id);
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

}
