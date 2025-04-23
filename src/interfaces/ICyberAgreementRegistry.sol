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

pragma solidity ^0.8.0;

interface ICyberAgreementRegistry {
    struct Template {
        string legalContractUri;
        string title;
        string[] globalFields;
        string[] partyFields;
    }

    struct ContractData {
        bytes32 templateId;
        string[] globalValues;
        address[] parties;
        uint256 numSignatures;
        bytes32 transactionHash;
    }

    event TemplateCreated(
        bytes32 indexed templateId,
        string indexed title,
        string legalContractUri,
        string[] globalFields,
        string[] signerFields
    );

    event ContractCreated(
        bytes32 indexed contractId,
        bytes32 indexed templateId,
        address[] parties
    );

    event AgreementSigned(
        bytes32 indexed contractId,
        address indexed party,
        uint256 timestamp
    );

    event ContractFullySigned(bytes32 indexed contractId, uint256 timestamp);

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external;

    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes32 secretHash,
        address finalizer, 
        uint256 expiry
    ) external returns (bytes32);

    function signContract(
        bytes32 contractId,
        string[] memory partyValues,
        bool fillUnallocated,
        string memory secret
    ) external;

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature, 
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret 
    ) external;

    //function voidContractFor(bytes32 contractId, address party, bytes calldata signature) public {
    function voidContractFor(
        bytes32 contractId,
        address party,
        bytes calldata signature
    ) external;

    function finalizeContract(bytes32 contractId) external;

    function getParties(bytes32 contractId) external view returns (address[] memory);

    function hasSigned(bytes32 contractId, address signer) external view returns (bool);

    function getSignatureTimestamp(bytes32 contractId, address signer) external view returns (uint256);

    function allPartiesSigned(bytes32 contractId) external view returns (bool);

    function getContractDetails(
        bytes32 contractId
    )
        external
        view
        returns (
            bytes32 templateId,
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory partyFields,
            string[] memory globalValues,
            address[] memory parties,
            string[][] memory partyValues,
            uint256[] memory signedAt,
            uint256 numSignatures,
            bool isComplete,
            bytes32 transactionHash
        );

    function getTemplateDetails(
        bytes32 templateId
    )
        external
        view
        returns (
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory signerFields
        );

    function getSignerValues(
        bytes32 contractId,
        address signer
    ) external view returns (string[] memory signerValues);

    function isVoided(bytes32 contractId) external view returns (bool);

    function getAgreementsForParty(address party) external view returns (bytes32[] memory);

    function getContractJson(bytes32 contractId) external view returns (string memory);

    function getContractTransactionHash(bytes32 contractId) external view returns (bytes32);

    function isFinalized(bytes32 contractId) external view returns (bool);

    function allPartiesFinalized(bytes32 contractId) external view returns (bool);
}
