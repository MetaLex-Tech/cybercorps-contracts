// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberCertPrinterStorage} from "../src/storage/CyberCertPrinterStorage.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {IUriBuilder} from "../src/interfaces/IUriBuilder.sol";
import {
    CertificateDetails,
    Endorsement,
    ICyberCertPrinter,
    OwnerDetails,
    RestrictionType,
    RestrictiveLegend
} from "../src/interfaces/ICyberCertPrinter.sol";
import {ICertificateExtension} from "../src/storage/extensions/ICertificateExtension.sol";
import {FundInterestData} from "../src/storage/extensions/FundInterestExtension.sol";

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

/// @dev Test-only subclass exposing a hook to recreate the pre-enumeration ("legacy") storage state directly —
/// owners[] populated but the legal-owner enumeration empty — so tests don't have to vm.store into the diamond
/// storage by hand. It only ADDS a function; all production CyberCertPrinter logic is inherited unchanged.
contract CyberCertPrinterEnhanced is CyberCertPrinter {
    /// @dev Clear the legal-owner enumeration for `owner`/`tokenIds`, mimicking certs minted before the
    /// enumeration existed (owners[] stays; count/index/tracked are zeroed).
    function debugClearLegalOwnerEnumeration(address owner, uint256[] calldata tokenIds) external {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            delete s.legalOwnedTokens[owner][s.legalOwnedTokensIndex[tokenId]];
            delete s.legalOwnedTokensIndex[tokenId];
            s.legalOwnedTokenTracked[tokenId] = false;
        }
        s.legalOwnerTokenCount[owner] = 0;
    }

    /// @dev Zero a token's base acquisitionTimestamp, mimicking a cert minted before it became a base field.
    function debugClearAcquisitionTimestamp(uint256 tokenId) external {
        CyberCertPrinterStorage.cyberCertStorage().acquisitionTimestamp[tokenId] = 0;
    }
}

contract MockFundInterestExtension is ICertificateExtension {
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool) {
        return extensionType == keccak256("FUND_INTEREST");
    }
    function getExtensionURI(bytes memory) external pure returns (string memory) { return ""; }
}

