// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {LeXcheXBadgeRender} from "../src/creds/LeXcheXBadgeRender.sol";
import {Credential, CredentialCategory, CategoryKind} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";

/// @notice Covers the regulatoryJurisdiction rendering added to LeXcheXBadgeRender: the tokenURI metadata
/// trait and the SVG row are emitted only when the field is set, and never displace the physical jurisdiction.
contract LeXcheXBadgeRenderTest is Test {
    using stdJson for string;

    function _cred(string memory regulatory) internal pure returns (Credential memory c) {
        c.investorName = "Acme Feeder LP";
        c.investorType = "Fund";
        c.investorJurisdiction = "KY";
        c.regulatoryJurisdiction = regulatory;
        c.expiryDate = 1_893_456_000;
    }

    function _cat() internal pure returns (CredentialCategory memory c) {
        c.name = "Accredited";
        c.description = "desc";
        c.kind = CategoryKind.ACCREDITED_INVESTOR;
        c.burnAuth = IERC5484.BurnAuth.OwnerOnly;
        c.exists = true;
        c.active = true;
    }

    function test_TokenUri_IncludesRegulatoryJurisdiction_WhenSet() public {
        (string memory json, string memory svg) = _decode(LeXcheXBadgeRender.tokenURI(1, _cred("US"), _cat(), true));

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
        (string memory json, string memory svg) = _decode(LeXcheXBadgeRender.tokenURI(1, _cred(""), _cat(), true));

        (bool foundReg,) = _trait(json, "Regulatory Jurisdiction");
        assertFalse(foundReg, "reg trait should be absent");

        // The physical jurisdiction is still rendered.
        (bool foundJx, string memory jxValue) = _trait(json, "Jurisdiction");
        assertTrue(foundJx, "physical trait missing");
        assertEq(jxValue, "KY");

        assertFalse(vm.contains(svg, "REGULATORY"), "svg reg row should be absent");
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
