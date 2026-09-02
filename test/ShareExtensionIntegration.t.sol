// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {ShareCertDataLayerLib} from "../src/storage/extensions/ShareCertDataLayerLib.sol";
import {
    SeriesTerms,
    ShareCertData,
    ShareExtension,
    TransferRestriction
} from "../src/storage/extensions/ShareExtension.sol";
import {ShareExtensionLogic} from "../src/storage/extensions/ShareExtensionLogic.sol";
import {ShareCertDataLayer, ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {REAL_WORLD_IPFS_URI, RealWorldShareCert} from "./libs/RealWorldShareCert.sol";

/// @notice The layered share payload on a real stack: a real IssuanceManager, a real printer and a real
///         cert. `ShareExtensionLogic` gives back bytes, and this suite stores those bytes at the scope
///         they belong to. Every check then reads the chain through `resolveCert`.
///
/// Each scope has its own write path. The class payload goes through `IssuanceManager.updateSecurityClass`,
/// the series payload through `LedgerEntryToken.setSeriesData`, and the cert payload through
/// `LedgerEntryToken.updateCertificateDetails`, which the IssuanceManager alone can call.
///
/// The fixture is the real Series Seed 2 payload, split as an issuance must split it: the five
/// series-wide sections on the printer, `certificateData` on the cert.
contract ShareExtensionIntegrationTest is Test {
    bytes32 internal constant SALT = keccak256("ShareExtensionIntegrationTest");

    BorgAuth internal auth;
    IssuanceManager internal im;
    LedgerEntryToken internal printer;
    ShareExtensionV3 internal ext;
    ShareExtensionLogic internal logic;

    address internal holder = makeAddr("holder");
    uint256 internal tokenId;

    function setUp() public {
        auth = new BorgAuth(address(this));

        CertificateUriBuilder uriBuilder = CertificateUriBuilder(
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

        // The corp holds the IssuanceManager address and the IssuanceManager holds the corp address, so
        // the proxy is deployed first and initialized after the corp exists.
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

        ext = ShareExtensionV3(
            address(
                new ERC1967Proxy(
                    address(new ShareExtensionV3()),
                    abi.encodeWithSelector(ShareExtension.initialize.selector, address(auth))
                )
            )
        );
        logic = new ShareExtensionLogic();

        printer = LedgerEntryToken(
            im.createCertPrinter(
                RealWorldShareCert.legends(),
                "Seed Preferred Stock - MetaLeX Labs, Inc.",
                "MLI-SEED-PREFSTCK",
                REAL_WORLD_IPFS_URI,
                SecurityClass.PreferredStock,
                SecuritySeries.SeriesSeed,
                address(ext),
                RealWorldShareCert.encodedSeriesLayer()
            )
        );
        tokenId = im.createCertAndAssign(address(printer), holder, _certDetails());
    }

    /// @notice The stored layers merge back to the whole payload. This is the baseline every write test
    ///         starts from.
    function test_resolveCert_MergesTheLayersTheChainHolds() public view {
        assertEq(
            keccak256(abi.encode(ext.resolveCert(address(printer), tokenId))),
            keccak256(abi.encode(RealWorldShareCert.shareCertData())),
            "the cert and the printer hold the whole security between them"
        );
    }

    // --- Series scope ---

    function test_updateSeriesName_WritesToThePrinter() public {
        printer.setSeriesData(logic.updateSeriesName(_storedSeriesLayer(), "Series Seed 2-A"));

        ShareCertData memory resolved = ext.resolveCert(address(printer), tokenId);
        assertEq(resolved.terms.seriesName, "Series Seed 2-A", "the new name resolves off the chain");
        assertEq(
            resolved.transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "the other series sections are kept"
        );
        assertEq(
            resolved.certificateData.sourceAuthorityURI, RealWorldShareCert.PINATA_URI, "the cert layer is untouched"
        );
    }

    function test_addTransferRestriction_WritesToThePrinter() public {
        TransferRestriction memory added;
        added.restrictionText = "Added by board resolution";

        printer.setSeriesData(logic.addTransferRestriction(_storedSeriesLayer(), added));

        ShareCertData memory resolved = ext.resolveCert(address(printer), tokenId);
        uint256 last = resolved.transferRestrictions.length - 1;
        assertEq(last, RealWorldShareCert.transferRestrictions().length, "one more than before");
        assertEq(resolved.transferRestrictions[last].restrictionText, "Added by board resolution");
    }

    function test_recordStockSplit_WritesToThePrinter() public {
        printer.setSeriesData(logic.recordStockSplit(_storedSeriesLayer(), 2, 1, "ipfs://split", block.timestamp));

        ShareCertData memory resolved = ext.resolveCert(address(printer), tokenId);
        SeriesTerms memory before = RealWorldShareCert.seriesTerms();
        assertEq(resolved.terms.parValue, before.parValue / 2, "par value halves");
        assertEq(resolved.terms.authorizedShares, before.authorizedShares * 2, "authorized shares double");
        assertEq(resolved.splitHistory.length, RealWorldShareCert.splitHistory().length + 1, "the split is recorded");
    }

    /// @notice A change aimed at a section the layer does not carry is refused. The cert layer inherits
    ///         its restrictions, so nothing is written and the chain keeps what the series holds.
    function test_addTransferRestriction_RefusesTheStoredCertLayer() public {
        TransferRestriction memory added;
        bytes memory certLayer = printer.getExtensionData(tokenId);

        vm.expectRevert(bytes("ShareExtensionLogic: layer has no transferRestrictions section"));
        logic.addTransferRestriction(certLayer, added);

        assertEq(
            ext.resolveCert(address(printer), tokenId).transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length,
            "the stored restrictions are unchanged"
        );
    }

    // --- Class scope ---

    /// @notice The class payload is stored on the IssuanceManager, and `resolveCert` reads it through the
    ///         printer's class ID. Its terms lose to the series terms. Its restrictions are added to them.
    function test_updateSecurityClass_WritesTheClassLayer() public {
        SeriesTerms memory classTerms = RealWorldShareCert.seriesTerms();
        classTerms.seriesName = "Preferred Stock (class default)";

        ShareCertDataLayer memory classLayer;
        classLayer.terms = new SeriesTerms[](1);
        classLayer.terms[0] = classTerms;
        classLayer.transferRestrictions = new TransferRestriction[][](1);
        classLayer.transferRestrictions[0] = _oneRestriction("Class transfer restriction");

        im.updateSecurityClass(
            im.getPrinterClassId(address(printer)),
            SecurityClass.PreferredStock,
            "ipfs://certificate-of-designation",
            address(ext),
            abi.encode(classLayer)
        );

        ShareCertData memory resolved = ext.resolveCert(address(printer), tokenId);
        assertEq(resolved.terms.seriesName, "Series Seed 2", "the series terms win over the class terms");
        assertEq(
            resolved.transferRestrictions.length,
            RealWorldShareCert.transferRestrictions().length + 1,
            "the class restriction is added to the series ones"
        );
        assertEq(
            resolved.transferRestrictions[0].restrictionText, "Class transfer restriction", "the class comes first"
        );
    }

    // --- Cert scope ---

    /// @notice The overwrite flag on the stored cert layer drops the series list. This is the only way a
    ///         cert can remove what a layer above it holds.
    function test_updateCertificateDetails_WritesTheCertLayer() public {
        ShareCertDataLayer memory certLayer = ShareCertDataLayerLib.decodeLayer(printer.getExtensionData(tokenId));
        certLayer.transferRestrictions = new TransferRestriction[][](1);
        certLayer.transferRestrictions[0] = new TransferRestriction[](0);
        certLayer.overwriteTransferRestrictions = true;

        CertificateDetails memory details = printer.getActiveCertificateDetails(tokenId);
        details.extensionData = abi.encode(certLayer);

        vm.prank(address(im));
        printer.updateCertificateDetails(tokenId, details);

        ShareCertData memory resolved = ext.resolveCert(address(printer), tokenId);
        assertEq(resolved.transferRestrictions.length, 0, "the cert clears the series restrictions");
        assertEq(resolved.terms.seriesName, "Series Seed 2", "the sections the cert leaves unset still resolve");
        assertEq(
            resolved.specialVotingRights.length,
            RealWorldShareCert.votingRights().length,
            "a flag on one section leaves the other sections alone"
        );
    }

    function _storedSeriesLayer() internal view returns (bytes memory seriesData) {
        (, seriesData) = printer.getSeriesInfo();
    }

    function _oneRestriction(string memory text) internal pure returns (TransferRestriction[] memory list) {
        list = new TransferRestriction[](1);
        list[0].restrictionText = text;
    }

    function _certDetails() internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100_000e18,
            issuerUSDValuationAtTimeOfInvestment: 25_000_000e18,
            unitsRepresented: 10_000e18,
            legalDetails: "Series Seed 2 Preferred Stock Certificate",
            extensionData: RealWorldShareCert.encodedCertLayer()
        });
    }
}
