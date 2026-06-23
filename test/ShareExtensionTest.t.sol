// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {
    ShareExtension,
    SeriesTerms,
    CertificateData,
    MandatoryConversionTrigger,
    SpecialVotingRight,
    TransferRestrictionException,
    TransferRestriction,
    SplitRecord
} from "../src/storage/extensions/ShareExtension.sol";

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
