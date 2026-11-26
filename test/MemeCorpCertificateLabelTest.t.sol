// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {
    CertificateSVGParams,
    MEMECORP_COMPANY_TYPE,
    SecurityClass,
    SecuritySeries
} from "../src/CyberCorpConstants.sol";
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictionType,
    RestrictiveLegend
} from "../src/interfaces/ILedgerEntryToken.sol";
import {EmptyExtension, SvgUriHarness} from "./CertificateSvgCompatibilityTest.t.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A memeCorp is an onchain company record with no legal entity behind it. Its units carry no rights.
///         The security class enum has no neutral value, so the renderers key on the exact company type:
///         a memeCorp certificate shows "Meme Units" and never a security class, share wording or a
///         securities ledger claim. Every other company type renders as before.
contract MemeCorpCertificateLabelTest is Test {
    string private constant FOOTER_OPEN = '<text x="512" y="885" font-size="14" fill="#9A9A98" text-anchor="middle">';
    string private constant MEME_FOOTER_TAIL = " is not a legal entity. Meme units carry no rights.</text>";

    CertificateImageBuilderContract private image;

    function setUp() public {
        image = new CertificateImageBuilderContract();
    }

    function _params(bool memeUnits) private pure returns (CertificateSVGParams memory p) {
        p.corpName = "Pepe Pals";
        p.securityType = SecurityClass.CommonStock;
        p.securitySeries = SecuritySeries.NA;
        p.officerName = "Founder";
        p.officerTitle = "Operator";
        p.jurisdiction = "None (onchain only)";
        p.ownerName = "Founder";
        p.tokenId = 0;
        p.units = 1_000_000e18;
        p.issuerAddress = address(0xBEEF);
        p.ownerAddress = address(0xCAFE);
        p.consideration = 1e18;
        p.considerationKnown = true;
        p.statusKnown = true;
        p.transferRestrictions = new string[](0);
        p.memeUnits = memeUnits;
    }

    // ------------------------------------------------------------------
    // Image
    // ------------------------------------------------------------------

    function testMemeImageShowsNeutralLabels() public view {
        string memory svg = image.buildCertificateSVG(_params(true), 1709164800);
        assertTrue(_contains(svg, ">Meme Units</text>"), "class line");
        assertTrue(_contains(svg, 'text-anchor="middle">Units</text>'), "unit tile");
        assertTrue(_contains(svg, string.concat(FOOTER_OPEN, "Pepe Pals", MEME_FOOTER_TAIL)), "footer");
        assertTrue(_contains(svg, "/unit<"), "price per unit");
    }

    function testMemeImageMakesNoSecurityOrShareClaim() public view {
        string memory svg = image.buildCertificateSVG(_params(true), 1709164800);
        assertFalse(_contains(svg, "Common Stock"));
        assertFalse(_contains(svg, "Shares"));
        assertFalse(_contains(svg, "/sh<"));
        assertFalse(_contains(svg, "securities ledger"));
    }

    function testMemeImageNeutralForEveryClass() public view {
        for (uint8 c; c <= uint8(type(SecurityClass).max); ++c) {
            CertificateSVGParams memory p = _params(true);
            p.securityType = SecurityClass(c);
            string memory svg = image.buildCertificateSVG(p, 1709164800);
            assertTrue(_contains(svg, ">Meme Units</text>"), "class line");
            assertTrue(_contains(svg, 'text-anchor="middle">Units</text>'), "unit tile");
            assertFalse(_contains(svg, "securities ledger"), "footer");
        }
    }

    function testMemeFooterEscapesAndTruncatesTheName() public view {
        CertificateSVGParams memory p = _params(true);
        p.corpName = "<Pepe & Pals> with a name far longer than the footer allows";
        string memory svg = image.buildCertificateSVG(p, 1709164800);
        assertFalse(_contains(svg, "<Pepe"));
        assertTrue(_contains(svg, "&lt;Pepe &amp; Pals&gt;"));
        assertTrue(_contains(svg, MEME_FOOTER_TAIL));
    }

    function testOrdinaryImageIsUnchangedByTheFlagField() public view {
        string memory svg = image.buildCertificateSVG(_params(false), 1709164800);
        assertTrue(_contains(svg, ">Common Stock</text>"));
        assertTrue(_contains(svg, 'text-anchor="middle">Shares</text>'));
        assertTrue(_contains(svg, "/sh<"));
        assertTrue(
            _contains(svg, "This constitutes an official entry on the tokenized securities ledger of Pepe Pals.")
        );
        assertFalse(_contains(svg, "Meme"));
    }

    // ------------------------------------------------------------------
    // Company type match
    // ------------------------------------------------------------------

    function testCompanyTypeMatchIsExact() public {
        SvgUriHarness builder = new SvgUriHarness(address(image));
        assertTrue(builder.isMemeCorpType("memeCorp (no legal entity)"));
        assertTrue(builder.isMemeCorpType(MEMECORP_COMPANY_TYPE));
        assertFalse(builder.isMemeCorpType("memecorp (no legal entity)"));
        assertFalse(builder.isMemeCorpType("memeCorp (no legal entity) "));
        assertFalse(builder.isMemeCorpType(" memeCorp (no legal entity)"));
        assertFalse(builder.isMemeCorpType("memeCorp"));
        assertFalse(builder.isMemeCorpType("Corporation memeCorp (no legal entity)"));
        assertFalse(builder.isMemeCorpType(""));
        assertFalse(builder.isMemeCorpType("Corporation"));
        assertFalse(builder.isMemeCorpType("Segregated Portfolio of Segregated Portfolio Company"));
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    function testMemeMetadataUsesMemeUnitEverywhere() public {
        string memory json = _render(MEMECORP_COMPANY_TYPE);
        assertEq(vm.parseJsonString(json, ".type"), "MemeUnit");
        assertEq(vm.parseJsonString(json, ".securityType"), "MemeUnit");
        assertEq(vm.parseJsonString(json, ".attributes[9].trait_type"), "securityType");
        assertEq(vm.parseJsonString(json, ".attributes[9].value"), "MemeUnit");
        assertEq(vm.parseJsonString(json, ".cyberCORPType"), MEMECORP_COMPANY_TYPE);
        assertFalse(_contains(json, "CommonStock"));
        string memory svg = _decode(vm.parseJsonString(json, ".image"), bytes("data:image/svg+xml;base64,").length);
        assertTrue(_contains(svg, ">Meme Units</text>"));
        assertTrue(_contains(svg, string.concat(FOOTER_OPEN, "Pepe Pals", MEME_FOOTER_TAIL)));
    }

    function testNearMissCompanyTypeKeepsTheSecurityClass() public {
        string memory json = _render("memecorp (no legal entity)");
        assertEq(vm.parseJsonString(json, ".type"), "CommonStock");
        assertEq(vm.parseJsonString(json, ".securityType"), "CommonStock");
        assertEq(vm.parseJsonString(json, ".attributes[9].value"), "CommonStock");
        string memory svg = _decode(vm.parseJsonString(json, ".image"), bytes("data:image/svg+xml;base64,").length);
        assertTrue(_contains(svg, ">Common Stock</text>"));
        assertFalse(_contains(svg, "Meme"));
    }

    function _render(string memory companyType) private returns (string memory) {
        SvgUriHarness builder = new SvgUriHarness(address(image));
        address token = address(0x1234);
        address registry = address(0x2234);
        address extension = address(0x3234);
        // STOP behaves like old fallbacks: successful call with no return data.
        vm.etch(token, hex"00");
        vm.etch(registry, hex"00");
        vm.etch(extension, address(new EmptyExtension()).code);

        CertificateDetails memory d;
        d.signingOfficerName = "Founder";
        d.signingOfficerTitle = "Operator";
        d.unitsRepresented = 1_000_000e18;
        d.investmentAmountUSD = 1e18;
        Endorsement[] memory e = new Endorsement[](0);
        RestrictiveLegend[] memory legends = new RestrictiveLegend[](1);
        legends[0].restrictionType = RestrictionType.Custom;
        legends[0].text = "No transfer restrictions apply.";
        legends[0].active = true;

        return builder.buildCertificateUriNotEncoded(
            "Pepe Pals",
            companyType,
            "None (onchain only)",
            "@pepepals",
            SecurityClass.CommonStock,
            SecuritySeries.NA,
            "ipfs://cert",
            legends,
            d,
            e,
            OwnerDetails("Founder", address(0xCAFE)),
            registry,
            bytes32(uint256(1)),
            0,
            token,
            extension
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _contains(string memory a, string memory b) private pure returns (bool) {
        bytes memory hay = bytes(a);
        bytes memory needle = bytes(b);
        if (needle.length > hay.length) return false;
        for (uint256 i; i + needle.length <= hay.length; ++i) {
            bool found = true;
            for (uint256 j; j < needle.length; ++j) {
                if (hay[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function _decode(string memory uri, uint256 prefix) private pure returns (string memory) {
        bytes memory input = bytes(uri);
        require(input.length > prefix, "nonblank SVG required");
        bytes memory decoded = new bytes((input.length - prefix) / 4 * 3);
        uint256 accumulator;
        uint256 bits;
        uint256 cursor;
        for (uint256 i = prefix; i < input.length && input[i] != "="; ++i) {
            uint256 c = uint8(input[i]);
            uint256 value = c >= 65 && c <= 90
                ? c - 65
                : c >= 97 && c <= 122 ? c - 71 : c >= 48 && c <= 57 ? c + 4 : c == 43 ? 62 : 63;
            accumulator = (accumulator << 6) | value;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                decoded[cursor++] = bytes1(uint8(accumulator >> bits));
            }
        }
        assembly ("memory-safe") {
            mstore(decoded, cursor)
        }
        return string(decoded);
    }
}
