// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ExemptionPathway, HostingMode} from "../src/interfaces/ISecondaryTradeStorage.sol";
import "../src/libs/auth.sol";
import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Reuse the minimal real-contract fixture mocks rather than redeclaring them.
import {
    MockCyberCorpForIM,
    MockUriBuilderForIM
} from "./IssuanceManagerTest.t.sol";

/// @title IssuanceManagerSecondaryTransferTest
/// @notice Exercises the real IssuanceManager.secondaryTransfer against a real CyberCertPrinter (no mocks),
/// proving the mutate-and-mint ownership change, the seller-token and buyer-token endorsements materialized at
/// finalization, and the SecondaryTransferExecuted signal an indexer reads for the buyer's new token id.
contract IssuanceManagerSecondaryTransferTest is Test {
    bytes32 constant SALT = bytes32(keccak256("IssuanceManagerSecondaryTransferTest"));

    IssuanceManager public issuanceManager;
    BorgAuth public auth;

    address public owner;
    address public seller;
    address public buyer;

    uint256 constant UNITS = 100;
    bytes constant SELLER_SIG = hex"deadbeef";
    bytes32 constant SETTLEMENT_ID = keccak256("settlement");

    function setUp() public {
        owner = address(this);
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");

        auth = new BorgAuth(owner);

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new IssuanceManagerFactory{salt: SALT}()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        new IssuanceManager(),
                        new CyberCertPrinter(),
                        new CyberScrip()
                    )
                )
            )
        );

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(new MockCyberCorpForIM()),
            address(new MockUriBuilderForIM()),
            address(imFactory)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenarios
    // ─────────────────────────────────────────────────────────────────────────

    // Full sale: the entire seller position is sold, so the seller's Ledger Entry Token is voided and the
    // buyer's new token represents all the units.
    function test_SecondaryTransfer_FullSale_VoidsSellerMintsBuyer() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);

        // The buyer's new token is the next minted id (seller cert is tokenId 0).
        uint256 expectedBuyerTokenId = 1;
        vm.expectEmit(true, true, true, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(
            SETTLEMENT_ID, address(cert), buyer, 0, expectedBuyerTokenId, seller, UNITS, 0, UNITS, true, true
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, UNITS, "Bob", HostingMode.DIRECT, address(0)));

        // Seller side: token voided, real endorsement materialized.
        assertTrue(cert.isVoided(0), "seller cert voided on full sale");
        _assertSellerEndorsement(cert, 0, "Bob");

        // Buyer side: new token minted to the buyer for all units.
        assertEq(cert.legalOwnerOf(expectedBuyerTokenId), buyer, "buyer is registered owner");
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).unitsRepresented, UNITS, "buyer units");
        // A secondary-acquired cert carries no primary-issuance basis: those fields are blank.
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).investmentAmountUSD, 0, "buyer cost basis blank");
        assertEq(
            cert.getCertificateDetails(expectedBuyerTokenId).issuerUSDValuationAtTimeOfInvestment,
            0,
            "buyer valuation blank"
        );
        _assertMirrorEndorsement(cert, expectedBuyerTokenId, "Bob");
    }

    // Partial sale: only part of the seller position is sold, so the seller's token is decremented in place
    // (not voided) and the buyer's new token represents only the sold units.
    function test_SecondaryTransfer_PartialSale_DecrementsSeller() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        uint256 soldUnits = 40;

        uint256 expectedBuyerTokenId = 1;
        vm.expectEmit(true, true, true, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(
            SETTLEMENT_ID, address(cert), buyer, 0, expectedBuyerTokenId, seller, soldUnits, UNITS - soldUnits, soldUnits, false, true
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, soldUnits, "Bob", HostingMode.DIRECT, address(0)));

        // Seller side: not voided, units decremented by the sold lot.
        assertFalse(cert.isVoided(0), "seller cert survives a partial sale");
        assertEq(cert.getCertificateDetails(0).unitsRepresented, UNITS - soldUnits, "seller remainder");
        // The seller's cert keeps its primary-issuance basis snapshot; only units decrement.
        assertEq(cert.getCertificateDetails(0).investmentAmountUSD, 1000, "seller cost basis unchanged");
        assertEq(
            cert.getCertificateDetails(0).issuerUSDValuationAtTimeOfInvestment,
            10000,
            "seller valuation unchanged"
        );
        _assertSellerEndorsement(cert, 0, "Bob");

        // Buyer side: new token for the sold units only, with blank cost basis (secondary acquisition).
        assertEq(cert.legalOwnerOf(expectedBuyerTokenId), buyer, "buyer is registered owner");
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).unitsRepresented, soldUnits, "buyer units");
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).investmentAmountUSD, 0, "buyer cost basis blank");
        assertEq(
            cert.getCertificateDetails(expectedBuyerTokenId).issuerUSDValuationAtTimeOfInvestment,
            0,
            "buyer valuation blank"
        );
        _assertMirrorEndorsement(cert, expectedBuyerTokenId, "Bob");
    }

    // A scripified seller token must decrement its RAW (in-cert) units, not the effective balance that folds
    // scripified units back in. Reading effective and writing it straight back would corrupt the stored raw
    // count, double-counting the scripified portion on the next read.
    function test_SecondaryTransfer_ScripifiedSellerToken_DecrementsRawUnits() public {
        ICyberCertPrinter cert = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0), "Cert", "CERT", "uri://cert",
                SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0)
            )
        );
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 100,
            legalDetails: "",
            extensionData: bytes("")
        });
        issuanceManager.createCertAndAssign(address(cert), seller, details);

        // Scripify 30 of the 100 units: raw -> 70, scripified 30, effective stays 100.
        _deployScrip(address(cert));
        vm.prank(seller);
        issuanceManager.scripifyCert(address(cert), 0, 30, address(0));
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 70, "raw after scripify");
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 100, "effective after scripify");

        // Sell 40 of the raw 70.
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 40, "Bob", HostingMode.DIRECT, address(0)));

        // Seller raw drops by exactly the sold units (70 -> 30); the scripified portion is untouched, so the
        // effective view is 30 + 30. An effective read-write would have stored 60 raw (effective 90) — corruption.
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 30, "seller raw should decrement and not include scripified units");
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 60, "seller effective = raw + scripified");
        assertFalse(cert.isVoided(0), "partial sale keeps seller token active");

        // Buyer gets a fresh token for the sold units only.
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 40, "buyer raw units");
        assertEq(cert.legalOwnerOf(1), buyer, "buyer owns new token");
    }

    // Administered hosting (HostingMode.ADMINISTERED) custodies the new token with the admin multisig, but the
    // buyer is still the registered legal owner of record (spec §7.4A) — custody and ownership are distinct.
    function test_SecondaryTransfer_AdministeredHosting_MultisigCustodiesBuyerOwns() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        address adminMultisig = makeAddr("adminMultisig");

        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, UNITS, "Bob", HostingMode.ADMINISTERED, adminMultisig));

        // Custody: the multisig holds the NFT. Ownership of record: the buyer, not the custodian.
        assertEq(cert.ownerOf(1), adminMultisig, "administered token custodied by multisig");
        assertEq(cert.legalOwnerOf(1), buyer, "buyer is the registered legal owner under administered hosting");
        assertEq(cert.balanceOf(buyer), 0, "buyer does not custody the NFT");
        _assertMirrorEndorsement(cert, 1, "Bob");
    }

    // Fresh-mint-per-lot: a buyer's repeat purchase mints a NEW cert each time (its own acquisitionTimestamp
    // clock) rather than folding into an existing one — the per-lot holding-period model (§7.5).
    function test_SecondaryTransfer_RepeatPurchase_MintsDistinctLots() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);

        // First purchase: 40 units mints the buyer a fresh cert (id 1).
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 40, "Bob", HostingMode.DIRECT, address(0)));
        assertEq(cert.balanceOf(buyer), 1, "buyer holds one cert after the first purchase");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 40, "first cert holds 40");

        // Second purchase: another 40 units mints a distinct new cert (id 2), reported as a fresh mint.
        vm.expectEmit(true, true, true, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(SETTLEMENT_ID, address(cert), buyer, 0, 2, seller, 40, 20, 40, false, true);
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 40, "Bob", HostingMode.DIRECT, address(0)));

        assertEq(cert.totalSupply(), 3, "a new cert minted per lot (seller 0 + buyer 1 + buyer 2)");
        assertEq(cert.balanceOf(buyer), 2, "buyer holds one cert per lot");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 40, "first lot unchanged");
        assertEq(cert.getCertificateDetails(2).unitsRepresented, 40, "second lot is its own cert");
    }

    // Fresh-mint-per-lot: a secondary purchase never folds into a cert the buyer already holds from PRIMARY
    // issuance — a distinct lot is minted, and the primary cert (units and cost-basis snapshot) is untouched.
    function test_SecondaryTransfer_DoesNotMergeIntoPrimaryCert() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);

        // The buyer already holds a primary-issued cert (id 1) with its own cost basis.
        CertificateDetails memory primaryDetails = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 2000,
            issuerUSDValuationAtTimeOfInvestment: 20000,
            unitsRepresented: 50,
            legalDetails: "",
            extensionData: bytes("")
        });
        issuanceManager.createCertAndAssign(address(cert), buyer, primaryDetails);

        // A secondary purchase of 30 units mints a fresh lot (id 2), leaving the primary cert untouched.
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 30, "Bob", HostingMode.DIRECT, address(0)));

        CertificateDetails memory primary = cert.getCertificateDetails(1);
        assertEq(primary.unitsRepresented, 50, "primary cert units untouched");
        assertEq(primary.investmentAmountUSD, 2000, "primary cost-basis snapshot unchanged");
        assertEq(primary.issuerUSDValuationAtTimeOfInvestment, 20000, "primary valuation snapshot unchanged");

        CertificateDetails memory secondaryLot = cert.getCertificateDetails(2);
        assertEq(secondaryLot.unitsRepresented, 30, "secondary purchase is its own lot");
        assertEq(secondaryLot.investmentAmountUSD, 0, "secondary lot carries no primary-issuance basis");
        assertEq(cert.balanceOf(buyer), 2, "buyer holds the primary cert and the new secondary lot");
    }

    // TODO should test administered hosted as well

    // Administered hosting where ONE multisig custodies certs for two different legal owners. Fresh-mint-per-lot
    // means each fill mints its own cert to the multisig, owned of record by the respective buyer — the legal
    // owner of record (not the shared custodian) is what distinguishes lots.
    function test_SecondaryTransfer_AdministeredHosting_MintsLotPerFillByLegalOwner() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        address adminMultisig = makeAddr("adminMultisig");
        (address buyer2,) = makeAddrAndKey("buyer2");

        // The same multisig custodies both buyers' certs.
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer, address(cert), 0, 30, "Bob", HostingMode.ADMINISTERED, adminMultisig));
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer2, address(cert), 0, 40, "Carol", HostingMode.ADMINISTERED, adminMultisig));

        // Bob buys again: a distinct new lot (id 3) is minted to the multisig, owned of record by Bob.
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer, address(cert), 0, 30, "Bob", HostingMode.ADMINISTERED, adminMultisig));

        assertEq(cert.balanceOf(adminMultisig), 3, "multisig custodies one cert per lot");
        assertEq(cert.balanceOfLegalOwner(buyer), 2, "Bob owns of record two lots");
        assertEq(cert.balanceOfLegalOwner(buyer2), 1, "Carol owns of record one lot");
        assertEq(cert.legalOwnerOf(1), buyer, "lot 1 owned of record by Bob");
        assertEq(cert.legalOwnerOf(2), buyer2, "lot 2 owned of record by Carol");
        assertEq(cert.legalOwnerOf(3), buyer, "Bob's second lot owned of record by Bob");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 30, "Bob's first lot");
        assertEq(cert.getCertificateDetails(3).unitsRepresented, 30, "Bob's second lot is distinct");
        assertEq(cert.getCertificateDetails(2).unitsRepresented, 40, "Carol's lot untouched");
    }

    // The admin can correct a cert's issue timestamp for a position issued off-chain before being recorded
    // on-chain (overrides the mint-stamped value); non-admins cannot.
    function test_SetIssueTimestamp_AdminOverridesMintStamp() public {
        vm.warp(200 days);
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        assertEq(cert.issueTimestamp(0), uint64(block.timestamp), "mint stamps the on-chain issue time");

        uint64 historical = uint64(110 days); // truly issued off-chain, earlier than the on-chain record
        vm.expectEmit(true, false, false, true, address(cert));
        emit ICyberCertPrinter.IssueTimestampSet(0, historical);
        issuanceManager.setIssueTimestamp(address(cert), 0, historical);
        assertEq(cert.issueTimestamp(0), historical, "admin override applied");

        address notAdmin = makeAddr("notAdmin");
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(abi.encodeWithSignature("BorgAuth_NotAuthorized(uint256,address)", adminRole, notAdmin));
        issuanceManager.setIssueTimestamp(address(cert), 0, historical);
    }

    // The admin can override a cert's acquisition timestamp (e.g. to seed a seasoned migrated position);
    // non-admins cannot.
    function test_SetAcquisitionTimestamp_AdminOverridesMintStamp() public {
        vm.warp(200 days);
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        assertEq(cert.acquisitionTimestamp(0), uint64(block.timestamp), "mint stamps the acquisition time");

        uint64 seasoned = uint64(110 days); // acquired off-chain earlier than the on-chain record
        vm.expectEmit(true, false, false, true, address(cert));
        emit ICyberCertPrinter.AcquisitionTimestampSet(0, seasoned);
        issuanceManager.setAcquisitionTimestamp(address(cert), 0, seasoned);
        assertEq(cert.acquisitionTimestamp(0), seasoned, "admin override applied");

        address notAdmin = makeAddr("notAdmin");
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(abi.encodeWithSignature("BorgAuth_NotAuthorized(uint256,address)", adminRole, notAdmin));
        issuanceManager.setAcquisitionTimestamp(address(cert), 0, seasoned);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Deploys a printer and mints the seller's Ledger Entry Token (id 0, `units` units)
    function _deployPrinterWithSellerCert(uint256 units) internal returns (ICyberCertPrinter cert) {
        cert = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Cert",
                "CERT",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: bytes("")
        });
        issuanceManager.createCertAndAssign(address(cert), seller, details);
    }

    function _deployScrip(address cert) internal {
        issuanceManager.deployCyberScrip(
            cert,
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, // scripToCertMinimum
            1, // ratio numerator
            1, // ratio denominator
            new uint256[](0),
            false, // whitelist disabled
            true,
            true,
            true
        );
    }

    function _dealMetadata(
        address cert,
        uint256 tokenId,
        uint256 units,
        string memory buyerName,
        HostingMode buyerHostingMode,
        address adminMultisig
    ) internal view returns (bytes memory) {
        return _dealMetadataFor(buyer, cert, tokenId, units, buyerName, buyerHostingMode, adminMultisig);
    }

    function _dealMetadataFor(
        address buyerAddr,
        address cert,
        uint256 tokenId,
        uint256 units,
        string memory buyerName,
        HostingMode buyerHostingMode,
        address adminMultisig
    ) internal pure returns (bytes memory) {
        return abi.encode(
            cert,
            tokenId,
            units,
            buyerAddr,
            buyerName,
            buyerHostingMode,
            adminMultisig,
            ExemptionPathway.SECTION_4A7,
            SETTLEMENT_ID,
            SELLER_SIG
        );
    }

    /// @dev The buyer's new token carries one mirror endorsement (index 0) back-pointing to the seller and the
    /// settlement agreement, reusing the seller's open-endorsement signature.
    function _assertMirrorEndorsement(ICyberCertPrinter cert, uint256 buyerTokenId, string memory buyerName)
        internal
        view
    {
        // Concrete type: the ICyberCertPrinter interface declares a stale flat-tuple return; the contract
        // returns the Endorsement struct.
        Endorsement memory mirror = CyberCertPrinter(address(cert)).getEndorsementHistory(buyerTokenId, 0);
        assertEq(mirror.endorser, seller, "mirror endorser is the seller");
        assertEq(mirror.endorsee, buyer, "mirror endorsee is the buyer");
        assertEq(mirror.endorseeName, buyerName, "mirror endorsee name");
        assertEq(mirror.agreementId, SETTLEMENT_ID, "mirror bound to the settlement");
        assertEq(mirror.signatureHash, SELLER_SIG, "mirror reuses the seller signature");
    }

    /// @dev secondaryTransfer materializes the seller's real endorsement on the seller token at finalization
    /// (no open endorsement is written at acceptance). It sits at index 1 — index 0 is the endorsement the mint
    /// (createCertAndAssign) records. Endorser is the seller of record (spec §3676-3680), endorsee the now-known
    /// buyer.
    function _assertSellerEndorsement(ICyberCertPrinter cert, uint256 sellerTokenId, string memory buyerName)
        internal
        view
    {
        Endorsement memory e = CyberCertPrinter(address(cert)).getEndorsementHistory(sellerTokenId, 1);
        assertEq(e.endorser, seller, "seller-token endorser is the seller");
        assertEq(e.endorsee, buyer, "seller-token endorsee is the buyer");
        assertEq(e.endorseeName, buyerName, "seller-token endorsee name");
        assertEq(e.agreementId, SETTLEMENT_ID, "seller endorsement bound to the settlement");
        assertEq(e.signatureHash, SELLER_SIG, "seller endorsement carries the seller signature");
    }
}
