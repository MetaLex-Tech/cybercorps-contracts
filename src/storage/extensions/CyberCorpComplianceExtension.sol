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

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICyberCorpExtension.sol";
import "../../libs/auth.sol";

struct FeeDetail {
    string feeName;
    uint256 feeBps;
    uint256 flatFee;
    address recipient;
    string feeToken;
    string notes;
}

struct CyberCorpComplianceData {
    bool erisaAllowed;
    uint256 maxOwnershipBps;
    uint256 minNonZeroOwnershipBps;
    uint256 maxHolderCount;
    bool cfiusApprovalRequired;
    string[] holderRestrictions;
    FeeDetail[] feeDetails;
}

contract CyberCorpComplianceExtension is
    UUPSUpgradeable,
    ICyberCorpExtension,
    BorgAuthACL
{
    bytes32 public constant EXTENSION_TYPE =
        keccak256("CYBERCORP_COMPLIANCE");

    uint256[30] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(
        bytes memory data
    ) external pure returns (CyberCorpComplianceData memory) {
        return abi.decode(data, (CyberCorpComplianceData));
    }

    function encodeExtensionData(
        CyberCorpComplianceData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(
        bytes32 extensionType
    ) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(
        bytes memory data
    ) external pure override returns (string memory) {
        CyberCorpComplianceData memory decoded = abi.decode(
            data,
            (CyberCorpComplianceData)
        );

        return string(
            abi.encodePacked(
                ', "CyberCorpCompliance": {',
                '"erisaAllowed": "',
                boolToString(decoded.erisaAllowed),
                '", "maxOwnershipBps": "',
                uint256ToString(decoded.maxOwnershipBps),
                '", "minNonZeroOwnershipBps": "',
                uint256ToString(decoded.minNonZeroOwnershipBps),
                '", "maxHolderCount": "',
                uint256ToString(decoded.maxHolderCount),
                '", "cfiusApprovalRequired": "',
                boolToString(decoded.cfiusApprovalRequired),
                '", "holderRestrictions": ',
                stringArrayToJson(decoded.holderRestrictions),
                ', "feeDetails": ',
                feeDetailsToJson(decoded.feeDetails),
                "}"
            )
        );
    }

    function feeDetailsToJson(
        FeeDetail[] memory details
    ) internal pure returns (string memory) {
        string memory json = "[";

        for (uint256 i = 0; i < details.length; i++) {
            if (i > 0) {
                json = string.concat(json, ", ");
            }

            json = string.concat(
                json,
                '{"feeName": "',
                details[i].feeName,
                '", "feeBps": "',
                uint256ToString(details[i].feeBps),
                '", "flatFee": "',
                uint256ToString(details[i].flatFee),
                '", "recipient": "',
                addressToString(details[i].recipient),
                '", "feeToken": "',
                details[i].feeToken,
                '", "notes": "',
                details[i].notes,
                '"}'
            );
        }

        return string.concat(json, "]");
    }

    function stringArrayToJson(
        string[] memory values
    ) internal pure returns (string memory) {
        string memory json = "[";

        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) {
                json = string.concat(json, ", ");
            }
            json = string.concat(json, '"', values[i], '"');
        }

        return string.concat(json, "]");
    }

    function boolToString(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    function addressToString(address account) internal pure returns (string memory) {
        return _toHexString(abi.encodePacked(account));
    }

    function _toHexString(bytes memory data) internal pure returns (string memory) {
        bytes16 symbols = 0x30313233343536373839616263646566;
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = symbols[uint8(data[i] >> 4)];
            str[3 + i * 2] = symbols[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
