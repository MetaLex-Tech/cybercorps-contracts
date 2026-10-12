// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParamsV2, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictionType,
    RestrictiveLegend
} from "../src/interfaces/ILedgerEntryToken.sol";
import {EmptyExtension, SvgUriHarness} from "./CertificateSvgCompatibilityTest.t.sol";

/// @notice The certificate footer names the issuing company and makes no statutory claim. Before this
///         change every company's token carried "Recorded on the MetaLeX Labs, Inc. Tokenized Stock
///         Ledger pursuant to DGCL §§219, 224.", so a Wyoming LLC's SAFE asserted a place on another
///         company's Delaware stock ledger (Base, LET 0x8a79ebbd0ba6bf8e3c109962a6250d512cbf63a1, token 0).
contract CertificateFooterTest is Test {
    string private constant FOOTER_OPEN =
        '<text x="512" y="885" font-size="14" fill="#9A9A98" text-anchor="middle">';
    string private constant OLD_FOOTER =
        unicode'<text x="512" y="885" font-size="14" fill="#9A9A98" text-anchor="middle">Recorded on the MetaLeX Labs, Inc. Tokenized Stock Ledger pursuant to DGCL §§219, 224.</text>';
    string private constant SENTENCE = "This constitutes an official entry on the tokenized securities ledger of ";

    CertificateImageBuilderContract private image;

    function setUp() public {
        image = new CertificateImageBuilderContract();
    }

    /// @dev The parameters behind test/res/let-svg-10fa89f2-delaware-corp.svg, captured from the renderer
    ///      at develop 10fa89f2 before this change.
    function _delawareCorp() private pure returns (CertificateSVGParamsV2 memory p) {
        p.certificate.corpName = "MetaLeX Labs, Inc.";
        p.certificate.securityType = SecurityClass.CommonStock;
        p.certificate.securitySeries = SecuritySeries.SeriesSeed;
        p.certificate.officerName = "Officer";
        p.certificate.officerTitle = "CEO";
        p.certificate.jurisdiction = "Delaware";
        p.certificate.ownerName = "Holder";
        p.certificate.tokenId = 7;
        p.certificate.units = 25e17;
        p.issuerAddress = address(0xBEEF);
        p.ownerAddress = address(0xCAFE);
        p.consideration = 25e16;
        p.considerationKnown = true;
        p.statusKnown = true;
        p.transferRestrictions = new string[](2);
        p.transferRestrictions[0] = "Board consent";
        p.transferRestrictions[1] = "ROFR & co-sale";
    }

    /// @dev The parameters behind test/res/let-svg-10fa89f2-wyoming-llc-voided.svg, from the same capture.
    function _wyomingLlcVoided() private pure returns (CertificateSVGParamsV2 memory p) {
        p = _delawareCorp();
        p.certificate.corpName = "Empulser Enterprises LLC";
        p.certificate.jurisdiction = "Wyoming";
        p.certificate.securityType = SecurityClass.SAFE;
        p.certificate.securitySeries = SecuritySeries.ACE;
        p.isVoided = true;
    }

    function _footer(string memory name) private pure returns (string memory) {
        return string.concat(FOOTER_OPEN, SENTENCE, name, ".</text>");
    }

    function testFooterNamesTheIssuer() public view {
        string memory svg = image.buildCertificateSVGV2(_delawareCorp(), 1709164800);
        (, bytes memory footer,) = _splitAtFooter(svg);
        assertEq(string(footer), _footer("MetaLeX Labs, Inc."));
        assertFalse(_contains(svg, "DGCL"));
    }

    function testAnLlcNoLongerClaimsAnotherCompanysStockLedger() public view {
        string memory svg = image.buildCertificateSVGV2(_wyomingLlcVoided(), 0);
        (, bytes memory footer,) = _splitAtFooter(svg);
        assertEq(string(footer), _footer("Empulser Enterprises LLC"));
        assertFalse(_contains(svg, "MetaLeX Labs"));
        assertFalse(_contains(svg, "Stock Ledger"));
        assertFalse(_contains(svg, "DGCL"));
    }

    /// @notice The sentence is the same for every company; the jurisdiction plays no part.
    function testFooterDoesNotDependOnJurisdiction() public view {
        CertificateSVGParamsV2 memory p = _delawareCorp();
        string memory delaware = image.buildCertificateSVGV2(p, 1709164800);
        p.certificate.jurisdiction = "Wyoming";
        assertEq(image.buildCertificateSVGV2(p, 1709164800), delaware);
        p.certificate.jurisdiction = "";
        assertEq(image.buildCertificateSVGV2(p, 1709164800), delaware);
    }

    function testFooterEscapesAndTruncatesTheName() public view {
        CertificateSVGParamsV2 memory p = _delawareCorp();
        p.certificate.corpName = 'Smith & Wesson <Co> "SA"';
        (, bytes memory footer,) = _splitAtFooter(image.buildCertificateSVGV2(p, 0));
        assertEq(string(footer), _footer("Smith &amp; Wesson &lt;Co&gt; &quot;SA&quot;"));

        // 54 code points: the footer cuts at 26 with "...", the parties block's limit, so a long name in a
        // wide font cannot push the 14px sentence past the 1024px edge. The header keeps its own cut at 38.
        p.certificate.corpName = "Extraordinarily Long Company Name Holdings Corporation";
        string memory svg = image.buildCertificateSVGV2(p, 0);
        (, footer,) = _splitAtFooter(svg);
        assertEq(string(footer), _footer("Extraordinarily Long Compa..."));
        assertTrue(_contains(svg, 'y="190" font-size="32" fill="#f2f2f2" text-anchor="middle">Extraordinarily Long Company Name Hold...</text>'));
    }

    /// @notice The legacy (V1) entry point renders through the same content builder.
    function testLegacyEntryPointRendersTheSameFooter() public view {
        CertificateSVGParamsV2 memory p = _delawareCorp();
        (, bytes memory footer,) = _splitAtFooter(image.buildCertificateSVG(p.certificate, 1709164800));
        assertEq(string(footer), _footer("MetaLeX Labs, Inc."));
    }

    /// @notice Only the footer element changed. Everything before and after it is byte-identical to the
    ///         SVG the unmodified renderer produced for the same parameters.
    function testEverythingButTheFooterIsUnchanged() public view {
        _assertOnlyFooterChanged(
            image.buildCertificateSVGV2(_delawareCorp(), 1709164800),
            vm.readFile("test/res/let-svg-10fa89f2-delaware-corp.svg"),
            "MetaLeX Labs, Inc."
        );
        _assertOnlyFooterChanged(
            image.buildCertificateSVGV2(_wyomingLlcVoided(), 0),
            vm.readFile("test/res/let-svg-10fa89f2-wyoming-llc-voided.svg"),
            "Empulser Enterprises LLC"
        );
    }

    /// @notice The footer reaches the token metadata through CertificateUriBuilder with the live Empulser
    ///         company fields, and the JSON around the image is untouched.
    function testUriBuilderEmbedsTheIssuerFooter() public {
        SvgUriHarness builder = new SvgUriHarness(address(image));
        address token = address(0x1234);
        address registry = address(0x2234);
        address extension = address(0x3234);
        // STOP behaves like old fallbacks: successful call with no return data.
        vm.etch(token, hex"00");
        vm.etch(registry, hex"00");
        vm.etch(extension, address(new EmptyExtension()).code);

        CertificateDetails memory d;
        d.signingOfficerName = "Gabriel Shapiro";
        d.signingOfficerTitle = "attorney";
        d.unitsRepresented = 1e18;
        d.investmentAmountUSD = 805000e18;
        d.extensionData = hex"1234";
        Endorsement[] memory e = new Endorsement[](1);
        e[0].endorseeName = "Holder";
        e[0].signatureHash = hex"1234";
        RestrictiveLegend[] memory legends = new RestrictiveLegend[](1);
        legends[0].restrictionType = RestrictionType.Custom;
        legends[0].text = "RIA compliance legend";
        legends[0].active = true;

        string memory json = builder.buildCertificateUriNotEncoded(
            "Empulser Enterprises LLC", "Limited liability company", "Wyoming", "@contact",
            SecurityClass.SAFE, SecuritySeries.ACE, "ipfs://cert", legends, d, e,
            OwnerDetails("Holder", address(0xCAFE)), registry, bytes32(uint256(1)), 0, token, extension
        );
        string memory svg = _decode(vm.parseJsonString(json, ".image"), bytes("data:image/svg+xml;base64,").length);
        (, bytes memory footer,) = _splitAtFooter(svg);
        assertEq(string(footer), _footer("Empulser Enterprises LLC"));
        assertFalse(_contains(svg, "DGCL"));
        assertEq(vm.parseJsonString(json, ".cyberCORPType"), "Limited liability company");
        assertEq(vm.parseJsonString(json, ".cyberCORPJurisdiction"), "Wyoming");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _assertOnlyFooterChanged(string memory svg, string memory baseline, string memory name) private pure {
        (bytes memory prefix, bytes memory footer, bytes memory suffix) = _splitAtFooter(svg);
        (bytes memory oldPrefix, bytes memory oldFooter, bytes memory oldSuffix) = _splitAtFooter(baseline);
        assertEq(string(oldFooter), OLD_FOOTER, "the baseline carries the old footer");
        assertEq(string(footer), _footer(name), "the new footer");
        assertEq(prefix, oldPrefix, "bytes before the footer");
        assertEq(suffix, oldSuffix, "bytes after the footer");
    }

    /// @return prefix everything before the footer element, footer the element, suffix everything after
    function _splitAtFooter(string memory svg)
        private
        pure
        returns (bytes memory prefix, bytes memory footer, bytes memory suffix)
    {
        bytes memory b = bytes(svg);
        uint256 start = _indexOf(b, bytes(FOOTER_OPEN), 0);
        uint256 end = _indexOf(b, bytes("</text>"), start) + 7;
        return (_slice(b, 0, start), _slice(b, start, end), _slice(b, end, b.length));
    }

    function _indexOf(bytes memory hay, bytes memory needle, uint256 from) private pure returns (uint256) {
        for (uint256 i = from; i + needle.length <= hay.length; ++i) {
            bool found = true;
            for (uint256 j; j < needle.length; ++j) {
                if (hay[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        revert("needle not found");
    }

    function _slice(bytes memory b, uint256 start, uint256 end) private pure returns (bytes memory out) {
        out = new bytes(end - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = b[start + i];
        }
    }

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
