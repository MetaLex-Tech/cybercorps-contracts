// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {ExemptionPathway} from "../src/interfaces/ISecondaryTradeStorage.sol";
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
            SETTLEMENT_ID, address(cert), 0, expectedBuyerTokenId, seller, buyer, UNITS, true
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, UNITS, "Bob", 0, address(0)));

        // Seller side: token voided, reservation cleared, real endorsement materialized.
        assertTrue(cert.isVoided(0), "seller cert voided on full sale");
        assertEq(cert.unitsReserved(0), 0, "reservation consumed");
        _assertSellerEndorsement(cert, 0, "Bob");

        // Buyer side: new token minted to the buyer for all units.
        assertEq(cert.legalOwnerOf(expectedBuyerTokenId), buyer, "buyer is registered owner");
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).unitsRepresented, UNITS, "buyer units");
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
            SETTLEMENT_ID, address(cert), 0, expectedBuyerTokenId, seller, buyer, soldUnits, false
        );
        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, soldUnits, "Bob", 0, address(0)));

        // Seller side: not voided, units decremented, reservation reduced by the consumed lot.
        assertFalse(cert.isVoided(0), "seller cert survives a partial sale");
        assertEq(cert.getCertificateDetails(0).unitsRepresented, UNITS - soldUnits, "seller remainder");
        assertEq(cert.unitsReserved(0), UNITS - soldUnits, "reservation reduced by consumed lot");
        _assertSellerEndorsement(cert, 0, "Bob");

        // Buyer side: new token for the sold units only.
        assertEq(cert.legalOwnerOf(expectedBuyerTokenId), buyer, "buyer is registered owner");
        assertEq(cert.getCertificateDetails(expectedBuyerTokenId).unitsRepresented, soldUnits, "buyer units");
        _assertMirrorEndorsement(cert, expectedBuyerTokenId, "Bob");
    }

    // Administered hosting (buyerHostingMode == 1) delivers the new token to the admin multisig.
    function test_SecondaryTransfer_AdministeredHosting_DeliversToMultisig() public {
        ICyberCertPrinter cert = _deployPrinterWithSellerCert(UNITS);
        address adminMultisig = makeAddr("adminMultisig");

        issuanceManager.secondaryTransfer(_dealMetadata(address(cert), 0, UNITS, "Bob", 1, adminMultisig));

        // Token custody is the multisig under administered hosting.
        assertEq(cert.ownerOf(1), adminMultisig, "administered token held by multisig");
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
        uint8 buyerHostingMode,
        address adminMultisig
    ) internal view returns (bytes memory) {
        return abi.encode(
            cert,
            tokenId,
            units,
            buyer,
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
