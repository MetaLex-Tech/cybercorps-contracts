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

import "../interfaces/IIssuanceManager.sol";

/// @title DealManagerStorage
/// @notice Storage library for the DealManager contract that handles persistent data storage
/// @dev Uses the unstructured storage pattern to manage deal-related data
library DealManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.deal.manager.storage.v1");

    /// @notice Main storage layout struct that holds all deal manager data
    /// @dev Uses unstructured storage pattern to avoid storage collisions
    struct DealManagerData {
        /// @notice Reference to the issuance manager contract
        IIssuanceManager issuanceManager;
        address upgradeFactory;
        
        /// @notice Mapping from agreement IDs to their counter party values
        mapping(bytes32 => string[]) counterPartyValues;
    }

    /// @notice Retrieves the storage reference for the DealManagerData struct
    /// @dev Uses assembly to compute the storage position
    /// @return ds Reference to the DealManagerData struct in storage
    function dealManagerStorage() internal pure returns (DealManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// @notice Retrieves counter party values for a specific agreement
    /// @dev Accesses the storage mapping directly
    /// @param agreementId The unique identifier of the agreement
    /// @return string[] Array of counter party values
    function getCounterPartyValues(bytes32 agreementId) internal view returns (string[] storage) {
        return dealManagerStorage().counterPartyValues[agreementId];
    }

    /// @notice Retrieves the current issuance manager
    /// @dev Returns the stored issuance manager reference
    /// @return IIssuanceManager The current issuance manager contract
    function getIssuanceManager() internal view returns (IIssuanceManager) {
        return dealManagerStorage().issuanceManager;
    }

    /// @notice Sets counter party values for a specific agreement
    /// @dev Updates the storage mapping with new values
    /// @param agreementId The unique identifier of the agreement
    /// @param values Array of counter party values to store
    function setCounterPartyValues(bytes32 agreementId, string[] memory values) internal {
        dealManagerStorage().counterPartyValues[agreementId] = values;
    }

    /// @notice Updates the issuance manager reference
    /// @dev Sets a new issuance manager contract address
    /// @param _issuanceManager Address of the new issuance manager contract
    function setIssuanceManager(address _issuanceManager) internal {
        dealManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }

    function setUpgradeFactory(address _upgradeFactory) internal {
        dealManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() external view returns (address) {
        return dealManagerStorage().upgradeFactory;
    }
} 