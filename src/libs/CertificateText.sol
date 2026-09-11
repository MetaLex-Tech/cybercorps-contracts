// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {JsonLib} from "./JsonLib.sol";

library CertificateText {
    /// @dev XML 1.0 text, replacing invalid UTF-8 and prohibited characters. Limit display length
    /// by code points so long names cannot overflow the artwork; full values remain in JSON.
    function xml(string memory value, uint256 limit) internal pure returns (string memory) {
        bytes memory source = bytes(value);
        bytes memory out = new bytes(source.length * 6 + 3);
        uint256 cursor;
        uint256 i;
        uint256 count;
        while (i < source.length && count < limit) {
            uint256 n = JsonLib.utf8SequenceLength(source, i);
            bytes memory replacement;
            bytes1 c = source[i];
            if (n == 0 || (n == 1 && uint8(c) < 32 && c != 0x09 && c != 0x0a && c != 0x0d)
                || (n == 3 && c == 0xef && source[i + 1] == 0xbf && uint8(source[i + 2]) >= 0xbe)) {
                replacement = hex"efbfbd";
            } else if (c == "&") replacement = bytes("&amp;");
            else if (c == "<") replacement = bytes("&lt;");
            else if (c == ">") replacement = bytes("&gt;");
            else if (c == '"') replacement = bytes("&quot;");
            else if (c == "'") replacement = bytes("&apos;");
            if (replacement.length > 0) {
                for (uint256 j; j < replacement.length; ++j) out[cursor++] = replacement[j];
            } else {
                for (uint256 j; j < n; ++j) out[cursor++] = source[i + j];
            }
            i += n == 0 ? 1 : n;
            ++count;
        }
        if (i < source.length) {
            out[cursor++] = "."; out[cursor++] = "."; out[cursor++] = ".";
        }
        assembly ("memory-safe") { mstore(out, cursor) }
        return string(out);
    }
}
