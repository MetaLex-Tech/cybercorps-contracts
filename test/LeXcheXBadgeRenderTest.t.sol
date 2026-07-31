// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {LeXcheXBadgeRender} from "../src/creds/LeXcheXBadgeRender.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {InvestorType} from "../src/interfaces/ILexChexBadge.sol";

/// @notice Covers the lookThroughJurisdiction rendering added to LeXcheXBadgeRender: the tokenURI metadata
/// trait and the SVG row are emitted only when the field is set, and never displace the physical jurisdiction.
contract LeXcheXBadgeRenderTest is Test {
    using stdJson for string;

    function _cred(string memory regulatory) internal pure returns (Credential memory c) {
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "KY";
        c.lookThroughJurisdiction = regulatory;
        c.expiryDate = 1_893_456_000;
    }

    function test_TokenUri_IncludesRegulatoryJurisdiction_WhenSet() public {
        (string memory json, string memory svg) = _decode(LeXcheXBadgeRender.tokenURI(1, _cred("US"), true));

        (bool foundReg, string memory regValue) = _trait(json, "Regulatory Jurisdiction");
        assertTrue(foundReg, "reg trait missing");
        assertEq(regValue, "US");

        (bool foundJx, string memory jxValue) = _trait(json, "Jurisdiction");
        assertTrue(foundJx, "physical trait missing");
        assertEq(jxValue, "KY");

        // The SVG image is XML, not JSON — no field parser applies, so a substring check is the only option.
        assertTrue(vm.contains(svg, "REGULATORY"), "svg reg row missing");
    }

    function test_TokenUri_OmitsRegulatoryJurisdiction_WhenEmpty() public {
        (string memory json, string memory svg) = _decode(LeXcheXBadgeRender.tokenURI(1, _cred(""), true));

        (bool foundReg,) = _trait(json, "Regulatory Jurisdiction");
        assertFalse(foundReg, "reg trait should be absent");

        // The physical jurisdiction is still rendered.
        (bool foundJx, string memory jxValue) = _trait(json, "Jurisdiction");
        assertTrue(foundJx, "physical trait missing");
        assertEq(jxValue, "KY");

        assertFalse(vm.contains(svg, "REGULATORY"), "svg reg row should be absent");
    }

    // ── Audit findings ──────────────────────────────────────────────────────────

    // L1 — the expiry is the holder's record of when re-attestation is due, so it has to be the real date.
    // Covers a leap day, both sides of a month boundary, and a year end.
    function test_Audit_L1_ExpiryRendersTheRealCalendarDate() public {
        assertEq(_expiryShown(1_767_225_600), "1/1/2026");   // 2026-01-01
        assertEq(_expiryShown(1_772_323_200), "3/1/2026");   // 2026-03-01, the day after a 28-day February
        assertEq(_expiryShown(1_772_236_800), "2/28/2026");  // 2026-02-28
        assertEq(_expiryShown(1_709_164_800), "2/29/2024");  // 2024-02-29, a leap day
        assertEq(_expiryShown(1_798_675_200), "12/31/2026"); // 2026-12-31
        assertEq(_expiryShown(1_893_456_000), "1/1/2030");   // the fixture's default expiry
    }

    /// @dev Renders a credential expiring at `ts` and reads the Expiry trait back.
    function _expiryShown(uint64 ts) internal view returns (string memory) {
        Credential memory c = _cred("");
        c.expiryDate = ts;
        (string memory json,) = _decode(LeXcheXBadgeRender.tokenURI(1, c, true));
        (bool found, string memory shown) = _trait(json, "Expiry");
        assertTrue(found, "expiry trait missing");
        return shown;
    }

    // L2 — jurisdictions are typed in by an operator, the only part of a credential that can contain
    // characters JSON reserves. A quote has to stay inside the value instead of ending it.
    function test_Audit_L2_JurisdictionIsEscapedInJson() public {
        Credential memory c = _cred("");
        c.investorJurisdiction = "US\", \"injected\": \"yes";
        (string memory json,) = _decode(LeXcheXBadgeRender.tokenURI(1, c, true));

        // The whole value stays one string, and no extra field appears next to it.
        assertEq(json.readString(".attributes[1].value"), "US\", \"injected\": \"yes");
        assertFalse(vm.keyExistsJson(json, ".attributes[1].injected"), "no field was injected");
    }

    // The same value in the SVG, where the reserved characters are XML's instead.
    function test_Audit_L2_JurisdictionIsEscapedInSvg() public {
        Credential memory c = _cred("<script>&");
        c.investorJurisdiction = "KY";
        (, string memory svg) = _decode(LeXcheXBadgeRender.tokenURI(1, c, true));

        assertTrue(vm.contains(svg, "&lt;script&gt;&amp;"), "reserved characters must be escaped");
        assertFalse(vm.contains(svg, "<script>"), "raw markup must not reach the image");
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    /// @dev Reads the metadata `attributes` array as JSON and returns the value for a trait_type (exact match).
    function _trait(string memory json, string memory traitType)
        internal
        view
        returns (bool found, string memory value)
    {
        bytes32 target = keccak256(bytes(traitType));
        for (uint256 i = 0;; i++) {
            string memory element = string.concat(".attributes[", vm.toString(i), "]");
            if (!json.keyExists(element)) break;
            if (keccak256(bytes(json.readString(string.concat(element, ".trait_type")))) == target) {
                return (true, json.readString(string.concat(element, ".value")));
            }
        }
        return (false, "");
    }

    /// @dev Splits the base64 data URI into its decoded (outer JSON, inner SVG). forge-std has JSON parsing
    /// (parseJsonString) and toBase64 encoding but no base64 decode cheatcode, so decoding is hand-rolled.
    function _decode(string memory uri) internal pure returns (string memory json, string memory svg) {
        json = string(_b64decode(_afterComma(uri)));
        svg = string(_b64decode(_afterComma(json.readString(".image"))));
    }

    /// @dev The payload of a `data:...;base64,<payload>` URI (base64 has no comma, so one split suffices).
    function _afterComma(string memory dataUri) internal pure returns (string memory) {
        bytes memory b = bytes(dataUri);
        uint256 start;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") {
                start = i + 1;
                break;
            }
        }
        bytes memory out = new bytes(b.length - start);
        for (uint256 i = start; i < b.length; i++) {
            out[i - start] = b[i];
        }
        return string(out);
    }

    function _b64decode(string memory s) internal pure returns (bytes memory) {
        bytes memory data = bytes(s);
        uint256 len = data.length;
        if (len == 0) return "";

        bytes memory alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint8[128] memory table;
        for (uint8 i = 0; i < 64; i++) {
            table[uint8(alphabet[i])] = i;
        }

        uint256 padding;
        if (data[len - 1] == "=") padding++;
        if (data[len - 2] == "=") padding++;
        uint256 outLen = (len / 4) * 3 - padding;

        bytes memory result = new bytes(outLen);
        uint256 j;
        for (uint256 i = 0; i < len; i += 4) {
            uint256 n = (uint256(table[uint8(data[i])]) << 18) | (uint256(table[uint8(data[i + 1])]) << 12)
                | (uint256(table[uint8(data[i + 2])]) << 6) | uint256(table[uint8(data[i + 3])]);
            if (j < outLen) result[j++] = bytes1(uint8(n >> 16));
            if (j < outLen) result[j++] = bytes1(uint8(n >> 8));
            if (j < outLen) result[j++] = bytes1(uint8(n));
        }
        return result;
    }
}
