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

import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/utils/Create2.sol";
import "../interfaces/ICondition.sol";
import "../interfaces/ILedgerEntryToken.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberScrip.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/IIssuanceManagerFactory.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import {ExemptionPathway, HostingMode} from "../interfaces/ISecondaryTradeStorage.sol";
import "./LedgerEntryTokenStorage.sol";

library IssuanceManagerStorage {
    error ConditionCheckFailed();
    error ScripifiedCertNotAllowed();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    error ScripifyOverMax();
    error RecertificationApprovalRequired();
    error CompanyDetailsNotSet();
    error InvalidScripRatio();
    error ScripOutstanding();
    error SignatureRequired();
    error InvalidInvestor();
    error InvalidInvestorName();
    error InvalidAmount();
    error CertificateVoided();
    error NotLegalOwner();
    error AmountExceedsAvailableUnits();
    error ZeroSharesMinted();
    error EmptyVault();
    error VaultRedemptionExceedsClaim();
    error VaultWithdrawalExceedsAssets();
    error ClassDoesNotExist();
    error SecurityClassAlreadyDefined();
    error NotAPrinter();
    error CertNotEmpty();

    /// @dev Ray precision for vault price-per-share (assets per 1 nominal share, 1e27 = 1.0).
    uint256 internal constant VAULT_RAY = 1e27;

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

    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.issuancemanager.storage.v1");

    // Main storage layout struct
    struct IssuanceManagerData {
        UpgradeableBeacon cyberCertPrinterBeacon;
        address CORP;
        address uriBuilder;
        address upgradeFactory;
        address[] printers;
        UpgradeableBeacon cyberScripBeacon;
        mapping(address => address) scripifiedCert;
        mapping(address => ICondition[]) certToScripConditions;
        mapping(address => ICondition[]) scripToCertConditions;
        mapping(address => uint256) scripToCertMinimums;
        mapping(address => ScripRatio) scripRatios;
        mapping(address => bool) scripifyWhitelistEnabled;
        mapping(address => mapping(uint256 => bool)) scripifyWhitelist;
        mapping(address => mapping(uint256 => CertScripState)) certScripStates;
        mapping(address => CertScripUnitPool) certScripUnitPools;
        mapping(address => mapping(address => RecertificationApproval))
            recertificationApprovals;
        // Class-level LET designations (appended for upgrade safety). classIds start at 1; 0 = unclassified.
        // Each printer is the series scope and may be assigned to one class; several printers can share one.
        mapping(uint256 => SecurityClassInfo) securityClasses;
        uint256 securityClassCount;
        mapping(address => uint256) printerClassIds;
        // Canonical class for each SecurityClass enum value. A value of 0 means it has not been defined.
        mapping(SecurityClass => uint256) classIdByType;
    }

    struct ScripRatio {
        uint256 numerator;
        uint256 denominator;
    }

    struct RecertSelection {
        bool foundActive;
        uint256 activeTokenId;
    }

    /// @notice Per-certificate vault position: nominal shares in the scripified-units vault.
    ///         Claim on underlying (wad) = vaultNominalShares * totalAssetsWad / totalNominalShares.
    /// @dev Three slots preserve layout vs legacy (amount, reductionDebt, maxUnitsRepresented);
    ///      `vaultEpoch` is appended, so existing positions read epoch 0 and match a fresh pool.
    struct CertScripState {
        uint256 vaultNominalShares;
        /// @dev Legacy `reductionDebt` slot — unused after ERC4626 vault migration.
        uint256 deprecatedMasterChefDebtSlot;
        uint256 maxUnitsRepresented;
        /// @dev Vault epoch `vaultNominalShares` was recorded in; a stale epoch means zero shares.
        uint256 vaultEpoch;
    }

    /// @notice ERC4626-style pool for scripified certificate units (underlying in 18-dec wad).
    struct CertScripUnitPool {
        uint256 totalAssetsWad;
        uint256 totalNominalShares;
        /// @dev Bumped whenever the pool empties, invalidating every outstanding position at once.
        uint256 vaultEpoch;
    }

    struct RecertificationApproval {
        bool approved;
        string investorName;
        CertificateDetails details;
        /// @dev CyberCorp officer signature bytes, applied as issuer signature on the new certificate at conversion.
        bytes officerSignature;
        /// @dev Timestamp recorded when approval is set (endorsement / signature context).
        uint256 endorsementTimestamp;
    }

    // Returns the storage layout
    function issuanceManagerStorage() internal pure returns (IssuanceManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getCORP() internal view returns (address) {
        return issuanceManagerStorage().CORP;
    }

    function getUriBuilder() internal view returns (address) {
        return issuanceManagerStorage().uriBuilder;
    }

    function getCyberCertPrinterBeacon() internal view returns (UpgradeableBeacon) {
        return issuanceManagerStorage().cyberCertPrinterBeacon;
    }

    function getPrinters() internal view returns (address[] storage) {
        return issuanceManagerStorage().printers;
    }

    /// @dev Linear membership scan over the printer registry. The list is admin-curated and small, and it is
    /// the only authoritative source of printers created by this IssuanceManager (mirrors removePrinter).
    function isPrinter(address printer) internal view returns (bool) {
        address[] storage printers = issuanceManagerStorage().printers;
        for (uint256 i = 0; i < printers.length; i++) {
            if (printers[i] == printer) return true;
        }
        return false;
    }

    // Setters
    function setCORP(address _corp) internal {
        issuanceManagerStorage().CORP = _corp;
    }

    function setUriBuilder(address _uriBuilder) internal {
        issuanceManagerStorage().uriBuilder = _uriBuilder;
    }

    function setCyberScripBeacon(UpgradeableBeacon _beacon) internal {
        issuanceManagerStorage().cyberScripBeacon = _beacon;
    }

    function getCyberScripBeacon() internal view returns (UpgradeableBeacon) {
        return issuanceManagerStorage().cyberScripBeacon;
    }

    function setCyberCertPrinterBeacon(UpgradeableBeacon _beacon) internal {
        issuanceManagerStorage().cyberCertPrinterBeacon = _beacon;
    }

    function addPrinter(address _printer) internal {
        require(_printer != address(0), "Zero address not allowed");
        IssuanceManagerData storage s = issuanceManagerStorage();
        s.printers.push(_printer);
    }

    function setUpgradeFactory(address _upgradeFactory) internal {
        issuanceManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() internal view returns (address) {
        return issuanceManagerStorage().upgradeFactory;
    }

    function removePrinter(address _printer) internal {
        IssuanceManagerData storage s = issuanceManagerStorage();
        
        // Find and remove from array
        uint256 length = s.printers.length;
        for (uint256 i = 0; i < length; i++) {
            if (s.printers[i] == _printer) {
                // Move the last element to the position being deleted (unless we're deleting the last element)
                if (i != length - 1) {
                    s.printers[i] = s.printers[length - 1];
                }
                s.printers.pop();
                break;
            }
        }
    }

    // Class-level LET designations. Mutators are external (delegatecalled) to keep IssuanceManager itself
    // under the EIP-170 size limit; wrappers there enforce access control before delegating here.

    /// @notice Registers a new class; classIds are sequential starting at 1 (0 = unclassified).
    function executeDefineSecurityClass(
        SecurityClass classType,
        string memory documentURI,
        address dataExtension,
        bytes memory classData
    ) external returns (uint256 classId) {
        IssuanceManagerData storage s = issuanceManagerStorage();
        if (s.classIdByType[classType] != 0) revert SecurityClassAlreadyDefined();
        classId = ++s.securityClassCount;
        s.securityClasses[classId] = SecurityClassInfo(classType, documentURI, dataExtension, classData);
        s.classIdByType[classType] = classId;
        emit SecurityClassDefined(classId, classType, documentURI, dataExtension);
    }

    function executeUpdateSecurityClass(
        uint256 classId,
        SecurityClass classType,
        string memory documentURI,
        address dataExtension,
        bytes memory classData
    ) external {
        IssuanceManagerData storage s = issuanceManagerStorage();
        if (classId == 0 || classId > s.securityClassCount) revert ClassDoesNotExist();
        // Re-index classIdByType when the type changes, otherwise the reverse index keeps pointing at the
        // old type and the new type reads as undefined, letting a second class be created for it.
        SecurityClass oldType = s.securityClasses[classId].classType;
        if (classType != oldType) {
            if (s.classIdByType[classType] != 0) revert SecurityClassAlreadyDefined();
            delete s.classIdByType[oldType];
            s.classIdByType[classType] = classId;
        }
        s.securityClasses[classId] = SecurityClassInfo(classType, documentURI, dataExtension, classData);
        emit SecurityClassUpdated(classId, classType, documentURI, dataExtension);
    }

    /// @notice Assigns a printer (the series scope) to a class; classId 0 clears the assignment.
    /// Also the backfill path for printers created before the class registry existed.
    function executeSetPrinterClass(address printer, uint256 classId) external {
        IssuanceManagerData storage s = issuanceManagerStorage();
        if (!isPrinter(printer)) revert NotAPrinter();
        if (classId > s.securityClassCount) revert ClassDoesNotExist();
        s.printerClassIds[printer] = classId;
        emit PrinterClassAssigned(printer, classId);
    }

    function getSecurityClass(uint256 classId) internal view returns (SecurityClassInfo storage) {
        return issuanceManagerStorage().securityClasses[classId];
    }

    function getSecurityClassCount() internal view returns (uint256) {
        return issuanceManagerStorage().securityClassCount;
    }

    function getPrinterClassId(address printer) internal view returns (uint256) {
        return issuanceManagerStorage().printerClassIds[printer];
    }

    /// @dev Creates the empty canonical class for `classType` when one has not been explicitly
    /// defined, then returns its ID. Class metadata can be populated later with updateSecurityClass.
    function _getOrCreateClassId(SecurityClass classType) private returns (uint256 classId) {
        IssuanceManagerData storage s = issuanceManagerStorage();
        classId = s.classIdByType[classType];
        if (classId != 0) return classId;

        classId = ++s.securityClassCount;
        s.securityClasses[classId] = SecurityClassInfo(classType, "", address(0), bytes(""));
        s.classIdByType[classType] = classId;
        emit SecurityClassDefined(classId, classType, "", address(0));
    }

    // Beacon upgrade function
    function upgradeCertPrinterBeaconImplementation(address _newImplementation) internal {
        issuanceManagerStorage().cyberCertPrinterBeacon.upgradeTo(_newImplementation);
    }

    function updateScripBeaconImplementation(address _newImplementation) internal {
        issuanceManagerStorage().cyberScripBeacon.upgradeTo(_newImplementation);
    }

    function getScripifiedCert(address certAddress) internal view returns (address) {
        return issuanceManagerStorage().scripifiedCert[certAddress];
    }

    function setScripifiedCert(address certAddress, address scripifiedCert) internal {
        issuanceManagerStorage().scripifiedCert[certAddress] = scripifiedCert;
    }

    function getCertToScripConditions(address certAddress) internal view returns (ICondition[] storage) {
        return issuanceManagerStorage().certToScripConditions[certAddress];
    }

    function getScripToCertConditions(address certAddress) internal view returns (ICondition[] storage) {
        return issuanceManagerStorage().scripToCertConditions[certAddress];
    }

    function setScripToCertConditions(address certAddress, ICondition[] memory conditions) internal {
        delete issuanceManagerStorage().scripToCertConditions[certAddress];
        for (uint i = 0; i < conditions.length; i++) {
            issuanceManagerStorage().scripToCertConditions[certAddress].push(conditions[i]);
        }
    }

    function getScripToCertMinimum(address certAddress) internal view returns (uint256) {
        return issuanceManagerStorage().scripToCertMinimums[certAddress];
    }

    function setScripToCertMinimum(address certAddress, uint256 minimum) internal {
        issuanceManagerStorage().scripToCertMinimums[certAddress] = minimum;
    }

    function isScripifyWhitelisted(
        address certAddress,
        uint256 id
    ) internal view returns (bool) {
        return issuanceManagerStorage().scripifyWhitelist[certAddress][id];
    }

    function setScripifyWhitelistEnabled(
        address certAddress,
        bool enabled
    ) internal {
        issuanceManagerStorage().scripifyWhitelistEnabled[certAddress] = enabled;
    }

    function getScripifyWhitelistEnabled(
        address certAddress
    ) internal view returns (bool) {
        return issuanceManagerStorage().scripifyWhitelistEnabled[certAddress];
    }

    function setScripifyWhitelisted(
        address certAddress,
        uint256 id,
        bool isWhitelisted
    ) internal {
        issuanceManagerStorage().scripifyWhitelist[certAddress][id] = isWhitelisted;
    }

    function setCertToScripConditions(address certAddress, ICondition[] memory conditions) internal {
        delete issuanceManagerStorage().certToScripConditions[certAddress];
        for (uint i = 0; i < conditions.length; i++) {
            issuanceManagerStorage().certToScripConditions[certAddress].push(conditions[i]);
        }
    }

    function getScripRatio(address certAddress) internal view returns (ScripRatio storage) {
        return issuanceManagerStorage().scripRatios[certAddress];
    }

    function setScripRatio(address certAddress, uint256 numerator, uint256 denominator) internal {
        issuanceManagerStorage().scripRatios[certAddress] = ScripRatio({
            numerator: numerator,
            denominator: denominator
        });
    }

    function getCertScripState(
        address certAddress,
        uint256 id
    ) internal view returns (CertScripState storage) {
        return issuanceManagerStorage().certScripStates[certAddress][id];
    }

    /// @notice Underlying wad claim for one certificate’s vault position (pro-rata on total pool).
    function _assetsOfVaultPosition(
        address certAddress,
        uint256 tokenId
    ) internal view returns (uint256 assetsWad) {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        if (pool.totalNominalShares == 0) {
            return 0;
        }
        return
            _vaultSharesOf(certAddress, tokenId) * pool.totalAssetsWad /
            pool.totalNominalShares;
    }

    /// @dev Shares this certificate holds in the pool's current epoch. A position recorded before the pool
    ///      last emptied is worthless and reads as zero without needing to have been written back.
    function _vaultSharesOf(
        address certAddress,
        uint256 tokenId
    ) internal view returns (uint256) {
        CertScripState storage certState = getCertScripState(certAddress, tokenId);
        if (
            certState.vaultEpoch !=
            issuanceManagerStorage().certScripUnitPools[certAddress].vaultEpoch
        ) {
            return 0;
        }
        return certState.vaultNominalShares;
    }

    /// @dev Same position, normalized into the current epoch so it is safe to write to: a stale position is
    ///      cleared before use, so the deposit path can never add new shares on top of dead ones.
    function _vaultPositionForWrite(
        address certAddress,
        uint256 tokenId
    ) internal returns (CertScripState storage certState) {
        certState = getCertScripState(certAddress, tokenId);
        uint256 epoch = issuanceManagerStorage()
            .certScripUnitPools[certAddress]
            .vaultEpoch;
        if (certState.vaultEpoch != epoch) {
            certState.vaultNominalShares = 0;
            certState.vaultEpoch = epoch;
        }
    }

    /// @dev Scrip-token-equivalent claim for a single certificate's vault position.
    function getScripPoolAmountById(
        address certAddress,
        uint256 tokenId
    ) internal view returns (uint256 scripEquivalent) {
        (uint256 num, uint256 den) = _getScripRatioOrDefault(certAddress);
        uint256 assetsWad = _assetsOfVaultPosition(certAddress, tokenId);
        if (assetsWad == 0) return 0;
        return assetsWad * num / den;
    }

    /// @dev Nominal vault shares held by a single certificate.
    function getScripPoolSharesById(
        address certAddress,
        uint256 tokenId
    ) internal view returns (uint256 shares) {
        return _vaultSharesOf(certAddress, tokenId);
    }

    function getRecertificationApproval(
        address certAddress,
        address investor
    ) internal view returns (RecertificationApproval storage) {
        return issuanceManagerStorage().recertificationApprovals[certAddress][
            investor
        ];
    }

    function getRecertificationApprovalData(
        address certAddress,
        address investor
    )
        internal
        view
        returns (
            bool approved,
            string memory investorName,
            CertificateDetails memory details,
            bytes memory officerSignature,
            uint256 endorsementTimestamp
        )
    {
        RecertificationApproval storage approval = getRecertificationApproval(
            certAddress,
            investor
        );
        approved = approval.approved;
        investorName = approval.investorName;
        details = approval.details;
        officerSignature = approval.officerSignature;
        endorsementTimestamp = approval.endorsementTimestamp;
    }

    function setRecertificationApproval(
        address certAddress,
        address investor,
        string memory investorName,
        CertificateDetails memory details,
        bytes memory officerSignature
    ) internal {
        issuanceManagerStorage().recertificationApprovals[certAddress][
            investor
        ] = RecertificationApproval({
            approved: true,
            investorName: investorName,
            details: details,
            officerSignature: officerSignature,
            endorsementTimestamp: block.timestamp
        });
    }

    function clearRecertificationApproval(
        address certAddress,
        address investor
    ) internal {
        delete issuanceManagerStorage().recertificationApprovals[certAddress][
            investor
        ];
    }

    /// @return totalTrackedScrip ERC20 scrip total supply (canonical circulating scrip).
    /// @return pricePerShareRay underlying wad per nominal vault share, ray precision (0 if empty vault).
    function getScripPoolTotals(
        address certAddress
    )
        internal
        view
        returns (uint256 totalTrackedScrip, uint256 pricePerShareRay)
    {
        address scrip = getScripifiedCert(certAddress);
        totalTrackedScrip = scrip == address(0) ? 0 : ICyberScrip(scrip).totalSupply();
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        pricePerShareRay = pool.totalNominalShares == 0
            ? 0
            : pool.totalAssetsWad * VAULT_RAY / pool.totalNominalShares;
    }

    function getCertScripUnitVault(
        address certAddress
    ) internal view returns (uint256 totalAssetsWad, uint256 totalNominalShares) {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        totalAssetsWad = pool.totalAssetsWad;
        totalNominalShares = pool.totalNominalShares;
    }

    function getCertScripifiedStatus(
        address certAddress,
        uint256 id
    )
        internal
        view
        returns (bool isScripified, uint256 scripifiedUnits, uint256 maxUnitsRepresented)
    {
        CertScripState storage certState = getCertScripState(certAddress, id);
        scripifiedUnits = getCurrentCertScripifiedUnits(certAddress, id);
        isScripified = scripifiedUnits > 0;
        maxUnitsRepresented = certState.maxUnitsRepresented;
    }

    function getCurrentCertScripifiedUnits(
        address certAddress,
        uint256 id
    ) internal view returns (uint256) {
        return _assetsOfVaultPosition(certAddress, id);
    }

    /// @notice Deploys the LedgerEntryToken and CyberScrip beacons and wires up core storage.
    /// @dev Split out of IssuanceManager.initialize to keep that contract under the EIP-170 size
    /// limit. Runs via delegatecall, so `address(this)` is the IssuanceManager and it owns the beacons.
    function executeInitialize(
        address upgradeFactory,
        address corp,
        address uriBuilder
    ) external {
        address cyberCertPrinterRefImpl = IIssuanceManagerFactory(
            upgradeFactory
        ).getCyberCertPrinterRefImplementation();
        UpgradeableBeacon beaconCertPrinter = new UpgradeableBeacon(
            cyberCertPrinterRefImpl,
            address(this)
        );
        emit IIssuanceManager.CertPrinterBeaconImplementationUpgraded(
            cyberCertPrinterRefImpl
        );

        address cyberScripRefImpl = IIssuanceManagerFactory(upgradeFactory)
            .getCyberScripRefImplementation();
        UpgradeableBeacon beaconScrip = new UpgradeableBeacon(
            cyberScripRefImpl,
            address(this)
        );
        emit IIssuanceManager.ScripBeaconImplementationUpgraded(cyberScripRefImpl);

        setCORP(corp);
        setUriBuilder(uriBuilder);
        setCyberCertPrinterBeacon(beaconCertPrinter);
        setUpgradeFactory(upgradeFactory);
        setCyberScripBeacon(beaconScrip);
    }

    function executeCreateCertPrinter(
        string[] memory ledger,
        string memory name,
        string memory ticker,
        string memory certificateUri,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        address extension,
        bytes memory seriesData
    ) external returns (address newCert) {
        bytes32 salt = keccak256(abi.encodePacked(getPrinters().length, address(this)));
        newCert = Create2.deploy(0, salt, _getBytecodeCertPrinter());
        addPrinter(newCert);
        ILedgerEntryToken(newCert).initialize(
            ledger,
            name,
            ticker,
            certificateUri,
            address(this),
            securityType,
            securitySeries,
            extension,
            seriesData
        );
        uint256 classId = _getOrCreateClassId(securityType);
        issuanceManagerStorage().printerClassIds[newCert] = classId;
        emit PrinterClassAssigned(newCert, classId);
        emit CertPrinterCreated(
            newCert,
            getCORP(),
            ledger,
            name,
            ticker,
            securityType,
            securitySeries,
            certificateUri
        );
    }

    function executeCreateCert(
        address certAddress,
        address to,
        CertificateDetails memory details
    ) external returns (uint256 id) {
        ILedgerEntryToken cert = ILedgerEntryToken(certAddress);
        uint256 tokenId = cert.totalSupply();
        id = cert.safeMint(tokenId, to, details);
        _emitCertificateCreated(tokenId, certAddress, details);
    }

    function executeAssignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory details,
        string memory investorName
    ) external {
        ILedgerEntryToken(certAddress).assignCert(from, tokenId, investor, details, investorName);
    }

    function executeCreateCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory details,
        string memory investorName,
        bytes memory endorsementSignature,
        uint256 timestamp
    ) external returns (uint256 tokenId) {
        ILedgerEntryToken cert;
        (cert, tokenId) = _mintAssignedCert(
            certAddress,
            investor,
            investor, // primary issuance is always direct-hosted for now
            details,
            investorName
        );

        Endorsement memory newEndorsement = Endorsement({
            endorser: address(this),
            timestamp: timestamp,
            signatureHash: endorsementSignature,
            registry: address(0),
            agreementId: 0,
            endorsee: investor,
            endorseeName: investorName
        });
        cert.addEndorsement(tokenId, newEndorsement);

        bytes memory escrowedOfficerSignature = _getEscrowedOfficerSignature();

        if (endorsementSignature.length > 0) {
            cert.addIssuerSignature(tokenId, endorsementSignature);
        }
        if (escrowedOfficerSignature.length > 0) {
            cert.addIssuerSignature(tokenId, escrowedOfficerSignature);
        }

        _emitCertificateCreated(tokenId, certAddress, details);
    }

    function executeCreateCertSignAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory details,
        bytes memory endorsementSignature,
        address registry,
        bytes32 agreementId,
        string memory investorName
    ) external returns (uint256 tokenId) {
        ILedgerEntryToken cert;
        (cert, tokenId) = _mintAssignedCert(
            certAddress,
            investor,
            investor, // primary issuance is always direct-hosted for now
            details,
            investorName
        );

        Endorsement memory newEndorsement = Endorsement({
            endorser: address(this),
            timestamp: block.timestamp,
            signatureHash: endorsementSignature,
            registry: registry,
            agreementId: agreementId,
            endorsee: investor,
            endorseeName: investorName
        });
        cert.addEndorsement(tokenId, newEndorsement);

        bytes memory escrowedOfficerSignature = _getEscrowedOfficerSignature();

        if (endorsementSignature.length > 0) {
            cert.addIssuerSignature(tokenId, endorsementSignature);
        }
        if (escrowedOfficerSignature.length > 0) {
            cert.addIssuerSignature(tokenId, escrowedOfficerSignature);
        }

        _emitCertificateCreated(tokenId, certAddress, details);
    }

    /// @notice Executes the secondary-trade ownership change at finalization (spec §7.4A steps a–d).
    /// @dev Mutate-and-mint: the seller's Ledger Entry Token never moves wallets; ownership transfers via
    /// metadata. Core scope — acquisitionDate / Rule 144(d)(3) tacking / per-pathway certLegend updates are
    /// deferred (need a FundInterest extensionData format that does not exist yet), so exemptionPathway is
    /// decoded for the record but otherwise unused here.
    function executeSecondaryTransfer(bytes calldata dealMetadata)
        external
        returns (uint256 buyerTokenId)
    {
        (
            address certPrinter,
            uint256 tokenId,
            uint256 units,
            address buyer,
            string memory buyerName,
            HostingMode buyerHostingMode,
            address adminMultisig,
            ,
            bytes32 settlementAgreementId,
            bytes memory openEndorsementSig
        ) = abi.decode(
            dealMetadata,
            (address, uint256, uint256, address, string, HostingMode, address, ExemptionPathway, bytes32, bytes)
        );

        ILedgerEntryToken cert = ILedgerEntryToken(certPrinter);

        // Registered owner of the seller's Ledger Entry Token, unchanged by hosting mode (the token never moves).
        address seller = cert.legalOwnerOf(tokenId);

        // We don't check if seller's cert is voided again here because the buyer's lot reissuance will check it.

        // (a) Materialize the seller's endorsement on the Ledger Entry Token. The seller signs in blank at
        // posting/acceptance (spec §7.3.1) and that signature rides in dealMetadata; the endorsement is written
        // here, at finalization, with the now-known buyer as endorsee (spec §7.4A step 1). Recorded while the
        // token is still Assigned, before the void/decrement below. The seller is always the endorser of record
        // (spec §3676-3680); the IssuanceManager is only the operational executor.
        Endorsement memory sellerEndorsement = Endorsement({
            endorser: seller,
            timestamp: block.timestamp,
            signatureHash: openEndorsementSig,
            registry: address(0),
            agreementId: settlementAgreementId,
            endorsee: buyer,
            endorseeName: buyerName
        });
        cert.addEndorsement(tokenId, sellerEndorsement);

        // (b) Mutate the seller's Ledger Entry Token in place: decrement the sold units, then void if the
        // token is fully sold (nothing left). Decrement-first so the struct carries no stale balance at void.
        CertificateDetails memory sellerDetails = cert.getActiveCertificateDetails(tokenId);
        if (units > sellerDetails.unitsRepresented) revert AmountExceedsAvailableUnits();
        sellerDetails.unitsRepresented -= units;
        cert.updateCertificateDetails(tokenId, sellerDetails);
        // A lot that keeps a vault claim is not empty: its scrip is still outstanding, and the seller redeems
        // it through this lot. The actual voiding uses the same rule as executeVoidEmptyCerts, which sweeps
        // the lot later, once the claim is gone.
        bool sellerVoided = sellerDetails.unitsRepresented == 0
            && _assetsOfVaultPosition(certPrinter, tokenId) == 0;
        // (c) Deliver the buyer's units as a fresh lot (fresh-mint-per-lot): each acquisition mints its own
        // Ledger Entry Token carrying its own acquisitionTimestamp (per-lot holding-period clock, stamped at
        // mint). The lot inherits the seller's non-basis terms; cost basis stays blank (no primary-issuance
        // basis). Custodian is the admin multisig under Administered hosting, otherwise the buyer.
        bool buyerTokenIsMinted = true;
        address custodian = buyerHostingMode == HostingMode.ADMINISTERED ? adminMultisig : buyer;
        CertificateDetails memory buyerDetails = CertificateDetails({
            signingOfficerName: sellerDetails.signingOfficerName,
            signingOfficerTitle: sellerDetails.signingOfficerTitle,
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: units,
            legalDetails: sellerDetails.legalDetails,
            extensionData: sellerDetails.extensionData
        });
        (, buyerTokenId) = _mintReissuedCert(certPrinter, tokenId, custodian, buyer, buyerDetails, buyerName);
        uint256 buyerUnitsAfter = units; // absolute post-mutation balance on the buyer token, reported in the event

        // Void the emptied seller lot only after the buyer's lot is registered. The printer rejects a reissue
        // from a void lot, and on a full sale this settlement is what empties it, so voiding first would make
        // the trade reject itself.
        if (sellerVoided) {
            cert.voidCert(tokenId);
        }

        // (d) Mirror the seller's endorsement onto the buyer's token: both tokens carry the identical
        // chain-of-title record (endorser = seller, endorsee = buyer, this agreement), so reuse the (b) struct.
        cert.addEndorsement(buyerTokenId, sellerEndorsement);

        emit IIssuanceManager.SecondaryTransferExecuted(
            settlementAgreementId, certPrinter, buyer, tokenId, buyerTokenId, seller, units,
            sellerDetails.unitsRepresented, buyerUnitsAfter, sellerVoided, buyerTokenIsMinted
        );
    }

    /// @notice Voids lots that represent nothing, so they stop counting in the printer's holder tally.
    /// @dev A fully scripified lot stays counted through its vault claim. Another party can remove that
    /// claim: an empty vault pool retires every position at once. The lot then holds zero units, but its
    /// status is not Void, so the tally still counts its holder and the holder cap refuses buyers on a count
    /// that is too high. Permissionless, because a lot that still holds units cannot be voided here.
    /// Already-void lots are skipped, so one of them does not fail the batch.
    function executeVoidEmptyCerts(address certAddress, uint256[] calldata tokenIds) external {
        if (!isPrinter(certAddress)) revert NotAPrinter();
        ILedgerEntryToken cert = ILedgerEntryToken(certAddress);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (cert.isVoided(tokenId)) continue;
            if (cert.getActiveCertificateDetails(tokenId).unitsRepresented != 0) revert CertNotEmpty();
            if (_assetsOfVaultPosition(certAddress, tokenId) != 0) revert CertNotEmpty();
            cert.voidCert(tokenId);
        }
    }

    function executeSetScripRatio(
        address certAddress,
        uint256 numerator,
        uint256 denominator
    ) external {
        if (numerator == 0 || denominator == 0) revert InvalidScripRatio();
        // The ratio is read live at both mint and redeem, so repricing while scrip is
        // outstanding retroactively changes what already-issued scrip redeems for. Only
        // settable before the scrip contract exists or once every holder has redeemed.
        address scripifiedCert = getScripifiedCert(certAddress);
        if (
            scripifiedCert != address(0) &&
            ICyberScrip(scripifiedCert).totalSupply() != 0
        ) {
            revert ScripOutstanding();
        }
        setScripRatio(certAddress, numerator, denominator);
    }

    function executeSetScripToCertMinimum(
        address certAddress,
        uint256 minimum
    ) external {
        setScripToCertMinimum(certAddress, minimum);
        emit ScripToCertMinimumSet(certAddress, minimum);
    }

    function executeSetScripifyWhitelistEnabled(
        address certAddress,
        bool enabled
    ) external {
        setScripifyWhitelistEnabled(certAddress, enabled);
        emit ScripifyWhitelistEnabledSet(certAddress, enabled);
    }

    function executeSetScripifyWhitelistIds(
        address certAddress,
        uint256[] memory ids,
        bool isWhitelisted
    ) external {
        for (uint256 i = 0; i < ids.length; i++) {
            setScripifyWhitelisted(certAddress, ids[i], isWhitelisted);
            emit ScripifyWhitelistUpdated(certAddress, ids[i], isWhitelisted);
        }
    }

    function executeDeployCyberScrip(
        address certAddress,
        address auth,
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
    ) external returns (address newScrip) {
        if (scripRatioNumerator == 0 || scripRatioDenominator == 0) {
            revert InvalidScripRatio();
        }

        bytes32 salt = keccak256(abi.encodePacked(certAddress, address(this)));
        newScrip = Create2.deploy(0, salt, _getBytecodeScrip());
        emit CyberScripDeployed(
            certAddress,
            newScrip,
            scripRatioNumerator,
            scripRatioDenominator,
            enableForceTransfer,
            enableForceBurn,
            enableFreeze
        );

        ICyberScrip(newScrip).initialize(
            auth,
            certAddress,
            address(this),
            string(
                abi.encodePacked("scrip", ILedgerEntryToken(certAddress).name())
            ),
            string(
                abi.encodePacked("scrip", ILedgerEntryToken(certAddress).symbol())
            ),
            typeRestrictionHooks,
            enableForceTransfer,
            enableForceBurn,
            enableFreeze
        );

        setScripifiedCert(certAddress, newScrip);
        setCertToScripConditions(certAddress, certToScripConditions);
        setScripToCertConditions(certAddress, scripToCertConditions);
        setScripToCertMinimum(certAddress, scripToCertMinimum);
        setScripRatio(certAddress, scripRatioNumerator, scripRatioDenominator);
        emit ScripToCertMinimumSet(certAddress, scripToCertMinimum);

        setScripifyWhitelistEnabled(certAddress, scripifyWhitelistEnabled);
        emit ScripifyWhitelistEnabledSet(certAddress, scripifyWhitelistEnabled);

        for (uint256 i = 0; i < scripifyWhitelistIds.length; i++) {
            setScripifyWhitelisted(certAddress, scripifyWhitelistIds[i], true);
            emit ScripifyWhitelistUpdated(certAddress, scripifyWhitelistIds[i], true);
        }
    }

    function executeScripifyCert(
        address certAddress,
        uint256 id,
        uint256 amount,
        address target,
        address account
    ) external {
        if (amount == 0) revert InvalidAmount();

        address scripifiedCert = getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();

        if (getScripifyWhitelistEnabled(certAddress)) {
            if (!isScripifyWhitelisted(certAddress, id)) {
                revert ScripifyNotWhitelisted();
            }
        }
        
        ICondition[] storage conditions = getCertToScripConditions(certAddress);
        bytes4 selector = bytes4(
            keccak256("scripifyCert(address,uint256,uint256,address)")
        );
        for (uint256 i = 0; i < conditions.length; i++) {
            if (
                !conditions[i].checkCondition(
                    certAddress,
                    selector,
                    abi.encode(id, amount, target)
                )
            ) {
                revert ConditionCheckFailed();
            }
        }

        ILedgerEntryToken certificate = ILedgerEntryToken(certAddress);
        if (certificate.isVoided(id)) revert CertificateVoided();
        if (certificate.legalOwnerOf(id) != account) revert NotLegalOwner();

        address toSend = target;
        if (toSend == address(0)) toSend = account;

        CertificateDetails memory details = certificate
            .getActiveCertificateDetails(id);

        // Reserved units are committed to pending deals; only free units may be scripified,
        // otherwise scripify could pull collateral out from under a live reservation.
        if (amount > details.unitsRepresented - certificate.unitsReserved(id)) {
            revert AmountExceedsAvailableUnits();
        }

        (uint256 numerator, uint256 denominator) = _getScripRatioOrDefault(
            certAddress
        );
        uint256 scripAmount = amount * numerator;
        scripAmount = scripAmount / denominator;
        CertScripState storage certState = getCertScripState(certAddress, id);
        uint256 currentScripifiedUnits = getCurrentCertScripifiedUnits(
            certAddress,
            id
        );
        uint256 totalUnits = details.unitsRepresented + currentScripifiedUnits;
        if (totalUnits > certState.maxUnitsRepresented) {
            certState.maxUnitsRepresented = totalUnits;
        }
        if (currentScripifiedUnits + amount > certState.maxUnitsRepresented) {
            revert ScripifyOverMax();
        }

        _depositCertScripUnits(certAddress, id, amount);
        details.unitsRepresented = details.unitsRepresented - amount;
        certificate.updateCertificateDetails(id, details);
        ICyberScrip(scripifiedCert).mint(toSend, scripAmount);
        (uint256 newTotalAssetsWad, uint256 newTotalNominalShares) = getCertScripUnitVault(
            certAddress
        );
        emit ScripifiedCert(
            certAddress,
            id,
            scripifiedCert,
            amount,
            details.unitsRepresented,
            getScripPoolSharesById(certAddress, id),
            newTotalAssetsWad,
            newTotalNominalShares
        );
    }

    function executeConvertScripToCert(
        address certAddress,
        uint256 amount,
        address account,
        bytes4 convertSelector
    ) external {
        address scripifiedCert = getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();
        uint256 minimum = getScripToCertMinimum(certAddress);
        if (minimum > 0 && amount < minimum) revert ScripToCertMinimumNotMet();

        (uint256 numerator, uint256 denominator) = _getScripRatioOrDefault(
            certAddress
        );
        uint256 units = amount * denominator;
        units = units / numerator;


        ICondition[] storage conditions = getScripToCertConditions(certAddress);
        for (uint256 i = 0; i < conditions.length; i++) {
            if (
                !conditions[i].checkCondition(
                    certAddress,
                    convertSelector,
                    abi.encode(amount, account)
                )
            ) {
                revert ConditionCheckFailed();
            }
        }

        ILedgerEntryToken certificate = ILedgerEntryToken(certAddress);
        RecertSelection memory selection = _selectFirstLegalOwnedToken(
            certAddress,
            account
        );
        bool requiresApproval = !selection.foundActive;
        RecertificationApproval memory approval;
        if (requiresApproval) {
            (
                bool approved,
                string memory investorName,
                CertificateDetails memory approvedDetails,
                bytes memory officerSignature,
                uint256 endorsementTimestamp
            ) = getRecertificationApprovalData(certAddress, account);
            if (!approved) revert RecertificationApprovalRequired();
            if (officerSignature.length == 0) revert SignatureRequired();
            approval.approved = approved;
            approval.investorName = investorName;
            approval.details = approvedDetails;
            approval.officerSignature = officerSignature;
            approval.endorsementTimestamp = endorsementTimestamp;
        }

        if (selection.foundActive) {
            // Redeem vault shares for this certificate up to pool claim; burn nominals. Conversion
            // above claim is still backed by burned scrip, so dilute remaining pool pro-rata via
            // _withdrawVaultAssets (same economics as excess scrip burning without a cert position).
            uint256 claimWad = _assetsOfVaultPosition(
                certAddress,
                selection.activeTokenId
            );
            uint256 fromVaultWad = units < claimWad ? units : claimWad;
            uint256 redeemedWad;
            if (fromVaultWad > 0) {
                redeemedWad = _redeemVaultForCert(
                    certAddress,
                    selection.activeTokenId,
                    fromVaultWad
                );
            }
            if (units > redeemedWad) {
                _withdrawVaultAssets(certAddress, units - redeemedWad);
            }
        } else {
            // No active cert: socialized withdrawal from the shared vault (nominals unchanged).
            _withdrawVaultAssets(certAddress, units);
        }
        ICyberScrip(scripifiedCert).burnFrom(account, amount);

        if (selection.foundActive) {
            CertificateDetails memory activeDetails = certificate
                .getActiveCertificateDetails(selection.activeTokenId);
            activeDetails.unitsRepresented =
                activeDetails.unitsRepresented +
                units;
            certificate.updateCertificateDetails(
                selection.activeTokenId,
                activeDetails
            );
            _setCertMaxFromCurrent(
                certAddress,
                selection.activeTokenId,
                activeDetails.unitsRepresented
            );
            CertificateDetails memory effectiveDetails = certificate
                .getCertificateDetails(selection.activeTokenId);
            CertificateDetails memory activeAfter = certificate
                .getActiveCertificateDetails(selection.activeTokenId);
            (
                uint256 newTotalAssetsWad,
                uint256 newTotalNominalShares
            ) = getCertScripUnitVault(certAddress);
            emit ScripAddedToExistingCert(
                certAddress,
                account,
                selection.activeTokenId,
                amount,
                effectiveDetails.unitsRepresented,
                effectiveDetails.unitsRepresented - activeAfter.unitsRepresented
            );
            emit ScripRecertified(
                certAddress,
                account,
                selection.activeTokenId,
                amount,
                effectiveDetails.unitsRepresented,
                getScripPoolSharesById(certAddress, selection.activeTokenId),
                newTotalAssetsWad,
                newTotalNominalShares
            );
        } else {
            CertificateDetails memory details = approval.details;
            details.unitsRepresented = units;
            uint256 createdTokenId = IIssuanceManager(address(this))
                .createCertAndAssignWithName(
                    certAddress,
                    account,
                    details,
                    approval.investorName,
                    approval.officerSignature,
                    approval.endorsementTimestamp
                );
            clearRecertificationApproval(certAddress, account);
            _setCertMaxFromCurrent(
                certAddress,
                createdTokenId,
                details.unitsRepresented
            );
            CertificateDetails memory effectiveDetails = certificate
                .getCertificateDetails(createdTokenId);
            (
                uint256 newTotalAssetsWad,
                uint256 newTotalNominalShares
            ) = getCertScripUnitVault(certAddress);
            emit ScripRecertified(
                certAddress,
                account,
                createdTokenId,
                amount,
                effectiveDetails.unitsRepresented,
                getScripPoolSharesById(certAddress, createdTokenId),
                newTotalAssetsWad,
                newTotalNominalShares
            );
        }
    }

    function executeForceScripBurn(
        address certAddress,
        address account,
        uint256 amount
    ) external {
        if (amount == 0) revert InvalidAmount();

        address scripifiedCert = getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();

        (uint256 numerator, uint256 denominator) = _getScripRatioOrDefault(
            certAddress
        );
        uint256 units = amount * denominator;
        units = units / numerator;

        _withdrawVaultAssets(certAddress, units);
        ICyberScrip(scripifiedCert).forceBurn(account, amount);
    }

    function executeSetRecertificationApproval(
        address certAddress,
        address investor,
        string memory investorName,
        CertificateDetails memory details,
        bytes memory officerSignature
    ) external {
        if (investor == address(0)) revert InvalidInvestor();
        if (bytes(investorName).length == 0) revert InvalidInvestorName();
        if (officerSignature.length == 0) revert SignatureRequired();
        setRecertificationApproval(
            certAddress,
            investor,
            investorName,
            details,
            officerSignature
        );
        emit RecertificationApprovalSet(certAddress, investor, investorName);
    }

    function executeClearRecertificationApproval(
        address certAddress,
        address investor
    ) external {
        clearRecertificationApproval(certAddress, investor);
        emit RecertificationApprovalCleared(certAddress, investor);
    }

    /// @dev First active (non-voided) cert that `owner` is the legal owner of record for, via the printer's
    /// per-legal-owner enumeration. Independent of ERC-721 custody, so it works under administered hosting
    /// where a multisig custodies many holders' certs — no scan of the custodian's whole balance.
    function _selectFirstLegalOwnedToken(
        address certAddress,
        address owner
    ) internal view returns (RecertSelection memory selection) {
        ILedgerEntryToken certificate = ILedgerEntryToken(certAddress);
        uint256 ownedBalance = certificate.balanceOfLegalOwner(owner);

        for (uint256 i = 0; i < ownedBalance; i++) {
            uint256 tokenId = certificate.tokenOfLegalOwnerByIndex(owner, i);
            if (certificate.isVoided(tokenId)) continue;
            selection.foundActive = true;
            selection.activeTokenId = tokenId;
            return selection;
        }
    }

    /// @dev Mint a new cert: the NFT is custodied by `to` while `owner` is recorded as the legal owner of
    /// record. Direct issuance passes to == owner; administered hosting custodies with a multisig (`to`) for
    /// the buyer/holder of record (`owner`).
    function _mintAssignedCert(
        address certAddress,
        address to,
        address owner,
        CertificateDetails memory details,
        string memory ownerName
    )
        internal
        returns (ILedgerEntryToken cert, uint256 tokenId)
    {
        _requireCompanyDetailsSet();
        cert = ILedgerEntryToken(certAddress);
        tokenId = cert.totalSupply();
        cert.safeMintAndAssign(to, owner, tokenId, details, ownerName);
        _emitCertificateCreated(tokenId, certAddress, details);
    }

    /// @dev Secondary-trade counterpart of _mintAssignedCert. The two cannot share one helper: a fresh mint
    /// looks identical to an issuance from the printer's side, so the reissue has to name the lot it came
    /// from or the register gate cannot tell that title moved.
    function _mintReissuedCert(
        address certAddress,
        uint256 sourceTokenId,
        address to,
        address owner,
        CertificateDetails memory details,
        string memory ownerName
    )
        internal
        returns (ILedgerEntryToken cert, uint256 tokenId)
    {
        _requireCompanyDetailsSet();
        cert = ILedgerEntryToken(certAddress);
        tokenId = cert.totalSupply();
        cert.safeMintFromAndAssign(sourceTokenId, to, owner, tokenId, details, ownerName);
        _emitCertificateCreated(tokenId, certAddress, details);
    }

    function _requireCompanyDetailsSet() internal view {
        if (bytes(ICyberCorp(getCORP()).cyberCORPName()).length == 0) {
            revert CompanyDetailsNotSet();
        }
    }

    function _emitCertificateCreated(
        uint256 tokenId,
        address certAddress,
        CertificateDetails memory details
    ) internal {
        emit CertificateCreated(
            tokenId,
            certAddress,
            details.investmentAmountUSD,
            details.issuerUSDValuationAtTimeOfInvestment,
            details
        );
    }

    function _getEscrowedOfficerSignature()
        internal
        view
        returns (bytes memory escrowedOfficerSignature)
    {
        address corp = getCORP();
        try ICyberCorp(corp).getEscrowedOfficerSignatureCount() returns (
            uint256 count
        ) {
            if (count > 0) {
                try ICyberCorp(corp).getEscrowedOfficerSignature(0) returns (
                    bytes memory sig
                ) {
                    escrowedOfficerSignature = sig;
                } catch {}
            }
        } catch {}
    }

    function _getBytecodeCertPrinter() internal view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            sourceCodeBytes,
            abi.encode(getCyberCertPrinterBeacon(), "")
        );
    }

    function _getBytecodeScrip() internal view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(
            sourceCodeBytes,
            abi.encode(getCyberScripBeacon(), "")
        );
    }

    function _getScripRatioOrDefault(
        address certAddress
    ) internal view returns (uint256 numerator, uint256 denominator) {
        ScripRatio storage ratio = getScripRatio(certAddress);
        numerator = ratio.numerator;
        denominator = ratio.denominator;
        if (numerator == 0 || denominator == 0) {
            return (1, 1);
        }
    }

    function _setCertMaxFromCurrent(
        address certAddress,
        uint256 tokenId,
        uint256 currentUnits
    ) internal {
        CertScripState storage certState = getCertScripState(certAddress, tokenId);
        uint256 currentTotal = currentUnits +
            getCurrentCertScripifiedUnits(certAddress, tokenId);
        if (currentTotal > certState.maxUnitsRepresented) {
            certState.maxUnitsRepresented = currentTotal;
        }
    }

    /// @notice Deposit units (wad) into the shared vault; mint nominal shares to this certificate.
    function _depositCertScripUnits(
        address certAddress,
        uint256 tokenId,
        uint256 assetsWad
    ) internal {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        CertScripState storage certState = _vaultPositionForWrite(
            certAddress,
            tokenId
        );

        uint256 sharesMinted = pool.totalNominalShares == 0
            ? assetsWad
            : assetsWad * pool.totalNominalShares / pool.totalAssetsWad;
        if (sharesMinted == 0) revert ZeroSharesMinted();

        certState.vaultNominalShares += sharesMinted;
        pool.totalNominalShares += sharesMinted;
        pool.totalAssetsWad += assetsWad;
    }

    /// @notice ERC4626-style withdraw: burn this certificate's nominal shares and pull `assetsWad`
    ///         from the vault (exact asset burn; shares burnt round up).
    function _redeemVaultForCert(
        address certAddress,
        uint256 tokenId,
        uint256 assetsWad
    ) internal returns (uint256 assetsRemovedWad) {
        if (assetsWad == 0) return 0;
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        CertScripState storage certState = _vaultPositionForWrite(
            certAddress,
            tokenId
        );
        uint256 S = pool.totalNominalShares;
        uint256 T = pool.totalAssetsWad;
        if (S == 0 || T == 0) revert EmptyVault();

        uint256 claimWad = certState.vaultNominalShares * T / S;
        if (assetsWad > claimWad) revert VaultRedemptionExceedsClaim();

        uint256 sharesBurned = (assetsWad * S + T - 1) / T;
        if (sharesBurned > certState.vaultNominalShares) {
            sharesBurned = certState.vaultNominalShares;
            assetsWad = sharesBurned * T / S;
        }

        certState.vaultNominalShares -= sharesBurned;
        pool.totalNominalShares -= sharesBurned;
        pool.totalAssetsWad -= assetsWad;

        if (pool.totalAssetsWad == 0) {
            _resetVaultPositions(certAddress);
        }
        return assetsWad;
    }

    /// @notice Remove underlying from vault; all certificate positions diluted pro-rata
    ///         (nominal shares unchanged, price per share in underlying drops).
    function _withdrawVaultAssets(
        address certAddress,
        uint256 assetsOutWad
    ) internal {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        if (pool.totalAssetsWad == 0) revert EmptyVault();
        if (assetsOutWad > pool.totalAssetsWad) {
            revert VaultWithdrawalExceedsAssets();
        }

        pool.totalAssetsWad -= assetsOutWad;
        if (pool.totalAssetsWad == 0) {
            _resetVaultPositions(certAddress);
        }
    }

    /// @dev Retires every outstanding position in one step by bumping the epoch, so an emptied pool costs
    ///      O(1) instead of a walk over the printer's whole (permanently growing) token supply.
    function _resetVaultPositions(address certAddress) internal {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        pool.totalNominalShares = 0;
        pool.vaultEpoch++;
    }
}
