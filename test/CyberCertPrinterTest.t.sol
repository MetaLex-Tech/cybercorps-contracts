// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {LedgerEntryTokenStorage} from "../src/storage/LedgerEntryTokenStorage.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {IUriBuilder} from "../src/interfaces/IUriBuilder.sol";
import {
    CertificateDetails,
    Endorsement,
    ILedgerEntryToken,
    OwnerDetails,
    RestrictionType,
    RestrictiveLegend
} from "../src/interfaces/ILedgerEntryToken.sol";
import {ICertificateExtension, IFundInterestExtension} from "../src/storage/extensions/ICertificateExtension.sol";
import {FundInterestData, FUND_INTEREST_EXTENSION_TYPE} from "../src/storage/extensions/FundInterestExtension.sol";

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
    BorgAuth public immutable auth;

    constructor(address corp, address builder) {
        CORP = corp;
        uriBuilder = builder;
        // Owner is the deployer (the test contract), so arbitrary EOAs are neither admin nor manager.
        auth = new BorgAuth(msg.sender);
    }

    function AUTH() external view returns (address) {
        return address(auth);
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
/// storage by hand. It only ADDS a function; all production LedgerEntryToken logic is inherited unchanged.
contract CyberCertPrinterEnhanced is LedgerEntryToken {
    /// @dev Clear the legal-owner enumeration for `owner`/`tokenIds`, mimicking certs minted before the
    /// enumeration existed (owners[] stays; count/index/tracked are zeroed).
    function debugClearLegalOwnerEnumeration(address owner, uint256[] calldata tokenIds) external {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
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
        LedgerEntryTokenStorage.cyberCertStorage().acquisitionTimestamp[tokenId] = 0;
    }

    /// @dev Flip endorsementRequired to exercise the bearer (unrestricted) mode; production certs are always
    /// registered (endorsementRequired == true, set at initialize with no setter).
    function debugSetEndorsementRequired(bool required) external {
        LedgerEntryTokenStorage.cyberCertStorage().endorsementRequired = required;
    }
}

contract MockFundInterestExtension is IFundInterestExtension {
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool) {
        return extensionType == FUND_INTEREST_EXTENSION_TYPE;
    }
    function getExtensionURI(bytes memory) external pure returns (string memory) { return ""; }
    function acquisitionDate(bytes memory data) external pure returns (uint64) {
        return abi.decode(data, (FundInterestData)).acquisitionDate;
    }
    function tackedFromAcquisitionDate(bytes memory data) external pure returns (uint64) {
        return abi.decode(data, (FundInterestData)).tackedFromAcquisitionDate;
    }
    function withTackedFrom(bytes memory data, uint64 ts) external pure returns (bytes memory) {
        FundInterestData memory fid = abi.decode(data, (FundInterestData));
        fid.tackedFromAcquisitionDate = ts;
        return abi.encode(fid);
    }
}

contract MockNonFundExtension is ICertificateExtension {
    function supportsExtensionType(bytes32) external pure returns (bool) { return false; }
    function getExtensionURI(bytes memory) external pure returns (string memory) { return ""; }
}

/// @notice Minimal LeXcheXBadge surface the look-through tally samples: beneficial-owner count + US flag.
contract MockLookThroughBadge {
    mapping(address => uint32) internal bo;
    mapping(address => bool) internal us;

    function setBo(address a, uint32 c) external { bo[a] = c; }
    function setUs(address a, bool v) external { us[a] = v; }

    function getBeneficialOwnerCount(address a) external view returns (uint32) { return bo[a]; }
    function isUSLookThroughInvestor(address a) external view returns (bool) { return us[a]; }
}