contract MockNonFundExtension is ICertificateExtension {
    function supportsExtensionType(bytes32) external pure returns (bool) { return false; }
    function getExtensionURI(bytes memory) external pure returns (string memory) { return ""; }
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

        CyberCertPrinter implementation = new CyberCertPrinterEnhanced();
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
        vm.expectRevert(ICyberCertPrinter.SignatureRequired.selector);
        printer.addIssuerSignature(1, "");
    }

    function test_AddIssuerSignature_RevertsForNonexistentToken() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ICyberCertPrinter.TokenDoesNotExist.selector);
        printer.addIssuerSignature(999, hex"123456");
    }

    function test_AddIssuerSignature_RevertsWhenCallerIsNotIssuanceManager() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(investor);
        vm.expectRevert(ICyberCertPrinter.NotIssuanceManager.selector);
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
        vm.expectRevert(ICyberCertPrinter.NotIssuanceManager.selector);
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
        vm.expectRevert(ICyberCertPrinter.ExceedsAvailableUnits.selector);
        printer.increaseUnitsReserved(1, 101);
    }

    function test_UnitsReserved_RevertsWhenDecreaseExceedsReservedUnits() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);

        vm.prank(address(issuanceManager));
        vm.expectRevert(ICyberCertPrinter.ExceedsReservedUnits.selector);
        printer.decreaseUnitsReserved(1, 41);
    }

    function test_UnitsReserved_RevertsForNonexistentTokens() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ICyberCertPrinter.TokenDoesNotExist.selector);
        printer.increaseUnitsReserved(999, 1);

        vm.prank(address(issuanceManager));
        vm.expectRevert(ICyberCertPrinter.TokenDoesNotExist.selector);
        printer.decreaseUnitsReserved(999, 1);
    }

    function test_ReservedCert_BlocksTransferUntilReleased() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.setTokenTransferable(1, true);
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));

        // Reserving units escrows the cert; its legal ownership is frozen while any units are reserved.
        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 1);

        vm.prank(investor);
        vm.expectRevert(ICyberCertPrinter.CertificateReserved.selector);
        printer.transferFrom(investor, recipient, 1);

        // Releasing the reservation (settlement/void) unfreezes the transfer.
        vm.prank(address(issuanceManager));
        printer.decreaseUnitsReserved(1, 1);
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);
        assertEq(printer.legalOwnerOf(1), recipient);
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
        vm.expectRevert(ICyberCertPrinter.TokenNotTransferable.selector);
        printer.transferFrom(investor, recipient, 2);
    }

    function test_TokenTransferable_RevertsWhenCallerIsNotIssuanceManager() public {
        vm.prank(investor);
        vm.expectRevert(ICyberCertPrinter.NotIssuanceManager.selector);
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

    // A same-owner write that changes the holder-of-record name emits LegalOwnerChanged (from == to) and leaves
    // the acquisition clock untouched.
    function test_SetLegalOwner_SameOwnerNameChange_EmitsWithoutRestamp() public {
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(investor, 1, _details(100, bytes("")), "Alice");
        uint64 acquiredAt = printer.acquisitionTimestamp(1);
        CertificateDetails memory d = _details(100, bytes(""));

        vm.expectEmit(true, true, true, true, address(printer));
        emit ICyberCertPrinter.LegalOwnerChanged(1, investor, investor, "", acquiredAt);
        vm.prank(address(issuanceManager));
        printer.assignCert(investor, 1, investor, d); // recordAssign resets the name to "" for the same owner

        assertEq(printer.acquisitionTimestamp(1), acquiredAt, "same-owner name change must not reset the clock");
    }

    // Clearing the legal owner to address(0) is a "negative" change: it emits LegalOwnerChanged and clears the
    // acquisition clock (acquisitionTimestamp != 0 iff there is an owner of record).
    function test_SetLegalOwner_ClearToZero_EmitsNegativeEvent() public {
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(investor, 1, _details(100, bytes("")), "Alice");
        CertificateDetails memory d = _details(100, bytes(""));

        vm.expectEmit(true, true, true, true, address(printer));
        emit ICyberCertPrinter.LegalOwnerChanged(1, investor, address(0), "", 0);
        vm.prank(address(issuanceManager));
        printer.assignCert(investor, 1, address(0), d);

        assertEq(printer.legalOwnerOf(1), address(0), "legal owner cleared");
        assertEq(printer.acquisitionTimestamp(1), 0, "clock cleared with the owner");
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

    // ── Legal-owner enumeration: backward compatibility for legacy printers ──

    // Re-running the backfill on a printer that already tracks every token is a no-op (idempotent), never
    // double-counting.
    function test_BackfillLegalOwners_IdempotentOnTrackedPrinter() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));
        _mintCert(3, recipient, 100, bytes(""));

        printer.backfillLegalOwners(0, printer.totalSupply());
        printer.backfillLegalOwners(0, 100); // over-wide range clamps to supply

        assertEq(printer.balanceOfLegalOwner(investor), 2);
        assertEq(printer.balanceOfLegalOwner(recipient), 1);
        assertEq(printer.tokenOfLegalOwnerByIndex(investor, 0), 1);
        assertEq(printer.tokenOfLegalOwnerByIndex(investor, 1), 2);
    }

    // A legacy token (enumeration never populated) must not underflow legalOwnerTokenCount when it is burned.
    function test_LegalOwnerEnumeration_LegacyBurnDoesNotUnderflow() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        CyberCertPrinterEnhanced(address(printer)).debugClearLegalOwnerEnumeration(investor, ids);
        assertEq(printer.balanceOfLegalOwner(investor), 0, "legacy enumeration starts empty");

        vm.prank(address(issuanceManager));
        printer.burn(1); // must not revert (guarded no-op remove)

        assertEq(printer.balanceOfLegalOwner(investor), 0);
    }

    // An owner-write (endorsed transfer) on a legacy token lazily backfills it under the new owner — and the
    // implicit remove from the old owner is a safe no-op (no underflow).
    function test_LegalOwnerEnumeration_LegacyOwnerWriteLazilyBackfills() public {
        _mintCert(1, investor, 100, bytes(""));
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        CyberCertPrinterEnhanced(address(printer)).debugClearLegalOwnerEnumeration(investor, ids);
        assertEq(printer.balanceOfLegalOwner(investor), 0);

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        assertEq(printer.legalOwnerOf(1), recipient);
        assertEq(printer.balanceOfLegalOwner(recipient), 1, "lazily tracked under new owner");
        assertEq(printer.tokenOfLegalOwnerByIndex(recipient, 0), 1);
        assertEq(printer.balanceOfLegalOwner(investor), 0, "old owner stays empty, no underflow add");
    }

    // The explicit batched backfill repopulates the enumeration from owners[] for all live tokens, in batches,
    // and is safe to re-run.
    function test_BackfillLegalOwners_RepopulatesLegacyEnumeration() public {
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));
        _mintCert(3, investor, 100, bytes(""));
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        CyberCertPrinterEnhanced(address(printer)).debugClearLegalOwnerEnumeration(investor, ids);
        assertEq(printer.balanceOfLegalOwner(investor), 0);

        printer.backfillLegalOwners(0, 2);
        assertEq(printer.balanceOfLegalOwner(investor), 2);
        printer.backfillLegalOwners(2, 10); // clamps to supply
        assertEq(printer.balanceOfLegalOwner(investor), 3);

        printer.backfillLegalOwners(0, 3); // re-run safe
        assertEq(printer.balanceOfLegalOwner(investor), 3);
        assertEq(printer.tokenOfLegalOwnerByIndex(investor, 0), 1);
        assertEq(printer.tokenOfLegalOwnerByIndex(investor, 2), 3);
    }

    // Backfill copies a legacy token's acquisitionDate (from FundInterestExtension data) into the base
    // acquisitionTimestamp mapping, is idempotent, and never overwrites a token whose base value is already set.
    function test_BackfillAcquisitionTimestamp_CopiesLegacyFromExtension() public {
        MockFundInterestExtension ext = new MockFundInterestExtension();
        vm.prank(address(issuanceManager));
        printer.setExtension(0, address(ext));

        uint64 legacyAcq = 12345;
        bytes memory fid =
            abi.encode(FundInterestData({acquisitionDate: legacyAcq, tackedFromAcquisitionDate: 0, customProvisions: ""}));
        _mintCert(1, investor, 100, fid); // token 1: legacy (base timestamp cleared below)
        _mintCert(2, investor, 100, fid); // token 2: keeps its mint-time stamp
        uint64 mintStamp = printer.acquisitionTimestamp(2);

        CyberCertPrinterEnhanced(address(printer)).debugClearAcquisitionTimestamp(1);
        assertEq(printer.acquisitionTimestamp(1), 0, "precondition: token 1 base timestamp cleared");

        printer.backfillAcquisitionTimestamps(0, 10);
        assertEq(printer.acquisitionTimestamp(1), legacyAcq, "legacy token backfilled from extensionData");
        assertEq(printer.acquisitionTimestamp(2), mintStamp, "already-set token is not overwritten");

        printer.backfillAcquisitionTimestamps(0, 10); // idempotent re-run
        assertEq(printer.acquisitionTimestamp(1), legacyAcq, "backfill is idempotent");
    }

    // Backfill is a no-op on a printer whose extension is not FUND_INTEREST.
    function test_BackfillAcquisitionTimestamp_NoOpOnNonFundInterestPrinter() public {
        MockNonFundExtension ext = new MockNonFundExtension();
        vm.prank(address(issuanceManager));
        printer.setExtension(0, address(ext));

        bytes memory fid =
            abi.encode(FundInterestData({acquisitionDate: 12345, tackedFromAcquisitionDate: 0, customProvisions: ""}));
        _mintCert(1, investor, 100, fid);
        CyberCertPrinterEnhanced(address(printer)).debugClearAcquisitionTimestamp(1);

        printer.backfillAcquisitionTimestamps(0, 10);
        assertEq(printer.acquisitionTimestamp(1), 0, "non-FUND_INTEREST printer: backfill is a no-op");
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

    // Chokepoint invariant: raw unitsRepresented may never be written below the units locked in pending deals.
    function test_UpdateCertificateDetails_RevertsWhenBelowReserved() public {
        _mintCert(1, investor, 100, bytes(""));
        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);

        CertificateDetails memory updated = _details(39, bytes(""));
        vm.prank(address(issuanceManager));
        vm.expectRevert(ICyberCertPrinter.ExceedsAvailableUnits.selector);
        printer.updateCertificateDetails(1, updated);
    }

    // Boundary: lowering exactly to the reserved amount is allowed (guard is strict `<`, not `<=`).
    function test_UpdateCertificateDetails_AllowsLoweringToReserved() public {
        _mintCert(1, investor, 100, bytes(""));
        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);

        CertificateDetails memory updated = _details(40, bytes(""));
        vm.prank(address(issuanceManager));
        printer.updateCertificateDetails(1, updated);

        assertEq(printer.getActiveCertificateDetails(1).unitsRepresented, 40);
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
        vm.expectRevert(ICyberCertPrinter.TokenDoesNotExist.selector);
        printer.getIssuerSignatureCount(999);
    }

    function test_GetIssuerSignatureAt_RevertsForNonexistentToken() public {
        vm.expectRevert(ICyberCertPrinter.TokenDoesNotExist.selector);
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
