// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateSVGParamsV2, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CertificateSeries} from "../src/libs/CertificateSeries.sol";
import {ACESAFEData} from "../src/storage/extensions/ACESAFEExtension.sol";
import {ACESAFEResolvedData, ACESAFESeriesData} from "../src/storage/extensions/ACESAFEExtensionV3.sol";
import {SAFEData} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFEResolvedData, SAFESeriesData} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {SAFTEDataV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTEResolvedData, SAFTESeriesData} from "../src/storage/extensions/SAFTEExtensionV3.sol";
import {SAFTDataV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {SAFTResolvedData, SAFTSeriesData} from "../src/storage/extensions/SAFTExtensionV3.sol";
import {TokenWarrantDataV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";
import {TokenWarrantResolvedData, TokenWarrantSeriesData} from "../src/storage/extensions/TokenWarrantExtensionV3.sol";
import {RealWorldShareCert} from "./libs/RealWorldShareCert.sol";

/// @notice External entry point, so a test can check that a library call does not revert.
contract LeadingNameReader {
    function read(bytes memory data) external pure returns (string memory) {
        return CertificateSeries.leadingName(data);
    }
}

/// @notice The series text rule and the name reader, alone. The end-to-end cases are in
///         CertificateSeriesNameTest.
contract CertificateSeriesTest is Test {
    CertificateImageBuilderContract internal image;
    LeadingNameReader internal reader;

    function setUp() public {
        image = new CertificateImageBuilderContract();
        reader = new LeadingNameReader();
    }

    // --- leadingName ---

    /// @notice Every shape the URI renderer reads gives its series name.
    function test_leadingName_ReadsEveryShapeTheRendererReads() public pure {
        assertEq(CertificateSeries.leadingName(abi.encode(RealWorldShareCert.shareCertData())), "Series Seed 2");

        string[] memory none = new string[](0);
        SAFEData memory safe;
        assertEq(
            CertificateSeries.leadingName(abi.encode(SAFEResolvedData(SAFESeriesData("SAFE 1", none, "x"), safe))),
            "SAFE 1"
        );
        SAFTDataV2 memory saft;
        assertEq(
            CertificateSeries.leadingName(abi.encode(SAFTResolvedData(SAFTSeriesData("SAFT 1", 7, none, "x"), saft))),
            "SAFT 1"
        );
        SAFTEDataV2 memory safte;
        assertEq(
            CertificateSeries.leadingName(abi.encode(SAFTEResolvedData(SAFTESeriesData("SAFTE 1", none, "x"), safte))),
            "SAFTE 1"
        );
        TokenWarrantDataV2 memory warrant;
        assertEq(
            CertificateSeries.leadingName(
                abi.encode(TokenWarrantResolvedData(TokenWarrantSeriesData("Warrant 1", "TKN", none, "x"), warrant))
            ),
            "Warrant 1"
        );
        ACESAFEData memory ace;
        assertEq(
            CertificateSeries.leadingName(
                abi.encode(ACESAFEResolvedData(ACESAFESeriesData("ACE 1", "USDC", none, "x"), ace))
            ),
            "ACE 1"
        );
    }

    function testFuzz_leadingName_RoundTrips(string memory name, string memory other) public pure {
        bytes memory data = abi.encode(SAFEResolvedData(SAFESeriesData(name, new string[](2), other), SAFEData(other)));
        assertEq(CertificateSeries.leadingName(data), name);
    }

    /// @notice Arbitrary bytes give a string or "", never a revert.
    function testFuzz_leadingName_NeverReverts(bytes memory data) public view {
        string memory name = reader.read(data);
        assertLe(bytes(name).length, data.length);
    }

    /// @notice A valid encoding with one word replaced never reverts.
    function testFuzz_leadingName_CorruptedWordNeverReverts(uint256 word, uint256 value) public view {
        bytes memory data = abi.encode(RealWorldShareCert.shareCertData());
        word = bound(word, 0, data.length / 32 - 1);
        assembly ("memory-safe") {
            mstore(add(add(data, 32), mul(word, 32)), value)
        }
        reader.read(data);
    }

    /// @notice The name is a copy. The input is unchanged, and the bytes after the name are zero.
    function test_leadingName_CopiesTheNameAndClearsItsPadding() public pure {
        // Head offsets, then length 1, then "A" followed by 31 bytes of 0xff.
        bytes memory data = abi.encodePacked(
            uint256(0x20),
            uint256(0x20),
            uint256(0x20),
            uint256(1),
            bytes32(0x41ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
        );
        bytes32 before = keccak256(data);
        string memory name = CertificateSeries.leadingName(data);
        assertEq(name, "A");
        assertEq(keccak256(data), before, "the input is unchanged");
        bytes32 word;
        assembly ("memory-safe") {
            word := mload(add(name, 32))
        }
        assertEq(word, bytes32(bytes1("A")), "the bytes after the name are zero");

        data[0x80] = "B";
        assertEq(name, "A", "the name does not alias the input");
    }

    function test_leadingName_MalformedGivesEmpty() public pure {
        assertEq(CertificateSeries.leadingName(""), "");
        assertEq(CertificateSeries.leadingName(hex"20"), "");
        assertEq(CertificateSeries.leadingName(abi.encode(uint256(0x20), uint256(0x20))), "");
        assertEq(CertificateSeries.leadingName(abi.encode(uint256(0x21), uint256(0x20), uint256(0x20), uint256(0))), "");
        assertEq(CertificateSeries.leadingName(abi.encode(type(uint256).max, uint256(0), uint256(0), uint256(0))), "");
        // The string's length word is one byte short of its data.
        assertEq(
            CertificateSeries.leadingName(
                abi.encodePacked(uint256(0x20), uint256(0x20), uint256(0x20), uint256(33), bytes32("x"))
            ),
            ""
        );
        // Offsets that point back to the start are bounded and read a zero-length name.
        assertEq(CertificateSeries.leadingName(abi.encode(uint256(0), uint256(0), uint256(0))), "");
    }

    // --- text and label ---

    function test_text_ShowsTheNameOrTheFixedLabel() public pure {
        string[10] memory labels = [
            "Pre-Seed", "Series Seed", "Series A", "Series B", "Series C", "Series D", "Series E", "Series F", "", "ACE"
        ];
        for (uint256 i; i < labels.length; ++i) {
            SecuritySeries series = SecuritySeries(i);
            assertEq(CertificateSeries.label(series), labels[i]);
            assertEq(CertificateSeries.text("", series), labels[i]);
            assertEq(CertificateSeries.text("Series Seed 2", series), "Series Seed 2");
        }
    }

    // --- image builder ---

    function _params(SecuritySeries series) internal pure returns (CertificateSVGParamsV2 memory p) {
        p.certificate.corpName = "Example Corp";
        p.certificate.securityType = SecurityClass.PreferredStock;
        p.certificate.securitySeries = series;
        p.certificate.officerName = "Officer";
        p.certificate.ownerName = "Holder";
        p.certificate.tokenId = 1;
        p.certificate.units = 1e18;
        p.consideration = 1e18;
        p.considerationKnown = true;
        p.statusKnown = true;
    }

    /// @notice With no name, V3 is V2 to the byte, for every series and status.
    function test_V3WithoutANameIsV2() public view {
        for (uint256 i; i <= uint256(type(SecuritySeries).max); ++i) {
            CertificateSVGParamsV2 memory p = _params(SecuritySeries(i));
            assertEq(image.buildCertificateSVGV3(p, 1709164800, ""), image.buildCertificateSVGV2(p, 1709164800));
            p.isVoided = true;
            assertEq(image.buildCertificateSVGV3(p, 0, ""), image.buildCertificateSVGV2(p, 0));
        }
    }

    function test_V3ShowsTheNameAfterTheClass() public {
        string memory svg = image.buildCertificateSVGV3(_params(SecuritySeries.SeriesSeed), 0, "Series Seed 2");
        assertTrue(vm.contains(svg, 'text-anchor="middle">Preferred Stock Series Seed 2</text>'));
        assertFalse(vm.contains(svg, ">Preferred Stock Series Seed</text>"));
        // NA with a name shows the name.
        svg = image.buildCertificateSVGV3(_params(SecuritySeries.NA), 0, "Seed 2");
        assertTrue(vm.contains(svg, 'text-anchor="middle">Preferred Stock Seed 2</text>'));
    }

    // --- sizes ---

    /// @notice The renderers stay deployable under EIP-170. Tests build with the same optimizer settings
    ///         as the release build.
    function test_rendererSizesAreWithinEip170() public {
        uint256 limit = 24_576;
        uint256 uri = address(new CertificateUriBuilder()).code.length;
        uint256 img = address(image).code.length;
        uint256 content = vm.getDeployedCode("CertificateImageContentBuilder.sol:CertificateImageContentBuilder").length;
        emit log_named_uint("CertificateUriBuilder runtime", uri);
        emit log_named_uint("CertificateImageBuilderContract runtime", img);
        emit log_named_uint("CertificateImageContentBuilder runtime", content);
        assertLe(uri, limit);
        assertLe(img, limit);
        assertLe(content, limit);
    }
}
