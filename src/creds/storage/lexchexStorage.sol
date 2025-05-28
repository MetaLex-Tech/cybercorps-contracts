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

All rights reserved.*/

pragma solidity 0.8.28;

import "../../interfaces/ICyberAgreementRegistry.sol";

struct Accreditation {
    bytes32 agreementId;
    address registryAddress;
    string name;
    string entityType;
    string jurisdiction;
    string contact;
    uint256 issuanceDate;
    uint256 expiryDate;
    string voided;
    string[] portfolio;
    bytes signature;
}

library LeXcheXStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("metalex.lexchex.storage.v1");

    // Main storage layout struct
    struct LeXcheXData {
        // Token data
        mapping(uint256 => Accreditation) accreditations;
        uint256 supply;
        string certificateUri;
        
        // Contract configuration
        address auth;
        bool initialized;
    }

    // Returns the storage layout
    function lexchexStorage() internal pure returns (LeXcheXData storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // Internal getters for complex types
    function getAccreditation(uint256 tokenId) internal view returns (Accreditation storage) {
        return lexchexStorage().accreditations[tokenId];
    }

    function getSupply() internal view returns (uint256) {
        return lexchexStorage().supply;
    }

    function getCertificateUri() internal view returns (string memory) {
        return lexchexStorage().certificateUri;
    }

    // Setters
    function setAccreditation(uint256 tokenId, Accreditation memory accreditation) internal {
        lexchexStorage().accreditations[tokenId] = accreditation;
    }

    function incrementSupply() internal returns (uint256) {
        LeXcheXData storage s = lexchexStorage();
        uint256 current = s.supply;
        s.supply = current + 1;
        return current;
    }

    function setCertificateUri(string memory _certificateUri) internal {
        lexchexStorage().certificateUri = _certificateUri;
    }

    function setAuth(address _auth) internal {
        lexchexStorage().auth = _auth;
    }

    function setInitialized(bool _initialized) internal {
        lexchexStorage().initialized = _initialized;
    }

    function isInitialized() internal view returns (bool) {
        return lexchexStorage().initialized;
    }

    function getAuth() internal view returns (address) {
        return lexchexStorage().auth;
    }

    function deleteAccreditation(uint256 tokenId) internal {
        delete lexchexStorage().accreditations[tokenId];
    }
}
