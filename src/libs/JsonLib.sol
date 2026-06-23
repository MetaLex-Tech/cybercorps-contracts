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

library JsonLib {
    function boolToString(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    function jsonEscape(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 extra = 0;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == '"' || c == '\\') {
                // Group 1: Structural characters
                extra++;
            } else if (uint8(c) < 0x20) {
                if (c == bytes1(0x08) || c == '\t' || c == '\n' || c == bytes1(0x0C) || c == '\r') {
                    // Group 2: Named two-char control escapes
                    extra++;
                } else {
                    // Group 3: Remaining control characters — the \uXXXX range 0x00–0x1F
                    extra += 5; // \uXXXX: 1 byte → 6 bytes
                }
            }
        }
        if (extra == 0) return s;
        bytes memory out = new bytes(b.length + extra);
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            // Group 1: Structural characters
            if (c == '"')               { out[j++] = '\\'; out[j++] = '"';  }
            else if (c == '\\')         { out[j++] = '\\'; out[j++] = '\\'; }

            // Group 2: Named two-char control escapes
            else if (c == bytes1(0x08)) { out[j++] = '\\'; out[j++] = 'b';  }
            else if (c == '\t')         { out[j++] = '\\'; out[j++] = 't';  }
            else if (c == '\n')         { out[j++] = '\\'; out[j++] = 'n';  }
            else if (c == bytes1(0x0C)) { out[j++] = '\\'; out[j++] = 'f';  }
            else if (c == '\r')         { out[j++] = '\\'; out[j++] = 'r';  }

            // Group 3: Remaining control characters — the \uXXXX range 0x00–0x1F
            else if (uint8(c) < 0x20) {
                out[j++] = '\\';
                out[j++] = 'u';
                out[j++] = '0';
                out[j++] = '0';
                out[j++] = hexNibble(uint8(c) >> 4);
                out[j++] = hexNibble(uint8(c) & 0x0F);
            }
            else { out[j++] = c; }
        }
        return string(out);
    }

    function hexNibble(uint8 v) internal pure returns (bytes1) {
        // converts a value 0–15 to its ASCII character (0-9, a-f)
        return bytes1(v < 10 ? 0x30 + v : 0x61 + v - 10);
    }
}
