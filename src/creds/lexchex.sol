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
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./storage/lexchexStorage.sol";
import "../libs/auth.sol";  
import "../interfaces/ICyberAgreementRegistry.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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

contract LeXcheX is Initializable, ERC721EnumerableUpgradeable, UUPSUpgradeable, BorgAuthACL, IERC5484 {
    using LeXcheXStorage for *;
    using Strings for uint256;

    BurnAuth constant BURNAUTH = BurnAuth.OwnerOnly;
    uint256 public constant DURATION = 30 days;

    // Upgrade notes: Reduced gap to account for new variables (50 - 1 = 49)
    uint256[49] private __gap;

    // Custom errors
    error LexChex_SoulBound();
    error LexChex_TokenCannotBeBurned();
    error LexChex_OnlyIssuerCanBurn();
    error LexChex_OnlyOwnerCanBurn();
    error LexChex_OnlyIssuerOrOwnerCanBurn();
    error LexChex_TokenDoesNotExist();

    //events
    event LexChex_Issued(address indexed owner, uint256 indexed id, Accreditation acc);
    event LexChex_Voided(address indexed owner, uint256 indexed id, string reason);
    event LexChex_Burned(address indexed owner, uint256 indexed id);
    event LexChex_AccreditationSet(address indexed owner, uint256 indexed id, Accreditation acc);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __BorgAuthACL_init(_auth);
        __ERC721_init("LeXcheX", "LXC");
    }

    function mint(address to, Accreditation memory acc) public onlyAdmin returns (uint256 tokenId) {

        //mint the token
        tokenId = LeXcheXStorage.getSupply();
        _mint(to, tokenId);
        LeXcheXStorage.setAccreditation(tokenId, acc);
        emit LexChex_Issued(msg.sender, tokenId, acc);
        emit Issued(address(0), to, tokenId, BURNAUTH);
        LeXcheXStorage.incrementSupply();
    }

    function burn(uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        if(msg.sender != owner) {
            revert LexChex_OnlyOwnerCanBurn();
        }
        _burn(tokenId);
        LeXcheXStorage.deleteAccreditation(tokenId);
        emit LexChex_Burned(msg.sender, tokenId);
    }
     
    function void(uint256 id, string memory reason) external onlyOwner {
        Accreditation storage acc = LeXcheXStorage.getAccreditation(id);
        acc.voided = reason;
        emit LexChex_Voided(msg.sender, id, reason);
    }

    function burnAuth(uint256 tokenId) external view override returns (BurnAuth) {
        return BURNAUTH;
    }
    
    //read to check if the token is valid or not
    function isValid(uint256 tokenId) public view returns (bool) {
        Accreditation storage acc = LeXcheXStorage.getAccreditation(tokenId);
        if(acc.issuanceDate == 0) {
            return false;
        }
        if(bytes(acc.voided).length > 0) {
            return false;
        }
        if(block.timestamp > acc.expiryDate) {
            return false;
        }
        return true;
    }

    function accreditations(uint256 tokenId) public view returns (Accreditation memory) {
        return LeXcheXStorage.getAccreditation(tokenId);
    }

    function setAccreditation(uint256 tokenId, Accreditation memory acc) public onlyAdmin {
        LeXcheXStorage.setAccreditation(tokenId, acc);
        emit LexChex_AccreditationSet(msg.sender, tokenId, acc);
    }
    
    /**
     * @dev Get all token IDs owned by a specific address
     * @param owner The address to query
     * @return tokenIds Array of token IDs owned by the address
     */
    function getTokenIdsByOwner(address owner) public view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }
    
    /**
     * @dev Get the first token ID owned by an address (for single token scenarios)
     * @param owner The address to query
     * @return tokenId The first token ID owned by the address (reverts if no tokens)
     */
    function getAccreditationByOwner(address owner) public view returns (uint256) {
        uint256 balance = balanceOf(owner);
        require(balance > 0, "No tokens owned by this address");
        return tokenOfOwnerByIndex(owner, 0);
    }
    
    /**
     * @dev Get accreditation data for a token ID
     * @param tokenId The token ID to query
     * @return acc The accreditation data
     */
    function getAccreditation(uint256 tokenId) public view returns (Accreditation memory) {
        return LeXcheXStorage.getAccreditation(tokenId);
    }
    
    /**
     * @dev Check if a token is valid by owner address
     * @param owner The owner address to check
     * @return valid True if the owner has at least one valid token
     */
    function isValid(address owner) public view returns (bool) {
        uint256 balance = balanceOf(owner);
        if (balance == 0) return false;
        
        uint256 tokenId = tokenOfOwnerByIndex(owner, 0);
        return isValid(tokenId);
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

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
       // _requireMinted(tokenId);
        
        Accreditation memory acc = LeXcheXStorage.getAccreditation(tokenId);
        
        string memory image = generateSVGImage(acc);
        
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "U.S. Accredited Investor Certificate #',
                            tokenId.toString(),
                            '", "description": "This certificate represents verification of U.S. Accredited Investor status.",',
                            '"image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(image)),
                            '", "attributes": [',
                            '{"trait_type": "Name", "value": "',acc.investorName,'"},',
                            '{"trait_type": "Entity Type", "value": "',acc.investorType,'"},',
                            '{"trait_type": "Jurisdiction", "value": "',acc.investorJurisdiction,'"},',
                            '{"trait_type": "Status", "value": "',isValid(tokenId) ? "Valid" : "Invalid",'"}',
                            ']}'
                        )
                    )
                )
            )
        );
    }

    function generateSVGImage(Accreditation memory acc) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xhtml="http://www.w3.org/1999/xhtml" version="1.1" width="1000" height="650">',
                '<rect width="100%" height="100%"  fill="#191a18"/>',
                generateMetaLeXLogo(),
                generateSVGBody(acc),
                '</svg>'
            )
        );
    }

    function generateMetaLeXLogo() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg x="880" y="570" width="61" height="30" viewBox="0 0 61 30" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<path d="M29.5488 0C30.5107 0 31.291 0.779753 31.291 1.74121V11.957C31.291 12.543 30.9957 13.0902 30.5059 13.4121L6.69629 29.0605C6.41221 29.2472 6.07921 29.3467 5.73926 29.3467H1.74121C0.779536 29.3465 0 28.5668 0 27.6055V19.9648C8.27261e-05 19.3799 0.293816 18.8339 0.782227 18.5117L28.415 0.288086C28.6996 0.100412 29.0331 0 29.374 0H29.5488ZM54.7832 0.000976562C55.745 0.000976562 56.5243 0.77984 56.5244 1.74121V11.957C56.5244 12.543 56.23 13.0902 55.7402 13.4121L31.9307 29.0605C31.6465 29.2473 31.3137 29.3467 30.9736 29.3467H26.9756C26.0139 29.3466 25.2344 28.5669 25.2344 27.6055V19.9648C25.2345 19.38 25.5282 18.8338 26.0166 18.5117L53.6494 0.288086C53.934 0.100488 54.2675 0.000976562 54.6084 0.000976562H54.7832ZM58.9521 15.54C59.825 14.9532 60.9997 15.5783 61 16.6299V27.792C60.9999 28.6506 60.3033 29.3467 59.4443 29.3467H48.5459C47.687 29.3466 46.9903 28.6505 46.9902 27.792V24.3594C46.9902 23.842 47.2484 23.3582 47.6777 23.0693L58.9521 15.54Z" fill="#DAFF00"/>',
                '</svg>'
            )
        );
    }

    function generateSVGBody(Accreditation memory acc) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="0" y="83" width="1000px" height="50px" fill="url(#linGrad)"></rect>',
                '<text x="212" y="126" font-family="Georgia " font-size="53" fill="url(#textGrad)">U.S. Accredited Investor</text>',
                '<text x="249" y="226" font-family="Georgia" font-size="25" fill="#f2f2f2">THE HOLDER OF THIS CERTIFICATE IS A</text>',
                '<text x="318" y="266" font-family="Georgia" font-size="25" fill="#f2f2f2">U.S. ACCREDITED INVESTOR </text>',
                generateDefs(),
                '<rect width="100%" height="100%" fill="url(#grad1)" />',
                '<text x="150" y="360" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6" >CERTIFIED BY</text>',
                '<text x="385" y="355" font-family="Georgia" font-size="30" fill="url(#textGrad)" >',
                'Gabriel Shapiro, Esq., of MetaLeX',
                '</text>',
                '<rect x="380" y="363" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="150" y="450" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">GOOD UNTIL</text>',
                '<text x="495" y="440" font-family="Georgia" font-size="30" fill="url(#textGrad)" >',
                timestampToDate(acc.expiryDate),
                '</text>',
                '<rect x="380" y="453" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="325" y="570" font-family="Georgia" font-size="17" fill="#f2f2f2" opacity=".6">Non-transferable. Soul-bound. Verified on-chain.</text>',
                '<text x="210" y="600" font-family="Georgia" font-size="15" fill="#f2f2f2" opacity=".24">',
                bytes32ToHexString(acc.agreementId),
                '</text>'
            )
        );
    }

    function generateDefs() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<defs>',
                '<radialGradient id="grad1" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.07" />',
                '<stop offset="100%" style="stop-color:#191a18; stop-opacity:.07" />',
                '</radialGradient>',
                '<linearGradient id="linGrad">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.4" />',
                '<stop offset="20%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="80%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="100%" style="stop-color:#daff00; stop-opacity:.4" />',
                '</linearGradient>',
                '<linearGradient id="textGrad" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#F2F8CB; stop-opacity:1" />',
                '</linearGradient>',
                '</defs>'
            )
        );
    }

    function timestampToDate(uint256 timestamp) internal pure returns (string memory) {
        uint256 day = (timestamp / 86400) % 31 + 1;
        uint256 month = (timestamp / 2629743) % 12 + 1;
        uint256 year = (timestamp / 31556926) + 1970;
        
        return string(
            abi.encodePacked(
                Strings.toString(month),
                "/",
                Strings.toString(day),
                "/",
                Strings.toString(year)
            )
        );
    }

    function bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i*2] = bytes1(uint8(uint256(uint8(value[i] >> 4)) + (uint256(uint8(value[i] >> 4)) < 10 ? 48 : 87)));
            str[i*2+1] = bytes1(uint8(uint256(uint8(value[i] & 0x0f)) + (uint256(uint8(value[i] & 0x0f)) < 10 ? 48 : 87)));
        }
        return string(abi.encodePacked("0x", string(str)));
    }

    /// @dev Only owner can upgrade it
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}

