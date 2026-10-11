// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {
    CertificateSVGParams,
    CertificateSVGParamsV2,
    CompanyOfficer,
    SecurityClass,
    SecuritySeries
} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictiveLegend
} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SAFEData, SAFEExtension} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFEExtensionV3, SAFESeriesData} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {SAFTExtensionV3, SAFTSeriesData} from "../src/storage/extensions/SAFTExtensionV3.sol";
import {SeriesTerms, ShareCertData, ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
import {ShareCertDataLayer, ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {REAL_WORLD_IPFS_URI, RealWorldShareCert} from "./libs/RealWorldShareCert.sol";

/// @notice An image builder deployed before V3. It has the V1 and V2 selectors and nothing else, so a
///         V3 call to it reverts.
contract V2OnlyImageBuilder {
    CertificateImageBuilderContract internal immutable inner;

    constructor() {
        inner = new CertificateImageBuilderContract();
    }

    function buildCertificateSVG(CertificateSVGParams calldata params, uint256 timestamp)
        external
        view
        returns (string memory)
    {
        return inner.buildCertificateSVG(params, timestamp);
    }

    function buildCertificateSVGV2(CertificateSVGParamsV2 calldata params, uint256 timestamp)
        external
        view
        returns (string memory)
    {
        return inner.buildCertificateSVGV2(params, timestamp);
    }
}

/// @notice Shared decoding and search helpers.
abstract contract SeriesNameAssertions is Test {
    function _decode(string memory uri, uint256 prefix) internal pure returns (string memory) {
        bytes memory input = bytes(uri);
        require(input.length > prefix, "nonblank data URI required");
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

    /// @dev The JSON document of a `tokenURI` result.
    function _jsonOf(string memory uri) internal pure returns (string memory) {
        return _decode(uri, bytes("data:application/json;base64,").length);
    }

    /// @dev The SVG of a JSON document.
    function _svgOf(string memory json) internal view returns (string memory) {
        return _decode(vm.parseJsonString(json, ".image"), bytes("data:image/svg+xml;base64,").length);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool found) {
        bytes memory hay = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > hay.length) return false;
        assembly ("memory-safe") {
            let size := mload(n)
            let hash := keccak256(add(n, 32), size)
            let end := add(add(hay, 32), sub(mload(hay), size))
            for { let p := add(hay, 32) } iszero(gt(p, end)) { p := add(p, 1) } {
                if eq(keccak256(p, size), hash) {
                    found := 1
                    break
                }
            }
        }
    }

    /// @dev The class and series line of the image, exactly.
    function _assertLine(string memory svg, string memory line) internal pure {
        assertTrue(
            _contains(svg, string.concat('fill="#f2f2f2" text-anchor="middle">', line, "</text>")),
            string.concat("image shows: ", line)
        );
    }

    /// @dev The new root field and its attribute both carry `text`. The enum token field is unchanged.
    function _assertSeriesJson(string memory json, string memory text, string memory enumToken) internal view {
        assertEq(vm.parseJsonString(json, ".seriesName"), text, "root seriesName");
        assertTrue(
            _contains(json, string.concat('{"trait_type": "seriesName", "value": "', text, '"}')),
            "seriesName attribute"
        );
        assertEq(vm.parseJsonString(json, ".securitySeries"), enumToken, "securitySeries keeps the enum token");
        assertTrue(
            _contains(json, string.concat('{"trait_type": "securitySeries", "value": "', enumToken, '"}')),
            "securitySeries attribute keeps the enum token"
        );
    }
}

/// @notice A certificate shows its own free-text series name after its class, in the image and in the
///         JSON. Every case runs `tokenURI` on a real IssuanceManager, a real printer and real extensions.
contract CertificateSeriesNameTest is SeriesNameAssertions {
    bytes32 internal constant SALT = keccak256("CertificateSeriesNameTest");

    BorgAuth internal auth;
    IssuanceManager internal im;
    CertificateUriBuilder internal uriBuilder;
    address internal holder = makeAddr("holder");

    function setUp() public {
        auth = new BorgAuth(address(this));
        uriBuilder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(auth))
                )
            )
        );
        uriBuilder.setImageBuilder(address(new CertificateImageBuilderContract()));

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        address(new IssuanceManager()),
                        address(new LedgerEntryToken()),
                        address(new CyberScrip())
                    )
                )
            )
        );
        im = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        address corp = address(
            new ERC1967Proxy(
                address(new CyberCorp()),
                abi.encodeWithSelector(
                    CyberCorp.initialize.selector,
                    address(auth),
                    "MetaLeX Labs, Inc.",
                    "C-Corp",
                    "DE",
                    "hi@example.com",
                    "Delaware Court of Chancery",
                    address(im),
                    address(this),
                    CompanyOfficer(address(this), "Officer", "officer@example.com", "CEO"),
                    address(0),
                    address(0)
                )
            )
        );
        im.initialize(address(auth), corp, address(uriBuilder), address(imFactory));
    }

    // --- Share extension V1: the name is in the cert payload ---

    /// @notice The live mainnet case: a V1 share cert whose terms say "Series Seed 2" on a Series Seed
    ///         printer. The image showed "Preferred Stock Series Seed" for every cert.
    function test_shareV1_CertTermsNameIsShown() public {
        LedgerEntryToken printer = _shareV1Printer();
        uint256 tokenId = _mint(printer, abi.encode(RealWorldShareCert.shareCertData()));

        string memory json = _jsonOf(printer.tokenURI(tokenId));
        string memory svg = _svgOf(json);
        _assertLine(svg, "Preferred Stock Series Seed 2");
        assertFalse(_contains(svg, "Series Series"), "the stored word Series is not doubled");
        _assertSeriesJson(json, "Series Seed 2", "SeriesSeed");
        vm.parseJson(json);
    }

    /// @notice Two certs on one printer, each with its own name, show different names. This is the
    ///         mainnet printer's token 1 ("Series Seed 2") and token 2 ("Series Seed").
    function test_shareV1_EachCertShowsItsOwnName() public {
        LedgerEntryToken printer = _shareV1Printer();
        uint256 seed2 = _mint(printer, _shareV1Payload("Series Seed 2"));
        uint256 seed = _mint(printer, _shareV1Payload("Series Seed"));

        string memory json2 = _jsonOf(printer.tokenURI(seed2));
        string memory json1 = _jsonOf(printer.tokenURI(seed));
        _assertLine(_svgOf(json2), "Preferred Stock Series Seed 2");
        _assertLine(_svgOf(json1), "Preferred Stock Series Seed");
        assertFalse(_contains(_svgOf(json1), "Series Seed 2"), "the second cert does not take the first name");
        _assertSeriesJson(json2, "Series Seed 2", "SeriesSeed");
        _assertSeriesJson(json1, "Series Seed", "SeriesSeed");
    }

    /// @notice The name is shown as stored, after the class and one space. The renderer adds no
    ///         "Series" of its own.
    function test_shareV1_NameIsShownAsStored() public {
        LedgerEntryToken printer = _shareV1Printer();
        string[3] memory names = ["Seed 2", "Series A-1", "Series B Preferred"];
        string[3] memory lines =
            ["Preferred Stock Seed 2", "Preferred Stock Series A-1", "Preferred Stock Series B Preferred"];
        for (uint256 i; i < names.length; ++i) {
            string memory json = _jsonOf(printer.tokenURI(_mint(printer, _shareV1Payload(names[i]))));
            _assertLine(_svgOf(json), lines[i]);
            _assertSeriesJson(json, names[i], "SeriesSeed");
        }
    }

    /// @notice Markup in a name is escaped in the image and in the JSON. A long name is shortened in
    ///         the image only.
    function test_shareV1_NameIsEscapedAndLongNamesAreShortenedInTheImageOnly() public {
        LedgerEntryToken printer = _shareV1Printer();
        string memory markup = 'Series "A" <b>&</b>';
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, _shareV1Payload(markup))));
        _assertLine(_svgOf(json), "Preferred Stock Series &quot;A&quot; &lt;b&gt;&amp;&lt;/b&gt;");
        assertFalse(_contains(_svgOf(json), "<b>"), "no markup reaches the image");
        assertEq(vm.parseJsonString(json, ".seriesName"), markup, "the JSON keeps the exact name");

        // 60 code points. The image shows the first 48 and "...".
        string memory long = "Series Seed 2 Preferred Stock issued under the 2026 Plan A-1";
        json = _jsonOf(printer.tokenURI(_mint(printer, _shareV1Payload(long))));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed 2 Preferred Stock issued under the 2...");
        assertEq(vm.parseJsonString(json, ".seriesName"), long, "the JSON keeps the full name");
    }

    /// @notice An empty name shows the fixed label of the printer's series enum, as before.
    function test_shareV1_EmptyNameShowsTheFixedLabel() public {
        LedgerEntryToken printer = _shareV1Printer();
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, _shareV1Payload(""))));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed");
        _assertSeriesJson(json, "Series Seed", "SeriesSeed");
    }

    // --- Share extension V3: the extension resolves cert, series and class terms ---

    /// @notice The name is in the series layer. A cert whose layer sets no terms takes it.
    function test_shareV3_SeriesNameReachesACertThatSetsNoTerms() public {
        LedgerEntryToken printer = _shareV3Printer(RealWorldShareCert.encodedSeriesLayer());
        uint256 tokenId = _mint(printer, RealWorldShareCert.encodedCertLayer());

        string memory json = _jsonOf(printer.tokenURI(tokenId));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed 2");
        _assertSeriesJson(json, "Series Seed 2", "SeriesSeed");
    }

    /// @notice A cert layer that sets terms overrides the series name for that cert only.
    function test_shareV3_CertTermsOverrideTheSeriesName() public {
        LedgerEntryToken printer = _shareV3Printer(RealWorldShareCert.encodedSeriesLayer());
        uint256 inherits = _mint(printer, RealWorldShareCert.encodedCertLayer());

        ShareCertDataLayer memory certLayer;
        certLayer.terms = new SeriesTerms[](1);
        certLayer.terms[0] = RealWorldShareCert.seriesTerms();
        certLayer.terms[0].seriesName = "Series Seed 2-B";
        uint256 overrides = _mint(printer, abi.encode(certLayer));

        string memory json = _jsonOf(printer.tokenURI(overrides));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed 2-B");
        _assertSeriesJson(json, "Series Seed 2-B", "SeriesSeed");

        json = _jsonOf(printer.tokenURI(inherits));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed 2");
        _assertSeriesJson(json, "Series Seed 2", "SeriesSeed");
    }

    /// @notice With no series or cert terms, the class terms give the name.
    function test_shareV3_ClassTermsAreTheLastLayer() public {
        LedgerEntryToken printer = _shareV3Printer("");
        uint256 tokenId = _mint(printer, RealWorldShareCert.encodedCertLayer());
        _assertLine(_svgOf(_jsonOf(printer.tokenURI(tokenId))), "Preferred Stock Series Seed");

        (address extension,) = printer.getSeriesInfo();
        ShareCertDataLayer memory classLayer;
        classLayer.terms = new SeriesTerms[](1);
        classLayer.terms[0] = RealWorldShareCert.seriesTerms();
        classLayer.terms[0].seriesName = "Series Seed (class)";
        im.updateSecurityClass(
            im.getPrinterClassId(address(printer)), SecurityClass.PreferredStock, "", extension, abi.encode(classLayer)
        );

        string memory json = _jsonOf(printer.tokenURI(tokenId));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed (class)");
        _assertSeriesJson(json, "Series Seed (class)", "SeriesSeed");
    }

    // --- SAFE and SAFT V3: the name is in the printer's series data ---

    function test_safeV3_SeriesDataNameIsShown() public {
        LedgerEntryToken printer = _printer(
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            _proxy(address(new SAFEExtensionV3())),
            abi.encode(SAFESeriesData("Pre-Seed 2026", new string[](0), ""))
        );
        uint256 tokenId = _mint(printer, abi.encode(SAFEData("Valuation cap $10M")));

        string memory json = _jsonOf(printer.tokenURI(tokenId));
        _assertLine(_svgOf(json), "SAFE Pre-Seed 2026");
        _assertSeriesJson(json, "Pre-Seed 2026", "SeriesPreSeed");
        assertEq(vm.parseJsonString(json, ".SAFESeriesDetails.seriesName"), "Pre-Seed 2026");
    }

    /// @notice SAFT series data has more fields than SAFE series data. The name is still first.
    function test_saftV3_SeriesDataNameIsShown() public {
        LedgerEntryToken printer = _printer(
            SecurityClass.SAFT,
            SecuritySeries.NA,
            _proxy(address(new SAFTExtensionV3())),
            abi.encode(SAFTSeriesData("Strategic Round", 1_800_000_000, new string[](0), "custom"))
        );
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, "")));
        _assertLine(_svgOf(json), "SAFT Strategic Round");
        _assertSeriesJson(json, "Strategic Round", "NA");
    }

    /// @notice A SAFE V3 printer with no series data shows the fixed label.
    function test_safeV3_NoSeriesDataShowsTheFixedLabel() public {
        LedgerEntryToken printer =
            _printer(SecurityClass.SAFE, SecuritySeries.SeriesPreSeed, _proxy(address(new SAFEExtensionV3())), "");
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, abi.encode(SAFEData("")))));
        _assertLine(_svgOf(json), "SAFE Pre-Seed");
        _assertSeriesJson(json, "Pre-Seed", "SeriesPreSeed");
    }

    // --- Fixed-label fallback ---

    /// @notice A V1 extension other than the share extension stores no series name. Its payload is not
    ///         read for one, although it also starts with a string.
    function test_otherV1Extension_ShowsTheFixedLabel() public {
        LedgerEntryToken printer =
            _printer(SecurityClass.SAFE, SecuritySeries.SeriesSeed, _proxy(address(new SAFEExtension())), "");
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, abi.encode(SAFEData("Series Z custom terms")))));
        _assertLine(_svgOf(json), "SAFE Series Seed");
        _assertSeriesJson(json, "Series Seed", "SeriesSeed");
    }

    /// @notice With no extension the fixed label shows. NA has no label, so the line is the class and a
    ///         space, as before, and the JSON name is empty.
    function test_noExtension_ShowsTheFixedLabelAndNAShowsNoSeries() public {
        LedgerEntryToken printer = _printer(SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0), "");
        string memory json = _jsonOf(printer.tokenURI(_mint(printer, "")));
        _assertLine(_svgOf(json), "Common Stock Series A");
        _assertSeriesJson(json, "Series A", "SeriesA");

        printer = _printer(SecurityClass.CommonStock, SecuritySeries.NA, address(0), "");
        json = _jsonOf(printer.tokenURI(_mint(printer, "")));
        _assertLine(_svgOf(json), "Common Stock ");
        _assertSeriesJson(json, "", "NA");
    }

    // --- Image builder deployed before V3 ---

    /// @notice The URI renderer can be upgraded before the image builder. The image then shows the fixed
    ///         label through the V2 call, and the JSON already has the name.
    function test_imageBuilderWithoutV3_FallsBackToV2() public {
        uriBuilder.setImageBuilder(address(new V2OnlyImageBuilder()));
        LedgerEntryToken printer = _shareV1Printer();
        uint256 tokenId = _mint(printer, _shareV1Payload("Series Seed 2"));

        string memory json = _jsonOf(printer.tokenURI(tokenId));
        string memory svg = _svgOf(json);
        _assertLine(svg, "Preferred Stock Series Seed");
        assertFalse(_contains(svg, "Series Seed 2"), "a V2 image builder cannot show the name");
        _assertSeriesJson(json, "Series Seed 2", "SeriesSeed");
    }

    // --- Fixtures ---

    function _proxy(address implementation) internal returns (address) {
        return address(
            new ERC1967Proxy(implementation, abi.encodeWithSelector(ShareExtension.initialize.selector, address(auth)))
        );
    }

    function _printer(SecurityClass class_, SecuritySeries series, address extension, bytes memory seriesData)
        internal
        returns (LedgerEntryToken)
    {
        return LedgerEntryToken(
            im.createCertPrinter(
                RealWorldShareCert.legends(),
                "Series Name Printer",
                "SNP",
                REAL_WORLD_IPFS_URI,
                class_,
                series,
                extension,
                seriesData
            )
        );
    }

    function _shareV1Printer() internal returns (LedgerEntryToken) {
        return
            _printer(SecurityClass.PreferredStock, SecuritySeries.SeriesSeed, _proxy(address(new ShareExtension())), "");
    }

    function _shareV3Printer(bytes memory seriesLayer) internal returns (LedgerEntryToken) {
        return _printer(
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesSeed,
            _proxy(address(new ShareExtensionV3())),
            seriesLayer
        );
    }

    /// @dev The real Series Seed 2 payload with another series name, in the V1 shape.
    function _shareV1Payload(string memory seriesName) internal pure returns (bytes memory) {
        ShareCertData memory share = RealWorldShareCert.shareCertData();
        share.terms.seriesName = seriesName;
        return abi.encode(share);
    }

    function _mint(LedgerEntryToken printer, bytes memory extensionData) internal returns (uint256) {
        return im.createCertAndAssign(
            address(printer),
            holder,
            CertificateDetails({
                signingOfficerName: "Officer",
                signingOfficerTitle: "CEO",
                investmentAmountUSD: 100_000e18,
                issuerUSDValuationAtTimeOfInvestment: 25_000_000e18,
                unitsRepresented: 10_000e18,
                legalDetails: "",
                extensionData: extensionData
            })
        );
    }
}

