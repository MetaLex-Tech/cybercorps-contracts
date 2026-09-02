// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {
    ShareExtension,
    SeriesTerms,
    CertificateData,
    MandatoryConversionTrigger,
    ShareCertData,
    SpecialVotingRight,
    TransferRestrictionException,
    TransferRestriction,
    SplitRecord
} from "../src/storage/extensions/ShareExtension.sol";
import {ShareCertDataLayer} from "../src/storage/extensions/ShareExtensionV3.sol";
import {ShareExtensionLogic} from "../src/storage/extensions/ShareExtensionLogic.sol";
import {ShareCertDataLayerLib} from "../src/storage/extensions/ShareCertDataLayerLib.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {RealWorldShareCert} from "./libs/RealWorldShareCert.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateSVGParams, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {ICertificateImageBuilder} from "../src/interfaces/ICertificateImageBuilder.sol";

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
    ShareExtensionV3 internal ext;
    ShareExtensionLogic internal logic;

    function setUp() public {
        ext = new ShareExtensionV3();
        logic = new ShareExtensionLogic();
    }

    function _hash(ShareCertData memory share) internal pure returns (bytes32) {
        return keccak256(abi.encode(share));
    }

    // --- Format detection ---

    // --- Split and merge ---

    function testResolve_SeriesLayerFillsEverySectionTheCertLeavesEmpty() public view {
        assertEq(
            _hash(
                ShareCertDataLayerLib.resolve(
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

        ShareCertDataLayer memory certLayer;
        certLayer.certificateData = new CertificateData[](1);
        certLayer.certificateData[0] = RealWorldShareCert.certificateData();
        certLayer.terms = new SeriesTerms[](1);
        certLayer.terms[0] = certTerms;

        ShareCertData memory resolved = ShareCertDataLayerLib.resolve(
            "", RealWorldShareCert.encodedSeriesLayer(), abi.encode(certLayer)
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

        ShareCertDataLayer memory classLayer;
        classLayer.terms = new SeriesTerms[](1);
        classLayer.terms[0] = classTerms;
        classLayer.transferRestrictions = new TransferRestriction[][](1);
        classLayer.transferRestrictions[0] = _oneRestriction("class default");

        ShareCertDataLayer memory seriesLayer;
        seriesLayer.terms = new SeriesTerms[](1);
        seriesLayer.terms[0] = RealWorldShareCert.seriesTerms();

        ShareCertData memory resolved = ShareCertDataLayerLib.resolve(
            abi.encode(classLayer),
            abi.encode(seriesLayer),
            RealWorldShareCert.encodedCertLayer()
        );

        assertEq(resolved.terms.seriesName, "Series Seed 2", "the series wins over the class");
        assertEq(resolved.transferRestrictions.length, 1, "the class fills what neither layer below sets");
        assertEq(resolved.transferRestrictions[0].restrictionText, "class default");
    }

    /// @notice The list sections append. Every layer that sets one adds its entries, from the class
    ///         down to the cert, so no layer can drop what another layer sets.
    function testResolve_ListSectionsAppendEveryLayer() public view {
        ShareCertData memory resolved = ShareCertDataLayerLib.resolve(
            _restrictionLayer(_oneRestriction("class"), false),
            _restrictionLayer(_oneRestriction("series"), false),
            _restrictionLayer(_oneRestriction("cert"), false)
        );

        assertEq(resolved.transferRestrictions.length, 3, "every layer contributes");
        assertEq(resolved.transferRestrictions[0].restrictionText, "class", "the class comes first");
        assertEq(resolved.transferRestrictions[1].restrictionText, "series", "then the series");
        assertEq(resolved.transferRestrictions[2].restrictionText, "cert", "then the cert");
    }

    /// @notice The overwrite flag is the only way to remove what a layer above gives. A cert that sets
    ///         the flag keeps its own list alone.
    function testResolve_CertOverwriteFlagDropsTheLayersAboveIt() public view {
        ShareCertData memory resolved = ShareCertDataLayerLib.resolve(
            _restrictionLayer(_oneRestriction("class"), false),
            _restrictionLayer(_oneRestriction("series"), false),
            _restrictionLayer(_oneRestriction("cert"), true)
        );

        assertEq(resolved.transferRestrictions.length, 1, "the class and the series are dropped");
        assertEq(resolved.transferRestrictions[0].restrictionText, "cert");
    }

    /// @notice A flag drops the layers above the layer that sets it, and it keeps the layers below.
    function testResolve_SeriesOverwriteFlagDropsTheClassAndKeepsTheCert() public view {
        ShareCertData memory resolved = ShareCertDataLayerLib.resolve(
            _restrictionLayer(_oneRestriction("class"), false),
            _restrictionLayer(_oneRestriction("series"), true),
            _restrictionLayer(_oneRestriction("cert"), false)
        );

        assertEq(resolved.transferRestrictions.length, 2, "the class is dropped");
        assertEq(resolved.transferRestrictions[0].restrictionText, "series");
        assertEq(resolved.transferRestrictions[1].restrictionText, "cert");
    }

    /// @notice A flag on a layer that sets no list does nothing, so a stray flag cannot remove a
    ///         restriction by accident.
    function testResolve_AnOverwriteFlagWithNoListDoesNothing() public view {
        ShareCertDataLayer memory strayFlag;
        strayFlag.overwriteTransferRestrictions = true;

        ShareCertData memory resolved =
            ShareCertDataLayerLib.resolve("", RealWorldShareCert.encodedSeriesLayer(), abi.encode(strayFlag));

        assertEq(
            resolved.transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "the series restrictions stay"
        );
    }

    /// @notice To clear a section a layer needs both parts: an empty list, which appends nothing, and
    ///         the overwrite flag, which drops the layers above. An empty list alone changes nothing.
    function testResolve_AnEmptyListClearsOnlyWithTheOverwriteFlag() public view {
        bytes memory series = RealWorldShareCert.encodedSeriesLayer();
        TransferRestriction[] memory emptyList = new TransferRestriction[](0);

        assertEq(
            ShareCertDataLayerLib.resolve("", series, _restrictionLayer(emptyList, false)).transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "an empty list appends nothing and removes nothing"
        );
        assertEq(
            ShareCertDataLayerLib.resolve("", series, _restrictionLayer(emptyList, true)).transferRestrictions.length,
            0,
            "with the flag the empty list clears the series restrictions"
        );
        assertEq(
            ShareCertDataLayerLib.resolve("", series, RealWorldShareCert.encodedCertLayer()).transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "a cert that sets nothing still inherits them"
        );
    }

    function _oneRestriction(string memory text) internal pure returns (TransferRestriction[] memory list) {
        list = new TransferRestriction[](1);
        list[0].restrictionText = text;
    }

    /// @dev A layer that carries the transfer-restriction section alone, which is all a merge test
    ///      needs to see.
    function _restrictionLayer(
        TransferRestriction[] memory list,
        bool overwrite
    ) internal pure returns (bytes memory) {
        ShareCertDataLayer memory layer;
        layer.transferRestrictions = new TransferRestriction[][](1);
        layer.transferRestrictions[0] = list;
        layer.overwriteTransferRestrictions = overwrite;
        return abi.encode(layer);
    }

    /// @notice The codecs keep the legacy signatures but speak the shape this version stores. A whole
    ///         struct in comes back out, so a caller needs no special case.
    function testCodecs_RoundTripAWholeShareCertData() public view {
        ShareCertData memory original = RealWorldShareCert.shareCertData();

        bytes memory payload = ext.encodeExtensionData(original);
        assertEq(_hash(ext.decodeExtensionData(payload)), _hash(original), "the struct survives the round trip");

        // What it wrote is a plain cert layer.
        assertEq(
            _hash(ShareCertDataLayerLib.resolve("", "", payload)),
            _hash(original),
            "and it resolves to the same struct with no series and no class"
        );

        // The layer sets no overwrite flag, so a series still appends its list entries to it.
        ShareCertData memory withSeries =
            ShareCertDataLayerLib.resolve("", RealWorldShareCert.encodedSeriesLayer(), payload);
        assertEq(
            withSeries.transferRestrictions.length,
            original.transferRestrictions.length + RealWorldShareCert.transferRestrictions().length,
            "a series appends to a whole-struct payload"
        );
    }

    /// @notice Decoding a lean cert payload shows only what that cert sets. The sections it inherits
    ///         read back blank, because this view has no series and no class.
    function testCodecs_DecodeShowsOnlyTheCertScope() public view {
        ShareCertData memory decoded = ext.decodeExtensionData(RealWorldShareCert.encodedCertLayer());

        assertEq(decoded.certificateData.sourceAuthorityURI, RealWorldShareCert.PINATA_URI, "the cert scope is set");
        assertEq(decoded.terms.authorizedShares, 0, "the series terms are inherited, not stored here");
        assertEq(decoded.transferRestrictions.length, 0, "so are the restrictions");
    }

    // --- Backwards compatibility ---

    // --- Rendering ---

    /// @notice The cert-scope render shows what the cert layer itself carries. A section the cert
    ///         leaves unset renders blank, because this view cannot reach the layer that holds it.
    function testGetExtensionURI_CertScopeRendersBlankForWhatItInherits() public view {
        string memory json =
            string.concat("{", _stripLeadingSeparator(ext.getExtensionURI(RealWorldShareCert.encodedCertLayer())), "}");
        vm.parseJson(json);

        assertEq(vm.parseJsonString(json, ".shareDetails.certificateData.representationType"), "Tokenized");
        assertEq(vm.parseJsonString(json, ".shareDetails.paymentPercentage"), "10000");
        assertEq(vm.parseJsonString(json, ".shareDetails.terms.seriesName"), "", "the series terms are inherited");
        assertEq(vm.parseJsonStringArray(json, ".shareDetails.transferRestrictions").length, 0, "so are the restrictions");
    }

    /// @notice The legacy whole-struct render still works, on the legacy extension. A printer binds to
    ///         one extension at creation and cannot be repointed, so a legacy printer keeps this render.
    function testGetExtensionURI_LegacyExtensionStillRendersEverySection() public {
        ShareExtension legacy = new ShareExtension();
        string memory json = string.concat(
            "{", _stripLeadingSeparator(legacy.getExtensionURI(RealWorldShareCert.encodedShareCertData())), "}"
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
    ShareExtensionV3 internal ext;
    ShareExtensionLogic internal logic;

    function setUp() public {
        ext = new ShareExtensionV3();
        logic = new ShareExtensionLogic();
    }

    function testUpdateSeriesName_OnASeriesLayerKeepsEveryOtherSection() public view {
        bytes memory updated = logic.updateSeriesName(RealWorldShareCert.encodedSeriesLayer(), "Series Seed 2-A");

        ShareCertData memory resolved = ShareCertDataLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());
        assertEq(resolved.terms.seriesName, "Series Seed 2-A");
        assertEq(resolved.transferRestrictions.length, RealWorldShareCert.transferRestrictions().length);
        assertEq(resolved.specialVotingRights.length, RealWorldShareCert.votingRights().length);
    }

    function testAddTransferRestriction_AppendsToTheSeriesLayer() public view {
        TransferRestriction memory added;
        added.restrictionText = "Added by board resolution";

        bytes memory updated = logic.addTransferRestriction(RealWorldShareCert.encodedSeriesLayer(), added);
        ShareCertData memory resolved = ShareCertDataLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());

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
        ShareCertData memory resolved = ShareCertDataLayerLib.resolve("", updated, RealWorldShareCert.encodedCertLayer());

        SeriesTerms memory before = RealWorldShareCert.seriesTerms();
        assertEq(resolved.terms.parValue, before.parValue / 2, "par value halves");
        assertEq(resolved.terms.authorizedShares, before.authorizedShares * 2, "authorized shares double");
        assertEq(resolved.splitHistory.length, RealWorldShareCert.splitHistory().length + 1, "the split is recorded");
    }

}

/// @dev Advertises the V3 resolved path and returns a marker, so a test can tell which path the
///      builder took without standing up a whole printer.
contract ResolvedStubExtension {
    function supportsExtensionType(bytes32) external pure returns (bool) { return true; }
    function supportsResolvedExtensionData() external pure returns (bool) { return true; }
    function getResolvedExtensionURI(address, uint256) external pure returns (string memory) {
        return ', "resolved": "yes"';
    }
    function getExtensionURI(bytes memory) external pure returns (string memory) {
        return ', "perScope": "yes"';
    }
}

/// @dev The builder asks the printer for its reserved units, and that call is not guarded.
contract PrinterStub {
    function unitsReserved(uint256) external pure returns (uint256) { return 0; }
}

/// @dev The builder always draws an image, so it needs an image builder wired.
contract ImageBuilderStub is ICertificateImageBuilder {
    function buildCertificateSVG(CertificateSVGParams calldata, uint256) external pure returns (string memory) {
        return "<svg/>";
    }
}

/// @dev Same shape without the resolved surface, which is every extension that predates V3.
contract PerScopeStubExtension {
    function supportsExtensionType(bytes32) external pure returns (bool) { return true; }
    function getExtensionURI(bytes memory) external pure returns (string memory) {
        return ', "perScope": "yes"';
    }
}

/// @notice `CertificateUriBuilder` prefers the resolved section and falls back to the per-scope
///         sections. The cert payload alone is not the whole certificate once a section lives at the
///         series or the class scope, so a V3 extension renders every scope in one section.
contract CertificateUriBuilderResolvedPathTest is Test {
    CertificateUriBuilder internal builder;
    address internal printer;

    function setUp() public {
        BorgAuth auth = new BorgAuth(address(this));
        builder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(auth))
                )
            )
        );
        builder.setImageBuilder(address(new ImageBuilderStub()));
        printer = address(new PrinterStub());
    }

    function _render(address extension) internal view returns (string memory) {
        CertificateUriBuilder.CertificateDetails memory details;
        details.extensionData = bytes("payload");
        return builder.buildCertificateUriNotEncoded(
            "Corp", "C-Corp", "DE", "hi@example.com",
            SecurityClass.PreferredStock, SecuritySeries.SeriesSeed, "ipfs://cert",
            new string[](0), details, new CertificateUriBuilder.Endorsement[](0),
            CertificateUriBuilder.OwnerDetails("holder", address(0xBEEF)),
            address(0), bytes32(0), 1, printer, extension
        );
    }

    function testBuilder_PrefersTheResolvedSection() public {
        string memory json = _render(address(new ResolvedStubExtension()));
        assertEq(vm.parseJsonString(json, ".resolved"), "yes", "the resolved section is rendered");
        assertFalse(vm.keyExistsJson(json, ".perScope"), "the cert-scope section is not");
    }

    function testBuilder_FallsBackWhenTheExtensionPredatesV3() public {
        string memory json = _render(address(new PerScopeStubExtension()));
        assertEq(vm.parseJsonString(json, ".perScope"), "yes", "the cert-scope section still renders");
        assertFalse(vm.keyExistsJson(json, ".resolved"), "there is no resolved section");
    }
}
