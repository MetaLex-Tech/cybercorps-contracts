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

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./storage/lexchexStorage.sol";
import "../libs/auth.sol";  
import "../interfaces/ICyberAgreementRegistry.sol";

interface IERC5484 {
    enum BurnAuth {
        IssuerOnly,
        OwnerOnly,
        Both,
        Neither
    }

    event Issued(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        BurnAuth burnAuth
    );

    function burnAuth(uint256 tokenId) external view returns (BurnAuth);
}

contract LeXcheX is Initializable, ERC721EnumerableUpgradeable, BorgAuthACL, IERC5484 {

    BurnAuth BURNAUTH = BurnAuth.OwnerOnly;

    // Custom errors
    error LexChex_SoulBound();
    error LexChex_TokenCannotBeBurned();
    error LexChex_OnlyIssuerCanBurn();
    error LexChex_OnlyOwnerCanBurn();
    error LexChex_OnlyIssuerOrOwnerCanBurn();
    error LexChex_TokenDoesNotExist();

    struct accreditation {
        string agreementId;
        address registryAddress;
        uint256 issuanceDate;
        uint256 expiryDate;
        string voided;
        bytes signature;
    }
    
    mapping(uint256 => accreditation) public accreditations;

    string certificateUri;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __BorgAuthACL_init(_auth);
    }

    function mint(address to, uint256 tokenId) public onlyAdmin {
        _mint(to, tokenId);
        emit Issued(address(0), to, tokenId, BURNAUTH);
    }

    function burn(uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if(msg.sender != owner) {
            revert LexChex_OnlyOwnerCanBurn();
        }
        
        _burn(tokenId);
    }

    function burnAuth(uint256 tokenId) external view override returns (BurnAuth) {
        return BURNAUTH;
    }
    
    /**
     * @dev Override _update to enforce transferability restrictions
     * This function is called for all token transfers, mints, and burns
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Skip restriction checks for minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            revert LexChex_SoulBound();
        }
        
        return super._update(to, tokenId, auth);
    }
}