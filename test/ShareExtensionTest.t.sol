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
        string memory input = "\"\\\n\r\t";
        string memory json = string.concat('{"v":"', harness.jsonEscape(input), '"}');
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".v"), input);
    }
}
