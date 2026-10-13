// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParamsV2, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CertificateSvgCompatibilityTest, EmptyExtension, SvgUriHarness} from "./CertificateSvgCompatibilityTest.t.sol";
import {IssuanceManagerTest} from "./IssuanceManagerTest.t.sol";

contract SeriesEnumRenderingTest is CertificateSvgCompatibilityTest {
    function test_catalogMachineNamesAndBothImageSelectors() public view {
        string memory catalog = vm.readFile("test/res/series-catalog.json");
        for (uint256 code; code <= 83; ++code) {
            string memory key = string.concat(".entries[", vm.toString(code), "]");
            assertEq(vm.parseJsonUint(catalog, string.concat(key, ".code")), code);
            SecuritySeries series = SecuritySeries(code);
            assertEq(
                builder.securitySeriesToString(series), vm.parseJsonString(catalog, string.concat(key, ".identifier"))
            );
            CertificateSVGParamsV2 memory p = _params();
            p.certificate.securityType = code >= 82 ? SecurityClass.CommonStock : SecurityClass.PreferredStock;
            p.certificate.securitySeries = series;
            if (code >= 10) {
                string memory expected = string.concat(
                    vm.parseJsonString(catalog, string.concat(key, ".label")),
                    code >= 82 ? " Common Stock</text>" : " Preferred Stock</text>"
                );
                assertTrue(_contains(image.buildCertificateSVGV2(p, 0), expected), expected);
                assertTrue(_contains(image.buildCertificateSVG(p.certificate, 0), expected), expected);
            }
        }
    }

    function test_oldEnumNumbersAndImageWordingRemainStable() public view {
        assertEq(uint256(SecuritySeries.SeriesSeed), 1);
        assertEq(uint256(SecuritySeries.NA), 8);
        assertEq(uint256(SecuritySeries.ACE), 9);
        assertEq(uint256(SecuritySeries.SeriesSeed2), 19);
        assertEq(uint256(SecuritySeries.CommonA), 82);
        assertEq(uint256(SecuritySeries.CommonB), 83);
        CertificateSVGParamsV2 memory p = _params();
        p.certificate.securityType = SecurityClass.PreferredStock;
        assertTrue(_contains(image.buildCertificateSVGV2(p, 0), "Preferred Stock Series Seed</text>"));
        p.certificate.securityType = SecurityClass.CommonStock;
        p.certificate.securitySeries = SecuritySeries.NA;
        assertTrue(_contains(image.buildCertificateSVGV2(p, 0), "Common Stock </text>"));
        p.certificate.securitySeries = SecuritySeries.ACE;
        assertTrue(_contains(image.buildCertificateSVGV2(p, 0), "Common Stock ACE</text>"));
    }

    function test_rendererRefusesBeyondCatalog() public {
        (bool success,) = address(builder).call(abi.encodeWithSignature("securitySeriesToString(uint8)", uint8(84)));
        assertFalse(success);
    }
}

contract SeriesEnumIssuanceTest is IssuanceManagerTest {
    function test_directCreationAssignmentAndMetadata() public {
        SvgUriHarness renderer = new SvgUriHarness(address(new CertificateImageBuilderContract()));
        issuanceManager.setUriBuilder(address(renderer));
        address extension = address(new EmptyExtension());
        uint8[7] memory codes = [uint8(1), 8, 9, 10, 19, 81, 83];
        for (uint256 i; i < codes.length; ++i) {
            SecuritySeries series = SecuritySeries(codes[i]);
            SecurityClass securityClass =
                codes[i] == 8 || codes[i] == 83 ? SecurityClass.CommonStock : SecurityClass.PreferredStock;
            LedgerEntryToken printer = LedgerEntryToken(
                issuanceManager.createCertPrinter(
                    new string[](0),
                    "Series test",
                    vm.toString(i),
                    "ipfs://terms",
                    securityClass,
                    series,
                    extension,
                    bytes("")
                )
            );
            issuanceManager.createCertAndAssignWithName(
                address(printer), investor, _buildCertificateDetails(25), "Holder", bytes(""), block.timestamp
            );
            assertEq(uint256(printer.securitySeries()), codes[i]);
            assertEq(printer.ownerOf(0), investor);
            assertEq(printer.getCertificateDetails(0).unitsRepresented, 25e18);
            string memory json = _decode(printer.tokenURI(0), bytes("data:application/json;base64,").length);
            assertEq(vm.parseJsonString(json, ".securitySeries"), renderer.securitySeriesToString(series));
            assertGt(bytes(vm.parseJsonString(json, ".image")).length, bytes("data:image/svg+xml;base64,").length);
            assertEq(vm.parseJsonString(json, ".currentOwner.name"), "Holder");
        }
    }

    function _decode(string memory uri, uint256 prefix) internal pure returns (string memory) {
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
        assembly ("memory-safe") { mstore(decoded, cursor) }
        return string(decoded);
    }

    function test_newSeriesCreationStillRequiresOwner() public {
        vm.prank(investor);
        vm.expectRevert();
        issuanceManager.createCertPrinter(
            new string[](0),
            "Seed 2",
            "SEED2",
            "",
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesSeed2,
            address(0),
            bytes("")
        );
    }
}
