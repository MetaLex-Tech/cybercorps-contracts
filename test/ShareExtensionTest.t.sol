// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {
    SHARE_LAYER_TAG,
    ShareExtension,
    SeriesTerms,
    CertificateData,
    MandatoryConversionTrigger,
    ShareCertData,
    ShareLayer,
    SpecialVotingRight,
    TransferRestrictionException,
    TransferRestriction,
    SplitRecord
} from "../src/storage/extensions/ShareExtension.sol";
import {ShareExtensionLogic} from "../src/storage/extensions/ShareExtensionLogic.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {ShareLayerLib} from "../src/storage/extensions/ShareLayerLib.sol";
import {RealWorldShareCert} from "./libs/RealWorldShareCert.sol";

contract ShareExtensionHarness is ShareExtension {
    // _buildSeriesJson returns `"terms": {...}, ` (fragment); wrap for parseable JSON.
    function buildSeriesJson(SeriesTerms memory terms) external pure returns (string memory) {
        return string.concat('{', _buildSeriesJson(terms), '"_": 0}');
    }

    // _buildCertificateJson returns `"certificateData": {...}, ` (fragment); wrap for parseable JSON.
    function buildCertificateJson(CertificateData memory cert) external pure returns (string memory) {
        return string.concat('{', _buildCertificateJson(cert), '"_": 0}');
    }

    function buildMandatoryConversionTriggerJson(MandatoryConversionTrigger memory t) external pure returns (string memory) {
        return _buildMandatoryConversionTriggerJson(t);
    }

    function buildSpecialVotingRightJson(SpecialVotingRight memory r) external pure returns (string memory) {
        return _buildSpecialVotingRightJson(r);
    }

    function buildTransferRestrictionExceptionJson(TransferRestrictionException memory e) external pure returns (string memory) {
        return _buildTransferRestrictionExceptionJson(e);
    }

    function buildTransferRestrictionJson(TransferRestriction memory r) external pure returns (string memory) {
        return _buildTransferRestrictionJson(r);
    }

    function buildSplitRecordJson(SplitRecord memory s) external pure returns (string memory) {
        return _buildSplitRecordJson(s);
    }
}

