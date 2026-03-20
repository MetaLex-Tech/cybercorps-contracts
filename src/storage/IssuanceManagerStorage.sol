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
import "../interfaces/ITransferRestrictionHook.sol";
import "./CyberCertPrinterStorage.sol";

library IssuanceManagerStorage {
    error ConditionCheckFailed();
    error ScripifiedCertNotAllowed();
    error ScripRatioRemainder();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    error ScripifyOverMax();
    error RecertificationApprovalRequired();
    error CompanyDetailsNotSet();
    error InvalidScripRatio();

    /// @dev Ray precision for vault price-per-share (assets per 1 nominal share, 1e27 = 1.0).
    uint256 internal constant VAULT_RAY = 1e27;

    event ScripifiedCert(
        address indexed certAddress,
        uint256 indexed id,
        address indexed scripifiedCert,
        uint256 amount
    );
    event CertificateCreated(
        uint256 indexed tokenId,
        address indexed certificate,
        uint256 amount,
        uint256 cap,
        CertificateDetails details,
        string tokenURI
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

    function getPrinterAt(uint256 index) internal view returns (address) {
        return issuanceManagerStorage().printers[index];
    }

    function getPrintersCount() internal view returns (uint256) {
        return issuanceManagerStorage().printers.length;
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

    /// @dev Sum of scrip-token-equivalent held by `account` across all certs where they are legal owner.
    ///      Transfers of ERC20 do not change legal-owner vault claims.
    function getScripPoolUserAmount(
        address certAddress,
        address account
    ) internal view returns (uint256 scripEquivalent) {
        (uint256 num, uint256 den) = _getScripRatioOrDefault(certAddress);
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        uint256 supply = certificate.totalSupply();
        for (uint256 i = 0; i < supply; i++) {
            uint256 tokenId = certificate.tokenByIndex(i);
            if (certificate.legalOwnerOf(tokenId) != account) {
                continue;
            }
            uint256 assetsWad = _assetsOfVaultPosition(certAddress, tokenId);
            if (assetsWad == 0) continue;
            scripEquivalent += (assetsWad / 1e18) * num / den;
        }
    }

    function getScripPoolUserPosition(
        address certAddress,
        address account
    )
        internal
        view
        returns (uint256 recordedAmount, uint256 reductionDebt, uint256 currentAmount)
    {
        recordedAmount = 0;
        reductionDebt = 0;
        currentAmount = getScripPoolUserAmount(certAddress, account);
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
            CertificateDetails memory details
        )
    {
        RecertificationApproval storage approval = getRecertificationApproval(
            certAddress,
            investor
        );
        approved = approval.approved;
        investorName = approval.investorName;
        details = approval.details;
    }

    function setRecertificationApproval(
        address certAddress,
        address investor,
        string memory investorName,
        CertificateDetails memory details
    ) internal {
        issuanceManagerStorage().recertificationApprovals[certAddress][
            investor
        ] = RecertificationApproval({
            approved: true,
            investorName: investorName,
            details: details
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

    function selectRecertToken(
        address certAddress,
        address account
    ) external view returns (RecertSelection memory selection) {
        return _selectRecertToken(certAddress, account);
    }

    function executeCreateCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory details,
        string memory investorName
    ) external returns (uint256 tokenId) {
        (, tokenId, ) = _mintAssignedCert(
            certAddress,
            investor,
            details,
            investorName
        );
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
        string memory tokenURI;
        (cert, tokenId, tokenURI) = _mintAssignedCert(
            certAddress,
            investor,
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

        _emitCertificateCreated(tokenId, certAddress, details, tokenURI);
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
        if (amount == 0) revert ConditionCheckFailed();

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
        if (certificate.isVoided(id)) revert ConditionCheckFailed();
        if (certificate.legalOwnerOf(id) != account)
            revert ConditionCheckFailed();

        address toSend = target;
        if (toSend == address(0)) toSend = account;

        CertificateDetails memory details = certificate
            .getActiveCertificateDetails(id);
        // Treat unitsRepresented as 18-dec fixed point internally.
        uint256 amountWad = amount * 1e18;
        if (amountWad > details.unitsRepresented) revert ConditionCheckFailed();

        (uint256 numerator, uint256 denominator) = _getScripRatioOrDefault(
            certAddress
        );
        uint256 scripAmount = amount * numerator;
        if (scripAmount % denominator != 0) revert ScripRatioRemainder();
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
        if (currentScripifiedUnits + amountWad > certState.maxUnitsRepresented) {
            revert ScripifyOverMax();
        }

        _depositCertScripUnits(certAddress, id, amountWad);
        details.unitsRepresented = details.unitsRepresented - amountWad;
        certificate.updateCertificateDetails(id, details);
        ICyberScrip(scripifiedCert).mint(toSend, scripAmount);
        emit ScripifiedCert(certAddress, id, scripifiedCert, amount);
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
        if (units % numerator != 0) revert ScripRatioRemainder();
        units = units / numerator;
        uint256 unitsWad = units * 1e18;

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
        RecertSelection memory selection = _selectRecertToken(
            certAddress,
            account
        );
        bool requiresApproval = !selection.foundActive;
        RecertificationApproval memory approval;
        if (requiresApproval) {
            (
                bool approved,
                string memory investorName,
                CertificateDetails memory approvedDetails
            ) = getRecertificationApprovalData(certAddress, account);
            if (!approved) revert RecertificationApprovalRequired();
            approval.approved = approved;
            approval.investorName = investorName;
            approval.details = approvedDetails;
        }

        if (selection.foundActive) {
            // Redeem vault shares for this certificate up to pool claim; burn nominals. Conversion
            // above claim is still backed by burned scrip, so dilute remaining pool pro-rata via
            // _withdrawVaultAssets (same economics as excess scrip burning without a cert position).
            uint256 claimWad = _assetsOfVaultPosition(
                certAddress,
                selection.activeTokenId
            );
            uint256 fromVaultWad = unitsWad < claimWad ? unitsWad : claimWad;
            uint256 redeemedWad;
            if (fromVaultWad > 0) {
                redeemedWad = _redeemVaultForCert(
                    certAddress,
                    selection.activeTokenId,
                    fromVaultWad
                );
            }
            if (unitsWad > redeemedWad) {
                _withdrawVaultAssets(certAddress, unitsWad - redeemedWad);
            }
        } else {
            // No active cert: socialized withdrawal from the shared vault (nominals unchanged).
            _withdrawVaultAssets(certAddress, unitsWad);
        }
        ICyberScrip(scripifiedCert).burnFrom(account, amount);

        if (selection.foundActive) {
            CertificateDetails memory activeDetails = certificate
                .getActiveCertificateDetails(selection.activeTokenId);
            activeDetails.unitsRepresented =
                activeDetails.unitsRepresented +
                unitsWad;
            certificate.updateCertificateDetails(
                selection.activeTokenId,
                activeDetails
            );
            _setCertMaxFromCurrent(
                certAddress,
                selection.activeTokenId,
                activeDetails.unitsRepresented
            );
        } else {
            CertificateDetails memory details = approval.details;
            details.unitsRepresented = unitsWad;
            uint256 createdTokenId = IIssuanceManager(address(this))
                .createCertAndAssignWithName(
                    certAddress,
                    account,
                    details,
                    approval.investorName
                );
            clearRecertificationApproval(certAddress, account);
            _setCertMaxFromCurrent(
                certAddress,
                createdTokenId,
                details.unitsRepresented
            );
        }
    }

    function executeForceScripBurn(
        address certAddress,
        address account,
        uint256 amount
    ) external {
        if (amount == 0) revert ConditionCheckFailed();

        address scripifiedCert = getScripifiedCert(certAddress);
        if (scripifiedCert == address(0)) revert ScripifiedCertNotAllowed();

        (uint256 numerator, uint256 denominator) = _getScripRatioOrDefault(
            certAddress
        );
        uint256 units = amount * denominator;
        if (units % numerator != 0) revert ScripRatioRemainder();
        units = units / numerator;
        uint256 unitsWad = units * 1e18;

        _withdrawVaultAssets(certAddress, unitsWad);
        ICyberScrip(scripifiedCert).forceBurn(account, amount);
    }

    function _selectRecertToken(
        address certAddress,
        address account
    ) internal view returns (RecertSelection memory selection) {
        ICyberCertPrinter certificate = ICyberCertPrinter(certAddress);
        uint256 supply = certificate.totalSupply();

        for (uint256 i = 0; i < supply; i++) {
            uint256 tokenId = certificate.tokenByIndex(i);
            if (certificate.legalOwnerOf(tokenId) != account) continue;
            if (certificate.isVoided(tokenId)) continue;
            selection.foundActive = true;
            selection.activeTokenId = tokenId;
            return selection;
        }
    }

    function _mintAssignedCert(
        address certAddress,
        address investor,
        CertificateDetails memory details,
        string memory investorName
    )
        internal
        returns (ICyberCertPrinter cert, uint256 tokenId, string memory tokenURI)
    {
        _requireCompanyDetailsSet();
        cert = ICyberCertPrinter(certAddress);
        tokenId = cert.totalSupply();
        cert.safeMintAndAssign(investor, tokenId, details, investorName);
        tokenURI = cert.tokenURI(tokenId);
        _emitCertificateCreated(tokenId, certAddress, details, tokenURI);
    }

    function _requireCompanyDetailsSet() internal view {
        if (bytes(ICyberCorp(getCORP()).cyberCORPName()).length == 0) {
            revert CompanyDetailsNotSet();
        }
    }

    function _emitCertificateCreated(
        uint256 tokenId,
        address certAddress,
        CertificateDetails memory details,
        string memory tokenURI
    ) internal {
        emit CertificateCreated(
            tokenId,
            certAddress,
            details.investmentAmountUSD,
            details.issuerUSDValuationAtTimeOfInvestment,
            details,
            tokenURI
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
        if (sharesMinted == 0) revert ConditionCheckFailed();

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
        if (S == 0 || T == 0) revert ConditionCheckFailed();

        uint256 claimWad = certState.vaultNominalShares * T / S;
        if (assetsWad > claimWad) revert ConditionCheckFailed();

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
        if (assetsOutWad > pool.totalAssetsWad) revert ConditionCheckFailed();
        if (pool.totalAssetsWad == 0) revert ConditionCheckFailed();

        pool.totalAssetsWad -= assetsOutWad;
        if (pool.totalAssetsWad == 0) {
            _zeroAllVaultNominals(certAddress);
        }
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
