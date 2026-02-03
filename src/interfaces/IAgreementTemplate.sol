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
import {ICondition} from "./ICondition.sol";

/**
 * @title IAgreementTemplate
 * @notice Interface for agreement template contracts
 * @dev Templates are smart contracts that define the structure and validation
 *      of agreement data, as well as the conversion to human-readable strings for PDF generation.
 *      Templates also handle party data encoding/decoding.
 */
interface IAgreementTemplate is IERC165 {
    /**
     * @notice Party type enum
     */
    enum PartyType {
        Individual,
        Company
    }

    /**
     * @notice Standard party data structure
     * @param name The full name of the party
     * @param partyType The type of party (Individual or Company)
     * @param contactDetails Contact information for the party
     * @param jurisdiction Required if partyType == Company, indicates legal jurisdiction
     */
    struct PartyData {
        string name;
        PartyType partyType;
        string contactDetails;
        string jurisdiction;
    }

    /**
     * @notice Returns the URI to the template content directory
     * @dev The URI should point to a directory containing:
     *      - template.typ: The Typst template file for PDF generation
     *      - schema.json: The JSON schema for frontend form rendering
     * @return string memory The content URI (e.g., "ipfs://QmHash/")
     */
    function templateContentUri() external view returns (string memory);

    /**
     * @notice Encodes template-specific data to bytes
     * @param data The template-specific data struct as bytes
     * @return bytes memory The encoded data
     * @dev Should include validation logic before encoding
     */
    function encodeTemplateData(
        bytes memory data
    ) external pure returns (bytes memory);

    /**
     * @notice Decodes bytes to template-specific data
     * @param data The encoded bytes
     * @return bytes memory The decoded template-specific data struct
     */
    function decodeTemplateData(
        bytes memory data
    ) external pure returns (bytes memory);

    /**
     * @notice Validates template data before agreement creation
     * @param data The encoded template data to validate
     * @return bool True if the data is valid, false otherwise
     */
    function validateTemplateData(
        bytes memory data
    ) external view returns (bool);

    /**
     * @notice Converts typed template data to string key-value pairs for PDF generation
     * @param data The encoded template data
     * @return keys Array of string keys for the template values
     * @return values Array of string values corresponding to the keys
     * @dev Used by off-chain services to populate Typst templates
     */
    function getLegalWordingValues(
        bytes memory data
    ) external view returns (string[] memory keys, string[] memory values);

    /**
     * @notice Returns the closing conditions that must pass before finalization
     * @return ICondition[] memory Array of condition contracts to check
     * @dev Returns empty array if no conditions are required
     */
    function getClosingConditions() external view returns (ICondition[] memory);

    /**
     * @notice Encodes party data to bytes
     * @param partyData The party data struct to encode
     * @return bytes memory The encoded party data
     */
    function encodePartyData(
        PartyData memory partyData
    ) external pure returns (bytes memory);

    /**
     * @notice Decodes bytes to party data struct
     * @param data The encoded party data
     * @return PartyData memory The decoded party data struct
     */
    function decodePartyData(
        bytes memory data
    ) external pure returns (PartyData memory);

    /**
     * @notice Validates party data
     * @param partyData The party data to validate
     * @return bool True if valid, false otherwise
     */
    function validatePartyData(
        PartyData memory partyData
    ) external view returns (bool);
}
