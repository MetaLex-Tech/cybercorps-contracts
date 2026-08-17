// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {
    CertificateData,
    MandatoryConversionTrigger,
    SHARE_LAYER_TAG,
    SeriesTerms,
    SpecialVotingRight,
    ShareCertData,
    ShareLayer,
    SplitRecord,
    TransferRestriction
} from "../src/storage/extensions/ShareExtension.sol";
import {RealWorldShareCert} from "./libs/RealWorldShareCert.sol";
import {SecondaryTradeEquityGasLimitTest} from "./SecondaryTradeEquityGasLimit.t.sol";
import {Test, console2} from "forge-std/Test.sol";

/// @notice Design A. Every section is a static struct, and a bitmask says which sections this layer
///         sets. A section the layer does not set is still encoded, as a blank struct or an empty
///         array, because a static field always occupies its place in the encoding.
struct TypedLayerA {
    uint256 present;
    CertificateData certificateData;
    SeriesTerms terms;
    MandatoryConversionTrigger[] conversionTriggers;
    SpecialVotingRight[] votingRights;
    TransferRestriction[] transferRestrictions;
    SplitRecord[] splitHistory;
}

/// @notice Design B. The two struct sections become arrays of zero or one entry, so an unset section
///         costs one length word instead of a whole blank struct. The four list sections keep a flag,
///         which separates "this layer sets an empty list" from "this layer sets nothing".
struct TypedLayerB {
    CertificateData[] certificateData;
    SeriesTerms[] terms;
    bool setsConversionTriggers;
    MandatoryConversionTrigger[] conversionTriggers;
    bool setsVotingRights;
    SpecialVotingRight[] votingRights;
    bool setsTransferRestrictions;
    TransferRestriction[] transferRestrictions;
    bool setsSplitHistory;
    SplitRecord[] splitHistory;
}

/// @notice Design C. Every section is an array of zero or one entry, including the list sections.
///         One presence rule for all six: length zero inherits, length one sets. No mask, no flags.
struct TypedLayerC {
    CertificateData[] certificateData;
    SeriesTerms[] terms;
    MandatoryConversionTrigger[][] conversionTriggers;
    SpecialVotingRight[][] votingRights;
    TransferRestriction[][] transferRestrictions;
    SplitRecord[][] splitHistory;
}

