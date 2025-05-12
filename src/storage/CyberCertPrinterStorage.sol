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

import "../CyberCorpConstants.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import "./extensions/ICertificateExtension.sol";

struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmountUSD;
    uint256 issuerUSDValuationAtTimeOfInvestment;
    uint256 unitsRepresented;
    string legalDetails;
    bytes extensionData;
}

struct Endorsement {
    address endorser;
    uint256 timestamp;
    bytes signatureHash;
    address registry;  //optional
    bytes32 agreementId; //optional
    address endorsee;
    string endorseeName;
}

struct OwnerDetails {
    string name;
    address ownerAddress;
}

library CyberCertPrinterStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.cert.printer.storage.v1");

    // Main storage layout struct
    struct CyberCertStorage {
        // Token data
        mapping(uint256 => CertificateDetails) certificateDetails;
        mapping(uint256 => Endorsement[]) endorsements;
        mapping(uint256 => OwnerDetails) owners;
        mapping(uint256 => SecurityStatus) securityStatus;
        mapping(uint256 => string[]) certLegend;
        // Restriction hooks
        mapping(uint256 => ITransferRestrictionHook) restrictionHooksById;
        ITransferRestrictionHook globalRestrictionHook;
        address extension;
        // Contract configuration - making these public
        address issuanceManager;
        SecurityClass securityType;
        SecuritySeries securitySeries;
        string certificateUri;
        string[] defaultLegend;
        bool transferable;
        bool endorsementRequired;
        
    }

    // Returns the storage layout
    function cyberCertStorage() internal pure returns (CyberCertStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // Internal getters for complex types
    function getCertificateDetails(uint256 tokenId) internal view returns (CertificateDetails storage) {
        return cyberCertStorage().certificateDetails[tokenId];
    }

    function getEndorsements(uint256 tokenId) internal view returns (Endorsement[] storage) {
        return cyberCertStorage().endorsements[tokenId];
    }

    function getOwnerDetails(uint256 tokenId) internal view returns (OwnerDetails storage) {
        return cyberCertStorage().owners[tokenId];
    }

    function getSecurityStatus(uint256 tokenId) internal view returns (SecurityStatus) {
        return cyberCertStorage().securityStatus[tokenId];
    }

    // Setters
    function setCertificateDetails(uint256 tokenId, CertificateDetails memory details) internal {
        cyberCertStorage().certificateDetails[tokenId] = details;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory endorsement) internal {
        cyberCertStorage().endorsements[tokenId].push(endorsement);
    }

    function setOwnerDetails(uint256 tokenId, OwnerDetails memory details) internal {
        cyberCertStorage().owners[tokenId] = details;
    }

    function setSecurityStatus(uint256 tokenId, SecurityStatus status) internal {
        cyberCertStorage().securityStatus[tokenId] = status;
    }

    // Configuration setters
    function setIssuanceManager(address _issuanceManager) internal {
        cyberCertStorage().issuanceManager = _issuanceManager;
    }

    function setCertificateUri(string memory _certificateUri) internal {
        cyberCertStorage().certificateUri = _certificateUri;
    }

    function setTransferable(bool _transferable) internal {
        cyberCertStorage().transferable = _transferable;
    }

    function setRestrictionHook(uint256 tokenId, ITransferRestrictionHook hook) internal {
        cyberCertStorage().restrictionHooksById[tokenId] = hook;
    }

    function setGlobalRestrictionHook(ITransferRestrictionHook hook) internal {
        cyberCertStorage().globalRestrictionHook = hook;
    }

    // Update the getter/setter for defaultLegend
    function getDefaultLegend() internal view returns (string[] memory) {
        return cyberCertStorage().defaultLegend;
    }

    function setDefaultLegend(string[] memory _defaultLegend) internal {
        cyberCertStorage().defaultLegend = _defaultLegend;
    }

    // Extension management
    function setExtension(uint256 tokenId, address extension) internal {
        cyberCertStorage().extension = extension;
    }

    function getExtension(uint256 tokenId) internal view returns (address) {
        return cyberCertStorage().extension;
    }

    function _getExtensionData(uint256 tokenId) internal view returns (bytes memory) {
        return cyberCertStorage().certificateDetails[tokenId].extensionData;
    }

} 