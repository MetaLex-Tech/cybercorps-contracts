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
import "../CyberCorpConstants.sol";

interface ICyberCertPrinter {
    function initialize(string[] memory defaultLegend, string memory name, string memory ticker, string memory _certificateUri, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external;
    function updateIssuanceManager(address _issuanceManager) external;
    function updateDefaultLegend(string[] memory _ledger) external;
    function defaultLegend() external view returns (string[] memory);
    function setRestrictionHook(uint256 _id, address _hookAddress) external;
    function setGlobalRestrictionHook(address hookAddress) external;
    function safeMint(uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256);
    function setGlobalTransferable(bool _transferable) external;
    function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails memory details) external returns (uint256);
    function assignCert(address from, uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256);
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external;
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) external;
    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external;
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external;
    function burn(uint256 tokenId) external;
    function voidCert(uint256 tokenId) external;
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory);
    function addCertLegend(uint256 tokenId, string memory newLegend) external;
    function removeCertLegendAt(uint256 tokenId, uint256 index) external;
    function addDefaultLegend(string memory newLegend) external;
    function removeDefaultLegendAt(uint256 index) external;
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        address endorser,
        string memory endorseeName,
        address registry,
        bytes32 agreementId,
        uint256 timestamp,
        bytes memory signatureHash,
        address endorsee
    );
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
}
