// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {ExemptionPathway, HostingMode} from "../src/interfaces/ISecondaryTradeStorage.sol";
import "../src/libs/auth.sol";
import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Reuse the minimal real-contract fixture mocks rather than redeclaring them.
import {
    MockCyberCorpForCertEvent,
    MockUriBuilderForCertEvent
} from "./IssuanceManagerCertificateCreatedEventTest.t.sol";

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
            address(new MockCyberCorpForCertEvent()),
            address(new MockUriBuilderForCertEvent()),
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
        vm.expectEmit(true, true, false, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(
            SETTLEMENT_ID, address(cert), 0, expectedBuyerTokenId, seller, buyer, UNITS, true, true
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, UNITS, "Bob", HostingMode.DIRECT, address(0)));

        // Seller side: token voided, reservation cleared, real endorsement materialized.
        assertTrue(cert.isVoided(0), "seller cert voided on full sale");
        assertEq(cert.unitsReserved(0), 0, "reservation consumed");
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
        vm.expectEmit(true, true, false, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(
            SETTLEMENT_ID, address(cert), 0, expectedBuyerTokenId, seller, buyer, soldUnits, false, true
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, soldUnits, "Bob", HostingMode.DIRECT, address(0)));

        // Seller side: not voided, units decremented, reservation reduced by the consumed lot.
        assertFalse(cert.isVoided(0), "seller cert survives a partial sale");
        assertEq(cert.getCertificateDetails(0).unitsRepresented, UNITS - soldUnits, "seller remainder");
        assertEq(cert.unitsReserved(0), UNITS - soldUnits, "reservation reduced by consumed lot");
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

    // A buyer's repeat purchase consolidates by default: a second secondary transfer folds its units into the
    // buyer's existing active cert rather than minting a new one (mirrors the scrip-to-cert recert behavior).
    function test_SecondaryTransfer_RepeatPurchase_AccumulatesIntoExistingCert() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);

        // First purchase: 40 units mints the buyer a fresh cert (id 1).
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 40, "Bob", HostingMode.DIRECT, address(0)));
        assertEq(cert.balanceOf(buyer), 1, "buyer holds one cert after the first purchase");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 40, "first cert holds 40");

        // Second purchase: another 40 units reuses cert 1 (the event reports the existing token, not a new mint).
        vm.expectEmit(true, true, false, true, address(issuanceManager));
        emit IIssuanceManager.SecondaryTransferExecuted(SETTLEMENT_ID, address(cert), 0, 1, seller, buyer, 40, false, false);
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 40, "Bob", HostingMode.DIRECT, address(0)));

        assertEq(cert.totalSupply(), 2, "no new cert minted (seller 0 + buyer 1)");
        assertEq(cert.balanceOf(buyer), 1, "buyer still holds a single consolidated cert");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 80, "units accumulated into the existing cert");
    }

    // Merging a secondary purchase into a cert the buyer already holds from PRIMARY issuance must leave that
    // cert's cost-basis snapshot untouched — only units accumulate (spec: snapshot at primary issuance).
    function test_SecondaryTransfer_MergeIntoPrimaryCert_PreservesBasisSnapshot() public {
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

        // A secondary purchase of 30 units folds into the buyer's existing primary cert (id 1).
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, 30, "Bob", HostingMode.DIRECT, address(0)));

        CertificateDetails memory merged = cert.getCertificateDetails(1);
        assertEq(merged.unitsRepresented, 80, "secondary units folded into the primary cert");
        assertEq(merged.investmentAmountUSD, 2000, "primary cost-basis snapshot unchanged");
        assertEq(merged.issuerUSDValuationAtTimeOfInvestment, 20000, "primary valuation snapshot unchanged");
    }

    // TODO should test administered hosted as well

    // Administered hosting where ONE multisig custodies certs for two different legal owners. Consolidation must
    // target the buyer's OWN cert by legal owner of record — never another holder's cert that happens to share
    // the custodian. This is the case a custody (balanceOf) scan could not get right.
    function test_SecondaryTransfer_AdministeredHosting_AccumulatesByLegalOwnerNotCustodian() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        address adminMultisig = makeAddr("adminMultisig");
        (address buyer2,) = makeAddrAndKey("buyer2");

        // The same multisig custodies both buyers' certs.
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer, address(cert), 0, 30, "Bob", HostingMode.ADMINISTERED, adminMultisig));
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer2, address(cert), 0, 40, "Carol", HostingMode.ADMINISTERED, adminMultisig));

        // Bob buys again: must accumulate into Bob's cert (id 1), not Carol's (id 2).
        issuanceManager.secondaryTransfer(_dealMetadataFor(buyer, address(cert), 0, 30, "Bob", HostingMode.ADMINISTERED, adminMultisig));

        assertEq(cert.balanceOf(adminMultisig), 2, "multisig custodies one cert per legal owner");
        assertEq(cert.legalOwnerOf(1), buyer, "cert 1 owned of record by Bob");
        assertEq(cert.legalOwnerOf(2), buyer2, "cert 2 owned of record by Carol");
        assertEq(cert.getCertificateDetails(1).unitsRepresented, 60, "Bob's cert accumulated both his fills");
        assertEq(cert.getCertificateDetails(2).unitsRepresented, 40, "Carol's cert untouched");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Deploys a printer, mints the seller's Ledger Entry Token (id 0, `units` units), and reserves the
    /// whole position — the state the DealManager leaves at acceptOffer (no endorsement is written until finalize).
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
        issuanceManager.increaseUnitsReserved(address(cert), 0, units);
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
