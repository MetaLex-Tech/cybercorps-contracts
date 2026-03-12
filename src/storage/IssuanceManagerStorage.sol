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

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../interfaces/ICondition.sol";
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICyberScrip.sol";
import "../interfaces/IIssuanceManager.sol";
import "./CyberCertPrinterStorage.sol";

library IssuanceManagerStorage {
    error ConditionCheckFailed();
    error ScripifiedCertNotAllowed();
    error ScripRatioRemainder();
    error ScripToCertMinimumNotMet();
    error ScripifyNotWhitelisted();
    error ScripifyOverMax();

    uint256 internal constant ACC_REDUCTION_PRECISION = 1e18;

    event ScripifiedCert(
        address indexed certAddress,
        uint256 indexed id,
        address indexed scripifiedCert,
        uint256 amount
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
        mapping(address => ScripPoolState) scripPoolStates;
        mapping(address => mapping(address => ScripUserInfo)) scripPoolUsers;
    }

    struct ScripRatio {
        uint256 numerator;
        uint256 denominator;
    }

    struct RecertSelection {
        bool foundActive;
        uint256 activeTokenId;
        bool foundVoided;
        uint256 voidedTokenId;
    }

    struct CertScripState {
        uint256 amount;
        uint256 reductionDebt;
        uint256 maxUnitsRepresented;
    }

    struct ScripPoolState {
        uint256 totalTrackedScrip;
        uint256 accReductionPerShare;
    }

    struct CertScripUnitPool {
        uint256 totalScripifiedUnits;
        uint256 accReductionPerShare;
    }

    struct ScripUserInfo {
        uint256 amount;
        uint256 reductionDebt;
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

    function getScripPoolState(
        address certAddress
    ) internal view returns (ScripPoolState storage) {
        return issuanceManagerStorage().scripPoolStates[certAddress];
    }

    function getScripPoolUserInfo(
        address certAddress,
        address account
    ) internal view returns (ScripUserInfo storage) {
        return issuanceManagerStorage().scripPoolUsers[certAddress][account];
    }

    function getScripPoolUserAmount(
        address certAddress,
        address account
    ) internal view returns (uint256) {
        ScripPoolState storage pool = getScripPoolState(certAddress);
        ScripUserInfo storage user = getScripPoolUserInfo(certAddress, account);
        return _currentAmount(user.amount, user.reductionDebt, pool.accReductionPerShare);
    }

    function getScripPoolUserPosition(
        address certAddress,
        address account
    )
        internal
        view
        returns (uint256 recordedAmount, uint256 reductionDebt, uint256 currentAmount)
    {
        ScripUserInfo storage user = getScripPoolUserInfo(certAddress, account);
        recordedAmount = user.amount;
        reductionDebt = user.reductionDebt;
        currentAmount = getScripPoolUserAmount(certAddress, account);
    }

    function getScripPoolTotals(
        address certAddress
    )
        internal
        view
        returns (uint256 totalTrackedScrip, uint256 accReductionPerShare)
    {
        ScripPoolState storage pool = getScripPoolState(certAddress);
        totalTrackedScrip = pool.totalTrackedScrip;
        accReductionPerShare = pool.accReductionPerShare;
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
        CertScripState storage certState = getCertScripState(certAddress, id);
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        return
            _currentAmount(
                certState.amount,
                certState.reductionDebt,
                pool.accReductionPerShare
            );
    }

    function selectRecertToken(
        address certAddress,
        address account
    ) external view returns (RecertSelection memory selection) {
        return _selectRecertToken(certAddress, account);
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
        if (amount > details.unitsRepresented) revert ConditionCheckFailed();

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
        if (currentScripifiedUnits + amount > certState.maxUnitsRepresented) {
            revert ScripifyOverMax();
        }

        _depositCertScripUnits(certAddress, id, amount);
        details.unitsRepresented = details.unitsRepresented - amount;
        certificate.updateCertificateDetails(id, details);
        _depositScripPool(certAddress, account, scripAmount);
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

        _reduceScripPool(certAddress, amount);
        _reduceCertScripUnitsPool(certAddress, units);
        ICyberScrip(scripifiedCert).burnFrom(account, amount);

        if (selection.foundActive) {
            CertificateDetails memory activeDetails = certificate
                .getActiveCertificateDetails(selection.activeTokenId);
            activeDetails.unitsRepresented = activeDetails.unitsRepresented + units;
            certificate.updateCertificateDetails(
                selection.activeTokenId,
                activeDetails
            );
            _setCertMaxFromCurrent(
                certAddress,
                selection.activeTokenId,
                activeDetails.unitsRepresented
            );
        } else if (selection.foundVoided) {
            CertificateDetails memory voidedDetails = certificate
                .getActiveCertificateDetails(selection.voidedTokenId);
            voidedDetails.unitsRepresented = units;
            certificate.updateCertificateDetails(
                selection.voidedTokenId,
                voidedDetails
            );
            certificate.unvoidCert(selection.voidedTokenId);
            _setCertMaxFromCurrent(
                certAddress,
                selection.voidedTokenId,
                voidedDetails.unitsRepresented
            );

            address certCustodian = certificate.ownerOf(selection.voidedTokenId);
            if (certCustodian != account) {
                Endorsement memory recertEndorsement = Endorsement({
                    endorser: certCustodian,
                    timestamp: block.timestamp,
                    signatureHash: "",
                    registry: address(0),
                    agreementId: bytes32(0),
                    endorsee: account,
                    endorseeName: ""
                });
                certificate.endorseAndTransfer(
                    selection.voidedTokenId,
                    recertEndorsement,
                    certCustodian,
                    account
                );
            }
        } else {
            CertificateDetails memory details = _buildRecertDetails(
                certificate,
                units
            );
            uint256 createdTokenId = IIssuanceManager(address(this)).createCertAndAssign(
                certAddress,
                account,
                details
            );
            _setCertMaxFromCurrent(certAddress, createdTokenId, details.unitsRepresented);
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

        _reduceScripPool(certAddress, amount);
        _reduceCertScripUnitsPool(certAddress, units);
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

            if (!certificate.isVoided(tokenId)) {
                selection.foundActive = true;
                selection.activeTokenId = tokenId;
                return selection;
            }

            if (!selection.foundVoided) {
                selection.foundVoided = true;
                selection.voidedTokenId = tokenId;
            }
        }
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

    function _buildRecertDetails(
        ICyberCertPrinter certificate,
        uint256 units
    ) internal view returns (CertificateDetails memory details) {
        details.unitsRepresented = units;

        uint256 supply = certificate.totalSupply();
        if (supply == 0) {
            return details;
        }

        // Use the latest minted certificate as the best available template for recert fields.
        uint256 templateTokenId = certificate.tokenByIndex(supply - 1);
        CertificateDetails memory template = certificate.getCertificateDetails(
            templateTokenId
        );

        details.signingOfficerName = template.signingOfficerName;
        details.signingOfficerTitle = template.signingOfficerTitle;
        details.issuerUSDValuationAtTimeOfInvestment = template
            .issuerUSDValuationAtTimeOfInvestment;
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

    function _depositScripPool(
        address certAddress,
        address account,
        uint256 scripAmount
    ) internal {
        ScripPoolState storage pool = getScripPoolState(certAddress);
        ScripUserInfo storage user = getScripPoolUserInfo(certAddress, account);
        _syncUserScripPoolPosition(certAddress, account);
        pool.totalTrackedScrip = pool.totalTrackedScrip + scripAmount;
        user.amount = user.amount + scripAmount;
        user.reductionDebt =
            (user.amount * pool.accReductionPerShare) /
            ACC_REDUCTION_PRECISION;
    }

    function _reduceScripPool(address certAddress, uint256 burnedScripAmount) internal {
        ScripPoolState storage pool = getScripPoolState(certAddress);
        if (burnedScripAmount > pool.totalTrackedScrip) revert ConditionCheckFailed();
        if (pool.totalTrackedScrip == 0) revert ConditionCheckFailed();
        pool.accReductionPerShare =
            pool.accReductionPerShare +
            ((burnedScripAmount * ACC_REDUCTION_PRECISION) / pool.totalTrackedScrip);
        pool.totalTrackedScrip = pool.totalTrackedScrip - burnedScripAmount;
    }

    function _depositCertScripUnits(
        address certAddress,
        uint256 tokenId,
        uint256 units
    ) internal {
        IssuanceManagerData storage ds = issuanceManagerStorage();
        CertScripUnitPool storage pool = ds.certScripUnitPools[certAddress];
        CertScripState storage certState = ds.certScripStates[certAddress][tokenId];
        _syncCertScripPosition(certAddress, tokenId);
        pool.totalScripifiedUnits = pool.totalScripifiedUnits + units;
        certState.amount = certState.amount + units;
        certState.reductionDebt =
            (certState.amount * pool.accReductionPerShare) /
            ACC_REDUCTION_PRECISION;
    }

    function _reduceCertScripUnitsPool(
        address certAddress,
        uint256 burnedUnits
    ) internal {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        if (burnedUnits > pool.totalScripifiedUnits) revert ConditionCheckFailed();
        if (pool.totalScripifiedUnits == 0) revert ConditionCheckFailed();
        pool.accReductionPerShare =
            pool.accReductionPerShare +
            ((burnedUnits * ACC_REDUCTION_PRECISION) / pool.totalScripifiedUnits);
        pool.totalScripifiedUnits = pool.totalScripifiedUnits - burnedUnits;
    }

    function _syncUserScripPoolPosition(address certAddress, address account) internal {
        ScripPoolState storage pool = getScripPoolState(certAddress);
        ScripUserInfo storage user = getScripPoolUserInfo(certAddress, account);
        user.amount = _currentAmount(
            user.amount,
            user.reductionDebt,
            pool.accReductionPerShare
        );
        user.reductionDebt =
            (user.amount * pool.accReductionPerShare) /
            ACC_REDUCTION_PRECISION;
    }

    function _syncCertScripPosition(address certAddress, uint256 tokenId) internal {
        CertScripUnitPool storage pool = issuanceManagerStorage().certScripUnitPools[
            certAddress
        ];
        CertScripState storage certState = getCertScripState(certAddress, tokenId);
        certState.amount = _currentAmount(
            certState.amount,
            certState.reductionDebt,
            pool.accReductionPerShare
        );
        certState.reductionDebt =
            (certState.amount * pool.accReductionPerShare) /
            ACC_REDUCTION_PRECISION;
    }

    function _currentAmount(
        uint256 amount,
        uint256 reductionDebt,
        uint256 accReductionPerShare
    ) internal pure returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 accruedReduction = (amount * accReductionPerShare) /
            ACC_REDUCTION_PRECISION;
        if (accruedReduction <= reductionDebt) {
            return amount;
        }

        uint256 pendingReduction = accruedReduction - reductionDebt;
        if (pendingReduction >= amount) {
            return 0;
        }
        return amount - pendingReduction;
    }
}
