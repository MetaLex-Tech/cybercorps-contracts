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

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "./SAFEExtension.sol";

/// @notice Series-wide SAFE terms, encoded as the printer's seriesData.
struct SAFESeriesData {
    string seriesName;
    string[] governingDocumentURIs;
    string customProvisions;
}

/// @title SAFEExtensionV3 - SAFE certificate extension with typed series-scope data
/// @author MetaLeX Labs, Inc.
contract SAFEExtensionV3 is SAFEExtension {
    bytes32 public constant EXTENSION_TYPE_V3 = keccak256("SAFE_V3");

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE_V3 || extensionType == EXTENSION_TYPE;
    }

    function supportsSeriesExtensionData() external pure returns (bool) {
        return true;
    }

    function decodeSeriesExtensionData(bytes memory data) external pure returns (SAFESeriesData memory) {
        return abi.decode(data, (SAFESeriesData));
    }

    function encodeSeriesExtensionData(SAFESeriesData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function getSeriesExtensionURI(bytes memory data) external pure returns (string memory) {
        if (data.length == 0) return "";
        SAFESeriesData memory decoded = abi.decode(data, (SAFESeriesData));
        return string.concat(
            ', "SAFESeriesDetails": {"seriesName": "',
            decoded.seriesName,
            '", "governingDocumentURIs": ',
            _stringArrayToJson(decoded.governingDocumentURIs),
            ', "customProvisions": "',
            decoded.customProvisions,
            '"}'
        );
    }

    function _stringArrayToJson(string[] memory values) private pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) json = string.concat(json, ", ");
            json = string.concat(json, '"', values[i], '"');
        }
        return string.concat(json, "]");
    }
}
