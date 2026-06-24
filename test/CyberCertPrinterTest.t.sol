// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {IUriBuilder} from "../src/interfaces/IUriBuilder.sol";
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictionType,
    RestrictiveLegend
} from "../src/interfaces/ICyberCertPrinter.sol";

contract MockCyberCorp {
    address public dealManager;
    address public roundManager;

    constructor(address _dealManager, address _roundManager) {
        dealManager = _dealManager;
        roundManager = _roundManager;
    }

    function cyberCORPName() external pure returns (string memory) {
        return "Mock Corp";
    }

    function cyberCORPType() external pure returns (string memory) {
        return "C-Corp";
    }

    function cyberCORPJurisdiction() external pure returns (string memory) {
        return "DE";
    }

    function cyberCORPContactDetails() external pure returns (string memory) {
        return "mock@example.com";
    }
}

contract MockIssuanceManager {
    address public immutable CORP;
    address public immutable uriBuilder;

    constructor(address corp, address builder) {
        CORP = corp;
        uriBuilder = builder;
    }

    function companyName() external pure returns (string memory) {
        return "Mock Corp";
    }

    function getCertScripifiedStatus(
        address,
        uint256
    ) external pure returns (bool isScripified, uint256 scripifiedUnits, uint256 maxUnitsRepresented) {
        return (false, 0, 0);
    }
}

contract MockUriBuilder is IUriBuilder {
    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory certLegend,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return certLegend.length == 0 ? "legacy-empty" : string.concat("legacy:", certLegend[0]);
    }

    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory certLegend,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        if (certLegend.length == 0) return "structured-empty";
        return string.concat(
            _restrictionTypeToString(certLegend[0].restrictionType),
            "|",
            certLegend[0].title,
            "|",
            certLegend[0].text
        );
    }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory certLegend,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return certLegend.length == 0 ? "legacy-empty" : string.concat("legacy:", certLegend[0]);
    }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory certLegend,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        if (certLegend.length == 0) return "structured-empty";
        return string.concat(
            _restrictionTypeToString(certLegend[0].restrictionType),
            "|",
            certLegend[0].title,
            "|",
            certLegend[0].text
        );
    }

    function _restrictionTypeToString(RestrictionType restrictionType) private pure returns (string memory) {
        if (restrictionType == RestrictionType.RegulationS) return "RegulationS";
        if (restrictionType == RestrictionType.Custom) return "Custom";
        return "Other";
    }
}