/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // Load the table into memory
        string memory table = TABLE;

        // Encoding takes 3 bytes chunks of binary data from `bytes` data parameter
        // and split into 4 numbers of 6 bits.
        // The final Base64 length should be `bytes` data length multiplied by 4/3 rounded up
        // - `data.length + 2`  -> Round up
        // - `/ 3`              -> Number of 3-bytes chunks
        // - `4 *`              -> 4 characters for each chunk
        string memory result = new string(4 * ((data.length + 2) / 3));

        assembly {
            // Prepare the lookup table (skip the first "length" byte)
            let tablePtr := add(table, 1)

            // Prepare result pointer, jump over length
            let resultPtr := add(result, 32)

            // Run over the input, 3 bytes at a time
            for {
                let dataPtr := data
                let endPtr := add(data, mload(data))
            } lt(dataPtr, endPtr) {

            } {
                // Advance 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

                // To write each character, shift the 3 bytes (18 bits) chunk
                // 4 times in blocks of 6 bits for each character (18, 12, 6, 0)
                // and apply logical AND with 0x3F which is the number of
                // the previous character in the ASCII table prior to the Base64 Table
                // The result is then added to the table to get the character to write,
                // and finally write it in the result pointer but with a left shift
                // of 256 (1 byte) - 8 (1 ASCII char) = 248 bits

                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
            }

            // When data `bytes` is not exactly 3 bytes long
            // it is padded with `=` characters at the end
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }

        return result;
    }
}