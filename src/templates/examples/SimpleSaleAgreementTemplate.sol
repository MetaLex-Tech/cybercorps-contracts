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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AgreementTemplateBase} from "../AgreementTemplateBase.sol";
import {BorgAuthACL} from "../../libs/auth.sol";

/**
 * @title SimpleSaleAgreementTemplate
 * @notice Example template for a simple asset sale agreement
 * @dev This template demonstrates the implementation of IAgreementTemplate
 *      for a simple sale scenario where one party sells an asset to another.
 */
contract SimpleSaleAgreementTemplate is
    Initializable,
    UUPSUpgradeable,
    BorgAuthACL,
    AgreementTemplateBase
{
    using Strings for uint256;
    using Strings for address;

    /**
     * @notice Sale agreement data structure
     * @param assetAddress The address of the asset contract (ERC20 or NFT)
     * @param assetAmount The amount of tokens or NFT ID being sold
     * @param purchasePrice The price in wei to be paid
     * @param paymentToken The token used for payment (address(0) for ETH)
     * @param deliveryDate The timestamp by which the asset must be delivered
     * @param description A description of the asset being sold
     */
    struct SaleAgreementData {
        address assetAddress;
        uint256 assetAmount;
        uint256 purchasePrice;
        address paymentToken;
        uint256 deliveryDate;
        string description;
    }

    // Custom errors
    error InvalidAssetAddress();
    error InvalidAssetAmount();
    error InvalidPurchasePrice();
    error DeliveryDateInPast();
    error EmptyDescription();

    /**
     * @notice Initializes the template contract
     * @param _auth Address of the BorgAuth contract for authorization
     * @param _contentUri URI pointing to the template content directory
     */
    function initialize(
        address _auth,
        string memory _contentUri
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        _setTemplateContentUri(_contentUri);
    }

    /**
     * @notice Encodes SaleAgreementData to bytes
     * @param data The SaleAgreementData struct as bytes
     * @return bytes memory The encoded data
     * @dev Data should be validated before calling this function
     */
    function encodeTemplateData(
        bytes memory data
    ) external pure override returns (bytes memory) {
        // Just return the data - validation happens in validateTemplateData
        return data;
    }

    /**
     * @notice Decodes bytes to SaleAgreementData
     * @param data The encoded bytes
     * @return bytes memory The decoded SaleAgreementData struct
     */
    function decodeTemplateData(
        bytes memory data
    ) external pure override returns (bytes memory) {
        SaleAgreementData memory decoded = abi.decode(data, (SaleAgreementData));
        return abi.encode(decoded);
    }

    /**
     * @notice Validates template data
     * @param data The encoded template data to validate
     * @return bool True if the data is valid
     */
    function validateTemplateData(
        bytes memory data
    ) external view override returns (bool) {
        try this.decodeTemplateData(data) returns (bytes memory) {
            SaleAgreementData memory saleData = abi.decode(data, (SaleAgreementData));
            return _validateSaleData(saleData);
        } catch {
            return false;
        }
    }

    /**
     * @notice Converts typed template data to string key-value pairs for PDF generation
     * @param data The encoded template data
     * @return keys Array of string keys
     * @return values Array of string values
     */
    function getLegalWordingValues(
        bytes memory data
    ) external pure override returns (string[] memory keys, string[] memory values) {
        SaleAgreementData memory saleData = abi.decode(data, (SaleAgreementData));

        keys = new string[](6);
        values = new string[](6);

        keys[0] = "assetAddress";
        values[0] = _addressToString(saleData.assetAddress);

        keys[1] = "assetAmount";
        values[1] = saleData.assetAmount.toString();

        keys[2] = "purchasePrice";
        values[2] = _formatEther(saleData.purchasePrice);

        keys[3] = "paymentToken";
        values[3] = saleData.paymentToken == address(0) 
            ? "ETH" 
            : _addressToString(saleData.paymentToken);

        keys[4] = "deliveryDate";
        values[4] = _timestampToDateString(saleData.deliveryDate);

        keys[5] = "description";
        values[5] = saleData.description;

        return (keys, values);
    }

    /**
     * @notice Internal function to validate sale data
     * @param data The sale data to validate
     * @return bool True if valid
     */
    function _validateSaleData(SaleAgreementData memory data) internal view returns (bool) {
        // Asset address cannot be zero
        if (data.assetAddress == address(0)) {
            return false;
        }

        // Asset amount must be greater than zero
        if (data.assetAmount == 0) {
            return false;
        }

        // Purchase price must be greater than zero
        if (data.purchasePrice == 0) {
            return false;
        }

        // Delivery date must be in the future
        if (data.deliveryDate <= block.timestamp) {
            return false;
        }

        // Description cannot be empty
        if (bytes(data.description).length == 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Converts an address to a string
     * @param _addr The address to convert
     * @return string memory The address as a string
     */
    function _addressToString(address _addr) internal pure returns (string memory) {
        return _addr.toHexString();
    }

    /**
     * @notice Formats a wei amount as ether string
     * @param _weiAmount The amount in wei
     * @return string memory The formatted amount
     */
    function _formatEther(uint256 _weiAmount) internal pure returns (string memory) {
        uint256 etherValue = _weiAmount / 1e18;
        uint256 remainder = _weiAmount % 1e18;
        
        if (remainder == 0) {
            return string.concat(etherValue.toString(), " ETH");
        }
        
        // Get first 4 decimal places
        uint256 decimals = remainder / 1e14;
        
        return string.concat(
            etherValue.toString(),
            ".",
            _padLeft(decimals.toString(), 4),
            " ETH"
        );
    }

    /**
     * @notice Pads a string with leading zeros
     * @param _str The string to pad
     * @param _length The desired length
     * @return string memory The padded string
     */
    function _padLeft(string memory _str, uint256 _length) internal pure returns (string memory) {
        if (bytes(_str).length >= _length) {
            return _str;
        }
        
        uint256 padding = _length - bytes(_str).length;
        string memory result = _str;
        
        for (uint256 i = 0; i < padding; i++) {
            result = string.concat("0", result);
        }
        
        return result;
    }

    /**
     * @notice Converts a timestamp to a date string (YYYY-MM-DD)
     * @param _timestamp The Unix timestamp
     * @return string memory The date string
     */
    function _timestampToDateString(uint256 _timestamp) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day) = _timestampToDate(_timestamp);
        
        return string.concat(
            year.toString(),
            "-",
            _padLeft(month.toString(), 2),
            "-",
            _padLeft(day.toString(), 2)
        );
    }

    /**
     * @notice Converts a timestamp to year, month, day
     * @param _timestamp The Unix timestamp
     * @return year The year
     * @return month The month (1-12)
     * @return day The day (1-31)
     * @dev Algorithm from https://howardhinnant.github.io/date_algorithms.html
     */
    function _timestampToDate(uint256 _timestamp) internal pure returns (
        uint256 year,
        uint256 month,
        uint256 day
    ) {
        uint256 z = _timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        
        day = doy - (153 * mp + 2) / 5 + 1;
        if (mp < 10) {
            month = mp + 3;
        } else {
            month = mp - 9;
        }
        if (month <= 2) {
            year = yoe + era * 400 + 1;
        } else {
            year = yoe + era * 400;
        }
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable by owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Authorization handled by onlyOwner modifier
    }

    /**
     * @notice Storage gap for upgradeability
     */
    uint256[40] private __gap;
}
