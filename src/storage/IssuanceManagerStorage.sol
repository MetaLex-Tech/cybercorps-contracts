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
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/ICyberScrip.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/IIssuanceManagerFactory.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import {ExemptionPathway} from "../interfaces/ISecondaryTradeStorage.sol";
import "./CyberCertPrinterStorage.sol";

library IssuanceManagerStorage {
    error ConditionCheckFailed();
    error ScripifiedCertNotAllowed();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    error ScripifyOverMax();
    error RecertificationApprovalRequired();
    error CompanyDetailsNotSet();
    error InvalidScripRatio();
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
    /// @dev Three slots preserve layout vs legacy (amount, reductionDebt, maxUnitsRepresented).
    struct CertScripState {
        uint256 vaultNominalShares;
        /// @dev Legacy `reductionDebt` slot — unused after ERC4626 vault migration.
        uint256 deprecatedMasterChefDebtSlot;
        uint256 maxUnitsRepresented;
    }

    /// @notice ERC4626-style pool for scripified certificate units (underlying in 18-dec wad).
    struct CertScripUnitPool {
        uint256 totalAssetsWad;
        uint256 totalNominalShares;
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
        CertScripState storage certState = getCertScripState(certAddress, tokenId);
        return
            certState.vaultNominalShares * pool.totalAssetsWad / pool.totalNominalShares;
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
        return getCertScripState(certAddress, tokenId).vaultNominalShares;
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

    /// @notice Deploys the CyberCertPrinter and CyberScrip beacons and wires up core storage.
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
        address extension
    ) external returns (address newCert) {
        bytes32 salt = keccak256(abi.encodePacked(getPrinters().length, address(this)));
        newCert = Create2.deploy(0, salt, _getBytecodeCertPrinter());
        addPrinter(newCert);
        ICyberCertPrinter(newCert).initialize(
            ledger,
            name,
            ticker,
            certificateUri,
            address(this),
            securityType,
            securitySeries,
            extension
        );
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
        ICyberCertPrinter cert = ICyberCertPrinter(certAddress);
        uint256 tokenId = cert.totalSupply();
        id = cert.safeMint(tokenId, to, details);
        _emitCertificateCreated(tokenId, certAddress, details);
    }

    function executeAssignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory details
    ) external {
        ICyberCertPrinter(certAddress).assignCert(from, tokenId, investor, details);
    }

    function executeCreateCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory details,
        string memory investorName,
        bytes memory endorsementSignature,
        uint256 timestamp
    ) external returns (uint256 tokenId) {
        ICyberCertPrinter cert;
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
        ICyberCertPrinter cert;
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

    function executeAddIssuerSignature(
        address certAddress,
        uint256 tokenId,
        bytes memory signature
    ) external {
        if (signature.length == 0) revert SignatureRequired();
        ICyberCertPrinter(certAddress).addIssuerSignature(tokenId, signature);
    }

    function executeEndorseCertificate(
        address certAddress,
        uint256 tokenId,
        address endorser,
        bytes memory signature,
        bytes32 agreementId
    ) external {
        Endorsement memory newEndorsement = Endorsement({
            endorser: endorser,
            timestamp: block.timestamp,
            signatureHash: signature,
            registry: address(0),
            agreementId: agreementId,
            endorsee: address(0),
            endorseeName: ""
        });
        ICyberCertPrinter(certAddress).addEndorsement(tokenId, newEndorsement);
    }

    // TOOD WIP: review needed
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
            uint8 buyerHostingMode,
            address adminMultisig,
            ,
            bytes32 settlementAgreementId,
            bytes memory openEndorsementSig
        ) = abi.decode(
            dealMetadata,
            (address, uint256, uint256, address, string, uint8, address, ExemptionPathway, bytes32, bytes)
        );

        ICyberCertPrinter cert = ICyberCertPrinter(certPrinter);
        // Registered owner of the seller's Ledger Entry Token, unchanged by hosting mode (the token never moves).
        address seller = cert.legalOwnerOf(tokenId);

        // (a) Consume this lot's unit reservation engaged at posting/acceptance.
        cert.decreaseUnitsReserved(tokenId, units);

        // (b) Materialize the seller's endorsement on the Ledger Entry Token. The seller signs in blank at
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

        // (c) Mutate the seller's Ledger Entry Token in place: void on a full sale, decrement on a partial.
        CertificateDetails memory details = cert.getCertificateDetails(tokenId);
        bool sellerVoided = units >= details.unitsRepresented;
        if (sellerVoided) {
            cert.voidCert(tokenId);
        } else {
            details.unitsRepresented -= units;
            cert.updateCertificateDetails(tokenId, details);
        }
        // The buyer's new token inherits the seller's terms (legalDetails, valuation, …) for the sold quantity.
        // Build a fresh struct rather than aliasing `details` (memory assignment is by reference).
        CertificateDetails memory buyerDetails = CertificateDetails({
            signingOfficerName: details.signingOfficerName,
            signingOfficerTitle: details.signingOfficerTitle,
            investmentAmountUSD: details.investmentAmountUSD,
            issuerUSDValuationAtTimeOfInvestment: details.issuerUSDValuationAtTimeOfInvestment,
            unitsRepresented: units,
            legalDetails: details.legalDetails,
            extensionData: details.extensionData
        });

        // (d) Deliver the buyer's units. By default we consolidate: if the buyer already holds an active
        // (non-voided) Ledger Entry Token on this printer, fold the purchased units into it rather than
        // fragmenting their position across one cert per fill; mint a fresh token only when they hold none.
        // A printer is scoped to one security class/series, so consolidation never merges across security types
        // (the folded units inherit the existing cert's terms). We look the buyer up by legal owner of record,
        // so this is correct under both hosting modes — including Administered, where the multisig custodies the
        // NFT but the buyer is the registered owner. The custodian only decides where a freshly minted NFT lands.
        address custodian = buyerHostingMode == 1 ? adminMultisig : buyer;
        RecertSelection memory existing = _selectFirstLegalOwnedToken(certPrinter, buyer);
        if (existing.foundActive) {
            // TODO: accumulating lots bought across different offers keeps the existing cert's per-cert basis
            // (investmentAmountUSD / issuerUSDValuationAtTimeOfInvestment) and drops the new lot's — a
            // heterogeneous merge. Fills of one offer share a source cert so stay homogeneous; revisit if
            // cross-offer basis must be preserved.
            buyerTokenId = existing.activeTokenId;
            CertificateDetails memory accDetails = cert.getCertificateDetails(buyerTokenId);
            accDetails.unitsRepresented += units;
            cert.updateCertificateDetails(buyerTokenId, accDetails);
        } else {
            (, buyerTokenId) = _mintAssignedCert(certPrinter, custodian, buyer, buyerDetails, buyerName);
        }

        // (e) Mirror endorsement on the new token: chain-of-title back-pointer to the seller and the agreement,
        // reusing the seller's open-endorsement signature.
        Endorsement memory mirror = Endorsement({
            endorser: seller,
            timestamp: block.timestamp,
            signatureHash: openEndorsementSig,
            registry: address(0),
            agreementId: settlementAgreementId,
            endorsee: buyer,
            endorseeName: buyerName
        });
        cert.addEndorsement(buyerTokenId, mirror);

        emit IIssuanceManager.SecondaryTransferExecuted(
            settlementAgreementId, certPrinter, tokenId, buyerTokenId, seller, buyer, units, sellerVoided
        );
    }

    function executeVoidCertificate(address certAddress, uint256 tokenId) external {
        ICyberCertPrinter(certAddress).voidCert(tokenId);
    }

    function executeUnvoidCertificate(address certAddress, uint256 tokenId) external {
        ICyberCertPrinter(certAddress).unvoidCert(tokenId);
    }

    function executeSetGlobalTransferable(
        address certAddress,
        bool transferable
    ) external {
        ICyberCertPrinter(certAddress).setGlobalTransferable(transferable);
    }

    function executeSetRestrictionHook(
        address certAddress,
        uint256 id,
        address hookAddress
    ) external {
        ICyberCertPrinter(certAddress).setRestrictionHook(id, hookAddress);
    }

    function executeSetGlobalRestrictionHook(
        address certAddress,
        address hookAddress
    ) external {
        ICyberCertPrinter(certAddress).setGlobalRestrictionHook(hookAddress);
    }

    function executeSetTokenTransferable(
        address certAddress,
        uint256 tokenId,
        bool value
    ) external {
        ICyberCertPrinter(certAddress).setTokenTransferable(tokenId, value);
    }

    function executeIncreaseUnitsReserved(
        address certAddress,
        uint256 tokenId,
        uint256 amount
    ) external {
        ICyberCertPrinter(certAddress).increaseUnitsReserved(tokenId, amount);
    }

    function executeDecreaseUnitsReserved(
        address certAddress,
        uint256 tokenId,
        uint256 amount
    ) external {
        ICyberCertPrinter(certAddress).decreaseUnitsReserved(tokenId, amount);
    }

    function executeSetScripRatio(
        address certAddress,
        uint256 numerator,
        uint256 denominator
    ) external {
        if (numerator == 0 || denominator == 0) revert InvalidScripRatio();
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

    function executeAddDefaultLegend(
        address certAddress,
        string memory newLegend
    ) external {
        ICyberCertPrinter(certAddress).addDefaultLegend(newLegend);
    }

    function executeRemoveDefaultLegendAt(
        address certAddress,
        uint256 index
    ) external {
        ICyberCertPrinter(certAddress).removeDefaultLegendAt(index);
    }

    function executeAddCertLegend(
        address certAddress,
        uint256 tokenId,
        string memory newLegend
    ) external {
        ICyberCertPrinter(certAddress).addCertLegend(tokenId, newLegend);
    }

    function executeRemoveCertLegendAt(
        address certAddress,
        uint256 tokenId,
        uint256 index
    ) external {
        ICyberCertPrinter(certAddress).removeCertLegendAt(tokenId, index);
    }

    function executeAddDefaultRestrictiveLegend(
        address certAddress,
        RestrictiveLegend memory newLegend
    ) external {
        ICyberCertPrinter(certAddress).addDefaultRestrictiveLegend(newLegend);
    }

    function executeRemoveDefaultRestrictiveLegendAt(
        address certAddress,
        uint256 index
    ) external {
        ICyberCertPrinter(certAddress).removeDefaultRestrictiveLegendAt(index);
    }

    function executeAddCertRestrictiveLegend(
        address certAddress,
        uint256 tokenId,
        RestrictiveLegend memory newLegend
    ) external {
        ICyberCertPrinter(certAddress).addCertRestrictiveLegend(tokenId, newLegend);
    }

    function executeRemoveCertRestrictiveLegendAt(
        address certAddress,
        uint256 tokenId,
        uint256 index
    ) external {
        ICyberCertPrinter(certAddress).removeCertRestrictiveLegendAt(tokenId, index);
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
                abi.encodePacked("scrip", ICyberCertPrinter(certAddress).name())
            ),
            string(
                abi.encodePacked("scrip", ICyberCertPrinter(certAddress).symbol())
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

        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        if (certificate.isVoided(id)) revert CertificateVoided();
        if (certificate.legalOwnerOf(id) != account) revert NotLegalOwner();

        address toSend = target;
        if (toSend == address(0)) toSend = account;

        CertificateDetails memory details = certificate
            .getActiveCertificateDetails(id);

        if (amount > details.unitsRepresented) {
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

        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
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

    function executeSetScripRestrictionHooks(
        address certAddress,
        ITransferRestrictionHook[] memory hooks
    ) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).setRestrictionHook(hooks);
    }

    function executeDisableScripForceTransfer(address certAddress) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).disableForceTransfer();
    }

    function executeDisableScripForceBurn(address certAddress) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).disableForceBurn();
    }

    function executeDisableScripFreeze(address certAddress) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).disableFreeze();
    }

    function executeSetScripFrozen(
        address certAddress,
        address account,
        bool isFrozen
    ) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).setFrozen(
            account,
            isFrozen
        );
    }

    function executeForceScripTransfer(
        address certAddress,
        address from,
        address to,
        uint256 amount
    ) external {
        ICyberScrip(_getScripifiedCertOrRevert(certAddress)).forceTransfer(
            from,
            to,
            amount
        );
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
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
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
        returns (ICyberCertPrinter cert, uint256 tokenId)
    {
        _requireCompanyDetailsSet();
        cert = ICyberCertPrinter(certAddress);
        tokenId = cert.totalSupply();
        cert.safeMintAndAssign(to, owner, tokenId, details, ownerName);
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
        IssuanceManagerData storage ds = issuanceManagerStorage();
        CertScripUnitPool storage pool = ds.certScripUnitPools[certAddress];
        CertScripState storage certState = ds.certScripStates[certAddress][tokenId];

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
        CertScripState storage certState = getCertScripState(certAddress, tokenId);
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
            _zeroAllVaultNominals(certAddress);
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
            _zeroAllVaultNominals(certAddress);
        }
    }

    function _getScripifiedCertOrRevert(
        address certAddress
    ) internal view returns (address scripifiedCert) {
        scripifiedCert = getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();
    }

    function _zeroAllVaultNominals(address certAddress) internal {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        uint256 supply = certificate.totalSupply();
        for (uint256 i = 0; i < supply; i++) {
            uint256 tokenId = certificate.tokenByIndex(i);
            getCertScripState(certAddress, tokenId).vaultNominalShares = 0;
        }
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        pool.totalNominalShares = 0;
    }
}