contract ShareExtensionTest is Test {
    ShareExtensionHarness internal harness;

    function setUp() public {
        harness = new ShareExtensionHarness();
    }

    // --- Common-input round-trip tests for all fields that use _jsonEscape() ---

    // SeriesTerms fields

    function testBuildSeriesJson_SeriesName_RealWorldValues() public view {
        string memory input = 'Series "A-1"';
        SeriesTerms memory t;
        t.seriesName = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.seriesName"), input);
    }

    function testBuildSeriesJson_SourceAuthorityURI_RealWorldValues() public view {
        string memory input = 'https://example.com/auth?ref="series-a"';
        SeriesTerms memory t;
        t.sourceAuthorityURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.sourceAuthorityURI"), input);
    }

    function testBuildSeriesJson_RedemptionSchedule_RealWorldValues() public view {
        string memory input = 'Quarterly per "Schedule A" of the Charter';
        SeriesTerms memory t;
        t.redemptionSchedule = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.redemptionSchedule"), input);
    }

    function testBuildSeriesJson_RedemptionTriggerDescription_RealWorldValues() public view {
        string memory input = 'Upon "Qualified IPO" or company election';
        SeriesTerms memory t;
        t.redemptionTriggerDescription = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.redemptionTriggerDescription"), input);
    }

    function testBuildSeriesJson_PayToPlayTermsURI_RealWorldValues() public view {
        string memory input = 'https://example.com/p2p?type="standard"';
        SeriesTerms memory t;
        t.payToPlayTermsURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.payToPlayTermsURI"), input);
    }

    function testBuildSeriesJson_RegistrationRightsURI_RealWorldValues() public view {
        string memory input = 'https://example.com/reg-rights?id="2024"';
        SeriesTerms memory t;
        t.registrationRightsURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.registrationRightsURI"), input);
    }

    function testBuildSeriesJson_ProRataRightsURI_RealWorldValues() public view {
        string memory input = 'https://example.com/pro-rata?rights="standard"';
        SeriesTerms memory t;
        t.proRataRightsURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.proRataRightsURI"), input);
    }

    function testBuildSeriesJson_InformationRightsURI_RealWorldValues() public view {
        string memory input = 'https://example.com/information-rights?version="2024"';
        SeriesTerms memory t;
        t.informationRightsURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.informationRightsURI"), input);
    }

    function testBuildSeriesJson_DragAlongTermsURI_RealWorldValues() public view {
        string memory input = 'https://example.com/drag-along?v="2024"';
        SeriesTerms memory t;
        t.dragAlongTermsURI = input;
        string memory json = harness.buildSeriesJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".terms.dragAlongTermsURI"), input);
    }

    // CertificateData fields

    function testBuildCertificateJson_SourceAuthorityURI_RealWorldValues() public view {
        string memory input = 'https://example.com/cert?name="Series A"';
        CertificateData memory c;
        c.sourceAuthorityURI = input;
        string memory json = harness.buildCertificateJson(c);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".certificateData.sourceAuthorityURI"), input);
    }

    // MandatoryConversionTrigger fields

    function testBuildMandatoryConversionTriggerJson_AdditionalConditions_RealWorldValues() public view {
        string memory input = 'Conditioned on "Board Approval" and notice';
        MandatoryConversionTrigger memory t;
        t.additionalConditions = input;
        string memory json = harness.buildMandatoryConversionTriggerJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".additionalConditions"), input);
    }

    function testBuildMandatoryConversionTriggerJson_Description_RealWorldValues() public view {
        string memory input = 'Triggers on "Qualified IPO" per Section 3';
        MandatoryConversionTrigger memory t;
        t.description = input;
        string memory json = harness.buildMandatoryConversionTriggerJson(t);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".description"), input);
    }

    // SpecialVotingRight fields

    function testBuildSpecialVotingRightJson_Description_RealWorldValues() public view {
        string memory input = 'Veto right on "Major Decisions" per Exhibit C';
        SpecialVotingRight memory r;
        r.description = input;
        string memory json = harness.buildSpecialVotingRightJson(r);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".description"), input);
    }

    // TransferRestrictionException fields

    function testBuildTransferRestrictionExceptionJson_ExceptionText_RealWorldValues() public view {
        string memory input = 'Permitted transfers to "Affiliates" per the Agreement';
        TransferRestrictionException memory e;
        e.exceptionText = input;
        string memory json = harness.buildTransferRestrictionExceptionJson(e);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".exceptionText"), input);
    }

    // TransferRestriction fields

    function testBuildTransferRestrictionJson_RestrictionText_RealWorldValues() public view {
        string memory input = 'Restricted per "Stockholders Agreement" Section 4.1';
        TransferRestriction memory r;
        r.restrictionText = input;
        string memory json = harness.buildTransferRestrictionJson(r);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".restrictionText"), input);
    }

    function testBuildTransferRestrictionJson_SourceAgreement_RealWorldValues() public view {
        string memory input = 'Stockholders Agreement dated "2024-01-15", Exhibit A';
        TransferRestriction memory r;
        r.sourceAgreement = input;
        string memory json = harness.buildTransferRestrictionJson(r);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".sourceAgreement"), input);
    }

    // SplitRecord fields

    function testBuildSplitRecordJson_SourceAuthorityURI_RealWorldValues() public view {
        string memory input = 'https://example.com/split?ref="board-res-2024"';
        SplitRecord memory s;
        s.sourceAuthorityURI = input;
        string memory json = harness.buildSplitRecordJson(s);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".sourceAuthorityURI"), input);
    }
}

