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
import {ShareCertDataLayerLib} from "./ShareCertDataLayerLib.sol";

/// @notice One layer of a `ShareCertData`, with the same six sections. This is the shape a payload is
/// stored in. `ShareCertDataLayerLib.resolve` merges the layers and gives back a whole `ShareCertData`,
/// so a reader keeps one flat shape and never sees an unset section.
///
/// The same struct is stored at three scopes, and each stored copy is one layer: the class payload on
/// the IssuanceManager, the series payload on the printer, and the per-cert payload. The class is the
/// least granular scope. The cert is the most granular. A payload is a plain `abi.encode` of this
/// struct. There is no tag, because a printer binds to one extension at creation.
///
/// A set section resolves by its shape:
///
/// - Single-value sections (`certificateData`, `terms`) overwrite. The most granular layer that sets
///   one wins: cert, then series, then class.
/// - List sections append, from the class to the series to the cert. A layer adds to what its parents
///   give and removes nothing, so a cert payload cannot drop a class restriction.
/// - An overwrite flag makes the list of the layer that sets it replace the lists above it. A flag
///   applies upward only. On the series it drops the class and keeps the cert. On the class it does
///   nothing.
/// - A flag on an unset section does nothing, which keeps a stray flag safe. To clear a section, set
///   an empty list and set the flag.
///
/// The scope of each section is a best guess. Put a section at the scope where it is the same for every
/// cert below it. Override it lower down when one cert is different.

/// @dev Each section is an array because each section is optional. This is `Option<T>` in Solidity: the
/// array holds one element, or it is empty. The struct is equivalent to:
///
/// struct ShareCertDataLayer {
///     Option<CertificateData> certificateData;
///     Option<SeriesTerms> terms;
///     Option<MandatoryConversionTrigger[]> conversionTriggers;
///     Option<SpecialVotingRight[]> votingRights;
///     Option<TransferRestriction[]> transferRestrictions;
///     Option<SplitRecord[]> splitHistory;
///     bool overwriteConversionTriggers;
///     bool overwriteVotingRights;
///     bool overwriteTransferRestrictions;
///     bool overwriteSplitHistory;
/// }
struct ShareCertDataLayer {
    CertificateData[] certificateData;
    SeriesTerms[] terms;
    MandatoryConversionTrigger[][] conversionTriggers;
    SpecialVotingRight[][] votingRights;
    TransferRestriction[][] transferRestrictions;
    SplitRecord[][] splitHistory;
    bool overwriteConversionTriggers;
    bool overwriteVotingRights;
    bool overwriteTransferRestrictions;
    bool overwriteSplitHistory;
}

contract ShareExtensionV3 is ShareExtension {
    bytes32 public constant EXTENSION_TYPE_V3 = keccak256("SHARE_V3");

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE_V3 || extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) public pure override returns (string memory) {
        return super.getExtensionURI(ShareCertDataLayerLib.resolveEncoded("", "", data));
    }

    function decodeExtensionData(bytes memory data) external pure override returns (ShareCertData memory) {
        return ShareCertDataLayerLib.resolve("", "", data);
    }

    function encodeExtensionData(ShareCertData memory data) external pure override returns (bytes memory) {
        return ShareCertDataLayerLib.encodeAsLayer(data);
    }

    function resolveCert(address printer, uint256 tokenId) external view returns (ShareCertData memory) {
        return ShareCertDataLayerLib.resolveCert(printer, tokenId);
    }

    function supportsResolvedExtensionData() external pure returns (bool) {
        return true;
    }

    function getResolvedExtensionURI(address printer, uint256 tokenId) external view returns (string memory) {
        return super.getExtensionURI(ShareCertDataLayerLib.resolveEncoded(printer, tokenId));
    }
}
