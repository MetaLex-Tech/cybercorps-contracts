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

import {ScopedDataLayerLib} from "./ScopedDataLayerLib.sol";
import "./SAFTExtensionV2.sol";

/// @notice Series-wide SAFT terms, encoded as the printer's seriesData.
struct SAFTSeriesData {
    string seriesName;
    uint256 tokenGenerationEventDate;
    string[] governingDocumentURIs;
    string customProvisions;
}

/// @notice The whole certificate: the series terms and the cert terms, side by side. The two scopes
/// hold different fields, so this is a pairing and not a merge.
struct SAFTResolvedData {
    SAFTSeriesData series;
    SAFTDataV2 certificate;
}

/// @title SAFTExtensionV3 - SAFT certificate extension with typed series-scope data
/// @author MetaLeX Labs, Inc.
contract SAFTExtensionV3 is SAFTExtensionV2 {
    bytes32 public constant EXTENSION_TYPE_V3 = keccak256("SAFT_V3");

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE_V3 || extensionType == EXTENSION_TYPE;
    }

    function decodeSeriesExtensionData(bytes memory data) external pure returns (SAFTSeriesData memory) {
        return abi.decode(data, (SAFTSeriesData));
    }

    function encodeSeriesExtensionData(SAFTSeriesData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    /// @notice Announces the resolved-render path to `CertificateUriBuilder`.
    function supportsResolvedExtensionData() external pure returns (bool) {
        return true;
    }

    /// @notice The typed whole certificate. A scope with no payload reads back as a blank struct.
    function resolveCert(address printer, uint256 tokenId) public view returns (SAFTResolvedData memory resolved) {
        (bytes memory certData, bytes memory seriesData) = ScopedDataLayerLib.getScopedPayloads(printer, tokenId);
        if (certData.length != 0) resolved.certificate = abi.decode(certData, (SAFTDataV2));
        if (seriesData.length != 0) resolved.series = abi.decode(seriesData, (SAFTSeriesData));
    }

    /// @notice Renders the whole certificate: the cert scope and the series scope in one section.
    /// @dev The cert payload alone is not the whole certificate, so this replaces the per-scope calls.
    ///      A scope with no payload is left out rather than rendered blank.
    function getResolvedExtensionURI(address printer, uint256 tokenId) external view returns (string memory) {
        (bytes memory certData, bytes memory seriesData) = ScopedDataLayerLib.getScopedPayloads(printer, tokenId);
        return string.concat(
            certData.length == 0 ? "" : getExtensionURI(certData),
            _buildSeriesJson(seriesData)
        );
    }

    function _buildSeriesJson(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        SAFTSeriesData memory decoded = abi.decode(data, (SAFTSeriesData));
        return string.concat(
            ', "SAFTSeriesDetails": {"seriesName": "', decoded.seriesName,
            '", "tokenGenerationEventDate": "', _uintToString(decoded.tokenGenerationEventDate),
            '", "customProvisions": "', decoded.customProvisions, '"}'
        );
    }

    function _uintToString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 digits; uint256 temp = value;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) { digits--; buffer[digits] = bytes1(uint8(48 + value % 10)); value /= 10; }
        return string(buffer);
    }
}
