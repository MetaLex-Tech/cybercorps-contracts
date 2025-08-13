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

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../interfaces/ICondition.sol";

library IssuanceManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.issuancemanager.storage.v1");

    // Main storage layout struct
    struct IssuanceManagerData {
        UpgradeableBeacon CyberCertPrinterBeacon;
        address CORP;
        address uriBuilder;
        address upgradeFactory;
        address[] printers;
        UpgradeableBeacon CyberScripBeacon;
        mapping(address => address) scripifiedCert;
        mapping(address => ICondition[]) certToScripConditions;
        mapping(address => ICondition[]) scripToCertConditions;
        // SAFE conversion tracking
        mapping(address => mapping(uint256 => bool)) safeConverted; // safePrinter => tokenId => converted
        mapping(address => mapping(uint256 => address)) safeToEquityPrinter; // safePrinter => tokenId => equity printer
        mapping(address => mapping(uint256 => uint256)) safeToEquityTokenId; // safePrinter => tokenId => new equity tokenId
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
        return issuanceManagerStorage().CyberCertPrinterBeacon;
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
        issuanceManagerStorage().CyberScripBeacon = _beacon;
    }

    function getCyberScripBeacon() internal view returns (UpgradeableBeacon) {
        return issuanceManagerStorage().CyberScripBeacon;
    }

    function setCyberCertPrinterBeacon(UpgradeableBeacon _beacon) internal {
        issuanceManagerStorage().CyberCertPrinterBeacon = _beacon;
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
    function updateBeaconImplementation(address _newImplementation) internal {
        issuanceManagerStorage().CyberCertPrinterBeacon.upgradeTo(_newImplementation);
    }

    function updateCyberScripBeacon(address _newImplementation) internal {
        issuanceManagerStorage().CyberScripBeacon.upgradeTo(_newImplementation);
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

    // ------- SAFE conversion helpers -------
    function isSafeConverted(address safePrinter, uint256 safeTokenId) internal view returns (bool) {
        return issuanceManagerStorage().safeConverted[safePrinter][safeTokenId];
    }

    function setSafeConversion(
        address safePrinter,
        uint256 safeTokenId,
        address equityPrinter,
        uint256 equityTokenId
    ) internal {
        IssuanceManagerData storage s = issuanceManagerStorage();
        s.safeConverted[safePrinter][safeTokenId] = true;
        s.safeToEquityPrinter[safePrinter][safeTokenId] = equityPrinter;
        s.safeToEquityTokenId[safePrinter][safeTokenId] = equityTokenId;
    }

    function getSafeConversion(address safePrinter, uint256 safeTokenId) internal view returns (bool converted, address equityPrinter, uint256 equityTokenId) {
        IssuanceManagerData storage s = issuanceManagerStorage();
        converted = s.safeConverted[safePrinter][safeTokenId];
        equityPrinter = s.safeToEquityPrinter[safePrinter][safeTokenId];
        equityTokenId = s.safeToEquityTokenId[safePrinter][safeTokenId];
    }

    function setCertToScripConditions(address certAddress, ICondition[] memory conditions) internal {
        delete issuanceManagerStorage().certToScripConditions[certAddress];
        for (uint i = 0; i < conditions.length; i++) {
            issuanceManagerStorage().certToScripConditions[certAddress].push(conditions[i]);
        }
    }

    function setScripToCertConditions(address certAddress, ICondition[] memory conditions) internal {
        delete issuanceManagerStorage().scripToCertConditions[certAddress];
        for (uint i = 0; i < conditions.length; i++) {
            issuanceManagerStorage().scripToCertConditions[certAddress].push(conditions[i]);
        }
    }
} 