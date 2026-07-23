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

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";
import "../../libs/auth.sol";

struct SAFTData {
    UnlockStartTimeType unlockStartTimeType;    // enum of different types, can be agreementExecutionTime, tgeTime, or setTime
    uint256 unlockStartTime;                
    uint256 unlockingPeriod; //in interval units
    uint256 unlockingCliffPeriod; // seconds
    uint256 unlockingCliffPercentage; 
    UnlockingIntervalType unlockingIntervalType;
}

contract SAFTExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("SAFT");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;

    //ofset to leave for future upgrades
    uint256[30] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(bytes memory data) external view returns (SAFTData memory) {
        return abi.decode(data, (SAFTData));
    }

    function encodeExtensionData(SAFTData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        SAFTData memory decoded = abi.decode(data, (SAFTData));
        
        string memory json = string(abi.encodePacked(
            ', "SAFTDetails": {',
            '"unlockStartTimeType": "', UnlockStartTimeTypeToString(decoded.unlockStartTimeType),
            '", "unlockStartTime": "', uint256ToString(decoded.unlockStartTime),
            '", "unlockingPeriod": "', uint256ToString(decoded.unlockingPeriod),
            '", "unlockingCliffPeriod": "', uint256ToString(decoded.unlockingCliffPeriod),
            '", "unlockingCliffPercentage": "', uint256ToString(decoded.unlockingCliffPercentage),
            '", "unlockingIntervalType": "', UnlockingIntervalTypeToString(decoded.unlockingIntervalType),
            '"}'
        ));
        
        return json;
    }

        // Helper function to convert uint256 to string
    function uint256ToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        } 
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function UnlockStartTimeTypeToString(UnlockStartTimeType _type) internal pure returns (string memory) {
        if (_type == UnlockStartTimeType.tokenWarrantTime) return "agreementExecutionTime";
        if (_type == UnlockStartTimeType.tgeTime) return "tgeTime";
        if (_type == UnlockStartTimeType.setTime) return "setTime";
        return "Unknown";
    }

    function UnlockingIntervalTypeToString(UnlockingIntervalType _type) internal pure returns (string memory) {
        if (_type == UnlockingIntervalType.blockly) return "blockly";
        if (_type == UnlockingIntervalType.secondly) return "secondly";
        if (_type == UnlockingIntervalType.hourly) return "hourly";
        if (_type == UnlockingIntervalType.daily) return "daily";
        if (_type == UnlockingIntervalType.monthly) return "monthly";
        return "Unknown";
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}