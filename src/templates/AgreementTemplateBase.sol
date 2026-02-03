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

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IAgreementTemplate} from "../interfaces/IAgreementTemplate.sol";
import {ICondition} from "../interfaces/ICondition.sol";

/**
 * @title AgreementTemplateBase
 * @notice Abstract base contract for agreement templates
 * @dev Provides default implementations for party data handling and ERC165 support.
 *      Template developers can inherit from this contract and override functions as needed.
 */
abstract contract AgreementTemplateBase is IAgreementTemplate, ERC165 {
    string internal _templateContentUri;
    ICondition[] internal _closingConditions;

    /**
     * @notice Modifier to check if a string is not empty
     */
    modifier nonEmptyString(string memory str) {
        require(bytes(str).length > 0, "String cannot be empty");
        _;
    }

    /**
     * @notice Returns the content URI for this template
     */
    function templateContentUri()
        external
        view
        override
        returns (string memory)
    {
        return _templateContentUri;
    }

    /**
     * @notice Returns the closing conditions for this template
     */
    function getClosingConditions()
        external
        view
        override
        returns (ICondition[] memory)
    {
        return _closingConditions;
    }

    /**
     * @notice Default party data encoding using ABI encoding
     * @param partyData The party data struct to encode
     * @return bytes memory The encoded party data
     * @dev Override this function if you need custom encoding
     */
    function encodePartyData(
        PartyData memory partyData
    ) external pure override returns (bytes memory) {
        return abi.encode(partyData);
    }

    /**
     * @notice Default party data decoding using ABI decoding
     * @param data The encoded party data
     * @return PartyData memory The decoded party data struct
     * @dev Override this function if you used custom encoding
     */
    function decodePartyData(
        bytes memory data
    ) external pure override returns (PartyData memory) {
        return abi.decode(data, (PartyData));
    }

    /**
     * @notice Default party data validation
     * @param partyData The party data to validate
     * @return bool True if valid
     * @dev Validates that required fields are not empty:
     *      - name must not be empty
     *      - contactDetails must not be empty
     *      - jurisdiction required if partyType is Company
     *      Override for custom validation logic
     */
    function validatePartyData(
        PartyData memory partyData
    ) external pure override returns (bool) {
        // Name is required
        if (bytes(partyData.name).length == 0) {
            return false;
        }

        // Contact details are required
        if (bytes(partyData.contactDetails).length == 0) {
            return false;
        }

        // Jurisdiction is required for companies
        if (
            partyData.partyType == PartyType.Company &&
            bytes(partyData.jurisdiction).length == 0
        ) {
            return false;
        }

        return true;
    }

    /**
     * @notice ERC165 interface support
     * @param interfaceId The interface ID to check
     * @return bool True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IAgreementTemplate).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Sets the template content URI
     * @param contentUri The new content URI
     * @dev Internal function to be called during initialization
     */
    function _setTemplateContentUri(string memory contentUri) internal {
        _templateContentUri = contentUri;
    }

    /**
     * @notice Adds a closing condition to the template
     * @param condition The condition contract to add
     * @dev Internal function to be called during initialization or by authorized accounts
     */
    function _addClosingCondition(ICondition condition) internal {
        _closingConditions.push(condition);
    }

    /**
     * @notice Removes a closing condition from the template
     * @param index The index of the condition to remove
     * @dev Internal function to be called by authorized accounts
     */
    function _removeClosingCondition(uint256 index) internal {
        require(index < _closingConditions.length, "Index out of bounds");

        // Move the last element to the removed position and pop
        _closingConditions[index] = _closingConditions[
            _closingConditions.length - 1
        ];
        _closingConditions.pop();
    }

    /**
     * @notice Storage gap for upgradeable contracts
     * @dev Leave 40 slots as per existing project patterns
     */
    uint256[40] private __gap;
}

/**
 * @title PartyDataLib
 * @notice Library for PartyData helper functions
 */
library PartyDataLib {
    /**
     * @notice Converts PartyData to a string representation for debugging/logging
     * @param data The party data
     * @return string memory Human-readable representation
     */
    function toString(
        IAgreementTemplate.PartyData memory data
    ) internal pure returns (string memory) {
        return
            string.concat(
                "PartyData{name: ",
                data.name,
                ", type: ",
                data.partyType == IAgreementTemplate.PartyType.Individual
                    ? "Individual"
                    : "Company",
                ", contact: ",
                data.contactDetails,
                ", jurisdiction: ",
                data.jurisdiction,
                "}"
            );
    }

    /**
     * @notice Checks if two PartyData structs are equal
     * @param a First PartyData
     * @param b Second PartyData
     * @return bool True if equal
     */
    function equals(
        IAgreementTemplate.PartyData memory a,
        IAgreementTemplate.PartyData memory b
    ) internal pure returns (bool) {
        return
            keccak256(bytes(a.name)) == keccak256(bytes(b.name)) &&
            a.partyType == b.partyType &&
            keccak256(bytes(a.contactDetails)) ==
            keccak256(bytes(b.contactDetails)) &&
            keccak256(bytes(a.jurisdiction)) ==
            keccak256(bytes(b.jurisdiction));
    }
}