/// @notice The layered payload: how a `ShareCertData` splits across the class, series and cert scopes,
///         and how it merges back. The fixture is the real Series Seed 2 payload the gas guards use.
contract ShareLayerTest is Test {
    ShareExtension internal ext;
    ShareExtensionV3 internal extV3;

    function setUp() public {
        ext = new ShareExtension();
        extV3 = new ShareExtensionV3();
    }

    function _hash(ShareCertData memory share) internal pure returns (bytes32) {
        return keccak256(abi.encode(share));
    }

    // --- Format detection ---

    function testIsShareLayer_TellsLayeredFromLegacy() public view {
        assertFalse(ext.isShareLayer(RealWorldShareCert.encodedShareCertData()), "whole ShareCertData");
        assertFalse(ext.isShareLayer(abi.encode(RealWorldShareCert.seriesTerms())), "bare SeriesTerms");
        assertFalse(ext.isShareLayer(bytes("")), "empty");
        assertTrue(ext.isShareLayer(RealWorldShareCert.encodedCertLayer()), "cert layer");
        assertTrue(ext.isShareLayer(RealWorldShareCert.encodedSeriesLayer()), "series layer");
    }

    // --- Split and merge ---

    function testSplit_MovesEverySeriesWideSectionOffTheCert() public view {
        bytes memory whole = RealWorldShareCert.encodedShareCertData();
        (bytes memory series, bytes memory cert) = ShareLayerLib.split(RealWorldShareCert.shareCertData());

        assertLt(cert.length, whole.length / 10, "the cert keeps under a tenth of the payload");
        assertEq(
            _hash(ShareLayerLib.resolve("", series, cert)),
            _hash(RealWorldShareCert.shareCertData()),
            "the layers merge back to the whole struct"
        );
    }

    function testResolve_SeriesLayerFillsEverySectionTheCertLeavesEmpty() public view {
        assertEq(
            _hash(
                ShareLayerLib.resolve(
                    "", RealWorldShareCert.encodedSeriesLayer(), RealWorldShareCert.encodedCertLayer()
                )
            ),
            _hash(RealWorldShareCert.shareCertData()),
            "a lean cert reads back whole"
        );
    }

    function testResolve_CertSectionOverridesTheSeries() public view {
        SeriesTerms memory certTerms = RealWorldShareCert.seriesTerms();
        certTerms.seriesName = "Series Seed 2 (as adjusted)";

        ShareLayer memory certLayer;
        certLayer.certificateData = abi.encode(RealWorldShareCert.certificateData());
        certLayer.terms = abi.encode(certTerms);

        ShareCertData memory resolved = ShareLayerLib.resolve(
            "", RealWorldShareCert.encodedSeriesLayer(), abi.encode(SHARE_LAYER_TAG, certLayer)
        );

        assertEq(resolved.terms.seriesName, "Series Seed 2 (as adjusted)", "the cert wins");
        assertEq(
            resolved.transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "the sections the cert leaves empty still come from the series"
        );
    }

    function testResolve_SeriesSectionOverridesTheClass() public view {
        SeriesTerms memory classTerms = RealWorldShareCert.seriesTerms();
        classTerms.seriesName = "Preferred Stock (class default)";

        ShareLayer memory classLayer;
        classLayer.terms = abi.encode(classTerms);
        classLayer.transferRestrictions = abi.encode(new TransferRestriction[](0));

        ShareLayer memory seriesLayer;
        seriesLayer.terms = abi.encode(RealWorldShareCert.seriesTerms());

        ShareCertData memory resolved = ShareLayerLib.resolve(
            abi.encode(SHARE_LAYER_TAG, classLayer),
            abi.encode(SHARE_LAYER_TAG, seriesLayer),
            RealWorldShareCert.encodedCertLayer()
        );

        assertEq(resolved.terms.seriesName, "Series Seed 2", "the series wins over the class");
        assertEq(resolved.transferRestrictions.length, 0, "the class fills what neither layer below sets");
    }

    // --- Backwards compatibility ---

    function testResolve_LegacyCertPayloadReadsBackUnchanged() public view {
        assertEq(
            _hash(
                ShareLayerLib.resolve(
                    "", RealWorldShareCert.encodedSeriesLayer(), RealWorldShareCert.encodedShareCertData()
                )
            ),
            _hash(RealWorldShareCert.shareCertData()),
            "a whole-struct cert ignores the layers above it"
        );
    }

    function testResolve_LegacySeriesPayloadIsTheTermsSection() public view {
        ShareCertData memory resolved = ShareLayerLib.resolve(
            "", abi.encode(RealWorldShareCert.seriesTerms()), RealWorldShareCert.encodedCertLayer()
        );

        assertEq(resolved.terms.seriesName, "Series Seed 2", "a bare SeriesTerms still resolves");
        assertEq(resolved.transferRestrictions.length, 0, "it carries no other section");
    }

    function testGetSeriesExtensionURI_BarePayloadRendersAsBefore() public view {
        string memory json =
            string.concat("{", _stripLeadingSeparator(extV3.getSeriesExtensionURI(abi.encode(RealWorldShareCert.seriesTerms()))), "}");
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".seriesDetails.terms.seriesName"), "Series Seed 2");
        assertEq(vm.parseJsonString(json, ".seriesDetails.conversionRatio"), "1.00");
    }

    // --- Rendering ---

    function testGetSeriesExtensionURI_LayerRendersEverySectionItCarries() public view {
        string memory json = string.concat(
            "{", _stripLeadingSeparator(extV3.getSeriesExtensionURI(RealWorldShareCert.encodedSeriesLayer())), "}"
        );
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".seriesDetails.terms.seriesName"), "Series Seed 2");
        _assertRestrictionsRendered(json, ".seriesDetails");
        assertEq(vm.parseJsonString(json, ".seriesDetails.splitHistory[0].numerator"), "1");
    }

    function testGetExtensionURI_CertLayerRendersOnlyWhatTheCertCarries() public view {
        string memory json =
            string.concat("{", _stripLeadingSeparator(ext.getExtensionURI(RealWorldShareCert.encodedCertLayer())), "}");
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".shareDetails.certificateData.representationType"), "Tokenized");
        assertEq(vm.parseJsonString(json, ".shareDetails.paymentPercentage"), "10000");
        // The series sections are on the printer, so the cert section leaves them out.
        assertEq(vm.parseJsonKeys(json, ".shareDetails").length, 3, "certificateData, paymentPercentage, ratio");
    }

    function testGetExtensionURI_LegacyPayloadStillRendersEverySection() public view {
        string memory json = string.concat(
            "{", _stripLeadingSeparator(ext.getExtensionURI(RealWorldShareCert.encodedShareCertData())), "}"
        );
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".shareDetails.terms.seriesName"), "Series Seed 2");
        _assertRestrictionsRendered(json, ".shareDetails");
    }

    /// @dev Every restriction of the fixture is present at its own index, so nothing is dropped.
    function _assertRestrictionsRendered(string memory json, string memory root) internal view {
        TransferRestriction[] memory expected = RealWorldShareCert.transferRestrictions();
        for (uint256 i = 0; i < expected.length; i++) {
            string memory at = string.concat(root, ".transferRestrictions[", vm.toString(i), "]");
            assertEq(vm.parseJsonString(json, string.concat(at, ".restrictionText")), expected[i].restrictionText);
            assertEq(vm.parseJsonString(json, string.concat(at, ".sourceAgreement")), expected[i].sourceAgreement);
        }
    }

    /// @dev Both builders return a fragment that starts with ", " so it can be appended to a larger
    ///      object. Drop it to get parseable JSON.
    function _stripLeadingSeparator(string memory fragment) internal pure returns (string memory) {
        bytes memory b = bytes(fragment);
        bytes memory out = new bytes(b.length - 2);
        for (uint256 i = 2; i < b.length; i++) {
            out[i - 2] = b[i];
        }
        return string(out);
    }
}

