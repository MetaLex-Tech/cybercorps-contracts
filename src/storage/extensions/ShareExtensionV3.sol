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

import "./ShareExtension.sol";

/// @title ShareExtensionV3 - share certificate extension with series-scope data
/// @notice The series-scope payload is a `ShareLayer`: any of the six sections of a `ShareCertData` that
/// are the same for every certificate of a series (the printer) can be set once in the printer's
/// `seriesData` instead of being duplicated inside each cert. A bare `SeriesTerms` is still accepted as
/// the series payload, which is the format V3 wrote before layering. The per-cert surface
/// (`ShareCertData`) is inherited from ShareExtension unchanged for backwards compatibility. Supports
/// both the legacy "SHARE" type key and "SHARE_V3".
/// @author MetaLeX Labs, Inc.
contract ShareExtensionV3 is ShareExtension {
    bytes32 public constant EXTENSION_TYPE_V3 = keccak256("SHARE_V3");

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE_V3 || extensionType == EXTENSION_TYPE;
    }

    function supportsSeriesExtensionData() external pure returns (bool) {
        return true;
    }

    /// @dev Reads the bare `SeriesTerms` format only. Read a layered series payload with
    ///      `ShareLayerLib.seriesLayerOf`.
    function decodeSeriesExtensionData(bytes memory data) external pure returns (SeriesTerms memory) {
        return abi.decode(data, (SeriesTerms));
    }

    function encodeSeriesExtensionData(SeriesTerms memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function getSeriesExtensionURI(bytes memory seriesData) external pure returns (string memory) {
        if (seriesData.length == 0) return "";

        // A bare SeriesTerms payload becomes a layer that carries only the terms section, so both
        // formats render through the same path. The output for a bare payload is unchanged.
        return string(
            abi.encodePacked(', "seriesDetails": {', _buildTermsSectionsJson(seriesLayerOf(seriesData)), '}')
        );
    }
}