contract CyberCertPrinterTest is Test {
    CyberCertPrinter private printer;
    MockIssuanceManager private issuanceManager;

    address private investor = address(0xA11CE);
    address private recipient = address(0xB0B);
    address private initialExtension = address(0xE100);
    address private updatedExtension = address(0xE200);

    event CertificateSigned(uint256 indexed tokenId, bytes signature);
    event GlobalTransferableSet(bool indexed transferable);

    function setUp() public {
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        MockUriBuilder uriBuilder = new MockUriBuilder();
        issuanceManager = new MockIssuanceManager(address(corp), address(uriBuilder));

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Default legend";

        CyberCertPrinter implementation = new CyberCertPrinter();
        bytes memory initData = abi.encodeCall(
            CyberCertPrinter.initialize,
            (
                defaultLegend,
                "Mock Cert",
                "MCERT",
                "ipfs://certificate",
                address(issuanceManager),
                SecurityClass.PreferredStock,
                SecuritySeries.SeriesA,
                initialExtension
            )
        );
        printer = CyberCertPrinter(address(new ERC1967Proxy(address(implementation), initData)));
    }

    function test_AddIssuerSignature_StoresSignatureAndEmitsEvent() public {
        _mintCert(1, investor, 100, bytes("series-a-data"));

        bytes memory signature = hex"123456";

        vm.expectEmit(true, false, false, true);
        emit CertificateSigned(1, signature);

        vm.prank(address(issuanceManager));
        printer.addIssuerSignature(1, signature);

        assertEq(printer.getIssuerSignatureCount(1), 1);
        assertEq(printer.getIssuerSignatureAt(1, 0), signature);
    }

    function test_AddIssuerSignature_RevertsForEmptySignature() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.SignatureRequired.selector);
        printer.addIssuerSignature(1, "");
    }

    function test_AddIssuerSignature_RevertsForNonexistentToken() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.TokenDoesNotExist.selector);
        printer.addIssuerSignature(999, hex"123456");
    }

    function test_AddIssuerSignature_RevertsWhenCallerIsNotIssuanceManager() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(investor);
        vm.expectRevert(CyberCertPrinter.NotIssuanceManager.selector);
        printer.addIssuerSignature(1, hex"123456");
    }

    function test_GettersExposeConfiguredExtensionAndStoredExtensionData() public {
        bytes memory extensionData = abi.encode("Series Seed Preferred", uint256(10_000_000));
        _mintCert(1, investor, 100, extensionData);

        assertEq(printer.getExtension(1), initialExtension);
        assertEq(printer.getExtensionData(1), extensionData);
    }

    function test_SetExtension_UpdatesGlobalExtensionFromIssuanceManager() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setExtension(999, updatedExtension);

        assertEq(printer.getExtension(1), updatedExtension);
    }

    function test_SetExtension_RevertsWhenCallerIsNotIssuanceManager() public {
        vm.prank(investor);
        vm.expectRevert(CyberCertPrinter.NotIssuanceManager.selector);
        printer.setExtension(1, updatedExtension);
    }

    function test_UnitsReserved_IncreaseAndDecreaseWithinCertificateUnits() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);
        assertEq(printer.unitsReserved(1), 40);

        vm.prank(address(issuanceManager));
        printer.decreaseUnitsReserved(1, 15);
        assertEq(printer.unitsReserved(1), 25);
    }

    function test_UnitsReserved_RevertsWhenIncreaseExceedsUnitsRepresented() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.ExceedsAvailableUnits.selector);
        printer.increaseUnitsReserved(1, 101);
    }

    function test_UnitsReserved_RevertsWhenDecreaseExceedsReservedUnits() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);

        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.ExceedsReservedUnits.selector);
        printer.decreaseUnitsReserved(1, 41);
    }

    function test_UnitsReserved_RevertsForNonexistentTokens() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.TokenDoesNotExist.selector);
        printer.increaseUnitsReserved(999, 1);

        vm.prank(address(issuanceManager));
        vm.expectRevert(CyberCertPrinter.TokenDoesNotExist.selector);
        printer.decreaseUnitsReserved(999, 1);
    }

    function test_TokenTransferable_AllowsOneTokenWithoutEnablingGlobalTransfers() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setTokenTransferable(1, true);

        assertTrue(printer.isTokenTransferable(1));
        assertFalse(printer.isTokenTransferable(2));

        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));

        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);
        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.legalOwnerOf(1), recipient);

        vm.prank(investor);
        vm.expectRevert(CyberCertPrinter.TokenNotTransferable.selector);
        printer.transferFrom(investor, recipient, 2);
    }

    function test_TokenTransferable_RevertsWhenCallerIsNotIssuanceManager() public {
        vm.prank(investor);
        vm.expectRevert(CyberCertPrinter.NotIssuanceManager.selector);
        printer.setTokenTransferable(1, true);
    }

    function test_Initialize_SetsCertificateConfiguration() public view {
        assertEq(printer.name(), "Mock Cert");
        assertEq(printer.symbol(), "MCERT");
        assertEq(printer.certificateUri(), "ipfs://certificate");
        assertEq(printer.issuanceManager(), address(issuanceManager));
        assertEq(uint8(printer.securityType()), uint8(SecurityClass.PreferredStock));
        assertEq(uint8(printer.securitySeries()), uint8(SecuritySeries.SeriesA));
        assertEq(printer.getExtension(0), initialExtension);
        assertEq(printer.endorsementRequired(), true);
    }

    function test_SafeMint_CopiesDefaultLegendAndSetsLegalOwner() public {
        _mintCert(1, investor, 100, bytes(""));

        assertEq(printer.ownerOf(1), investor);
        assertEq(printer.legalOwnerOf(1), investor);
        assertEq(printer.getCertLegendCount(1), 1);
        assertEq(printer.getCertLegendAt(1, 0), "Default legend");
    }

    function test_HolderCount_TracksUniqueHoldersOnMint() public {
        assertEq(printer.holderCount(), 0);

        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.holderCount(), 1);

        _mintCert(2, investor, 100, bytes(""));
        assertEq(printer.holderCount(), 1);

        _mintCert(3, recipient, 100, bytes(""));
        assertEq(printer.holderCount(), 2);
    }

    function test_HolderCount_TracksUniqueHoldersOnTransfers() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);

        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);
        assertEq(printer.holderCount(), 2);

        vm.prank(investor);
        printer.addEndorsement(2, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 2);
        assertEq(printer.holderCount(), 1);
    }

    function test_HolderCount_TransferBetweenExistingHoldersDoesNotIncreaseCount() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, recipient, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);

        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        assertEq(printer.holderCount(), 1);
    }

    function test_HolderCount_SelfTransferDoesNotChangeCount() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);

        vm.prank(investor);
        printer.transferFrom(investor, investor, 1);

        assertEq(printer.holderCount(), 1);
    }

    function test_HolderCount_TracksUniqueHoldersOnBurn() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));
        assertEq(printer.holderCount(), 1);

        vm.prank(address(issuanceManager));
        printer.burn(1);
        assertEq(printer.holderCount(), 1);

        vm.prank(address(issuanceManager));
        printer.burn(2);
        assertEq(printer.holderCount(), 0);
    }

    function test_SafeMintAndAssign_StoresNamedLegalOwner() public {
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(investor, 1, _details(100, bytes("")), "Alice Investor");

        assertEq(printer.ownerOf(1), investor);
        assertEq(printer.legalOwnerOf(1), investor);
        assertEq(printer.getCertLegendAt(1, 0), "Default legend");
    }

    function test_AddDefaultRestrictiveLegend_StoresAndCopiesOnMint() public {
        RestrictiveLegend memory legend = _legend(
            RestrictionType.RegulationS,
            "Reg S Legend",
            "Transfer only offshore",
            "US",
            true
        );

        vm.prank(address(issuanceManager));
        printer.addDefaultRestrictiveLegend(legend);

        assertEq(printer.getDefaultRestrictiveLegendCount(), 1);
        RestrictiveLegend memory storedDefault = printer.getDefaultRestrictiveLegendAt(0);
        assertEq(uint8(storedDefault.restrictionType), uint8(RestrictionType.RegulationS));
        assertEq(storedDefault.title, "Reg S Legend");
        assertEq(storedDefault.text, "Transfer only offshore");
        assertEq(storedDefault.jurisdiction, "US");
        assertTrue(storedDefault.active);

        _mintCert(1, investor, 100, bytes(""));

        assertEq(printer.getCertRestrictiveLegendCount(1), 1);
        RestrictiveLegend memory storedCert = printer.getCertRestrictiveLegendAt(1, 0);
        assertEq(uint8(storedCert.restrictionType), uint8(RestrictionType.RegulationS));
        assertEq(storedCert.title, "Reg S Legend");
        assertEq(storedCert.text, "Transfer only offshore");
    }

    function test_AddAndRemoveCertRestrictiveLegend() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.addCertRestrictiveLegend(
            1,
            _legend(RestrictionType.Custom, "Custom Legend", "Board approval required", "DE", true)
        );

        assertEq(printer.getCertRestrictiveLegendCount(1), 1);
        RestrictiveLegend memory stored = printer.getCertRestrictiveLegendAt(1, 0);
        assertEq(stored.text, "Board approval required");

        vm.prank(address(issuanceManager));
        printer.removeCertRestrictiveLegendAt(1, 0);

        assertEq(printer.getCertRestrictiveLegendCount(1), 0);
    }

    function test_TokenURI_UsesStructuredRestrictiveLegend() public {
        vm.prank(address(issuanceManager));
        printer.addDefaultRestrictiveLegend(
            _legend(RestrictionType.RegulationS, "Reg S Legend", "Transfer only offshore", "US", true)
        );
        _mintCert(1, investor, 100, bytes(""));

        assertEq(printer.tokenURI(1), "RegulationS|Reg S Legend|Transfer only offshore");
    }

    function test_TokenURI_FallsBackToLegacyLegendAsCustom() public {
        _mintCert(1, investor, 100, bytes(""));

        assertEq(printer.tokenURI(1), "Custom||Default legend");
    }

    function test_CertificateUriBuilder_RendersStructuredRestrictiveLegends() public {
        CertificateUriBuilder builder = new CertificateUriBuilder();
        RestrictiveLegend[] memory legends = new RestrictiveLegend[](1);
        legends[0] = _legend(
            RestrictionType.RegulationS,
            "Reg S Legend",
            "Transfer only offshore",
            "US",
            true
        );
        legends[0].data = hex"1234";

        assertEq(
            builder.restrictiveLegendsToJson(legends),
            string.concat(
                '[{"id": 1, "restrictionType": "RegulationS", "title": "Reg S Legend", ',
                '"text": "Transfer only offshore", "jurisdiction": "US", ',
                '"referenceId": "0x0000000000000000000000000000000000000000000000000000000000000000", ',
                '"effectiveTimestamp": "0", "expirationTimestamp": "0", "active": "true", "data": "0x1234"}]'
            )
        );
    }

    function test_UpdateCertificateDetails_ReplacesStoredDetails() public {
        _mintCert(1, investor, 100, bytes("initial"));

        CertificateDetails memory updated = _details(250, bytes("updated"));
        vm.prank(address(issuanceManager));
        printer.updateCertificateDetails(1, updated);

        CertificateDetails memory stored = printer.getCertificateDetails(1);
        assertEq(stored.unitsRepresented, 250);
        assertEq(stored.extensionData, bytes("updated"));
    }

    function test_GetActiveCertificateDetails_ReturnsStoredDetails() public {
        _mintCert(1, investor, 123, bytes("active"));

        CertificateDetails memory details = printer.getActiveCertificateDetails(1);

        assertEq(details.unitsRepresented, 123);
        assertEq(details.extensionData, bytes("active"));
    }

    function test_AddIssuerSignature_AppendsMultipleSignaturesInOrder() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.addIssuerSignature(1, hex"aaaa");

        vm.prank(address(issuanceManager));
        printer.addIssuerSignature(1, hex"bbbbcc");

        assertEq(printer.getIssuerSignatureCount(1), 2);
        assertEq(printer.getIssuerSignatureAt(1, 0), hex"aaaa");
        assertEq(printer.getIssuerSignatureAt(1, 1), hex"bbbbcc");
    }

    function test_GetIssuerSignatureCount_RevertsForNonexistentToken() public {
        vm.expectRevert(CyberCertPrinter.TokenDoesNotExist.selector);
        printer.getIssuerSignatureCount(999);
    }

    function test_GetIssuerSignatureAt_RevertsForNonexistentToken() public {
        vm.expectRevert(CyberCertPrinter.TokenDoesNotExist.selector);
        printer.getIssuerSignatureAt(999, 0);
    }

    function test_SetGlobalTransferable_EmitsAndUpdatesFlag() public {
        vm.expectEmit(true, false, false, true);
        emit GlobalTransferableSet(true);

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);

        assertTrue(printer.transferable());
    }

    function test_GlobalTransferable_AllowsTransferWithEndorsement() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);

        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));

        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.legalOwnerOf(1), recipient);
    }

    function _mintCert(
        uint256 tokenId,
        address to,
        uint256 unitsRepresented,
        bytes memory extensionData
    ) private {
        vm.prank(address(issuanceManager));
        printer.safeMint(tokenId, to, _details(unitsRepresented, extensionData));
    }

    function _details(
        uint256 unitsRepresented,
        bytes memory extensionData
    ) private pure returns (CertificateDetails memory) {
        return
            CertificateDetails({
                signingOfficerName: "Officer",
                signingOfficerTitle: "CEO",
                investmentAmountUSD: 1_000,
                issuerUSDValuationAtTimeOfInvestment: 10_000,
                unitsRepresented: unitsRepresented,
                legalDetails: "Legal details",
                extensionData: extensionData
            });
    }

    function _legend(
        RestrictionType restrictionType,
        string memory title,
        string memory text,
        string memory jurisdiction,
        bool active
    ) private pure returns (RestrictiveLegend memory) {
        return RestrictiveLegend({
            restrictionType: restrictionType,
            title: title,
            text: text,
            jurisdiction: jurisdiction,
            referenceId: bytes32(0),
            effectiveTimestamp: 0,
            expirationTimestamp: 0,
            active: active,
            data: ""
        });
    }

    function _endorsement(
        address endorser,
        address endorsee
    ) private view returns (Endorsement memory) {
        return
            Endorsement({
                endorser: endorser,
                timestamp: block.timestamp,
                signatureHash: hex"abcd",
                registry: address(0),
                agreementId: bytes32(0),
                endorsee: endorsee,
                endorseeName: "Recipient"
            });
    }
}