contract CyberCertPrinterTest is Test {
    LedgerEntryToken private printer;
    MockIssuanceManager private issuanceManager;

    address private investor = address(0xA11CE);
    address private recipient = address(0xB0B);
    address private custodian = address(0xC0DE);
    address private custodian2 = address(0xC0DE2);
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

        LedgerEntryToken implementation = new CyberCertPrinterEnhanced();
        bytes memory initData = abi.encodeCall(
            LedgerEntryToken.initialize,
            (
                defaultLegend,
                "Mock Cert",
                "MCERT",
                "ipfs://certificate",
                address(issuanceManager),
                SecurityClass.PreferredStock,
                SecuritySeries.SeriesA,
                initialExtension,
                bytes("")
            )
        );
        printer = LedgerEntryToken(address(new ERC1967Proxy(address(implementation), initData)));
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
        vm.expectRevert(ILedgerEntryToken.SignatureRequired.selector);
        printer.addIssuerSignature(1, "");
    }

    function test_AddIssuerSignature_RevertsForNonexistentToken() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
        printer.addIssuerSignature(999, hex"123456");
    }

    function test_AddIssuerSignature_RevertsWhenCallerNotAuthorized() public {
        _mintCert(1, investor, 100, bytes(""));

        uint256 adminRole = issuanceManager.auth().ADMIN_ROLE();
        vm.prank(investor);
        vm.expectRevert(
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, investor)
        );
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
        vm.expectRevert(ILedgerEntryToken.NotIssuanceManager.selector);
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
        vm.expectRevert(ILedgerEntryToken.ExceedsAvailableUnits.selector);
        printer.increaseUnitsReserved(1, 101);
    }

    function test_UnitsReserved_RevertsWhenDecreaseExceedsReservedUnits() public {
        _mintCert(1, investor, 100, bytes(""));

        vm.prank(address(issuanceManager));
        printer.increaseUnitsReserved(1, 40);

        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.ExceedsReservedUnits.selector);
        printer.decreaseUnitsReserved(1, 41);
    }

    function test_UnitsReserved_RevertsForNonexistentTokens() public {
        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
        printer.increaseUnitsReserved(999, 1);

        vm.prank(address(issuanceManager));
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
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
        vm.expectRevert(ILedgerEntryToken.CertificateReserved.selector);
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
        vm.expectRevert(ILedgerEntryToken.TokenNotTransferable.selector);
        printer.transferFrom(investor, recipient, 2);
    }

    // ───────────────── Legal ownership vs. possession: scenario matrix ─────────────────
    //
    // Two independent layers: possession = ERC-721 ownerOf; legal title = legalOwnerOf. Legal title follows the
    // token only when it is DELIVERED to the party named in the token's latest endorsement — the delivery-vs-
    // payment (DvP) primitive that primary issuance uses to hand escrowed certs to investors on settlement.
    // Every other move is possession-only and leaves legal title untouched. The registrar (assignCert /
    // IssuanceManager void-and-reissue) can also move title directly, as a book-entry change with no token move.
    //
    //   Registered cert (endorsementRequired == true — the production default): the rules above apply.
    //
    //   Bearer cert (endorsementRequired == false): no endorsement gating; legal title simply tracks possession
    //   and follows the token on every transfer.
    //
    //  Legend: Alice = legal owner · Bob = buyer / endorsee · Cust, Cust2 = custodians · endorsee = latest endorsement.
    //  "before tx" / "after tx" bracket the operative transaction; ownerOf and legalOwnerOf appear under both so the
    //  change is visible. (Tests: Alice=investor, Bob=recipient, Cust=custodian, Cust2=custodian2.) A transfer promotes
    //  legal title only when `to == latest endorsee` (else possession-only); assignCert moves title book-entry (no token
    //  move); a secondary sale settles by void-and-reissue (#8).
    //
    //                                                   |──────────── before tx ────────────|─────── after tx ───────|
    //  # | Scenario                        | mode       | endorsee | ownerOf | legalOwnerOf | ownerOf | legalOwnerOf | fixed behavior
    // ---|---------------------------------|------------|----------|---------|--------------|---------|--------------|---------------------------
    //  1 | Custodial deposit               | registered | Alice    | Alice   | Alice        | Cust    | Alice        | to≠endorsee → no change
    //  2 | Custodial return (endorsed)     | registered | Alice    | Cust    | Alice        | Alice   | Alice        | to==endorsee → self-no-op
    //  3 | Custodian-to-custodian          | registered | Alice    | Cust    | Alice        | Cust2   | Alice        | to≠endorsee → no change
    //  4 | Administered delivery-out       | registered | Bob      | Cust    | Bob          | Bob     | Bob          | to==endorsee → self-no-op
    //  5 | Return, stale endorsement       | registered | Bob      | Cust    | Alice        | Alice   | Alice        | to≠endorsee → no change  (Claim #2)
    //  6 | Return, blank endorsement       | registered | blank    | Cust    | Alice        | Alice   | Alice        | blank is never a `to` → no change
    //  7 | Endorsed delivery (DvP)         | registered | Bob      | Alice   | Alice        | Bob     | Bob          | to==endorsee → promote
    //  8 | Custodial secondary sale        | registered | n/a      | Cust    | Alice        | Cust    | Bob          | void + reissue (new tokenId) †
    //  9 | Registrar reassignment (held)   | registered | n/a      | Alice   | Alice        | Alice   | Bob          | assignCert, no token move
    // 10 | Bearer transfer                 | bearer     | n/a      | Alice   | Alice        | Bob     | Bob          | title tracks possession
    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    //  † #8 is void-and-reissue (secondaryTransfer, administered): "before" is the seller's lot (then voided) and
    //    "after" is the freshly minted buyer lot under a NEW tokenId — not one token changing owner. #9 (assignCert)
    //    is the admin in-place reassignment it contrasts with. The full sale flow lives in the secondary-transfer / fork suites.

    // (1) Depositing with a custodian moves possession only; legal ownership stays with the depositor. The cert
    // is endorsed to its own owner (Alice) — the state Deal/Round issuance leaves — which the deposit doesn't match.
    function test_Matrix_Registered_CustodialDeposit() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, investor)); // endorsee == Alice

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1);

        assertEq(printer.ownerOf(1), custodian);
        assertEq(printer.legalOwnerOf(1), investor);
    }

    // (2) Canonical custodial return: the cert is endorsed to its own legal owner (Alice), so the return from the
    // custodian hits the `to == endorsee` branch — which re-asserts Alice as owner, i.e. a self-no-op.
    function test_Matrix_Registered_CustodialReturnToEndorsedOwner() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, investor)); // endorsee == Alice

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1);  // deposit
        vm.prank(custodian);
        printer.transferFrom(custodian, investor, 1);   // return: to == endorsee == Alice

        assertEq(printer.ownerOf(1), investor);
        assertEq(printer.legalOwnerOf(1), investor);
    }

    // (3) Re-delivery between custodians (ACATS-style) keeps legal ownership put; the endorsement to Alice does
    // not match the destination custodian, so no title change.
    function test_Matrix_Registered_CustodianToCustodian() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, investor)); // endorsee == Alice

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1);
        vm.prank(custodian);
        printer.transferFrom(custodian, custodian2, 1);

        assertEq(printer.ownerOf(1), custodian2);
        assertEq(printer.legalOwnerOf(1), investor);
    }

    // (4) Administered hosting: cert is minted to a custodian while legal title rests with the buyer (Bob), and
    // the mirrored endorsement names Bob — written by the registrar, since the custodian only has possession.
    // The custodian later delivers it out to Bob — to == endorsee, so the promote is a self-no-op (Bob is
    // already the legal owner) and possession catches up.
    function test_Matrix_Registered_AdministeredDeliveryOut() public {
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(custodian, recipient, 1, _details(100, bytes("")), "Buyer");
        _enableTransfers();
        vm.prank(address(issuanceManager));
        printer.addEndorsement(1, _endorsement(custodian, recipient)); // registrar endorses; endorsee == Bob

        vm.prank(custodian);
        printer.transferFrom(custodian, recipient, 1);

        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.legalOwnerOf(1), recipient);
    }

    // (5) A stale endorsement pointing at a third party (Bob) must not hijack a custodial return to Alice: the
    // return's `to` (Alice) ≠ the latest endorsee (Bob), so title is left with Alice, not misassigned to Bob (Claim #2).
    function test_Matrix_Registered_ReturnWithStaleEndorsementKeepsTitle() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();

        // Stale endorsement lingers on the token (endorsee is Bob, a third party — not Alice, the owner).
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1);
        vm.prank(custodian);
        printer.transferFrom(custodian, investor, 1);

        assertEq(printer.ownerOf(1), investor);
        assertEq(printer.legalOwnerOf(1), investor); // NOT reassigned to Bob, the stale endorsee
    }

    // (6) An endorsement in blank (endorseCertificate leaves endorsee unset) is a signed but unfilled assignment,
    // not a surrender of title: it must not be self-executing, and a custodial return must not clear the holder
    // of record. address(0) is never a transfer's `to`, so the delivery branch can never match it.
    function test_Matrix_Registered_ReturnWithBlankEndorsementKeepsTitle() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();

        vm.prank(address(issuanceManager));
        printer.endorseCertificate(1, investor, hex"abcd", bytes32(0)); // endorsee left blank

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1);
        assertEq(printer.legalOwnerOf(1), investor);

        vm.prank(custodian);
        printer.transferFrom(custodian, investor, 1);

        assertEq(printer.ownerOf(1), investor);
        assertEq(printer.legalOwnerOf(1), investor); // NOT wiped to address(0)
    }

    // (7) Delivering the token to the party named in the latest endorsement promotes legal title along with
    // possession — the delivery-vs-payment path primary issuance relies on (escrow → investor at settlement).
    function test_Matrix_Registered_EndorsedDeliveryMovesTitle() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();

        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.legalOwnerOf(1), recipient);
    }

    // (8) Custodial secondary sale: a market sale settled by void-and-reissue (IssuanceManager.secondaryTransfer,
    // administered hosting) — NOT an in-place reassignment. The seller's lot is voided and a fresh lot is minted
    // to the same custodian with the buyer as legal owner, so possession stays with the custodian while legal
    // ownership moves Alice → Bob across a NEW tokenId. (secondaryTransfer needs the full stack; this reproduces
    // its token-level effect — the flow is exercised end-to-end in the secondary-transfer / fork suites.)
    function test_Matrix_Registered_CustodialSecondarySale() public {
        // Seller's lot: held by the custodian, owned by Alice.
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(custodian, investor, 1, _details(100, bytes("")), "Alice");

        // Settlement: void the seller's lot, reissue a fresh lot to the same custodian for the buyer (Bob).
        _void(1);
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(custodian, recipient, 2, _details(100, bytes("")), "Bob");

        assertTrue(printer.isVoided(1));              // seller lot retired
        assertEq(printer.ownerOf(2), custodian);      // buyer lot: possession stays with the custodian
        assertEq(printer.legalOwnerOf(2), recipient); // legal ownership is now Bob
    }

    // (9) Registrar reassignment, self-held: the owner holds their own cert and legal title is reassigned
    // Alice → Bob as an in-place book-entry change by an admin (e.g. gift/inheritance/reorg, NOT a sale);
    // possession stays with Alice. This is the admin path the custodial secondary sale (#7) is contrasted with.
    function test_Matrix_Registered_RegistrarReassignmentMovesTitleOnly() public {
        _mintCert(1, investor, 100, bytes(""));

        _reassignLegalOwner(1, investor, recipient);

        assertEq(printer.ownerOf(1), investor);       // possession unchanged
        assertEq(printer.legalOwnerOf(1), recipient); // title moved
    }

    // (10) Bearer (unrestricted) certs have no registrar title: legal ownership tracks possession and follows
    // the token down the transfer chain.
    function test_Matrix_Bearer_TitleTracksPossession() public {
        _mintCert(1, investor, 100, bytes(""));
        CyberCertPrinterEnhanced(address(printer)).debugSetEndorsementRequired(false);
        _enableTransfers();

        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);
        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.legalOwnerOf(1), recipient);

        vm.prank(recipient);
        printer.transferFrom(recipient, custodian, 1);
        assertEq(printer.ownerOf(1), custodian);
        assertEq(printer.legalOwnerOf(1), custodian);
    }

    function test_TokenTransferable_RevertsWhenCallerNotAuthorized() public {
        uint256 adminRole = issuanceManager.auth().ADMIN_ROLE();
        vm.prank(investor);
        vm.expectRevert(
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, adminRole, investor)
        );
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
        emit ILedgerEntryToken.LegalOwnerChanged(1, investor, investor, "", acquiredAt);
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
        emit ILedgerEntryToken.LegalOwnerChanged(1, investor, address(0), "", 0);
        vm.prank(address(issuanceManager));
        printer.assignCert(investor, 1, address(0), d);

        assertEq(printer.legalOwnerOf(1), address(0), "legal owner cleared");
        assertEq(printer.acquisitionTimestamp(1), 0, "clock cleared with the owner");
    }

    // A genuine in-place legal-owner change (current != newOwner, both non-zero) restamps the acquisition clock
    // to now while leaving the immutable issue timestamp untouched.
    function test_SetLegalOwner_GenuineChange_RestampsAcquisitionKeepsIssue() public {
        vm.prank(address(issuanceManager));
        printer.safeMintAndAssign(investor, 1, _details(100, bytes("")), "Alice");
        uint64 issuedAt = printer.issueTimestamp(1);
        uint64 acquiredAt = printer.acquisitionTimestamp(1);

        vm.warp(block.timestamp + 30 days);
        CertificateDetails memory d = _details(100, bytes(""));

        vm.expectEmit(true, true, true, true, address(printer));
        emit ILedgerEntryToken.LegalOwnerChanged(1, investor, recipient, "", uint64(block.timestamp));
        vm.prank(address(issuanceManager));
        printer.assignCert(investor, 1, recipient, d);

        assertEq(printer.legalOwnerOf(1), recipient, "legal owner reassigned");
        assertEq(printer.acquisitionTimestamp(1), uint64(block.timestamp), "acquisition clock restamped to now");
        assertGt(uint64(block.timestamp), acquiredAt, "precondition: time advanced past original acquisition");
        assertEq(printer.issueTimestamp(1), issuedAt, "issue timestamp is immutable across owner changes");
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
        bytes memory fid = _fundInterestBlob(legacyAcq);
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

        bytes memory fid = _fundInterestBlob(12345);
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
        vm.expectRevert(ILedgerEntryToken.ExceedsAvailableUnits.selector);
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
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
        printer.getIssuerSignatureCount(999);
    }

    function test_GetIssuerSignatureAt_RevertsForNonexistentToken() public {
        vm.expectRevert(ILedgerEntryToken.TokenDoesNotExist.selector);
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

    // ───────────────── §3(c)(1)(A) look-through holder tally ─────────────────

    function _setBadge(MockLookThroughBadge b) private {
        vm.prank(address(issuanceManager));
        printer.setLookThroughBadge(address(b));
    }

    function _void(uint256 tokenId) private {
        vm.prank(address(issuanceManager));
        printer.voidCert(tokenId);
    }

    function _unvoid(uint256 tokenId) private {
        vm.prank(address(issuanceManager));
        printer.unvoidCert(tokenId);
    }

    function test_LookThrough_IndividualCountsAsOne() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 1);
        assertEq(printer.usLookThroughHolderCount(), 0);
        assertTrue(printer.isLegalHolder(investor));
    }

    function test_LookThrough_NoBadgeDegradesToOne() public {
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 1);
        assertEq(printer.usLookThroughHolderCount(), 0);
    }

    function test_LookThrough_UsEntityFlowsThroughBothTotals() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 5);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 5);
        assertEq(printer.usLookThroughHolderCount(), 5);
    }

    function test_LookThrough_ForeignEntityOnlyTotal() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 3);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 3);
        assertEq(printer.usLookThroughHolderCount(), 0);
    }

    function test_LookThrough_SecondLotResamplesWeight() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 5);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 5);
        // Re-credentialed before the next acquisition; the second lot resamples the weight.
        b.setBo(investor, 7);
        _mintCert(2, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 7);
        assertEq(printer.usLookThroughHolderCount(), 7);
    }

    function test_LookThrough_VoidAndUnvoidAdjustTally() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 4);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 4); // one holder, weight 4, two live lots

        _void(1); // still a holder via the other lot
        assertEq(printer.lookThroughHolderCount(), 4);
        assertTrue(printer.isLegalHolder(investor));

        _void(2); // last live lot gone: holder drops out
        assertEq(printer.lookThroughHolderCount(), 0);
        assertEq(printer.usLookThroughHolderCount(), 0);
        assertFalse(printer.isLegalHolder(investor));

        _unvoid(2); // restored
        assertEq(printer.lookThroughHolderCount(), 4);
        assertEq(printer.usLookThroughHolderCount(), 4);
        assertTrue(printer.isLegalHolder(investor));
    }

    function test_LookThrough_ResyncReconcilesBoAndJurisdiction() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 3);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 3);
        assertEq(printer.usLookThroughHolderCount(), 3);

        // BO count rises and jurisdiction flips to foreign: weight moves out of the US subtotal.
        b.setBo(investor, 6);
        b.setUs(investor, false);
        printer.resyncHolder(investor);
        assertEq(printer.lookThroughHolderCount(), 6);
        assertEq(printer.usLookThroughHolderCount(), 0);
    }

    function test_LookThrough_ResyncNonHolderIsNoop() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(recipient, 9);
        _setBadge(b);
        printer.resyncHolder(recipient); // not a holder
        assertEq(printer.lookThroughHolderCount(), 0);
    }

    function test_LookThrough_BackfillIsIdempotent() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 5);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, recipient, 100, bytes("")); // individual, weight 1
        uint256 total = printer.lookThroughHolderCount(); // 5 + 1

        // Re-running backfill over the live set must not double-count (liveCounted guards it).
        printer.backfillLookThroughTally(0, 10);
        printer.backfillLookThroughTally(0, 10);
        assertEq(printer.lookThroughHolderCount(), total);
        assertEq(printer.usLookThroughHolderCount(), 5);
    }

    function test_LookThrough_ResyncHoldersBatchReconcilesEach() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 3);
        b.setUs(investor, true);
        b.setBo(recipient, 2);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, recipient, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 5); // 3 (US) + 2
        assertEq(printer.usLookThroughHolderCount(), 3);

        // Both re-credentialed: investor's weight falls and leaves the US subtotal; recipient's weight rises.
        b.setBo(investor, 1);
        b.setUs(investor, false);
        b.setBo(recipient, 4);
        address[] memory owners = new address[](2);
        owners[0] = investor;
        owners[1] = recipient;
        printer.resyncHolders(owners);
        assertEq(printer.lookThroughHolderCount(), 5); // 1 + 4
        assertEq(printer.usLookThroughHolderCount(), 0);
    }

    function test_LookThrough_ResyncNonUsToUsMovesIntoSubtotal() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 2); // foreign at mint
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 2);
        assertEq(printer.usLookThroughHolderCount(), 0);

        b.setUs(investor, true); // re-credentialed as US-resident
        printer.resyncHolder(investor);
        assertEq(printer.lookThroughHolderCount(), 2);
        assertEq(printer.usLookThroughHolderCount(), 2);
    }

    // A voided lot contributes to neither owner's tally, so transferring it moves the legal-owner enumeration
    // while the look-through totals stay put — the one place the two accounting systems diverge.
    function test_LookThrough_VoidedCertTransferMovesOwnerNotTally() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 3);
        b.setUs(investor, true);
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 3);

        _void(1);
        assertEq(printer.lookThroughHolderCount(), 0);
        assertFalse(printer.isLegalHolder(investor));

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        // Enumeration follows the move …
        assertEq(printer.legalOwnerOf(1), recipient);
        assertEq(printer.balanceOfLegalOwner(investor), 0);
        assertEq(printer.balanceOfLegalOwner(recipient), 1);
        // … the tally does not, and neither party is a live holder via this lot.
        assertEq(printer.lookThroughHolderCount(), 0);
        assertEq(printer.usLookThroughHolderCount(), 0);
        assertFalse(printer.isLegalHolder(recipient));
    }


    // A single transfer drops the source below its last live lot and gives the destination its first,
    // reassigning weight (and the US subtotal) between two holders in one call.
    function test_LookThrough_TransferReassignsWeightBetweenHolders() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 5);
        b.setUs(investor, true);
        b.setBo(recipient, 3); // foreign
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 5);
        assertEq(printer.usLookThroughHolderCount(), 5);

        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);
        vm.prank(investor);
        printer.addEndorsement(1, _endorsement(investor, recipient));
        vm.prank(investor);
        printer.transferFrom(investor, recipient, 1);

        assertEq(printer.lookThroughHolderCount(), 3); // −5 investor, +3 recipient
        assertEq(printer.usLookThroughHolderCount(), 0);
        assertFalse(printer.isLegalHolder(investor));
        assertTrue(printer.isLegalHolder(recipient));
        assertEq(printer.legalOwnerOf(1), recipient);
    }

    // Feeder-classification policy: a feeder with any US beneficial owner is classified regulatory-US and all
    // its BOs count as US-resident; a wholly-non-US feeder contributes to the total only. No mixed feeders,
    // so the all-or-nothing US tally is exact.
    function test_LookThrough_ClassifiedFeedersCountWholesale() public {
        MockLookThroughBadge b = new MockLookThroughBadge();
        b.setBo(investor, 10);
        b.setUs(investor, true); // regulatory-US feeder (>=1 US beneficial owner)
        b.setBo(recipient, 6);
        b.setUs(recipient, false); // wholly-non-US feeder
        _setBadge(b);
        _mintCert(1, investor, 100, bytes(""));
        _mintCert(2, recipient, 100, bytes(""));
        assertEq(printer.lookThroughHolderCount(), 16); // 10 + 6
        assertEq(printer.usLookThroughHolderCount(), 10); // only the US-classified feeder's BOs
    }

    // Possession is not authority to endorse: a custodian holding a cert cannot endorse it to itself and take
    // legal title on delivery. Only the holder of record (or the registrar) may endorse.
    function test_AddEndorsement_CustodianCannotEndorseCertItMerelyHolds() public {
        _mintCert(1, investor, 100, bytes(""));
        _enableTransfers();

        vm.prank(investor);
        printer.transferFrom(investor, custodian, 1); // possession-only deposit
        assertEq(printer.legalOwnerOf(1), investor);

        vm.prank(custodian);
        vm.expectRevert(ILedgerEntryToken.InvalidEndorsement.selector);
        printer.addEndorsement(1, _endorsement(custodian, custodian));
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

    /// @dev Encoded FundInterestData with only acquisitionDate set; other fields default
    function _fundInterestBlob(uint64 acquisitionDate) private pure returns (bytes memory) {
        FundInterestData memory fid;
        fid.acquisitionDate = acquisitionDate;
        return abi.encode(fid);
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

    function _enableTransfers() private {
        vm.prank(address(issuanceManager));
        printer.setGlobalTransferable(true);
    }

    // Registrar path for a registered legal-owner change (sale/gift/inheritance/reorg): assignCert moves legal
    // title without moving the token, mirroring what IssuanceManager does at settlement.
    function _reassignLegalOwner(uint256 tokenId, address from, address to) private {
        vm.prank(address(issuanceManager));
        printer.assignCert(from, tokenId, to, _details(100, bytes("")));
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
