// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import {ShareClassTermsController} from "../src/storage/extensions/ShareClassTermsController.sol";
import {
    CertificateData,
    MandatoryConversionTrigger,
    SeriesTerms,
    ShareCertData,
    ShareExtension,
    ShareRepresentationType,
    SpecialVotingRight,
    SplitRecord,
    TransferRestriction
} from "../src/storage/extensions/ShareExtension.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

contract ClassTermsMigrationHarness {
    function migrate(address[] calldata certPrinters, address controller, bytes[] calldata extensionData) external {
        IssuanceManagerStorage.executeMigrateClassTermsControllers(certPrinters, controller, extensionData);
    }
}

contract CyberCertPrinterClassTermsTest is Test {
    using ERC1967ProxyLib for address;

    LedgerEntryToken internal printer;
    ShareExtension internal shareExtension;
    ShareClassTermsController internal controller;
    mapping(uint256 => uint256) internal scripifiedUnits;

    function setUp() public {
        shareExtension = new ShareExtension();
        BorgAuth auth = new BorgAuth(address(this));
        ShareClassTermsController controllerImplementation = new ShareClassTermsController();
        controller = ShareClassTermsController(
            address(
                new ERC1967Proxy(
                    address(controllerImplementation),
                    abi.encodeCall(ShareClassTermsController.initialize, (address(auth), address(shareExtension)))
                )
            )
        );
        LedgerEntryToken implementation = new LedgerEntryToken();
        string[] memory legends = new string[](0);
        printer = LedgerEntryToken(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        LedgerEntryToken.initialize,
                        (
                            legends,
                            "Common Stock",
                            "COMMON",
                            "ipfs://certificate",
                            address(this),
                            SecurityClass.CommonStock,
                            SecuritySeries.NA,
                            address(controller),
                            bytes("")
                        )
                    )
                )
            )
        );
    }

    function test_FirstMintMakesTermsCanonicalAndEnforcesCap() public {
        CertificateDetails memory first = _details(_terms("Common", 10), 6);
        controller.accountNewIssuance(address(printer), first.extensionData, first.unitsRepresented, true);
        printer.safeMint(0, address(0xA11CE), first);

        (bytes memory termsData, bytes32 termsHash, uint256 authorized, uint256 issued, bool configured) =
            controller.getClassTerms(address(printer));
        assertTrue(configured);
        assertEq(authorized, 10);
        assertEq(issued, 6);
        assertEq(termsHash, keccak256(termsData));

        vm.expectRevert(abi.encodeWithSelector(ShareClassTermsController.AuthorizedSharesExceeded.selector, 10, 11));
        CertificateDetails memory overCap = _details(_terms("Common", 10), 5);
        controller.accountNewIssuance(address(printer), overCap.extensionData, overCap.unitsRepresented, true);
    }

    function test_ClassTermsCanBeConfiguredBeforeFirstIssuance() public {
        controller.configureClassTerms(address(printer), _extensionData(_terms("Common", 10)));
        assertEq(_authorizedShares(), 10);
        assertEq(_issuedUnits(), 0);

        _mint(0, address(0xA11CE), _details(_terms("Common", 10), 4));
        assertEq(_issuedUnits(), 4);
    }

    function test_RejectsDifferentTermsForSameClass() public {
        _mint(0, address(0xA11CE), _details(_terms("Common", 10), 2));

        vm.expectRevert(ShareClassTermsController.ClassTermsMismatch.selector);
        CertificateDetails memory mismatch = _details(_terms("Common B", 10), 1);
        controller.accountNewIssuance(address(printer), mismatch.extensionData, mismatch.unitsRepresented, true);
    }

    // Develop's LedgerEntryToken has no burn: voided lots stay on the ledger, so the
    // lifecycle to maintain is void/unvoid only.
    function test_VoidUnvoidMaintainsIssuedUnits() public {
        _mint(0, address(0xA11CE), _details(_terms("Common", 10), 6));
        controller.releaseCertificateUnits(address(printer), 0);
        printer.voidCert(0);
        assertEq(_issuedUnits(), 0);

        controller.restoreCertificateUnits(address(printer), 0);
        printer.unvoidCert(0);
        assertEq(_issuedUnits(), 6);
    }

    function test_ScripRepresentationChangesDoNotDoubleCount() public {
        CertificateDetails memory details = _details(_terms("Common", 10), 6);
        _mint(0, address(0xA11CE), details);

        scripifiedUnits[0] = 2;
        details.unitsRepresented = 4;
        controller.accountCertificateUpdate(address(printer), 0, details.extensionData, details.unitsRepresented, false);
        printer.updateCertificateDetails(0, details);
        assertEq(_issuedUnits(), 6);

        // Voiding releases only the ACTIVE units (4): the 2 scripified units are still a
        // circulating ERC20 and stay counted, or the class could issue past its cap.
        controller.releaseCertificateUnits(address(printer), 0);
        printer.voidCert(0);
        assertEq(_issuedUnits(), 2);
        controller.restoreCertificateUnits(address(printer), 0);
        printer.unvoidCert(0);
        assertEq(_issuedUnits(), 6);
    }

    function test_VoidingScripifiedCertKeepsScripCounted_ThenForceBurnReleases() public {
        CertificateDetails memory details = _details(_terms("Common", 10), 6);
        _mint(0, address(0xA11CE), details);

        scripifiedUnits[0] = 2;
        details.unitsRepresented = 4;
        controller.accountCertificateUpdate(address(printer), 0, details.extensionData, details.unitsRepresented, false);
        printer.updateCertificateDetails(0, details);

        controller.releaseCertificateUnits(address(printer), 0);
        printer.voidCert(0);
        assertEq(_issuedUnits(), 2, "scrip units survive their certificate's void");

        // The freed capacity cannot be over-issued while the scrip circulates.
        vm.expectRevert(abi.encodeWithSelector(ShareClassTermsController.AuthorizedSharesExceeded.selector, 10, 11));
        CertificateDetails memory overCap = _details(_terms("Common", 10), 9);
        controller.accountNewIssuance(address(printer), overCap.extensionData, overCap.unitsRepresented, true);

        // Destroying the ERC20 (force burn) is what extinguishes the units.
        controller.releaseScripUnits(address(printer), 2);
        assertEq(_issuedUnits(), 0);
    }

    function test_AmendedTermsDoNotBrickExistingCertificates() public {
        CertificateDetails memory details = _details(_terms("Common", 10), 6);
        _mint(0, address(0xA11CE), details);

        controller.amendClassTerms(address(printer), _extensionData(_terms("Common Amended", 20)));

        // A representation-only update carrying the cert's ORIGINAL terms snapshot still works.
        scripifiedUnits[0] = 2;
        details.unitsRepresented = 4;
        controller.accountCertificateUpdate(address(printer), 0, details.extensionData, details.unitsRepresented, false);
        printer.updateCertificateDetails(0, details);
        assertEq(_issuedUnits(), 6);

        // Void/unvoid of a pre-amendment certificate also still works.
        controller.releaseCertificateUnits(address(printer), 0);
        printer.voidCert(0);
        controller.restoreCertificateUnits(address(printer), 0);
        printer.unvoidCert(0);
        assertEq(_issuedUnits(), 6);

        // Terms matching neither the canonical hash nor the cert's own snapshot still revert.
        vm.expectRevert(ShareClassTermsController.ClassTermsMismatch.selector);
        CertificateDetails memory foreign = _details(_terms("Something Else", 20), 4);
        controller.accountCertificateUpdate(address(printer), 0, foreign.extensionData, foreign.unitsRepresented, false);
    }

    function test_RecertificationMintValidatesTermsWithoutIncrementing() public {
        _mint(0, address(0xA11CE), _details(_terms("Common", 10), 10));

        CertificateDetails memory recert = _details(_terms("Common", 10), 3);
        controller.accountNewIssuance(address(printer), recert.extensionData, recert.unitsRepresented, false);
        printer.safeMintAndAssign(address(0xB0B), 1, recert, "Bob");
        assertEq(_issuedUnits(), 10);
    }

    function test_AmendmentCannotReduceAuthorizationBelowIssued() public {
        _mint(0, address(0xA11CE), _details(_terms("Common", 10), 6));

        vm.expectRevert(abi.encodeWithSelector(ShareClassTermsController.AuthorizedSharesBelowIssued.selector, 5, 6));
        controller.amendClassTerms(address(printer), _extensionData(_terms("Common", 5)));

        controller.amendClassTerms(address(printer), _extensionData(_terms("Common", 20)));
        assertEq(_authorizedShares(), 20);
    }

    function test_MigrationIsAtomicAndInstalledControllerCannotBeReplaced() public {
        ClassTermsMigrationHarness harness = new ClassTermsMigrationHarness();
        LedgerEntryToken firstLegacyPrinter = _deployPrinter(address(harness), address(shareExtension));
        LedgerEntryToken secondLegacyPrinter = _deployPrinter(address(harness), address(shareExtension));
        ShareClassTermsController firstController = _deployController();

        address[] memory printers = new address[](2);
        printers[0] = address(firstLegacyPrinter);
        printers[1] = address(secondLegacyPrinter);
        bytes[] memory extensionData = new bytes[](2);
        extensionData[0] = _extensionData(_terms("Legacy Common", 100));

        vm.expectRevert(ShareClassTermsController.InvalidShareExtensionData.selector);
        harness.migrate(printers, address(firstController), extensionData);
        assertEq(firstLegacyPrinter.getExtension(0), address(shareExtension));
        assertEq(secondLegacyPrinter.getExtension(0), address(shareExtension));

        extensionData[1] = _extensionData(_terms("Legacy Preferred", 200));
        harness.migrate(printers, address(firstController), extensionData);

        assertEq(firstLegacyPrinter.getExtension(0), address(firstController));
        assertEq(secondLegacyPrinter.getExtension(0), address(firstController));
        (,, uint256 authorized,, bool configured) = firstController.getClassTerms(address(firstLegacyPrinter));
        assertTrue(configured);
        assertEq(authorized, 100);
        (,, uint256 secondAuthorized,, bool secondConfigured) =
            firstController.getClassTerms(address(secondLegacyPrinter));
        assertTrue(secondConfigured);
        assertEq(secondAuthorized, 200);

        ShareClassTermsController replacementController = _deployController();
        address[] memory onePrinter = new address[](1);
        onePrinter[0] = address(firstLegacyPrinter);
        bytes[] memory oneTerms = new bytes[](1);
        oneTerms[0] = extensionData[0];
        vm.expectRevert(IssuanceManagerStorage.ClassTermsControllerAlreadyInstalled.selector);
        harness.migrate(onePrinter, address(replacementController), oneTerms);
        assertEq(firstLegacyPrinter.getExtension(0), address(firstController));
    }

    function test_MigrationRejectsMismatchedBatchLengths() public {
        ClassTermsMigrationHarness harness = new ClassTermsMigrationHarness();
        address[] memory printers = new address[](1);
        bytes[] memory noTerms = new bytes[](0);

        vm.expectRevert(IssuanceManagerStorage.ClassTermsMigrationLengthMismatch.selector);
        harness.migrate(printers, address(controller), noTerms);
    }

    function test_UpgradeToAndCallMigratesEveryPrinterAtomically() public {
        BorgAuth upgradeAuth = new BorgAuth(address(this));
        ShareClassTermsController controllerImplementation = new ShareClassTermsController();
        ShareClassTermsController upgradeController = ShareClassTermsController(
            address(
                new ERC1967Proxy(
                    address(controllerImplementation),
                    abi.encodeCall(
                        ShareClassTermsController.initialize, (address(upgradeAuth), address(shareExtension))
                    )
                )
            )
        );

        IssuanceManager initialImplementation = new IssuanceManager();
        IssuanceManagerFactory factory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeCall(
                        IssuanceManagerFactory.initialize,
                        (
                            address(upgradeAuth),
                            address(initialImplementation),
                            address(new LedgerEntryToken()),
                            address(new CyberScrip())
                        )
                    )
                )
            )
        );
        IssuanceManager manager = IssuanceManager(factory.deployIssuanceManager(keccak256("ClassTermsAtomicUpgrade")));
        manager.initialize(address(upgradeAuth), address(this), address(0xBEEF), address(factory));

        string[] memory legends = new string[](0);
        address[] memory printers = new address[](2);
        printers[0] = manager.createCertPrinter(
            legends,
            "Legacy Common",
            "LCOM",
            "ipfs://common",
            SecurityClass.CommonStock,
            SecuritySeries.NA,
            address(shareExtension),
            bytes("")
        );
        printers[1] = manager.createCertPrinter(
            legends,
            "Legacy Preferred",
            "LPREF",
            "ipfs://preferred",
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesA,
            address(shareExtension),
            bytes("")
        );

        bytes[] memory extensionData = new bytes[](2);
        extensionData[0] = _extensionData(_terms("Legacy Common", 100));
        IssuanceManager newImplementation = new IssuanceManager();
        factory.setRefImplementation(address(newImplementation));
        address oldImplementation = address(manager).getErc1967Implementation();

        bytes memory invalidMigrationCall = abi.encodeCall(
            IssuanceManager.migrateClassTermsControllers, (printers, address(upgradeController), extensionData)
        );
        vm.expectRevert(ShareClassTermsController.InvalidShareExtensionData.selector);
        manager.upgradeToAndCall(address(newImplementation), invalidMigrationCall);

        assertEq(address(manager).getErc1967Implementation(), oldImplementation);
        assertEq(LedgerEntryToken(printers[0]).getExtension(0), address(shareExtension));
        assertEq(LedgerEntryToken(printers[1]).getExtension(0), address(shareExtension));

        extensionData[1] = _extensionData(_terms("Legacy Preferred", 200));
        bytes memory migrationCall = abi.encodeCall(
            IssuanceManager.migrateClassTermsControllers, (printers, address(upgradeController), extensionData)
        );
        manager.upgradeToAndCall(address(newImplementation), migrationCall);

        assertEq(address(manager).getErc1967Implementation(), address(newImplementation));
        assertEq(LedgerEntryToken(printers[0]).getExtension(0), address(upgradeController));
        assertEq(LedgerEntryToken(printers[1]).getExtension(0), address(upgradeController));
        (,, uint256 firstAuthorized,, bool firstConfigured) = upgradeController.getClassTerms(printers[0]);
        (,, uint256 secondAuthorized,, bool secondConfigured) = upgradeController.getClassTerms(printers[1]);
        assertTrue(firstConfigured);
        assertTrue(secondConfigured);
        assertEq(firstAuthorized, 100);
        assertEq(secondAuthorized, 200);
    }

    function getCertScripifiedStatus(address, uint256 tokenId)
        external
        view
        returns (bool isScripified, uint256 units, uint256 maxUnitsRepresented)
    {
        units = scripifiedUnits[tokenId];
        return (units > 0, units, units);
    }

    function companyName() external pure returns (string memory) {
        return "Test Corp";
    }

    function _issuedUnits() internal view returns (uint256 issued) {
        (,,, issued,) = controller.getClassTerms(address(printer));
    }

    function _authorizedShares() internal view returns (uint256 authorized) {
        (,, authorized,,) = controller.getClassTerms(address(printer));
    }

    function _mint(uint256 tokenId, address recipient, CertificateDetails memory details) internal {
        controller.accountNewIssuance(address(printer), details.extensionData, details.unitsRepresented, true);
        printer.safeMint(tokenId, recipient, details);
    }

    function _deployController() internal returns (ShareClassTermsController deployedController) {
        BorgAuth auth = new BorgAuth(address(this));
        ShareClassTermsController implementation = new ShareClassTermsController();
        deployedController = ShareClassTermsController(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(ShareClassTermsController.initialize, (address(auth), address(shareExtension)))
                )
            )
        );
    }

    function _deployPrinter(address issuanceManager, address extension)
        internal
        returns (LedgerEntryToken deployedPrinter)
    {
        LedgerEntryToken implementation = new LedgerEntryToken();
        string[] memory legends = new string[](0);
        deployedPrinter = LedgerEntryToken(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        LedgerEntryToken.initialize,
                        (
                            legends,
                            "Common Stock",
                            "COMMON",
                            "ipfs://certificate",
                            issuanceManager,
                            SecurityClass.CommonStock,
                            SecuritySeries.NA,
                            extension,
                            bytes("")
                        )
                    )
                )
            )
        );
    }

    function _details(SeriesTerms memory terms, uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "President",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: _extensionData(terms)
        });
    }

    function _extensionData(SeriesTerms memory terms) internal pure returns (bytes memory) {
        ShareCertData memory share;
        share.terms = terms;
        share.certificateData = CertificateData({
            isPartlyPaid: false,
            amountPaid: 0,
            totalConsideration: 0,
            sourceAuthorityURI: "",
            representationType: ShareRepresentationType.Certificated,
            holdingPeriodTackingApplied: false
        });
        share.mandatoryConversionTriggers = new MandatoryConversionTrigger[](0);
        share.specialVotingRights = new SpecialVotingRight[](0);
        share.transferRestrictions = new TransferRestriction[](0);
        share.splitHistory = new SplitRecord[](0);
        return abi.encode(share);
    }

    function _terms(string memory name, uint256 authorized) internal pure returns (SeriesTerms memory terms) {
        terms.seriesName = name;
        terms.authorizedShares = authorized;
        terms.sourceAuthorityURI = "ipfs://board-resolution";
        terms.votesPerShare = 1;
    }
}
