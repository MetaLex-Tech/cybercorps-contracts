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

/**
 * @title AgreementTemplateBase
 * @notice OPTIONAL base contract for agreement templates
 * @dev Templates do not need to inherit from this contract - it is provided purely as a convenience.
 *      Provides default implementations for validate() and getClosingConditions().
 *      Templates that want complete control should implement IAgreementTemplate directly.
 */
abstract contract AgreementTemplateBase is IAgreementTemplate, ERC165 {
    string internal _contentUri;
    address[] internal _closingConditions;

    /**
     * @notice Returns the Arweave content URI for this template
     */
    function contentUri() external view override returns (string memory) {
        return _contentUri;
    }

    /**
     * @notice Returns the closing conditions for this template
     * @return Array of condition contract addresses
     * @dev Default implementation returns empty array. Override to add conditions.
     */
    function getClosingConditions()
        external
        view
        override
        returns (address[] memory)
    {
        return _closingConditions;
    }

    /**
     * @notice Validates template data
     * @param templateData ABI-encoded template input struct
     * @return true if valid
     * @dev Default implementation returns true (no validation). Override to add validation.
     */
    function validate(
        bytes memory templateData
    ) external view virtual override returns (bool) {
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
     * @notice Sets the content URI for this template
     * @param __contentUri The Arweave URI (format: "ar://<transaction-id>")
     * @dev Internal function to be called during construction
     */
    function _setContentUri(string memory __contentUri) internal {
        _contentUri = __contentUri;
    }

    /**
     * @notice Adds a closing condition to the template
     * @param condition The condition contract address to add
     * @dev Internal function to be called during construction
     */
    function _addClosingCondition(address condition) internal {
        _closingConditions.push(condition);
    }
}
