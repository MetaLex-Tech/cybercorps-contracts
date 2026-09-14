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

    function stringArrayToJson(string[] memory values) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) json = string.concat(json, ", ");
            json = string.concat(json, '"', jsonEscape(values[i]), '"');
        }
        return string.concat(json, "]");
    }

    /// @dev Length of the UTF-8 sequence that starts at `i`, or 0 when the bytes there are not one.
    /// Follows Unicode Table 3-7, so an overlong form, a surrogate, and anything above U+10FFFF all
    /// report 0. A Solidity string is any bytes, but RFC 8259 says JSON text must be valid UTF-8.
    function utf8SequenceLength(bytes memory b, uint256 i) internal pure returns (uint256) {
        uint8 c = uint8(b[i]);
        if (c < 0x80) return 1;
        if (c < 0xC2 || c > 0xF4) return 0;

        uint256 n = c < 0xE0 ? 2 : (c < 0xF0 ? 3 : 4);
        if (i + n > b.length) return 0;

        // Table 3-7 narrows the second byte for the four lead bytes that would otherwise admit an
        // overlong form, a surrogate, or a value above U+10FFFF.
        uint8 lo = c == 0xE0 ? 0xA0 : (c == 0xF0 ? 0x90 : 0x80);
        uint8 hi = c == 0xED ? 0x9F : (c == 0xF4 ? 0x8F : 0xBF);
        uint8 second = uint8(b[i + 1]);
        if (second < lo || second > hi) return 0;

        for (uint256 k = 2; k < n; k++) {
            uint8 t = uint8(b[i + k]);
            if (t < 0x80 || t > 0xBF) return 0;
        }
        return n;
    }

    /// @dev Escapes `s` for use inside a JSON string. A byte that is not part of a valid UTF-8
    /// sequence becomes U+FFFD, one per bad byte, so the result is always valid UTF-8 and this
    /// never reverts. A metadata read must always give an answer.
    function jsonEscape(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);

        uint256 outLength = 0;
        uint256 i = 0;
        while (i < b.length) {
            uint256 n = utf8SequenceLength(b, i);
            if (n == 0) {
                outLength += 3; // U+FFFD is 3 bytes
                i++;
            } else if (n > 1) {
                outLength += n;
                i += n;
            } else {
                outLength += escapedLength(b[i]);
                i++;
            }
        }
        // Every branch above keeps or grows the length, so equality means nothing changed.
        if (outLength == b.length) return s;

        bytes memory out = new bytes(outLength);
        uint256 j = 0;
        i = 0;
        while (i < b.length) {
            uint256 n = utf8SequenceLength(b, i);
            if (n == 0) {
                out[j++] = 0xEF; out[j++] = 0xBF; out[j++] = 0xBD;
                i++;
            } else if (n > 1) {
                for (uint256 k = 0; k < n; k++) out[j++] = b[i + k];
                i += n;
            } else {
                j = writeEscaped(out, j, b[i]);
                i++;
            }
        }
        return string(out);
    }

    /// @dev Bytes that one ASCII character takes after escaping.
    function escapedLength(bytes1 c) internal pure returns (uint256) {
        // Group 1: Structural characters
        if (c == '"' || c == '\\') return 2;
        if (uint8(c) >= 0x20) return 1;
        // Group 2: Named two-char control escapes
        if (c == bytes1(0x08) || c == '\t' || c == '\n' || c == bytes1(0x0C) || c == '\r') return 2;
        // Group 3: Remaining control characters — the \uXXXX range 0x00-0x1F
        return 6;
    }

    /// @dev Writes one escaped ASCII character at `j` and returns the next write position.
    function writeEscaped(bytes memory out, uint256 j, bytes1 c) internal pure returns (uint256) {
        // Group 1: Structural characters
        if (c == '"')               { out[j++] = '\\'; out[j++] = '"';  }
        else if (c == '\\')         { out[j++] = '\\'; out[j++] = '\\'; }

        // Group 2: Named two-char control escapes
        else if (c == bytes1(0x08)) { out[j++] = '\\'; out[j++] = 'b';  }
        else if (c == '\t')         { out[j++] = '\\'; out[j++] = 't';  }
        else if (c == '\n')         { out[j++] = '\\'; out[j++] = 'n';  }
        else if (c == bytes1(0x0C)) { out[j++] = '\\'; out[j++] = 'f';  }
        else if (c == '\r')         { out[j++] = '\\'; out[j++] = 'r';  }

        // Group 3: Remaining control characters — the \uXXXX range 0x00-0x1F
        else if (uint8(c) < 0x20) {
            out[j++] = '\\';
            out[j++] = 'u';
            out[j++] = '0';
            out[j++] = '0';
            out[j++] = hexNibble(uint8(c) >> 4);
            out[j++] = hexNibble(uint8(c) & 0x0F);
        }
        else { out[j++] = c; }
        return j;
    }

    function hexNibble(uint8 v) internal pure returns (bytes1) {
        // converts a value 0–15 to its ASCII character (0-9, a-f)
        return bytes1(v < 10 ? 0x30 + v : 0x61 + v - 10);
    }
}
