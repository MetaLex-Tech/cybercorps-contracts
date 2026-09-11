// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CertificateUriBuilder, Base64} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParams, CertificateSVGParamsV2, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {RestrictionType, RestrictiveLegend} from "../src/interfaces/ILedgerEntryToken.sol";
import {ICertificateImageBuilder, ICertificateImageBuilderV2} from "../src/interfaces/ICertificateImageBuilder.sol";
import {MockCyberCorp, MockIssuanceManager} from "./CyberCertPrinterTest.t.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CertificateDetails, ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SvgUriHarness is CertificateUriBuilder {
    constructor(address image) { imageBuilder = image; }
}

contract CertificateSvgCompatibilityTest is Test {
    SvgUriHarness internal builder;
    CertificateImageBuilderContract internal image;
    address internal constant TOKEN = address(0x1234);
    address internal constant REGISTRY = address(0x2234);
    address internal constant EXTENSION = address(0x3234);
    address internal constant MANAGER = address(0x4234);
    address internal constant CORP = address(0x5234);

    function setUp() public {
        image = new CertificateImageBuilderContract();
        builder = new SvgUriHarness(address(image));
        // STOP behaves like old fallbacks: successful call with no return data.
        vm.etch(TOKEN, hex"00"); vm.etch(REGISTRY, hex"00"); vm.etch(EXTENSION, hex"00");
        vm.etch(MANAGER, hex"00"); vm.etch(CORP, hex"00");
    }

    function _params() internal pure returns (CertificateSVGParamsV2 memory p) {
        p.certificate.corpName = "Example Corp";
        p.certificate.securityType = SecurityClass.CommonStock;
        p.certificate.securitySeries = SecuritySeries.SeriesSeed;
        p.certificate.officerName = "Officer";
        p.certificate.officerTitle = "CEO";
        p.certificate.ownerName = "Holder";
        p.certificate.tokenId = 1;
        p.certificate.units = 25e17;
        p.consideration = 25e16;
        p.considerationKnown = true;
        p.statusKnown = true;
    }

    function _json(bool legacy, bool encoded) internal view returns (string memory) {
        CertificateUriBuilder.CertificateDetails memory d;
        d.signingOfficerName = "Officer";
        d.signingOfficerTitle = "CEO";
        d.unitsRepresented = 25e17;
        d.investmentAmountUSD = 25e16;
        d.extensionData = hex"1234";
        CertificateUriBuilder.Endorsement[] memory e = new CertificateUriBuilder.Endorsement[](1);
        e[0].endorseeName = "Holder";
        e[0].signatureHash = hex"1234";
        CertificateUriBuilder.OwnerDetails memory owner = CertificateUriBuilder.OwnerDetails("Holder", address(0xCAFE));
        string[] memory texts = new string[](1); texts[0] = "Board consent";
        if (legacy) {
            if (encoded) return builder.buildCertificateUri("Example Corp", "Corp", "DE", "contact", SecurityClass.CommonStock,
                SecuritySeries.SeriesSeed, "ipfs://cert", texts, d, e, owner, REGISTRY, bytes32(uint256(1)), 1, TOKEN, EXTENSION);
            return builder.buildCertificateUriNotEncoded("Example Corp", "Corp", "DE", "contact", SecurityClass.CommonStock,
                SecuritySeries.SeriesSeed, "ipfs://cert", texts, d, e, owner, REGISTRY, bytes32(uint256(1)), 1, TOKEN, EXTENSION);
        }
        RestrictiveLegend[] memory legends = new RestrictiveLegend[](1);
        legends[0].restrictionType = RestrictionType.Custom;
        legends[0].text = texts[0]; legends[0].active = true;
        if (encoded) return builder.buildCertificateUri("Example Corp", "Corp", "DE", "contact", SecurityClass.CommonStock,
            SecuritySeries.SeriesSeed, "ipfs://cert", legends, d, e, owner, REGISTRY, bytes32(uint256(1)), 1, TOKEN, EXTENSION);
        return builder.buildCertificateUriNotEncoded("Example Corp", "Corp", "DE", "contact", SecurityClass.CommonStock,
            SecuritySeries.SeriesSeed, "ipfs://cert", legends, d, e, owner, REGISTRY, bytes32(uint256(1)), 1, TOKEN, EXTENSION);
    }

    function _svg(string memory json) internal view returns (string memory) {
        string memory uri = vm.parseJsonString(json, ".image");
        return _decode(uri, bytes("data:image/svg+xml;base64,").length);
    }

    function _decode(string memory uri, uint256 prefix) internal pure returns (string memory) {
        bytes memory input = bytes(uri);
        require(input.length > prefix, "nonblank SVG required");
        bytes memory decoded = new bytes((input.length - prefix) / 4 * 3);
        uint256 accumulator; uint256 bits; uint256 cursor;
        for (uint256 i = prefix; i < input.length && input[i] != "="; ++i) {
            uint256 c = uint8(input[i]);
            uint256 value = c >= 65 && c <= 90 ? c - 65 : c >= 97 && c <= 122 ? c - 71 : c >= 48 && c <= 57 ? c + 4 : c == 43 ? 62 : 63;
            accumulator = (accumulator << 6) | value; bits += 6;
            if (bits >= 8) { bits -= 8; decoded[cursor++] = bytes1(uint8(accumulator >> bits)); }
        }
        assembly ("memory-safe") { mstore(decoded, cursor) }
        return string(decoded);
    }

    function _contains(string memory a, string memory b) internal pure returns (bool) {
        bytes memory hay = bytes(a); bytes memory needle = bytes(b);
        if (needle.length > hay.length) return false;
        bool found;
        assembly ("memory-safe") {
            let n := mload(needle)
            let hash := keccak256(add(needle, 32), n)
            let end := add(add(hay, 32), sub(mload(hay), n))
            for { let p := add(hay, 32) } iszero(gt(p, end)) { p := add(p, 1) } {
                if eq(keccak256(p, n), hash) { found := 1 break }
            }
        }
        return found;
    }

    function testOldAndCurrentUriSelectorsWithAllOptionalDataMissing() public view {
        string memory json = _json(true, false);
        vm.parseJson(json);
        assertEq(json, _json(false, false));
        assertEq(_json(true, true), string.concat("data:application/json;base64,", Base64.encode(bytes(json))));
        assertEq(_json(false, true), _json(true, true));
        assertFalse(vm.keyExistsJson(json, ".unitsReserved"));
        assertEq(vm.parseJsonString(json, ".endorsementHistory[0].investorName"), "Holder");
        string memory svg = _svg(json);
        assertTrue(_contains(svg, "Ledger Entry Token"));
        assertFalse(_contains(svg, ">active</text>"));
        assertFalse(_contains(svg, "1970"));
    }

    function testIssueDateUsesStoredOverrideAndIgnoresAcquisitionAndReadTime() public {
        vm.mockCall(TOKEN, abi.encodeWithSignature("issueTimestamp(uint256)", 1), abi.encode(uint64(1709164800)));
        vm.mockCall(TOKEN, abi.encodeWithSignature("acquisitionTimestamp(uint256)", 1), abi.encode(uint64(1)));
        string memory first = _json(false, false);
        assertTrue(_contains(_svg(first), ">2-29-2024</text>"));
        vm.warp(2000000000); vm.roll(123456);
        vm.mockCall(TOKEN, abi.encodeWithSignature("acquisitionTimestamp(uint256)", 1), abi.encode(uint64(1900000000)));
        assertEq(first, _json(false, false));
        vm.mockCall(TOKEN, abi.encodeWithSignature("issueTimestamp(uint256)", 1), abi.encode(uint64(951782400)));
        assertTrue(_contains(_svg(_json(false, false)), ">2-29-2000</text>"));
    }

    function testMissingIssueDateIsStableAndDoesNotUseRegistryDate() public {
        string memory first = _json(false, false);
        vm.warp(2000000000); vm.roll(999999);
        assertEq(first, _json(false, false));
        vm.mockCall(TOKEN, abi.encodeWithSignature("issueTimestamp(uint256)", 1), abi.encode(type(uint256).max));
        assertEq(first, _json(false, false));
    }

    function testMalformedAndRevertingDependenciesDoNotDiscardMetadata() public {
        vm.mockCall(TOKEN, abi.encodeWithSignature("unitsReserved(uint256)", 1), hex"01");
        vm.mockCall(TOKEN, abi.encodeWithSignature("issueTimestamp(uint256)", 1), hex"01");
        vm.mockCall(TOKEN, abi.encodeWithSignature("isVoided(uint256)", 1), abi.encode(uint256(2)));
        vm.mockCall(TOKEN, abi.encodeWithSignature("getSeriesInfo()"), hex"01");
        vm.mockCall(REGISTRY, abi.encodeWithSignature("getContractDetails(bytes32)", bytes32(uint256(1))), hex"01");
        vm.mockCall(EXTENSION, abi.encodeWithSignature("getExtensionURI(bytes)", hex"1234"), hex"01");
        string memory json = _json(false, false);
        vm.parseJson(json); assertGt(bytes(_svg(json)).length, 0);
        assertEq(vm.parseJsonString(json, ".unitsRepresented"), "2.50");
        vm.mockCallRevert(TOKEN, abi.encodeWithSignature("getSeriesInfo()"), hex"1234");
        vm.mockCallRevert(REGISTRY, abi.encodeWithSignature("getContractDetails(bytes32)", bytes32(uint256(1))), hex"1234");
        vm.mockCallRevert(EXTENSION, abi.encodeWithSignature("getExtensionURI(bytes)", hex"1234"), hex"1234");
        assertEq(json, _json(false, false));
    }

    function testSupportedOptionalMetadataAndZeroReservationsPreserved() public {
        vm.mockCall(TOKEN, abi.encodeWithSignature("unitsReserved(uint256)", 1), abi.encode(uint256(0)));
        vm.mockCall(TOKEN, abi.encodeWithSignature("issuanceManager()"), abi.encode(MANAGER));
        vm.mockCall(MANAGER, abi.encodeWithSignature("CORP()"), abi.encode(CORP));
        vm.mockCall(CORP, abi.encodeWithSignature("getExtensionURI()"), abi.encode(', "issuerExtra": "yes"'));
        vm.mockCall(EXTENSION, abi.encodeWithSignature("getExtensionURI(bytes)", hex"1234"), abi.encode(', "certificateExtra": "yes"'));
        // A V1 or V2 extension does not answer the resolved probe, so the cert payload renders alone.
        string memory json = _json(false, false);
        assertEq(vm.parseJsonString(json, ".unitsReserved"), "0.00");
        assertEq(vm.parseJsonString(json, ".issuerExtra"), "yes");
        assertEq(vm.parseJsonString(json, ".certificateExtra"), "yes");

        // A V3 extension reads every scope itself and returns one section, which replaces the per-scope render.
        vm.mockCall(EXTENSION, abi.encodeWithSignature("supportsResolvedExtensionData()"), abi.encode(true));
        vm.mockCall(
            EXTENSION,
            abi.encodeWithSignature("getResolvedExtensionURI(address,uint256)", TOKEN, uint256(1)),
            abi.encode(', "resolvedExtra": "yes"')
        );
        json = _json(false, false);
        assertEq(vm.parseJsonString(json, ".resolvedExtra"), "yes");
        assertFalse(vm.keyExistsJson(json, ".certificateExtra"));
        assertEq(vm.parseJsonString(json, ".issuerExtra"), "yes");

        // A malformed resolved return omits that section and keeps every other field.
        vm.mockCall(
            EXTENSION, abi.encodeWithSignature("getResolvedExtensionURI(address,uint256)", TOKEN, uint256(1)), hex"01"
        );
        json = _json(false, false);
        assertFalse(vm.keyExistsJson(json, ".resolvedExtra"));
        assertEq(vm.parseJsonString(json, ".unitsReserved"), "0.00");
        assertEq(vm.parseJsonString(json, ".issuerExtra"), "yes");
    }

    function testRegistryEmptyGlobalFieldsWithPartyFieldsRemainsValidJson() public {
        string[] memory empty = new string[](0);
        string[] memory fields = new string[](2); fields[0] = "name"; fields[1] = 'quote"';
        string[][] memory values = new string[][](2);
        values[0] = new string[](1); values[0][0] = "Corp";
        values[1] = new string[](2); values[1][0] = "Holder"; values[1][1] = 'A"B';
        uint256[] memory signed = new uint256[](2); signed[0] = 2000000000;
        vm.mockCall(REGISTRY, abi.encodeWithSignature("getContractDetails(bytes32)", bytes32(uint256(1))),
            abi.encode(bytes32(0), "", empty, fields, empty, new address[](0), values, signed, uint256(1), false, bytes32(0)));
        string memory json = _json(false, false);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".endorsementHistory[0].purchaseAgreementDetails.companyDetails.name"), "Corp");
        assertEq(vm.parseJsonString(json, ".endorsementHistory[0].purchaseAgreementDetails.digitalSignature"), "0x1234");
        assertFalse(_contains(_svg(json), "2033"));
    }

    function testKnownVoidedAndActiveStatus() public {
        vm.mockCall(TOKEN, abi.encodeWithSignature("isVoided(uint256)", 1), abi.encode(true));
        string memory svg = _svg(_json(false, false));
        assertTrue(_contains(svg, ">VOIDED</text>")); assertFalse(_contains(svg, ">active</text>"));
        vm.mockCall(TOKEN, abi.encodeWithSignature("isVoided(uint256)", 1), abi.encode(false));
        assertTrue(_contains(_svg(_json(false, false)), ">active</text>"));
    }

    function testImageFailureReturnsValidJsonWithBlankImage() public {
        vm.etch(address(image), hex"00");
        string memory json = _json(false, false); vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".image"), "");
        assertEq(vm.parseJsonString(json, ".currentOwner.name"), "Holder");
    }

    function testOversizedAndGasExhaustingOptionalReturnIsOmitted() public {
        string memory expected = _json(false, false);
        // Return 128 KiB + 1 bytes. The call must be rejected before copying returndata.
        vm.etch(EXTENSION, hex"620200016000f3");
        assertEq(_json(false, false), expected);
        // Consume the entire optional-call gas allowance.
        vm.etch(EXTENSION, hex"5b600056");
        assertEq(_json(false, false), expected);
        vm.etch(EXTENSION, hex"00");
        vm.mockCall(EXTENSION, abi.encodeWithSignature("getExtensionURI(bytes)", hex"1234"), abi.encode(uint256(0xffff)));
        assertEq(_json(false, false), expected);
    }

    function testLegacyImageSelectorAndFallbackRemainCallable() public {
        CertificateSVGParamsV2 memory p = _params();
        assertTrue(_contains(image.buildCertificateSVG(p.certificate, 1709164800), "Ledger Entry Token"));
        vm.mockCallRevert(address(image), abi.encodeWithSelector(ICertificateImageBuilderV2.buildCertificateSVGV2.selector), hex"");
        assertEq(vm.parseJsonString(_json(false, false), ".image"), "");
        vm.mockCall(TOKEN, abi.encodeWithSignature("issueTimestamp(uint256)", 1), abi.encode(uint64(1709164800)));
        assertTrue(_contains(_svg(_json(false, false)), "Ledger Entry Token"));
    }

    function testGregorianDatesAndUnsupportedBounds() public view {
        CertificateSVGParamsV2 memory p = _params();
        assertTrue(_contains(image.buildCertificateSVGV2(p, 4107542400), ">3-1-2100</text>"));
        assertTrue(_contains(image.buildCertificateSVGV2(p, 1704067200), ">1-1-2024</text>"));
        assertTrue(_contains(image.buildCertificateSVGV2(p, 253402300799), ">12-31-9999</text>"));
        assertFalse(_contains(image.buildCertificateSVGV2(p, 0), "1970"));
        assertEq(image.buildCertificateSVGV2(p, type(uint256).max), image.buildCertificateSVGV2(p, 0));
    }

    function testXmlEscapingFractionalUnitsAndCurrencyNeutralConsideration() public view {
        CertificateSVGParamsV2 memory p = _params();
        p.certificate.corpName = 'A & B <C> "D"';
        bytes memory invalidName = hex"486f6c64657201ff";
        p.certificate.ownerName = string(invalidName);
        p.transferRestrictions = new string[](1); p.transferRestrictions[0] = 'No <script>&';
        string memory svg = image.buildCertificateSVGV2(p, 0);
        assertTrue(_contains(svg, "A &amp; B &lt;C&gt; &quot;D&quot;"));
        assertTrue(_contains(svg, "No &lt;script&gt;&amp;"));
        assertFalse(_contains(svg, "<script>"));
        assertTrue(_contains(svg, ">2.5</text>"));
        assertTrue(_contains(svg, ">0.1/sh</text>"));
        p.certificate.securityType = SecurityClass.SAFE;
        assertFalse(_contains(image.buildCertificateSVGV2(p, 0), "$"));
    }

    function testExtremeConsiderationAndZeroUnitsDoNotRevert() public view {
        CertificateSVGParamsV2 memory p = _params();
        p.consideration = type(uint256).max;
        p.certificate.units = 1;
        assertGt(bytes(image.buildCertificateSVGV2(p, 0)).length, 0);
        p.certificate.units = 0;
        assertGt(bytes(image.buildCertificateSVGV2(p, 0)).length, 0);
        p.certificate.units = type(uint256).max;
        assertTrue(_contains(image.buildCertificateSVGV2(p, 0), ">1/sh</text>"));
    }

    function testCurrentTokenMintOverridesAndLegalOwnerChange() public {
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        MockIssuanceManager manager = new MockIssuanceManager(address(corp), address(builder));
        LedgerEntryToken token = LedgerEntryToken(address(new ERC1967Proxy(address(new LedgerEntryToken()),
            abi.encodeCall(LedgerEntryToken.initialize, (new string[](0), "Shares", "SH", "ipfs://cert",
                address(manager), SecurityClass.CommonStock, SecuritySeries.SeriesSeed, address(0), bytes(""))))));
        CertificateDetails memory d;
        d.unitsRepresented = 25e17;
        d.signingOfficerName = "Officer";
        vm.warp(1709164800);
        vm.prank(address(manager));
        token.safeMintAndAssign(address(0xCAFE), 1, d, "Holder");
        string memory uri = token.tokenURI(1);
        assertTrue(_contains(_svg(_decode(uri, 29)), ">2-29-2024</text>"));
        vm.warp(1800000000); vm.roll(1234);
        assertEq(token.tokenURI(1), uri);
        vm.prank(address(manager)); token.setAcquisitionTimestamp(1, 1800000000);
        assertEq(token.tokenURI(1), uri);
        vm.prank(address(manager)); token.setIssueTimestamp(1, 951782400);
        assertTrue(_contains(_svg(_decode(token.tokenURI(1), 29)), ">2-29-2000</text>"));
        vm.startPrank(address(manager));
        token.setGlobalLegalTransferable(true);
        token.assignCert(address(0xCAFE), 1, address(0xBEEF), d, "Next Holder");
        vm.stopPrank();
        assertEq(token.issueTimestamp(1), 951782400);
        assertEq(token.acquisitionTimestamp(1), 1800000000);
        string memory json = _decode(token.tokenURI(1), 29);
        assertTrue(_contains(_svg(json), ">2-29-2000</text>"));
        assertEq(vm.parseJsonAddress(json, ".currentOwner.ownerAddress"), address(0xBEEF));
        vm.expectRevert(ILedgerEntryToken.URIQueryForNonexistentToken.selector);
        token.tokenURI(999);
    }

    function testLongTextPreviewRetainsFullRestrictionListInMetadata() public {
        CertificateSVGParamsV2 memory p = _params();
        p.certificate.corpName = "A very long corporation name with many more words than fit";
        p.certificate.ownerName = "A very long registered holder name that needs shortening";
        p.transferRestrictions = new string[](8);
        for (uint256 i; i < 8; ++i) p.transferRestrictions[i] = "Board consent required & securities transfer limitations apply";
        string memory svg = image.buildCertificateSVGV2(p, 1709164800);
        assertTrue(_contains(svg, "Additional restrictions in token metadata"));
        assertTrue(_contains(svg, "..."));
        if (vm.envOr("SVG_PREVIEW", false)) {
            emit log_named_string("SVG_LONG", svg);
            p = _params();
            p.issuerAddress = address(0x1234567890123456789012345678901234567890);
            p.ownerAddress = address(0x2234567890123456789012345678901234567890);
            emit log_named_string("SVG_NORMAL", image.buildCertificateSVGV2(p, 1709164800));
            p.isVoided = true;
            emit log_named_string("SVG_VOID", image.buildCertificateSVGV2(p, 1709164800));
        }
    }
}
