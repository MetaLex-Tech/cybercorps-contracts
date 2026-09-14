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

    // --- UTF-8 validity: RFC 8259 requires JSON text to be valid UTF-8, but a Solidity string is
    // any bytes. A byte that is not part of a valid sequence becomes U+FFFD (hex "efbfbd").

    string internal constant REPLACEMENT = "\xef\xbf\xbd";

    /// @dev Solidity refuses a string literal that is not valid UTF-8, which is what these tests need.
    /// A bytes value carries the same bytes past that check.
    function _raw(bytes memory value) private pure returns (string memory) {
        return string(value);
    }

    function testJsonEscape_KeepsValidTwoByteSequence() public pure {
        // U+00E9 LATIN SMALL LETTER E WITH ACUTE
        assertEq(JsonLib.jsonEscape(string(hex"c3a9")), string(hex"c3a9"));
    }

    function testJsonEscape_KeepsValidThreeByteSequence() public pure {
        // U+20AC EURO SIGN
        assertEq(JsonLib.jsonEscape(string(hex"e282ac")), string(hex"e282ac"));
    }

    function testJsonEscape_KeepsValidFourByteSequence() public pure {
        // U+1F600 GRINNING FACE
        assertEq(JsonLib.jsonEscape(string(hex"f09f9880")), string(hex"f09f9880"));
    }

    function testJsonEscape_ReplacesLoneContinuationByte() public pure {
        assertEq(JsonLib.jsonEscape(_raw(hex"80")), REPLACEMENT);
    }

    function testJsonEscape_ReplacesTruncatedSequence() public pure {
        // A name cut to a fixed byte length can end in a lead byte with no continuation.
        assertEq(JsonLib.jsonEscape(_raw(hex"41c3")), string.concat("A", REPLACEMENT));
    }

    function testJsonEscape_ReplacesOverlongForm() public pure {
        // C0 80 is an overlong encoding of U+0000. Both bytes are bad, so both are replaced.
        assertEq(JsonLib.jsonEscape(_raw(hex"c080")), string.concat(REPLACEMENT, REPLACEMENT));
    }

    function testJsonEscape_ReplacesSurrogate() public pure {
        // ED A0 80 would decode to U+D800, which UTF-8 does not allow.
        assertEq(
            JsonLib.jsonEscape(_raw(hex"eda080")),
            string.concat(REPLACEMENT, REPLACEMENT, REPLACEMENT)
        );
    }

    function testJsonEscape_ReplacesAboveMaxCodePoint() public pure {
        // F5 starts a value above U+10FFFF. The three continuation bytes are then stray.
        assertEq(
            JsonLib.jsonEscape(_raw(hex"f5808080")),
            string.concat(REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT)
        );
    }

    function testJsonEscape_MixesValidAndInvalidBytes() public pure {
        assertEq(
            JsonLib.jsonEscape(_raw(hex"41c3a9ff42")),
            string.concat(string(hex"41c3a9"), REPLACEMENT, "B")
        );
    }

    function testJsonEscape_RoundTripInvalidByte() public {
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(_raw(hex"4180ff42")), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), string.concat("A", REPLACEMENT, REPLACEMENT, "B"));
    }

    function testJsonEscape_RoundTripValidMultiByte() public {
        string memory input = string(hex"f09f9880");
        string memory json = string.concat('{"v":"', JsonLib.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }

    // --- stringArrayToJson ---

    function testStringArrayToJson_Empty() public pure {
        assertEq(JsonLib.stringArrayToJson(new string[](0)), "[]");
    }

    function testStringArrayToJson_EscapesEachElement() public pure {
        string[] memory values = new string[](2);
        values[0] = 'a"b';
        values[1] = "c";
        assertEq(JsonLib.stringArrayToJson(values), '["a\\"b", "c"]');
    }

    // --- boolToString ---

    function testBoolToString_True() public pure {
        assertEq(JsonLib.boolToString(true), "true");
    }

    function testBoolToString_False() public pure {
        assertEq(JsonLib.boolToString(false), "false");
    }
}