library TypedLayerFixture {
    function certLayerC() internal pure returns (bytes memory) {
        TypedLayerC memory layer;
        layer.certificateData = new CertificateData[](1);
        layer.certificateData[0] = RealWorldShareCert.certificateData();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function seriesLayerC() internal pure returns (bytes memory) {
        TypedLayerC memory layer;
        layer.terms = new SeriesTerms[](1);
        layer.terms[0] = RealWorldShareCert.seriesTerms();
        layer.conversionTriggers = new MandatoryConversionTrigger[][](1);
        layer.conversionTriggers[0] = RealWorldShareCert.conversionTriggers();
        layer.votingRights = new SpecialVotingRight[][](1);
        layer.votingRights[0] = RealWorldShareCert.votingRights();
        layer.transferRestrictions = new TransferRestriction[][](1);
        layer.transferRestrictions[0] = RealWorldShareCert.transferRestrictions();
        layer.splitHistory = new SplitRecord[][](1);
        layer.splitHistory[0] = RealWorldShareCert.splitHistory();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    /// @dev A cert that overrides nothing at all: the series sets even the certificateData default.
    ///      This is the floor each format puts on a lot, and settlement pays it on every lot forever.
    function emptyLayerA() internal pure returns (bytes memory) {
        TypedLayerA memory layer;
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function emptyLayerC() internal pure returns (bytes memory) {
        TypedLayerC memory layer;
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function certLayerA() internal pure returns (bytes memory) {
        TypedLayerA memory layer;
        layer.present = 1; // certificateData only
        layer.certificateData = RealWorldShareCert.certificateData();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function seriesLayerA() internal pure returns (bytes memory) {
        TypedLayerA memory layer;
        layer.present = 62; // every section except certificateData
        layer.terms = RealWorldShareCert.seriesTerms();
        layer.conversionTriggers = RealWorldShareCert.conversionTriggers();
        layer.votingRights = RealWorldShareCert.votingRights();
        layer.transferRestrictions = RealWorldShareCert.transferRestrictions();
        layer.splitHistory = RealWorldShareCert.splitHistory();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function certLayerB() internal pure returns (bytes memory) {
        TypedLayerB memory layer;
        layer.certificateData = new CertificateData[](1);
        layer.certificateData[0] = RealWorldShareCert.certificateData();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function seriesLayerB() internal pure returns (bytes memory) {
        TypedLayerB memory layer;
        layer.terms = new SeriesTerms[](1);
        layer.terms[0] = RealWorldShareCert.seriesTerms();
        layer.setsConversionTriggers = true;
        layer.conversionTriggers = RealWorldShareCert.conversionTriggers();
        layer.setsVotingRights = true;
        layer.votingRights = RealWorldShareCert.votingRights();
        layer.setsTransferRestrictions = true;
        layer.transferRestrictions = RealWorldShareCert.transferRestrictions();
        layer.setsSplitHistory = true;
        layer.splitHistory = RealWorldShareCert.splitHistory();
        return abi.encode(SHARE_LAYER_TAG, layer);
    }
}

/// @notice Measurement only. Runs the equity secondary-trade lifecycle with a typed cert payload in
///         place of the `bytes`-section payload, so the three formats can be compared on the same
///         trade. Nothing in `src` decodes these structs; the point is what each format costs to store.
contract SecondaryTradeEquityTypedLayerAAdhocTest is SecondaryTradeEquityGasLimitTest {
    function _seriesData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.seriesLayerA();
    }

    function _certExtensionData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.certLayerA();
    }
}

contract SecondaryTradeEquityTypedLayerBAdhocTest is SecondaryTradeEquityGasLimitTest {
    function _seriesData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.seriesLayerB();
    }

    function _certExtensionData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.certLayerB();
    }
}

contract SecondaryTradeEquityTypedLayerCAdhocTest is SecondaryTradeEquityGasLimitTest {
    function _seriesData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.seriesLayerC();
    }

    function _certExtensionData() internal pure override returns (bytes memory) {
        return TypedLayerFixture.certLayerC();
    }
}

contract ShareLayerPayloadSizeAdhocTest is Test {
    function test_report_everyFormatSize() public pure {
        _report("legacy whole struct", RealWorldShareCert.encodedShareCertData());
        _report("layered bytes  cert", RealWorldShareCert.encodedCertLayer());
        _report("typed A        cert", TypedLayerFixture.certLayerA());
        _report("typed B        cert", TypedLayerFixture.certLayerB());
        _report("typed C        cert", TypedLayerFixture.certLayerC());
        _report("empty A        cert", TypedLayerFixture.emptyLayerA());
        _report("empty C        cert", TypedLayerFixture.emptyLayerC());
        _report("layered bytes  serie", RealWorldShareCert.encodedSeriesLayer());
        _report("typed A        serie", TypedLayerFixture.seriesLayerA());
        _report("typed C        serie", TypedLayerFixture.seriesLayerC());
        _report("empty bytes    cert", abi.encode(SHARE_LAYER_TAG, ShareLayer((""),"","","","","")));
    }

    /// @notice The `bytes` payload and the design C payload are the same length and cost the same to
    ///         store, but they are not the same bytes. They are different wire formats, and both carry
    ///         the same tag, so a decoder cannot tell them apart. Adopting a typed format alongside
    ///         stored `bytes` layers needs its own tag.
    function test_report_bytesVsTypedC_sameSizeDifferentBytes() public pure {
        bytes memory asBytes = RealWorldShareCert.encodedCertLayer();
        bytes memory asTypedC = TypedLayerFixture.certLayerC();

        assertEq(asTypedC.length, asBytes.length, "same length");
        assertTrue(keccak256(asTypedC) != keccak256(asBytes), "not the same bytes");

        uint256 differing;
        uint256 firstDiff = type(uint256).max;
        for (uint256 i = 0; i < asBytes.length / 32; i++) {
            if (_wordAt(asBytes, i) != _wordAt(asTypedC, i)) {
                differing++;
                if (firstDiff == type(uint256).max) firstDiff = i;
            }
        }
        console2.log("words total / differing / first differing index:", asBytes.length / 32, differing, firstDiff);
        console2.logBytes32(_wordAt(asBytes, firstDiff));
        console2.logBytes32(_wordAt(asTypedC, firstDiff));
    }

    function _wordAt(bytes memory payload, uint256 index) private pure returns (bytes32 word) {
        assembly ("memory-safe") {
            word := mload(add(add(payload, 32), mul(index, 32)))
        }
    }

    /// @dev A mint writes the payload word by word. A zero word costs 100 gas, a non-zero word costs
    ///      about 22,100, so the non-zero word count predicts the cost far better than the byte count.
    function _report(string memory label, bytes memory payload) private pure {
        uint256 words = (payload.length + 31) / 32;
        uint256 nonZero;
        for (uint256 i = 0; i < words; i++) {
            bytes32 word;
            assembly ("memory-safe") {
                word := mload(add(add(payload, 32), mul(i, 32)))
            }
            if (word != bytes32(0)) nonZero++;
        }
        console2.log(label, payload.length, words, nonZero);
    }
}

/// @notice Size probes. Each holds the same resolver over a different layer format, so the difference
///         between them is what the format's ABI coder costs in bytecode. `ShareExtension` has 2,070 B
///         of EIP-170 margin and `ShareExtensionV3` has 1,589 B, so this is a hard budget, not a
///         preference.
contract ResolverOverBytesProbe {
    function resolve(bytes memory certData, bytes memory seriesData, bytes memory classData)
        external
        pure
        returns (ShareCertData memory share)
    {
        (, ShareLayer memory cert) = abi.decode(certData, (bytes32, ShareLayer));
        (, ShareLayer memory series) = abi.decode(seriesData, (bytes32, ShareLayer));
        (, ShareLayer memory class_) = abi.decode(classData, (bytes32, ShareLayer));
        bytes memory s = _pick(cert.certificateData, series.certificateData, class_.certificateData);
        if (s.length != 0) share.certificateData = abi.decode(s, (CertificateData));
        s = _pick(cert.terms, series.terms, class_.terms);
        if (s.length != 0) share.terms = abi.decode(s, (SeriesTerms));
        s = _pick(cert.conversionTriggers, series.conversionTriggers, class_.conversionTriggers);
        if (s.length != 0) share.mandatoryConversionTriggers = abi.decode(s, (MandatoryConversionTrigger[]));
        s = _pick(cert.votingRights, series.votingRights, class_.votingRights);
        if (s.length != 0) share.specialVotingRights = abi.decode(s, (SpecialVotingRight[]));
        s = _pick(cert.transferRestrictions, series.transferRestrictions, class_.transferRestrictions);
        if (s.length != 0) share.transferRestrictions = abi.decode(s, (TransferRestriction[]));
        s = _pick(cert.splitHistory, series.splitHistory, class_.splitHistory);
        if (s.length != 0) share.splitHistory = abi.decode(s, (SplitRecord[]));
    }

    function _pick(bytes memory a, bytes memory b, bytes memory c) private pure returns (bytes memory) {
        if (a.length != 0) return a;
        if (b.length != 0) return b;
        return c;
    }
}

contract ResolverOverTypedAProbe {
    uint256 private constant CERT_DATA = 1;
    uint256 private constant TERMS = 2;
    uint256 private constant TRIGGERS = 4;
    uint256 private constant VOTING = 8;
    uint256 private constant RESTRICTIONS = 16;
    uint256 private constant SPLITS = 32;

    function resolve(bytes memory certData, bytes memory seriesData, bytes memory classData)
        external
        pure
        returns (ShareCertData memory share)
    {
        (, TypedLayerA memory cert) = abi.decode(certData, (bytes32, TypedLayerA));
        (, TypedLayerA memory series) = abi.decode(seriesData, (bytes32, TypedLayerA));
        (, TypedLayerA memory class_) = abi.decode(classData, (bytes32, TypedLayerA));
        if (cert.present & CERT_DATA != 0) share.certificateData = cert.certificateData;
        else if (series.present & CERT_DATA != 0) share.certificateData = series.certificateData;
        else if (class_.present & CERT_DATA != 0) share.certificateData = class_.certificateData;

        if (cert.present & TERMS != 0) share.terms = cert.terms;
        else if (series.present & TERMS != 0) share.terms = series.terms;
        else if (class_.present & TERMS != 0) share.terms = class_.terms;

        if (cert.present & TRIGGERS != 0) share.mandatoryConversionTriggers = cert.conversionTriggers;
        else if (series.present & TRIGGERS != 0) share.mandatoryConversionTriggers = series.conversionTriggers;
        else if (class_.present & TRIGGERS != 0) share.mandatoryConversionTriggers = class_.conversionTriggers;

        if (cert.present & VOTING != 0) share.specialVotingRights = cert.votingRights;
        else if (series.present & VOTING != 0) share.specialVotingRights = series.votingRights;
        else if (class_.present & VOTING != 0) share.specialVotingRights = class_.votingRights;

        if (cert.present & RESTRICTIONS != 0) share.transferRestrictions = cert.transferRestrictions;
        else if (series.present & RESTRICTIONS != 0) share.transferRestrictions = series.transferRestrictions;
        else if (class_.present & RESTRICTIONS != 0) share.transferRestrictions = class_.transferRestrictions;

        if (cert.present & SPLITS != 0) share.splitHistory = cert.splitHistory;
        else if (series.present & SPLITS != 0) share.splitHistory = series.splitHistory;
        else if (class_.present & SPLITS != 0) share.splitHistory = class_.splitHistory;
    }
}
