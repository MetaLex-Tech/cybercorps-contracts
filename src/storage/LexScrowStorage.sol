/*    .o.                                                                                         
     .888.                                                                                        
    .8"888.                                                                                       
   .8' `888.                                                                                      
  .88ooo8888.                                                                                     
 .8'     `888.                                                                                    
o88o     o8888o                                                                                   
                                                                                                  
                                                                                                  
                                                                                                  
ooo        ooooo               .             oooo                                                 
`88.       .888'             .o8             `888                                                 
 888b     d'888   .ooooo.  .o888oo  .oooo.    888   .ooooo.  oooo    ooo                          
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888  d88' `88b  `88b..8P'                           
 8  `888'   888  888ooo888   888    .oP"888   888  888ooo888    Y888'                             
 8    Y     888  888    .o   888 . d8(  888   888  888    .o  .o8"'88b                            
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888o `Y8bod8P' o88'   888o                          
                                                                                                  
                                                                                                  
                                                                                                  
  .oooooo.                .o8                            .oooooo.                                 
 d8P'  `Y8b              "888                           d8P'  `Y8b                                
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.  
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b 
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
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

import "../interfaces/ICondition.sol";

enum TokenType {
    ERC20,
    ERC721,
    ERC1155
}

enum EscrowStatus {
    PENDING,
    PAID,
    FINALIZED,
    VOIDED
}

struct Token {
    TokenType tokenType;
    address tokenAddress;
    uint256 tokenId;
    uint256 amount;
}

struct Escrow {
    bytes32 agreementId;
    address counterParty;
    Token[] corpAssets;
    Token[] buyerAssets;
    bytes signature;
    uint256 expiry;
    EscrowStatus status;
}

library LexScrowStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.lexscrow.storage.v1");

    // Main storage layout struct
    struct LexScrowData {
        address CORP;
        address DEAL_REGISTRY;
        mapping(bytes32 => Escrow) escrows;
        mapping(bytes32 => ICondition[]) conditionsByEscrow;
    }

    // Returns the storage layout
    function lexScrowStorage() internal pure returns (LexScrowData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getCorp() internal view returns (address) {
        return lexScrowStorage().CORP;
    }

    function getDealRegistry() internal view returns (address) {
        return lexScrowStorage().DEAL_REGISTRY;
    }

    function getEscrow(bytes32 agreementId) internal view returns (Escrow storage) {
        return lexScrowStorage().escrows[agreementId];
    }

    function getConditionsByEscrow(bytes32 agreementId) internal view returns (ICondition[] storage) {
        return lexScrowStorage().conditionsByEscrow[agreementId];
    }

    // Setters
    function setCorp(address _corp) internal {
        lexScrowStorage().CORP = _corp;
    }

    function setDealRegistry(address _dealRegistry) internal {
        lexScrowStorage().DEAL_REGISTRY = _dealRegistry;
    }

    function setEscrow(bytes32 agreementId, Escrow memory escrow) internal {
        lexScrowStorage().escrows[agreementId] = escrow;
    }

    function addConditionToEscrow(bytes32 agreementId, ICondition condition) internal {
        lexScrowStorage().conditionsByEscrow[agreementId].push(condition);
    }

    function removeConditionFromEscrow(bytes32 agreementId, uint256 index) internal {
        ICondition[] storage conditions = lexScrowStorage().conditionsByEscrow[agreementId];
        require(index < conditions.length, "Index out of bounds");
        
        for (uint i = index; i < conditions.length - 1; i++) {
            conditions[i] = conditions[i + 1];
        }
        conditions.pop();
    }
} 