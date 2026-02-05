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

/**
 * @title IAgreementTemplate
 * @notice Interface for agreement template contracts
 * @dev Templates are immutable smart contracts that define the structure and validation
 *      of agreement data, compute derived values by reading on-chain state, and return
 *      ABI-encoded data for PDF generation.
 * 
 *      Templates are self-contained and should not inherit from base contracts unless desired.
 *      The frontend is responsible for encoding/decoding data using ABIs from template.json.
 */
interface IAgreementTemplate is IERC165 {
    /**
     * @notice Returns Arweave transaction ID containing template.json and template.typ
     * @return Arweave URI in format "ar://<transaction-id>"
     */
    function contentUri() external view returns (string memory);
    
    /**
     * @notice Returns computed wording values by reading blockchain state
     * @param templateData ABI-encoded template input struct
     * @return ABI-encoded output struct with values for PDF generation
     * @dev The output struct is defined by the template and documented in template.json
     */
    function getWordingValues(bytes memory templateData) external view returns (bytes memory);
    
    /**
     * @notice Returns conditions that must pass before agreement can be finalized
     * @return Array of condition contract addresses
     * @dev Returns empty array if no conditions are required
     */
    function getClosingConditions() external view returns (address[] memory);
    
    /**
     * @notice Optionally validates template data
     * @param templateData ABI-encoded template input struct
     * @return true if valid, false otherwise
     * @dev This function is OPTIONAL. If not implemented, it should return true.
     *      Templates may choose to implement validation or leave it to the frontend.
     *      The registry may call this during agreement creation if implemented.
     */
    function validate(bytes memory templateData) external view returns (bool);
}