/// @notice `ShareExtensionLogic` over a layered payload. A change lands on the section it belongs to,
///         the payload keeps its format, and a change aimed at a section the layer does not carry is
///         refused instead of overwriting what the layer inherits.
contract ShareLayerLogicTest is Test {
    ShareExtension internal ext;
    ShareExtensionLogic internal logic;

    function setUp() public {
        ext = new ShareExtension();
        logic = new ShareExtensionLogic();
    }

    function testUpdateSeriesName_OnASeriesLayerKeepsEveryOtherSection() public view {
        bytes memory updated = logic.updateSeriesName(RealWorldShareCert.encodedSeriesLayer(), "Series Seed 2-A");

        assertTrue(ext.isShareLayer(updated), "the payload keeps its format");
        ShareCertData memory resolved = ShareLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());
        assertEq(resolved.terms.seriesName, "Series Seed 2-A");
        assertEq(resolved.transferRestrictions.length, RealWorldShareCert.transferRestrictions().length);
        assertEq(resolved.specialVotingRights.length, RealWorldShareCert.votingRights().length);
    }

    function testAddTransferRestriction_AppendsToTheSeriesLayer() public view {
        TransferRestriction memory added;
        added.restrictionText = "Added by board resolution";

        bytes memory updated = logic.addTransferRestriction(RealWorldShareCert.encodedSeriesLayer(), added);
        ShareCertData memory resolved = ShareLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());

        uint256 last = resolved.transferRestrictions.length - 1;
        assertEq(last, RealWorldShareCert.transferRestrictions().length, "one more than before");
        assertEq(resolved.transferRestrictions[last].restrictionText, "Added by board resolution");
    }

    function testAddTransferRestriction_RefusesALayerThatInheritsTheSection() public {
        TransferRestriction memory added;
        bytes memory certLayer = RealWorldShareCert.encodedCertLayer();

        vm.expectRevert(bytes("ShareExtensionLogic: layer has no transferRestrictions section"));
        logic.addTransferRestriction(certLayer, added);
    }

    function testRecordStockSplit_RepricesTheSeriesLayer() public view {
        bytes memory updated =
            logic.recordStockSplit(RealWorldShareCert.encodedSeriesLayer(), 2, 1, "ipfs://split", 1_780_075_298);
        ShareCertData memory resolved = ShareLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());

        SeriesTerms memory before = RealWorldShareCert.seriesTerms();
        assertEq(resolved.terms.parValue, before.parValue / 2, "par value halves");
        assertEq(resolved.terms.authorizedShares, before.authorizedShares * 2, "authorized shares double");
        assertEq(resolved.splitHistory.length, RealWorldShareCert.splitHistory().length + 1, "the split is recorded");
    }

    function testUpdateSeriesName_LegacyPayloadStaysALegacyPayload() public view {
        bytes memory updated = logic.updateSeriesName(RealWorldShareCert.encodedShareCertData(), "Series Seed 2-A");

        assertFalse(ext.isShareLayer(updated), "the payload keeps its format");
        ShareCertData memory resolved = ShareLayerLib.resolve("", "", updated);
        assertEq(resolved.terms.seriesName, "Series Seed 2-A");
        assertEq(resolved.transferRestrictions.length, RealWorldShareCert.transferRestrictions().length);
    }
}
