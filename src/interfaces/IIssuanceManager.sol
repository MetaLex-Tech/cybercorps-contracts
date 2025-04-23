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

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "./ICyberCorp.sol";
import "./ITransferRestrictionHook.sol";
import "../CyberCorpConstants.sol";
import "../storage/CyberCertPrinterStorage.sol";

//Adapter interface for custom auth roles. Allows extensibility for different auth protocols i.e. hats.
interface IIssuanceManager is IERC721, IERC721Enumerable, IERC721Metadata {

    // Events
    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI);
    event HookStatusChanged(bool enabled);
    event WhitelistUpdated(address indexed account, bool whitelisted);

    // Issuance Manager Functions
    function initialize(
        address _auth,
        address _CORP,
        address _CyberCertPrinterImplementation,
        address _uriBuilder
    ) external;

    function createCertPrinter(
        string[] memory _ledger,
        string memory _name,
        string memory _ticker,
        string memory _certificateUri,
        SecurityClass _securityClass,
        SecuritySeries _securitySeries
    ) external returns (address);

    function createCert(
        address certAddress,
        address to,
        CertificateDetails memory _details
    ) external returns (uint256);

    function assignCert(
        address certAddress,
        address from,
        uint256 tokenId,
        address investor,
        CertificateDetails memory _details
    ) external;

    function createCertAndAssign(
        address certAddress,
        address investor,
        CertificateDetails memory _details
    ) external returns (uint256 tokenId);

    function signCertificate(
        address certAddress,
        uint256 tokenId,
        string calldata signatureURI
    ) external;

    function endorseCertificate(
        address certAddress,
        uint256 tokenId,
        address endorser,
        string calldata signatureURI
    ) external;

    function updateCertificateDetails(
        address certAddress,
        uint256 tokenId,
        CertificateDetails memory _details
    ) external;

    function voidCertificate(
        address certAddress,
        uint256 tokenId
    ) external;

    function convert(
        address certAddress,
        uint256 tokenId,
        address convertTo,
        uint256 stockAmount
    ) external;

    function upgradeImplementation(
        address _newImplementation
    ) external;

    function getBeaconImplementation() external view returns (address);

    // Certificate Details Functions
    function getCertificateDetails(
        uint256 tokenId
    ) external view returns (CertificateDetails memory);

    function getEndorsementHistory(
        uint256 tokenId,
        uint256 index
    ) external view returns (
        address endorser,
        string memory signatureURI,
        uint256 timestamp
    );

    // Transfer Hook Functions
    function setRestrictionHook(
        uint256 _id,
        address _hookAddress
    ) external;

    function setGlobalRestrictionHook(
        address hookAddress
    ) external;

    function restrictionHooksById(
        uint256 tokenId
    ) external view returns (ITransferRestrictionHook);

    function globalRestrictionHook() external view returns (ITransferRestrictionHook);

    // Beacon Functions
    function CyberCertPrinterBeacon() external view returns (address);
    function CORP() external view returns (address);
    function uriBuilder() external view returns (address);
    function certifications(uint256) external view returns (address);
    function companyName() external view returns (string memory);
    function companyJurisdiction() external view returns (string memory);
    function AUTH() external view returns (address);
}