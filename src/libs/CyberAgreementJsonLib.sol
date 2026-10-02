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

import "@openzeppelin/contracts/utils/Strings.sol";
import "./JsonLib.sol";

/// @notice JSON view of a CyberAgreementRegistry agreement.
/// It is a linked library, so the registry stays under the EIP-170 size limit.
library CyberAgreementJsonLib {
    struct AgreementJson {
        bytes32 templateId;
        string title;
        string legalContractUri;
        string[] globalFields;
        string[] partyFields;
        string[] globalValues;
        address[] parties;
        string[][] partyValues;
        uint256[] signedAt;
        uint256 numSignatures;
        bool voided;
        address[] voidRequestedBy;
        bool finalized;
    }

    /// @notice Render an agreement as JSON. `partyValues[i]` and `signedAt[i]` belong to `parties[i]`.
    function toJson(AgreementJson memory agreement) external pure returns (string memory) {
        // Start with basic fields
        string memory json = string(
            abi.encodePacked(
                '{"templateId": "',
                Strings.toHexString(uint256(agreement.templateId), 32),
                '", "title": "',
                JsonLib.jsonEscape(agreement.title),
                '", "legalContractUri": "',
                JsonLib.jsonEscape(agreement.legalContractUri),
                '", "ContractFields": {'
            )
        );

        // Add global fields and values as key-value pairs
        if (agreement.globalFields.length > 0) {
            for (uint256 i = 0; i < agreement.globalFields.length; i++) {
                json = string.concat(
                    json,
                    '"',
                    JsonLib.jsonEscape(agreement.globalFields[i]),
                    '": "',
                    JsonLib.jsonEscape(agreement.globalValues[i]),
                    '"'
                );
                if (i + 1 < agreement.globalFields.length) {
                    json = string.concat(json, ",");
                }
            }
        }
        json = string.concat(json, '}, "parties": {');

        // Add parties and their values as key-value pairs
        if (agreement.parties.length > 0) {
            for (uint256 i = 0; i < agreement.parties.length; i++) {
                json = string.concat(
                    json,
                    '"',
                    Strings.toHexString(agreement.parties[i]),
                    '": {'
                );

                // Add party fields and values
                if (agreement.partyFields.length > 0) {
                    string[] memory values = agreement.partyValues[i];
                    for (uint256 j = 0; j < agreement.partyFields.length; j++) {
                        json = string.concat(
                            json,
                            '"',
                            JsonLib.jsonEscape(agreement.partyFields[j]),
                            '": "'
                        );
                        if (values.length > j) {
                            json = string.concat(json, JsonLib.jsonEscape(values[j]));
                        }
                        json = string.concat(json, '"');
                        if (j + 1 < agreement.partyFields.length) {
                            json = string.concat(json, ",");
                        }
                    }
                }

                // Add signature timestamp
                if (agreement.partyFields.length > 0) {
                    json = string.concat(json, ",");
                }
                json = string.concat(
                    json,
                    '"signedAt": ',
                    Strings.toString(agreement.signedAt[i])
                );
                json = string.concat(json, "}");

                if (i + 1 < agreement.parties.length) {
                    json = string.concat(json, ",");
                }
            }
        }

        // Add metadata
        json = string.concat(
            json,
            '}, "numSignatures": ',
            Strings.toString(agreement.numSignatures)
        );
        json = string.concat(
            json,
            ', "isComplete": ',
            agreement.numSignatures == agreement.parties.length
                ? "true"
                : "false"
        );
        // Add voided status
        json = string.concat(
            json,
            ', "voided": ',
            agreement.voided ? "true" : "false"
        );
        // loop and add voidRequestedBy
        json = string.concat(json, ', "voidRequestedBy": [');
        for (uint256 i = 0; i < agreement.voidRequestedBy.length; i++) {
            json = string.concat(
                json,
                '"',
                Strings.toHexString(agreement.voidRequestedBy[i]),
                '"'
            );
            if (i + 1 < agreement.voidRequestedBy.length) {
                json = string.concat(json, ",");
            }
        }
        json = string.concat(json, "]");
        // add finalized status
        json = string.concat(
            json,
            ', "finalized": ',
            agreement.finalized ? "true" : "false"
        );
        json = string.concat(json, "}");
        return json;
    }
}
