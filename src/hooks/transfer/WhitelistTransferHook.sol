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

pragma solidity ^0.8.28;

import "./BaseTransferHook.sol";

/// @title WhitelistTransferHook
/// @notice Transfer hook that restricts transfers to whitelisted addresses
contract WhitelistTransferHook is BaseTransferHook {
    // Mapping of whitelisted addresses
    mapping(address => bool) public whitelisted;
    
    // Event for when addresses are added/removed from whitelist
    event WhitelistUpdated(address indexed account, bool whitelisted);
    
    constructor(address _auth) BaseTransferHook(_auth) {}
    
    /// @notice Add or remove addresses from the whitelist
    /// @param account The address to update
    /// @param _whitelisted Whether to whitelist or remove from whitelist
    function setWhitelisted(address account, bool _whitelisted) external onlyAdmin {
        whitelisted[account] = _whitelisted;
        emit WhitelistUpdated(account, _whitelisted);
    }
    
    /// @notice Batch add or remove addresses from the whitelist
    /// @param accounts Array of addresses to update
    /// @param _whitelisted Whether to whitelist or remove from whitelist
    function batchSetWhitelisted(address[] calldata accounts, bool _whitelisted) external onlyAdmin {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = _whitelisted;
            emit WhitelistUpdated(accounts[i], _whitelisted);
        }
    }
    
    /// @notice Check if a transfer is allowed based on whitelist
    /// @param from The address tokens are being transferred from
    /// @param to The address tokens are being transferred to
    /// @param tokenId The ID of the token being transferred
    /// @param data Additional data passed to the hook (not used in this implementation)
    /// @return allowed Whether the transfer is allowed
    /// @return reason The reason if the transfer is not allowed
    function _checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal view override returns (bool allowed, string memory reason) {
        // Allow transfers from whitelisted addresses to whitelisted addresses
        if (whitelisted[from] && whitelisted[to]) {
            return (true, "");
        }
        
        return (false, "Address not whitelisted");
    }
} 