/// @notice Stands in for an extension. It claims one extension type, renders no section, and gives
///         `resolveCert` the return data the test sets, or reverts.
contract SeriesExtensionMock {
    bytes32 internal claimed;
    bytes internal answer;
    bool internal fails;

    function configure(bytes32 extensionType, bytes memory resolveAnswer, bool resolveFails) external {
        claimed = extensionType;
        answer = resolveAnswer;
        fails = resolveFails;
    }

    function supportsExtensionType(bytes32 extensionType) external view returns (bool) {
        return extensionType == claimed;
    }

    function getExtensionURI(bytes memory) external pure returns (string memory) {
        return "";
    }

    function resolveCert(address, uint256) external view {
        if (fails) revert("resolve failure");
        bytes memory data = answer;
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }
}

contract SeriesUriHarness is CertificateUriBuilder {
    constructor(address image) {
        imageBuilder = image;
    }
}

/// @notice A name read that fails, or data that does not hold a name, never fails the render. The
///         certificate shows the fixed label instead.
contract CertificateSeriesNameFallbackTest is SeriesNameAssertions {
    SeriesUriHarness internal builder;
    SeriesExtensionMock internal mock;
    address internal constant TOKEN = address(0x1234);

    function setUp() public {
        builder = new SeriesUriHarness(address(new CertificateImageBuilderContract()));
        mock = new SeriesExtensionMock();
        // STOP behaves like a printer without the optional getters.
        vm.etch(TOKEN, hex"00");
    }

    function _render(address extension, bytes memory certData) internal view returns (string memory) {
        CertificateDetails memory details;
        details.signingOfficerName = "Officer";
        details.unitsRepresented = 1e18;
        details.extensionData = certData;
        return builder.buildCertificateUriNotEncoded(
            "Example Corp",
            "Corp",
            "DE",
            "",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesSeed,
            "",
            new RestrictiveLegend[](0),
            details,
            new Endorsement[](0),
            OwnerDetails("Holder", address(0xCAFE)),
            address(0),
            bytes32(0),
            1,
            TOKEN,
            extension
        );
    }

    function _assertFallback(string memory json) internal view {
        vm.parseJson(json);
        _assertLine(_svgOf(json), "Common Stock Series Seed");
        _assertSeriesJson(json, "Series Seed", "SeriesSeed");
    }

    /// @dev `abi.encode` of a struct whose first member is a struct that starts with `name`.
    function _named(string memory name) internal pure returns (bytes memory) {
        return abi.encode(SAFESeriesData(name, new string[](0), ""), SAFEData("cert"));
    }

    /// @notice Control: the mock does give a name when its data is well formed, so the cases below
    ///         prove the fallback and not a broken fixture.
    function test_wellFormedMockAnswerIsShown() public {
        mock.configure(keccak256("SAFE_V3"), _wrap(_named("Seed Extension")), false);
        string memory json = _render(address(mock), "");
        _assertLine(_svgOf(json), "Common Stock Seed Extension");
        _assertSeriesJson(json, "Seed Extension", "SeriesSeed");

        mock.configure(keccak256("SHARE"), "", false);
        json = _render(address(mock), _wrap(_named("Seed From Cert")));
        _assertSeriesJson(json, "Seed From Cert", "SeriesSeed");
    }

    function test_revertingResolveCertFallsBack() public {
        mock.configure(keccak256("SAFE_V3"), "", true);
        _assertFallback(_render(address(mock), ""));
    }

    function test_revertingOrMalformedTypeProbeFallsBack() public {
        mock.configure(keccak256("SHARE"), "", false);
        bytes memory payload = _wrap(_named("Never Shown"));
        vm.mockCallRevert(address(mock), abi.encodeWithSelector(mock.supportsExtensionType.selector), "probe failure");
        _assertFallback(_render(address(mock), payload));
        vm.clearMockedCalls();
        // A non-boolean or short answer is not a yes.
        vm.mockCall(address(mock), abi.encodeWithSelector(mock.supportsExtensionType.selector), abi.encode(uint256(2)));
        _assertFallback(_render(address(mock), payload));
        vm.mockCall(address(mock), abi.encodeWithSelector(mock.supportsExtensionType.selector), hex"01");
        _assertFallback(_render(address(mock), payload));
    }

    /// @notice A resolved answer over the return-data bound is not copied or read.
    function test_oversizedResolveCertAnswerFallsBack() public {
        address extension = address(0x5EE5);
        // Returns 128 KiB + 1 zero bytes to every call.
        vm.etch(extension, hex"620200016000f3");
        vm.mockCall(
            extension, abi.encodeWithSignature("supportsExtensionType(bytes32)", keccak256("SAFE_V3")), abi.encode(true)
        );
        _assertFallback(_render(extension, ""));
    }

    /// @notice Malformed resolved answers and malformed V1 share payloads.
    function test_malformedDataFallsBack() public {
        bytes[] memory cases = _malformed();
        for (uint256 i; i < cases.length; ++i) {
            mock.configure(keccak256("SAFE_V3"), cases[i], false);
            _assertFallback(_render(address(mock), ""));
            mock.configure(keccak256("SHARE"), "", false);
            _assertFallback(_render(address(mock), cases[i]));
        }
    }

    /// @notice An extension type that is not on the list is not read, even when its data starts with a
    ///         string. The fund interest V3 series data starts with `interestClass`, which is not a name.
    function test_unlistedExtensionTypeIsNotRead() public {
        mock.configure(keccak256("FUND_INTEREST"), _wrap(_named("Class A Units")), false);
        _assertFallback(_render(address(mock), _wrap(_named("Class A Units"))));
    }

    /// @dev Adds the outer tuple offset, as `abi.encode(outerStruct)` and a struct return value have.
    function _wrap(bytes memory tuple) internal pure returns (bytes memory) {
        return abi.encodePacked(uint256(0x20), tuple);
    }

    function _malformed() internal pure returns (bytes[] memory cases) {
        // The name's length word is at 0xc0 and its bytes start at 0xe0. Cut the data 5 bytes into the name.
        bytes memory valid = _wrap(_named("Never Shown"));
        bytes memory truncated = new bytes(0xe5);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = valid[i];
        }
        cases = new bytes[](9);
        cases[0] = hex"1234";
        cases[1] = abi.encode(uint256(0x20));
        // Each offset points past the end.
        cases[2] = abi.encode(uint256(0x1000), uint256(0x20), uint256(0x20));
        cases[3] = abi.encode(uint256(0x20), uint256(0x1000), uint256(0x20));
        cases[4] = abi.encode(uint256(0x20), uint256(0x20), uint256(0x1000));
        // Offsets that overflow when added.
        cases[5] = abi.encode(type(uint256).max, type(uint256).max, type(uint256).max);
        cases[6] = abi.encode(uint256(0x20), type(uint256).max - 0x1f, uint256(0x20));
        // The string length runs past the end.
        cases[7] = abi.encode(uint256(0x20), uint256(0x20), uint256(0x20), type(uint256).max);
        cases[8] = truncated;
        // Control: the cut is the only fault. The full encoding does hold the name.
        require(keccak256(bytes(_nameAt(valid))) == keccak256("Never Shown"), "fixture layout changed");
    }

    /// @dev Reads the fixture name at the fixed offsets that `_malformed` relies on.
    function _nameAt(bytes memory data) internal pure returns (string memory name) {
        name = new string(11);
        for (uint256 i; i < 11; ++i) {
            bytes(name)[i] = data[0xe0 + i];
        }
    }
}

