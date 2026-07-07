// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {JsonLib} from "../src/libs/JsonLib.sol";

contract JsonLibTest is Test {
    function testJsonEscape_EmptyString() public pure {
        assertEq(JsonLib.jsonEscape(""), "");
    }

    function testJsonEscape_NoSpecialChars() public pure {
        assertEq(JsonLib.jsonEscape("hello world"), "hello world");
    }

    function testJsonEscape_DoubleQuote() public pure {
        assertEq(JsonLib.jsonEscape('say "hi"'), "say \\\"hi\\\"");
    }

    function testJsonEscape_Backslash() public pure {
        assertEq(JsonLib.jsonEscape("path\\to"), "path\\\\to");
    }

    function testJsonEscape_Newline() public pure {
        assertEq(JsonLib.jsonEscape("line1\nline2"), "line1\\nline2");
    }

    function testJsonEscape_CarriageReturn() public pure {
        assertEq(JsonLib.jsonEscape("a\rb"), "a\\rb");
    }

    function testJsonEscape_Tab() public pure {
        assertEq(JsonLib.jsonEscape("a\tb"), "a\\tb");
    }

    function testJsonEscape_AdjacentSpecials() public pure {
        assertEq(JsonLib.jsonEscape('""'), "\\\"\\\"");
    }

    function testJsonEscape_AllSpecialsTogether() public pure {
        assertEq(JsonLib.jsonEscape("\"\\\n\r\t"), "\\\"\\\\\\n\\r\\t");
    }

    function testJsonEscape_RoundTripDoubleQuote() public {
        string memory input = 'say "hi"';
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripAllSpecials() public {
        // all 7 RFC 8259 named escapes: " (0x22) \ (0x5C) \b (0x08) \t (0x09) \n (0x0A) \f (0x0C) \r (0x0D)
        string memory input = string(hex"225c08090a0c0d");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- RFC 8259 named escapes missing from original: \b and \f ---

    function testJsonEscape_Backspace() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"08")), "\\b");
    }

    function testJsonEscape_FormFeed() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"0c")), "\\f");
    }

    function testJsonEscape_RoundTripBackspace() public {
        string memory input = string(hex"08");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripFormFeed() public {
        string memory input = string(hex"0c");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- \uXXXX range: U+0000-U+0007, U+000B, U+000E-U+001F ---

    function testJsonEscape_NulByte() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"00")), "\\u0000");
    }

    function testJsonEscape_ControlChar_SOH() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"01")), "\\u0001");
    }

    function testJsonEscape_VerticalTab() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"0b")), "\\u000b");
    }

    function testJsonEscape_UnitSeparator() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"1f")), "\\u001f");
    }

    function testJsonEscape_ControlChar_DLE() public pure {
        assertEq(JsonLib.jsonEscape(string(hex"10")), "\\u0010");
    }

    function testJsonEscape_RoundTripVerticalTab() public {
        string memory input = string(hex"0b");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripUnitSeparator() public {
        string memory input = string(hex"1f");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_MixedControlChars() public pure {
        // \b (0x08), \f (0x0C), VT (0x0B), US (0x1F) together
        string memory input = string(hex"080c0b1f");
        assertEq(JsonLib.jsonEscape(input), "\\b\\f\\u000b\\u001f");
    }

    function testJsonEscape_RoundTripMixedControlChars() public {
        string memory input = string(hex"080c0b1f");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- boolToString ---

    function testBoolToString_True() public pure {
        assertEq(JsonLib.boolToString(true), "true");
    }

    function testBoolToString_False() public pure {
        assertEq(JsonLib.boolToString(false), "false");
    }
}
