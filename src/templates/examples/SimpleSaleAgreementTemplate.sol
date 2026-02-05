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
  d8P'  `Y8b              "888"                           d8P'  `Y8b
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

import {IAgreementTemplate} from "../../interfaces/IAgreementTemplate.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title SimpleSaleAgreementTemplate
 * @notice Example template for a simple asset sale agreement
 * @dev Demonstrates the simplified template pattern:
 *      - No formatting in Solidity (done in template.typ instead)
 *      - Only fetches on-chain metadata
 *      - Returns raw values for frontend/template to format
 */
contract SimpleSaleAgreementTemplate is IAgreementTemplate {
    
    string public contentUri;
    address[] public closingConditions;
    
    struct SaleInput {
        address assetAddress;
        uint256 assetAmount;
        uint256 purchasePrice;
        address paymentToken;
        uint256 deliveryDate;
        string description;
    }
    
    struct SaleOutput {
        // Asset info
        address assetAddress;
        string assetName;
        string assetSymbol;
        uint8 assetDecimals;
        uint256 assetAmount;
        
        // Payment info
        uint256 purchasePrice;
        address paymentToken;
        string paymentTokenName;
        string paymentTokenSymbol;
        uint8 paymentTokenDecimals;
        
        // Other
        uint256 deliveryDate;
        string description;
    }

    constructor(string memory _contentUri, address[] memory _conditions) {
        contentUri = _contentUri;
        closingConditions = _conditions;
    }

    function getWordingValues(bytes memory templateData) 
        external 
        view 
        override 
        returns (bytes memory) 
    {
        SaleInput memory input = abi.decode(templateData, (SaleInput));
        
        // Fetch asset metadata from chain
        (string memory assetName, string memory assetSymbol, uint8 assetDecimals) = 
            _getTokenMetadata(input.assetAddress);
        
        // Fetch payment token metadata
        string memory paymentName;
        string memory paymentSymbol;
        uint8 paymentDecimals;
        
        if (input.paymentToken == address(0)) {
            paymentName = "Ether";
            paymentSymbol = "ETH";
            paymentDecimals = 18;
        } else {
            (paymentName, paymentSymbol, paymentDecimals) = _getTokenMetadata(input.paymentToken);
        }
        
        SaleOutput memory output = SaleOutput({
            assetAddress: input.assetAddress,
            assetName: assetName,
            assetSymbol: assetSymbol,
            assetDecimals: assetDecimals,
            assetAmount: input.assetAmount,
            purchasePrice: input.purchasePrice,
            paymentToken: input.paymentToken,
            paymentTokenName: paymentName,
            paymentTokenSymbol: paymentSymbol,
            paymentTokenDecimals: paymentDecimals,
            deliveryDate: input.deliveryDate,
            description: input.description
        });
        
        return abi.encode(output);
    }

    function validate(bytes memory templateData) 
        external 
        view 
        override 
        returns (bool) 
    {
        try this.getWordingValues(templateData) returns (bytes memory) {
            SaleInput memory input = abi.decode(templateData, (SaleInput));
            
            if (input.assetAddress == address(0)) return false;
            if (input.assetAmount == 0) return false;
            if (input.purchasePrice == 0) return false;
            if (input.deliveryDate <= block.timestamp) return false;
            if (bytes(input.description).length == 0) return false;
            
            return true;
        } catch {
            return false;
        }
    }

    function getClosingConditions() external view override returns (address[] memory) {
        return closingConditions;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IAgreementTemplate).interfaceId || 
               interfaceId == type(IERC165).interfaceId;
    }

    function _getTokenMetadata(address token) internal view returns (
        string memory name, 
        string memory symbol, 
        uint8 decimals
    ) {
        try IERC20Metadata(token).name() returns (string memory n) {
            name = n;
        } catch {
            name = "";
        }
        
        try IERC20Metadata(token).symbol() returns (string memory s) {
            symbol = s;
        } catch {
            symbol = "";
        }
        
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            decimals = 18;
        }
    }
}