/// @notice The mainnet printer from the report. Its V1 share certs say "Series Seed 2" (tokens 0, 1, 3)
///         and "Series Seed" (token 2), and the image showed "Preferred Stock Series Seed" for all.
contract CertificateSeriesNameForkTest is SeriesNameAssertions {
    address internal constant PRINTER = 0xc0449f24cf28dDA64aFfB74b81a460Fb9b1E0E37;
    // Pinned. The test asserts the names that the certs hold at this block.
    uint256 internal constant PINNED_BLOCK = 26_171_000;

    function setUp() public {
        vm.createSelectFork("ethereum", PINNED_BLOCK);
    }

    function testLiveImageShowsTheFixedLabelBeforeTheUpgrade() public view {
        string memory json = _jsonOf(LedgerEntryToken(PRINTER).tokenURI(1));
        _assertLine(_svgOf(json), "Preferred Stock Series Seed");
        assertFalse(vm.keyExistsJson(json, ".seriesName"));
        assertEq(vm.parseJsonString(json, ".shareDetails.terms.seriesName"), "Series Seed 2");
    }

    /// @notice URI renderer first, with the deployed image builder, which has no V3 call. The JSON has
    ///         the names and the image keeps the fixed label.
    function testUriOnlyUpgradeKeepsTheDeployedImageBuilder() public {
        address image = _upgrade(false);
        assertEq(image.code.length, 14_856, "the deployed image builder from before V3");
        string[4] memory names = ["Series Seed 2", "Series Seed 2", "Series Seed", "Series Seed 2"];
        for (uint256 tokenId; tokenId < 4; ++tokenId) {
            string memory json = _jsonOf(LedgerEntryToken(PRINTER).tokenURI(tokenId));
            _assertLine(_svgOf(json), "Preferred Stock Series Seed");
            _assertSeriesJson(json, names[tokenId], "SeriesSeed");
        }
    }

    /// @notice Both renderers in one call, as the upgrade script does. Each cert shows its own name.
    function testAtomicRenderingUpgradeShowsEachCertsName() public {
        _upgrade(true);
        string[4] memory names = ["Series Seed 2", "Series Seed 2", "Series Seed", "Series Seed 2"];
        for (uint256 tokenId; tokenId < 4; ++tokenId) {
            string memory json = _jsonOf(LedgerEntryToken(PRINTER).tokenURI(tokenId));
            vm.parseJson(json);
            _assertLine(_svgOf(json), string.concat("Preferred Stock ", names[tokenId]));
            _assertSeriesJson(json, names[tokenId], "SeriesSeed");
        }
    }

    /// @dev Local fork impersonation only. No transaction is broadcast.
    function _upgrade(bool replaceImage) internal returns (address image) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        CertificateUriBuilder builder = CertificateUriBuilder(core.uriBuilder);
        address authBefore = address(builder.AUTH());
        image = replaceImage ? address(new CertificateImageBuilderContract()) : builder.imageBuilder();
        address implementation = address(new CertificateUriBuilder());
        vm.prank(core.metalexSafe);
        builder.upgradeToAndCall(implementation, abi.encodeCall(CertificateUriBuilder.setImageBuilder, (image)));
        assertEq(builder.imageBuilder(), image);
        assertEq(address(builder.AUTH()), authBefore);
    }
}
