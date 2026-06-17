// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {
    CertificateDetails,
    Endorsement
} from "../src/storage/CyberCertPrinterStorage.sol";

contract MockCyberCorp {
    address public dealManager;
    address public roundManager;

    constructor(address _dealManager, address _roundManager) {
        dealManager = _dealManager;
        roundManager = _roundManager;
    }
}

contract MockIssuanceManager {
    address public immutable CORP;

    constructor(address corp) {
        CORP = corp;
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

contract CyberCertPrinterTest is Test {
    CyberCertPrinter private printer;
    MockIssuanceManager private issuanceManager;

    address private investor = address(0xA11CE);
    address private recipient = address(0xB0B);
    address private initialExtension = address(0xE100);
    address private updatedExtension = address(0xE200);

    event CertificateSigned(uint256 indexed tokenId, bytes signature);

    function setUp() public {
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        issuanceManager = new MockIssuanceManager(address(corp));

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Default legend";

        printer = new CyberCertPrinter();
        printer.initialize(
            defaultLegend,
            "Mock Cert",
            "MCERT",
            "ipfs://certificate",
            address(issuanceManager),
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesA,
            initialExtension
        );
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
