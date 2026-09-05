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

import "./ICyberCorp.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./ITransferRestrictionHook.sol";
import "./ICondition.sol";
import "../CyberCorpConstants.sol";
import "../storage/LedgerEntryTokenStorage.sol";

interface IIssuanceManager {
    // Events
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
        uint256 indexed tokenId, address indexed certificate, uint256 amount, uint256 cap, CertificateDetails details
    );
    event CompanyDetailsUpdated(string companyName, string jurisdiction);
    event CertPrinterBeaconImplementationUpgraded(address implementation);
    event ScripBeaconImplementationUpgraded(address implementation);
    event ScripToCertMinimumSet(address indexed certAddress, uint256 minimum);
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

    // Issuance Manager Functions
    function initialize(address _auth, address _CORP, address _uriBuilder, address _upgradeFactory) external;

    function createCertPrinter(
        string[] memory _ledger,
        string memory _name,
        string memory _ticker,
        string memory _certificateUri,
        SecurityClass _securityType,
        SecuritySeries _securitySeries,
        address _extension,
        bytes memory _seriesData
    ) external returns (address);

    function createCertPrinterWithClassTerms(
        string[] memory _ledger,
        string memory _name,
        string memory _ticker,
        string memory _certificateUri,
        SecurityClass _securityType,
        SecuritySeries _securitySeries,
        address _extension,
        bytes calldata _extensionData
    ) external returns (address);

    function migrateClassTermsControllers(
        address[] calldata certAddresses,
        address controller,
        bytes[] calldata extensionData
    ) external;

    function amendClassTerms(address certAddress, bytes calldata extensionData) external;

    function createCert(address certAddress, address to, CertificateDetails memory _details) external returns (uint256);

    function assignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory _details,
        string memory investorName
    ) external;

    function createCertAndAssign(address certAddress, address investor, CertificateDetails memory _details)
        external
        returns (uint256 tokenId);

    function createCertAndAssignWithName(
        address certAddress,
        address investor,
        CertificateDetails memory _details,
        string calldata investorName,
        bytes calldata endorsementSignature,
        uint256 timestamp
    ) external returns (uint256 tokenId);

    function createCertSignAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory _details,
        bytes calldata endorsementSignature,
        address registry,
        bytes32 agreementId,
        string calldata investorName
    ) external returns (uint256 tokenId);

    function getUpgradeFactory() external view returns (address);

    function upgradeCertPrinterBeaconImplementation(address _newImplementation) external;

    function getCertPrinterBeaconImplementation() external view returns (address);

    function upgradeScripBeaconImplementation(address _newImplementation) external;

    function getScripBeaconImplementation() external view returns (address);

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
    ) external returns (address);

    function scripifyCert(address certAddress, uint256 id, uint256 amount, address recipient) external;

    function setScripRatio(address certAddress, uint256 numerator, uint256 denominator) external;

    function getScripRatio(address certAddress) external view returns (uint256 numerator, uint256 denominator);

    function setScripToCertMinimum(address certAddress, uint256 minimum) external;

    function getScripToCertMinimum(address certAddress) external view returns (uint256);

    function setRecertificationApproval(
        address certAddress,
        address investor,
        string calldata investorName,
        CertificateDetails calldata details,
        bytes calldata officerSignature
    ) external;

    function clearRecertificationApproval(address certAddress, address investor) external;

    function getRecertificationApproval(address certAddress, address investor)
        external
        view
        returns (
            bool approved,
            string memory investorName,
            CertificateDetails memory details,
            bytes memory officerSignature,
            uint256 endorsementTimestamp
        );

    function setScripifyWhitelistEnabled(address certAddress, bool enabled) external;

    function addScripifyWhitelistIds(address certAddress, uint256[] memory ids) external;

    function removeScripifyWhitelistIds(address certAddress, uint256[] memory ids) external;

    function getScripifyWhitelistEnabled(address certAddress) external view returns (bool);

    function isScripifyWhitelisted(address certAddress, uint256 id) external view returns (bool);

    function getCertScripifiedStatus(address certAddress, uint256 id)
        external
        view
        returns (bool isScripified, uint256 scripifiedUnits, uint256 maxUnitsRepresented);

    function getScripVaultAssets(address certAddress) external view returns (uint256 totalAssetsWad);

    function getScripPoolAmountById(address certAddress, uint256 id) external view returns (uint256);

    function getScripPoolSharesById(address certAddress, uint256 id) external view returns (uint256);

    function convertScripToCert(address certAddress, uint256 amount) external;

    function voidEmptyCerts(
        address certAddress,
        uint256[] calldata tokenIds
    ) external;

    // Unlike other CyberScrip compliance controls, this one must be called by IssuanceManager due to
    // its reliance on internal states.
    function forceScripBurn(
        address certAddress,
        address account,
        uint256 amount
    ) external;

    // Class-level LET designations (classIds start at 1; 0 = unclassified)
    event SecurityClassDefined(
        uint256 indexed classId,
        SecurityClass classType,
        string documentURI,
        address dataExtension
    );
    event SecurityClassUpdated(
        uint256 indexed classId,
        SecurityClass classType,
        string documentURI,
        address dataExtension
    );
    event PrinterClassAssigned(address indexed printer, uint256 indexed classId);

    function defineSecurityClass(
        SecurityClass _classType,
        string memory _documentURI,
        address _dataExtension,
        bytes memory _classData
    ) external returns (uint256 classId);

    function updateSecurityClass(
        uint256 _classId,
        SecurityClass _classType,
        string memory _documentURI,
        address _dataExtension,
        bytes memory _classData
    ) external;

    function setPrinterClass(address _printer, uint256 _classId) external;
    function getSecurityClass(uint256 _classId) external view returns (SecurityClassInfo memory);
    function getSecurityClassCount() external view returns (uint256);
    function getPrinterClassId(address _printer) external view returns (uint256);

    // Beacon / Config Functions
    function CORP() external view returns (address);
    function uriBuilder() external view returns (address);
    function companyName() external view returns (string memory);
    function companyJurisdiction() external view returns (string memory);
    function AUTH() external view returns (address);
    function DEPLOY_VERSION() external view returns (string memory);
    function cyberCertPrinterBeacon() external view returns (UpgradeableBeacon);
    function cyberScripBeacon() external view returns (UpgradeableBeacon);
    function printers(uint256 index) external view returns (address);
    function isPrinter(address printer) external view returns (bool);
    function setUriBuilder(address _uriBuilder) external;

    /// @notice Single-source signal for the buyer's newly minted Ledger Entry Token at secondary settlement.
    /// @dev Emitted from the linked storage lib in the IssuanceManager's context; agreementId is the
    /// settlementAgreementId (joins the DealManager's finalization event) and sellerVoided distinguishes a
    /// full sale (seller token voided) from a partial (decremented in place).
    event SecondaryTransferExecuted(
        bytes32 indexed agreementId,
        address indexed certPrinter,
        address indexed buyer,
        uint256 sellerTokenId,
        uint256 buyerTokenId,
        address seller,
        uint256 units,
        uint256 sellerUnitsAfter, // 0 when the seller token is voided (full sale)
        uint256 buyerUnitsAfter, // == units on a fresh mint; existing balance + units on a fold (no-op atm because every secondary transfer is a new mint)
        bool sellerVoided,
        bool buyerTokenIsMinted // indicates whether it's a freshly minted token or folded into an existing one
    );

    // Secondary trade entry points (cyberTRADE; implementation pending)
    function secondaryTransfer(bytes calldata dealMetadata) external;
}
