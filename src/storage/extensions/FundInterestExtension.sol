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

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../libs/auth.sol";

/// @notice Per-certificate fund-interest data (spec §12B.3). The two dates drive the Rule 144 holding
/// period (HoldingPeriodCondition) and the Reg S distribution compliance period
/// (RegSDistributionComplianceCondition).
struct FundInterestData {
    uint64 acquisitionDate;           // when the holder acquired the interest (validity anchor for holds)
    uint64 tackedFromAcquisitionDate; // Rule 144(d)(3) tacking anchor; 0 = no tacking asserted
    string customProvisions;
}

/// @title FundInterestExtension - certificate extension for SPV fund interests
/// @author MetaLeX Labs, Inc.
contract FundInterestExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("FUND_INTEREST");

    //offset to leave for future upgrades
    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(bytes memory data) external pure returns (FundInterestData memory) {
        return abi.decode(data, (FundInterestData));
    }

    function encodeExtensionData(FundInterestData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(
        bytes memory /* printerExtensionData */,
        bytes memory certificateExtensionData
    ) external view override returns (string memory) {
        FundInterestData memory decoded = abi.decode(certificateExtensionData, (FundInterestData));

        return string(
            abi.encodePacked(
                ', "FundInterestDetails": {',
                '"acquisitionDate": "',
                uint256ToString(decoded.acquisitionDate),
                '", "tackedFromAcquisitionDate": "',
                uint256ToString(decoded.tackedFromAcquisitionDate),
                '", "customProvisions": "',
                decoded.customProvisions,
                '"}'
            )
        );
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

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
