// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";

contract ShareExtensionHarness is ShareExtension {
    function jsonEscape(string memory s) external pure returns (string memory) {
        return _jsonEscape(s);
    }
}

contract ShareExtensionTest is Test {
    ShareExtensionHarness internal harness;

    function setUp() public {
        harness = new ShareExtensionHarness();
    }

    function testJsonEscape_EmptyString() public view {
        assertEq(harness.jsonEscape(""), "");
    }

    function testJsonEscape_NoSpecialChars() public view {
        assertEq(harness.jsonEscape("hello world"), "hello world");
    }

    function testJsonEscape_DoubleQuote() public view {
        assertEq(harness.jsonEscape('say "hi"'), "say \\\"hi\\\"");
    }

    function testJsonEscape_Backslash() public view {
        assertEq(harness.jsonEscape("path\\to"), "path\\\\to");
    }

    function testJsonEscape_Newline() public view {
        assertEq(harness.jsonEscape("line1\nline2"), "line1\\nline2");
    }

    function testJsonEscape_CarriageReturn() public view {
        assertEq(harness.jsonEscape("a\rb"), "a\\rb");
    }

    function testJsonEscape_Tab() public view {
        assertEq(harness.jsonEscape("a\tb"), "a\\tb");
    }

    function testJsonEscape_AdjacentSpecials() public view {
        assertEq(harness.jsonEscape('""'), "\\\"\\\"");
    }

    function testJsonEscape_AllSpecialsTogether() public view {
        assertEq(harness.jsonEscape("\"\\\n\r\t"), "\\\"\\\\\\n\\r\\t");
    }

    function testJsonEscape_RoundTripDoubleQuote() public view {
        string memory input = 'say "hi"';
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripAllSpecials() public view {
        // all 7 RFC 8259 named escapes: " (0x22) \ (0x5C) \b (0x08) \t (0x09) \n (0x0A) \f (0x0C) \r (0x0D)
        string memory input = string(hex"225c08090a0c0d");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- RFC 8259 named escapes missing from original: \b and \f ---

    function testJsonEscape_Backspace() public view {
        assertEq(harness.jsonEscape(string(hex"08")), "\\b");
    }

    function testJsonEscape_FormFeed() public view {
        assertEq(harness.jsonEscape(string(hex"0c")), "\\f");
    }

    function testJsonEscape_RoundTripBackspace() public view {
        string memory input = string(hex"08");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripFormFeed() public view {
        string memory input = string(hex"0c");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- \uXXXX range: U+0000-U+0007, U+000B, U+000E-U+001F ---

    function testJsonEscape_NulByte() public view {
        assertEq(harness.jsonEscape(string(hex"00")), "\\u0000");
    }

    function testJsonEscape_ControlChar_SOH() public view {
        assertEq(harness.jsonEscape(string(hex"01")), "\\u0001");
    }

    function testJsonEscape_VerticalTab() public view {
        assertEq(harness.jsonEscape(string(hex"0b")), "\\u000b");
    }

    function testJsonEscape_UnitSeparator() public view {
        assertEq(harness.jsonEscape(string(hex"1f")), "\\u001f");
    }

    function testJsonEscape_ControlChar_DLE() public view {
        assertEq(harness.jsonEscape(string(hex"10")), "\\u0010");
    }

    function testJsonEscape_RoundTripVerticalTab() public view {
        string memory input = string(hex"0b");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_RoundTripUnitSeparator() public view {
        string memory input = string(hex"1f");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    function testJsonEscape_MixedControlChars() public view {
        // \b (0x08), \f (0x0C), VT (0x0B), US (0x1F) together
        string memory input = string(hex"080c0b1f");
        assertEq(harness.jsonEscape(input), "\\b\\f\\u000b\\u001f");
    }

    function testJsonEscape_RoundTripMixedControlChars() public view {
        string memory input = string(hex"080c0b1f");
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }
}
