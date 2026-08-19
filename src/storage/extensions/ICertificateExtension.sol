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

interface ICertificateExtension {
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool);
    function getExtensionURI(bytes memory data) external view returns (string memory);
}

/// @notice V3 certificate extension: the cert payload alone is not the whole certificate. A section
/// may be stored at the series scope (the printer's `seriesData`) or the class scope
/// (`SecurityClassInfo.classData`), so a reader that renders one scope on its own shows a partial
/// certificate. A V3 extension reaches every scope through the printer, merges them, and renders one
/// complete section.
///
/// Three more functions are expected of every implementation but cannot be declared here, because each
/// version returns its own types and Solidity has no generics. Read them through the concrete type.
///
/// | function                                | returns                                          |
/// |-----------------------------------------|--------------------------------------------------|
/// | `decodeExtensionData(bytes)`            | the shape that version stores on a certificate   |
/// | `encodeExtensionData(<stored shape>)`   | `bytes`                                          |
/// | `resolveCert(address printer, uint256)` | that version's resolved shape                    |
interface ICertificateExtensionV3 is ICertificateExtension {
    function supportsResolvedExtensionData() external pure returns (bool);
    /// @param printer the Ledger Entry Token that holds the cert, and the route to the series and class scopes
    /// @param tokenId the cert to resolve
    function getResolvedExtensionURI(address printer, uint256 tokenId) external view returns (string memory);
}

/// @notice Typed accessors over a fund-interest cert payload. Consumers (holding-period condition,
/// printer backfill/tacking) read and rewrite the payload through these instead of decoding the struct
/// directly, so each deployed extension version owns its own layout: a printer's payload is always decoded
/// by the extension that printer points at. Feature-detect with `supportsExtensionType(FUND_INTEREST)`
/// before casting.
interface IFundInterestExtension is ICertificateExtension {
    function acquisitionDate(bytes memory data) external pure returns (uint64);
    function tackedFromAcquisitionDate(bytes memory data) external pure returns (uint64);
    function withTackedFrom(bytes memory data, uint64 ts) external pure returns (bytes memory);
}
