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

import "./IIssuanceManager.sol";

interface IDealManager {
    function proposeDeal(
        address _certPrinterAddress,
        address _paymentToken,
        uint256 _paymentAmount,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        CertificateDetails memory _certDetails,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (bytes32 agreementId);

    function proposeAndSignDeal(
        address _certPrinterAddress,
        address _paymentToken,
        uint256 _paymentAmount,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        CertificateDetails memory _certDetails,
        address proposer,
        bytes memory signature,
        string[][] memory paryValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (bytes32 agreementId, uint256 certId);


    function finalizeDeal(
        address signer,
        bytes32 _agreementId,
        string[] memory _partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory buyerName,
        string memory secret
    ) external;

    function signDealAndPay(
        address signer,
        bytes32 agreementId,
        bytes memory signature,
        string[] memory partyValues,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) external;
    

    function signAndFinalizeDeal(
        address signer,
        bytes32 _agreementId,
        string[] memory _partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory buyerName,
        string memory secret
    ) external;

    function voidExpiredDeal(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function revokeDeal(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function signToVoid(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager
    ) external;
}
