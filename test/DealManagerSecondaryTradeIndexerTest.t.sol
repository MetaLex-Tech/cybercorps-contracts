/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o



ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



  .oooooo.                .o8                            .oooooo.
 d8P'  `Y8b              "888                           d8P'  `Y8b
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
             .o..P'                                                                     888
             `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {
    OfferSide,
    OfferStatus,
    ExemptionPathway,
    SecondaryEscrowStatus,
    Offer,
    SecondaryEscrow,
    PostOfferParams,
    AcceptOfferParams
} from "../src/storage/SecondaryTradeStorage.sol";
import {ISecondaryTradeStorage} from "../src/interfaces/ISecondaryTradeStorage.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
// Reuse the secondary-trade test mocks rather than redeclaring them.
import {SecERC20Mock, SecCertPrinterMock, SecIssuanceManagerMock, SecCorpMock} from "./DealManagerSecondaryTradeTest.t.sol";

/// @title DealManagerSecondaryTradeIndexerTest
/// @notice Simulates an off-chain indexer (e.g. powering the Legion UI) and proves the secondary-trade
/// events emit enough information to reconstruct trading status from logs alone.
/// @dev Each scenario records the logs of a real trade lifecycle, replays them through an in-memory indexer
/// that only ever reads event data (never contract storage), then asserts the reconstructed Offer and
/// settlement state matches the on-chain truth from getOffer/getSecondaryEscrow.
contract DealManagerSecondaryTradeIndexerTest is Test {
    // ─────────────────────────────────────────────────────────────────────────
    // Off-chain indexer model — populated only from emitted logs
    // ─────────────────────────────────────────────────────────────────────────

    struct IdxOffer {
        bool exists;
        bytes32 offerId;         // from OfferPosted's indexed topic
        address offeror;
        address spvAddress;
        uint8 side;
        address certPrinter;
        uint256 tokenId;
        address paymentToken;
        uint256 units;
        uint256 consideration;
        uint8 exemptionPathway;
        uint256 validUntil;
        address integrator;
        uint8 status;            // OfferStatus
        uint256 unitsAccepted;
        uint256 paymentAccepted;
        uint256 unitsFinalized;
        bytes32[] settlementAgreementIds; // accumulated from each OfferAccepted (push-only, mirrors on-chain)
        bytes32 templateId;
        string buyerName;
        uint8 buyerHostingMode;
        address adminMultisig;
        bytes counterpartyRestrictions;
        address[] thresholdConditions;
        address[] closingConditions;
        // additionalTerms is intentionally not indexed (human/legal-read only, not emitted).
    }

    struct IdxSettlement {
        bool exists;
        bytes32 offerId;
        address counterparty;
        address paymentToken;
        uint256 paymentAmount;
        uint256 units;
        uint256 tokenId;         // seller's Ledger Entry Token (from OfferAccepted; acceptor-supplied for buy offers)
        uint256 expiry;          // escrow settlement deadline (agreementExpiry from OfferAccepted)
        string buyerName;        // per-settlement materialization (from OfferAccepted)
        uint8 buyerHostingMode;
        address adminMultisig;
        bytes openEndorsementSig; // per-settlement endorsement used (from OfferAccepted)
        uint8 status;            // SecondaryEscrowStatus
        address feeDestination;  // escrow routing: snapshotted from the offer's integrator
        address seller;          // from Finalized
        address buyer;           // from Finalized
        uint256 fee;             // realized total fee (from SecondaryFeeDistributed; 0 if none)
        uint256 integratorFee;
        uint256 platformFee;
        address creditedIntegrator; // realized fee recipient (zero = platform-only)
    }

    mapping(bytes32 => IdxOffer) internal idxOffers;
    mapping(bytes32 => IdxSettlement) internal idxSettlements;
    bytes32[] internal idxOfferIds;
    bytes32[] internal idxSettlementIds;

    // Event topic0 hashes taken straight from the declarations, so they can't drift from the emitted signatures.
    bytes32 immutable TOPIC_OFFER_POSTED = ISecondaryTradeStorage.OfferPosted.selector;
    bytes32 immutable TOPIC_OFFER_CANCELLED = ISecondaryTradeStorage.OfferCancelled.selector;
    bytes32 immutable TOPIC_OFFER_ACCEPTED = ISecondaryTradeStorage.OfferAccepted.selector;
    bytes32 immutable TOPIC_FINALIZED = ISecondaryTradeStorage.SecondaryTradeAgreementFinalized.selector;
    bytes32 immutable TOPIC_VOIDED = ISecondaryTradeStorage.SecondaryTradeAgreementVoided.selector;
    bytes32 immutable TOPIC_FEE = ISecondaryTradeStorage.SecondaryFeeDistributed.selector;

    // ─────────────────────────────────────────────────────────────────────────
    // Chain fixtures (mirrors DealManagerSecondaryTradeTest setUp)
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 constant corpSalt = keccak256("DealManagerSecondaryTradeIndexerTest.corp");

    address public owner;
    uint256 public ownerKey;
    address public seller;
    uint256 public sellerKey;
    address public buyer;
    uint256 public buyerKey;
    address public keeper;
    address public company;

    SecERC20Mock public paymentToken;
    SecCertPrinterMock public certPrinter;
    SecIssuanceManagerMock public im;
    CyberAgreementRegistry public registry;
    SecCorpMock public corp;
    DealManagerFactory public dmFactory;
    DealManager public dm;
    BorgAuth public auth;

    bytes32 public constant TEMPLATE_ID = bytes32(0);
    string public constant TEMPLATE_URI = "ipfs://secondary-template";

    uint256 public constant CONSIDERATION = 10 ether;
    uint256 public constant UNITS = 100;
    uint256 public sellerTokenId;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        keeper = makeAddr("keeper");
        company = makeAddr("company");

        paymentToken = new SecERC20Mock();
        certPrinter = new SecCertPrinterMock();
        im = new SecIssuanceManagerMock();
        corp = new SecCorpMock(company);

        auth = new BorgAuth(owner);

        registry = CyberAgreementRegistry(address(new ERC1967Proxy(
            address(new CyberAgreementRegistry()),
            abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
        )));
        vm.prank(owner);
        registry.createTemplate(TEMPLATE_ID, "Secondary", TEMPLATE_URI, new string[](0), new string[](0));

        dmFactory = DealManagerFactory(address(new ERC1967Proxy(
            address(new DealManagerFactory()),
            abi.encodeWithSelector(
                DealManagerFactory.initialize.selector, address(auth), address(new DealManager())
            )
        )));

        dm = DealManager(dmFactory.deployDealManager(corpSalt));
        dm.initialize(address(auth), address(corp), address(registry), address(im), address(dmFactory));

        vm.prank(seller);
        sellerTokenId = certPrinter.mint(seller);

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);

        paymentToken.mint(seller, CONSIDERATION * 10);
        vm.prank(seller);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Trade-lifecycle helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _defaultSellOfferParams() internal view returns (PostOfferParams memory p) {
        p = PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(certPrinter),
            tokenId: sellerTokenId,
            units: UNITS,
            paymentToken: address(paymentToken),
            consideration: CONSIDERATION,
            exemptionPathway: ExemptionPathway.SECTION_4A7,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: bytes32(0),
            salt: uint256(keccak256("indexerSellOffer")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            buyerName: "",
            buyerHostingMode: 0,
            adminMultisig: address(0)
        });
    }

    function _defaultBuyOfferParams() internal view returns (PostOfferParams memory p) {
        p = PostOfferParams({
            side: OfferSide.BUY,
            certPrinter: address(certPrinter),
            tokenId: 0,
            units: UNITS,
            paymentToken: address(paymentToken),
            consideration: CONSIDERATION,
            exemptionPathway: ExemptionPathway.SECTION_4A7,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: bytes32(0),
            salt: uint256(keccak256("indexerBuyOffer")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "",
            buyerName: "Test Buyer",
            buyerHostingMode: 0,
            adminMultisig: address(0)
        });
    }

    function _postSellOffer() internal returns (bytes32 offerId) {
        vm.prank(seller);
        offerId = dm.postOffer(_defaultSellOfferParams());
    }

    function _postBuyOffer() internal returns (bytes32 offerId) {
        vm.prank(buyer);
        offerId = dm.postOffer(_defaultBuyOfferParams());
    }

    function _acceptSellOfferPartial(bytes32 offerId, uint256 units) internal returns (bytes32 settlementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: units,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementId = dm.acceptOffer(p);
    }

    function _acceptBuyOfferPartial(bytes32 offerId, uint256 units) internal returns (bytes32 settlementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: units,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, seller, sellerKey),
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        settlementId = dm.acceptOffer(p);
    }

    function _voidSettlementBothParties(bytes32 settlementId) internal {
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");
        vm.prank(seller);
        dm.voidSecondaryTradeAgreement(settlementId, seller, "");
    }

    function _agreementSig(bytes32 agreementId, string[] memory partyValues, uint256 key)
        internal view returns (bytes memory)
    {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            TEMPLATE_URI,
            new string[](0),
            new string[](0),
            new string[](0),
            partyValues,
            key
        );
    }

    function _acceptorSig(bytes32 offerId, address acceptor, uint256 key) internal view returns (bytes memory) {
        Offer memory o = dm.getOffer(offerId);
        bytes32 settlementSalt = keccak256(abi.encodePacked(o.salt, o.settlementAgreementIds.length));
        address[] memory parties = new address[](2);
        parties[0] = o.offeror;
        parties[1] = acceptor;
        bytes32 settlementId = keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties));
        return _agreementSig(settlementId, new string[](0), key);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // The indexer — consumes logs only
    // ─────────────────────────────────────────────────────────────────────────

    function _index(Vm.Log[] memory logs) internal {
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            // Only this DealManager's secondary-trade events; everything else (ERC20, registry, …) is ignored.
            if (log.emitter != address(dm) || log.topics.length == 0) continue;
            bytes32 topic = log.topics[0];
            if (topic == TOPIC_OFFER_POSTED) _handleOfferPosted(log);
            else if (topic == TOPIC_OFFER_ACCEPTED) _handleOfferAccepted(log);
            else if (topic == TOPIC_OFFER_CANCELLED) _handleOfferCancelled(log);
            else if (topic == TOPIC_FINALIZED) _handleFinalized(log);
            else if (topic == TOPIC_VOIDED) _handleVoided(log);
            else if (topic == TOPIC_FEE) _handleFee(log);
        }
    }

    function _addr(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function _handleOfferPosted(Vm.Log memory log) private {
        bytes32 offerId = log.topics[1];
        IdxOffer storage o = idxOffers[offerId];
        require(!o.exists, "indexer: offer posted twice");

        // Decode the flat OfferPosted data tuple straight into the offer record (order matches the event).
        (
            o.spvAddress, o.side, o.tokenId, o.units, o.paymentToken, o.consideration,
            o.exemptionPathway, o.validUntil, o.integrator, o.templateId, o.buyerName,
            o.buyerHostingMode, o.adminMultisig, o.counterpartyRestrictions,
            o.thresholdConditions, o.closingConditions
        ) = abi.decode(
            log.data,
            (address, uint8, uint256, uint256, address, uint256, uint8, uint256, address,
             bytes32, string, uint8, address, bytes, address[], address[])
        );

        o.exists = true;
        o.offerId = offerId;
        o.offeror = _addr(log.topics[2]);
        o.certPrinter = _addr(log.topics[3]);
        o.status = uint8(OfferStatus.LIVE);
        idxOfferIds.push(offerId);
    }

    function _handleOfferAccepted(Vm.Log memory log) private {
        bytes32 offerId = log.topics[1];
        bytes32 settlementId = log.topics[2];
        address acceptor = _addr(log.topics[3]);
        (uint256 units, address payToken, uint256 paymentAmount, uint256 tokenId, uint256 expiry,
         string memory buyerName, uint8 buyerHostingMode, address adminMultisig, bytes memory openEndorsementSig) =
            abi.decode(log.data, (uint256, address, uint256, uint256, uint256, string, uint8, address, bytes));

        IdxSettlement storage s = idxSettlements[settlementId];
        require(!s.exists, "indexer: settlement accepted twice");
        s.exists = true;
        s.offerId = offerId;
        s.counterparty = acceptor;
        s.paymentToken = payToken;
        s.paymentAmount = paymentAmount;
        s.units = units;
        s.tokenId = tokenId;
        s.expiry = expiry;
        s.buyerName = buyerName;
        s.buyerHostingMode = buyerHostingMode;
        s.adminMultisig = adminMultisig;
        s.openEndorsementSig = openEndorsementSig;
        s.status = uint8(SecondaryEscrowStatus.ACCEPTED);
        idxSettlementIds.push(settlementId);

        IdxOffer storage o = idxOffers[offerId];
        o.settlementAgreementIds.push(settlementId);
        // escrow.feeDestination is snapshotted from the offer's resolved integrator at acceptance.
        s.feeDestination = o.integrator;
        o.unitsAccepted += units;
        o.paymentAccepted += paymentAmount;
        o.status = o.unitsAccepted >= o.units
            ? uint8(OfferStatus.FULLY_ACCEPTED)
            : uint8(OfferStatus.PARTIALLY_ACCEPTED);
    }

    function _handleOfferCancelled(Vm.Log memory log) private {
        idxOffers[log.topics[1]].status = uint8(OfferStatus.CANCELLED);
    }

    function _handleFinalized(Vm.Log memory log) private {
        bytes32 agreementId = log.topics[1];
        (address sellerAddr, address buyerAddr, uint256 units, uint256 consideration) =
            abi.decode(log.data, (address, address, uint256, uint256));

        IdxSettlement storage s = idxSettlements[agreementId];
        s.status = uint8(SecondaryEscrowStatus.FINALIZED);
        s.seller = sellerAddr;
        s.buyer = buyerAddr;
        // Cross-event consistency: the finalized units/consideration must equal the funded settlement.
        require(units == s.units, "indexer: finalized units mismatch");
        require(consideration == s.paymentAmount, "indexer: finalized consideration mismatch");

        IdxOffer storage o = idxOffers[s.offerId];
        o.unitsFinalized += s.units;
        if (o.status != uint8(OfferStatus.CANCELLED) && o.unitsFinalized == o.units) {
            o.status = uint8(OfferStatus.FINALIZED);
        }
    }

    function _handleVoided(Vm.Log memory log) private {
        bytes32 agreementId = log.topics[1];
        IdxSettlement storage s = idxSettlements[agreementId];
        s.status = uint8(SecondaryEscrowStatus.VOIDED);

        IdxOffer storage o = idxOffers[s.offerId];
        o.unitsAccepted -= s.units;
        o.paymentAccepted -= s.paymentAmount;
        if (o.status != uint8(OfferStatus.CANCELLED) && o.status != uint8(OfferStatus.FINALIZED)) {
            o.status = o.unitsAccepted == 0 ? uint8(OfferStatus.LIVE) : uint8(OfferStatus.PARTIALLY_ACCEPTED);
        }
    }

    function _handleFee(Vm.Log memory log) private {
        IdxSettlement storage s = idxSettlements[log.topics[1]];
        s.creditedIntegrator = _addr(log.topics[3]);
        (s.fee, s.integratorFee, s.platformFee) = abi.decode(log.data, (uint256, uint256, uint256));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reconstruction assertions — indexer state vs on-chain truth
    // ─────────────────────────────────────────────────────────────────────────

    function _assertOfferReconstructed(bytes32 offerId) internal view {
        IdxOffer storage o = idxOffers[offerId];
        Offer memory c = dm.getOffer(offerId);
        assertTrue(o.exists, "offer reconstructed from logs");
        assertEq(o.offerId, c.offerId, "offerId");
        assertEq(o.offeror, c.offeror, "offeror");
        assertEq(o.spvAddress, c.spvAddress, "spvAddress");
        assertEq(o.side, uint8(c.side), "side");
        assertEq(o.certPrinter, c.certPrinter, "certPrinter");
        assertEq(o.tokenId, c.tokenId, "tokenId");
        assertEq(o.paymentToken, c.paymentToken, "paymentToken");
        assertEq(o.units, c.units, "units");
        assertEq(o.consideration, c.consideration, "consideration");
        assertEq(o.exemptionPathway, uint8(c.exemptionPathway), "exemptionPathway");
        assertEq(o.validUntil, c.validUntil, "validUntil");
        assertEq(o.integrator, c.integrator, "integrator");
        assertEq(o.status, uint8(c.status), "offer status");
        assertEq(o.unitsAccepted, c.unitsAccepted, "unitsAccepted");
        assertEq(o.paymentAccepted, c.paymentAccepted, "paymentAccepted");
        assertEq(o.unitsFinalized, c.unitsFinalized, "unitsFinalized");
        assertEq(o.settlementAgreementIds.length, c.settlementAgreementIds.length, "settlementAgreementIds length");
        for (uint256 i = 0; i < o.settlementAgreementIds.length; i++) {
            assertEq(o.settlementAgreementIds[i], c.settlementAgreementIds[i], "settlementAgreementId");
        }
        assertEq(o.templateId, c.templateId, "templateId");
        assertEq(o.buyerName, c.buyerName, "buyerName");
        assertEq(o.buyerHostingMode, c.buyerHostingMode, "buyerHostingMode");
        assertEq(o.adminMultisig, c.adminMultisig, "adminMultisig");
        assertEq(o.counterpartyRestrictions, c.counterpartyRestrictions, "counterpartyRestrictions");
        assertEq(o.thresholdConditions.length, c.thresholdConditions.length, "thresholdConditions length");
        for (uint256 i = 0; i < o.thresholdConditions.length; i++) {
            assertEq(o.thresholdConditions[i], c.thresholdConditions[i], "thresholdCondition");
        }
        assertEq(o.closingConditions.length, c.closingConditions.length, "closingConditions length");
        for (uint256 i = 0; i < o.closingConditions.length; i++) {
            assertEq(o.closingConditions[i], c.closingConditions[i], "closingCondition");
        }
    }

    function _assertSettlementReconstructed(bytes32 settlementId) internal view {
        IdxSettlement storage s = idxSettlements[settlementId];
        SecondaryEscrow memory c = dm.getSecondaryEscrow(settlementId);
        assertTrue(s.exists, "settlement reconstructed from logs");
        assertEq(s.offerId, c.offerId, "settlement offerId backlink");
        assertEq(s.counterparty, c.counterparty, "settlement counterparty");
        assertEq(s.paymentToken, c.paymentToken, "settlement paymentToken");
        assertEq(s.paymentAmount, c.paymentAmount, "settlement paymentAmount");
        assertEq(s.units, c.units, "settlement units");
        assertEq(s.tokenId, c.tokenId, "settlement tokenId");
        assertEq(s.expiry, c.expiry, "settlement expiry");
        assertEq(s.buyerName, c.buyerName, "settlement buyerName");
        assertEq(s.buyerHostingMode, c.buyerHostingMode, "settlement buyerHostingMode");
        assertEq(s.adminMultisig, c.adminMultisig, "settlement adminMultisig");
        assertEq(s.openEndorsementSig, c.openEndorsementSig, "settlement openEndorsementSig");
        assertEq(s.status, uint8(c.status), "settlement status");
        assertEq(s.feeDestination, c.feeDestination, "settlement feeDestination");
    }

    /// @dev Asserts the settlement's Finalized/Fee-derived fields (no on-chain counterpart) match expected
    /// values. All zero for a settlement that never finalized (ACCEPTED/VOIDED).
    function _assertSettlementDerived(
        bytes32 settlementId,
        address expectedSeller,
        address expectedBuyer,
        uint256 expectedFee,
        uint256 expectedIntegratorFee,
        uint256 expectedPlatformFee,
        address expectedCreditedIntegrator
    ) internal view {
        IdxSettlement storage s = idxSettlements[settlementId];
        assertEq(s.seller, expectedSeller, "settlement seller");
        assertEq(s.buyer, expectedBuyer, "settlement buyer");
        assertEq(s.fee, expectedFee, "settlement fee");
        assertEq(s.integratorFee, expectedIntegratorFee, "settlement integratorFee");
        assertEq(s.platformFee, expectedPlatformFee, "settlement platformFee");
        assertEq(s.creditedIntegrator, expectedCreditedIntegrator, "settlement creditedIntegrator");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenarios
    // ─────────────────────────────────────────────────────────────────────────

    // SELL offer, two partial fills, finalize one lot, void the other: walks LIVE → PARTIALLY_ACCEPTED →
    // FULLY_ACCEPTED and back to PARTIALLY_ACCEPTED, with one FINALIZED and one VOIDED settlement — all
    // reconstructed from OfferPosted / OfferAccepted / Finalized / Voided alone.
    function test_Indexer_SellLifecycle_PostAcceptFinalizeVoid() public {
        uint256 unitsA = 40;
        uint256 unitsB = 60;

        vm.recordLogs();
        bytes32 offerId = _postSellOffer();
        bytes32 lotA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 lotB = _acceptSellOfferPartial(offerId, unitsB);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotA);
        _voidSettlementBothParties(lotB);

        _index(vm.getRecordedLogs());

        // Exactly the offer and two settlements were discovered from the logs.
        assertEq(idxOfferIds.length, 1, "one offer indexed");
        assertEq(idxSettlementIds.length, 2, "two settlements indexed");

        // Reconstructed status matches chain truth field-by-field.
        _assertOfferReconstructed(offerId);
        _assertSettlementReconstructed(lotA);
        _assertSettlementReconstructed(lotB);
        // lot A finalized (no fee configured → fee fields zero); lot B voided, so its derived fields stay zero.
        _assertSettlementDerived(lotA, seller, buyer, 0, 0, 0, address(0));
        _assertSettlementDerived(lotB, address(0), address(0), 0, 0, 0, address(0));

        // Spell out the end state the indexer derived, purely for documentation.
        assertEq(idxOffers[offerId].status, uint8(OfferStatus.PARTIALLY_ACCEPTED), "offer back to PARTIALLY_ACCEPTED");
        assertEq(idxOffers[offerId].unitsAccepted, unitsA, "only the finalized lot's units stay accepted");
        assertEq(idxOffers[offerId].unitsFinalized, unitsA, "one lot finalized");
        assertEq(idxSettlements[lotA].status, uint8(SecondaryEscrowStatus.FINALIZED), "lot A FINALIZED");
        assertEq(idxSettlements[lotB].status, uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED");
    }

    // BUY offer counterpart of the sell lifecycle: two partial fills (driven from the seller side),
    // finalize one lot, void the other — same LIVE → PARTIALLY_ACCEPTED → FULLY_ACCEPTED → PARTIALLY_ACCEPTED
    // walk, reconstructed from OfferPosted / OfferAccepted / Finalized / Voided alone.
    function test_Indexer_BuyLifecycle_PostAcceptFinalizeVoid() public {
        uint256 unitsA = 40;
        uint256 unitsB = 60;

        vm.recordLogs();
        bytes32 offerId = _postBuyOffer();
        bytes32 lotA = _acceptBuyOfferPartial(offerId, unitsA);
        bytes32 lotB = _acceptBuyOfferPartial(offerId, unitsB);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotA);
        _voidSettlementBothParties(lotB);

        _index(vm.getRecordedLogs());

        // Exactly the offer and two settlements were discovered from the logs.
        assertEq(idxOfferIds.length, 1, "one offer indexed");
        assertEq(idxSettlementIds.length, 2, "two settlements indexed");

        // Reconstructed status matches chain truth field-by-field.
        _assertOfferReconstructed(offerId);
        _assertSettlementReconstructed(lotA);
        _assertSettlementReconstructed(lotB);
        // lot A finalized (no fee configured → fee fields zero); lot B voided, so its derived fields stay zero.
        _assertSettlementDerived(lotA, seller, buyer, 0, 0, 0, address(0));
        _assertSettlementDerived(lotB, address(0), address(0), 0, 0, 0, address(0));

        // Spell out the end state the indexer derived, purely for documentation.
        assertEq(idxOffers[offerId].side, uint8(OfferSide.BUY), "buy side reconstructed");
        assertEq(idxOffers[offerId].status, uint8(OfferStatus.PARTIALLY_ACCEPTED), "offer back to PARTIALLY_ACCEPTED");
        assertEq(idxOffers[offerId].unitsAccepted, unitsA, "only the finalized lot's units stay accepted");
        assertEq(idxOffers[offerId].unitsFinalized, unitsA, "one lot finalized");
        assertEq(idxSettlements[lotA].status, uint8(SecondaryEscrowStatus.FINALIZED), "lot A FINALIZED");
        assertEq(idxSettlements[lotB].status, uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED");
    }

    // SELL offer counterpart of the buy offer cancel: one partial fill, then cancel — the committed lot stays
    // ACCEPTED while the offer goes CANCELLED, reconstructed from OfferPosted / OfferAccepted / OfferCancelled.
    function test_Indexer_SellLifecycle_PostAcceptCancel() public {
        uint256 units = 40;

        vm.recordLogs();
        bytes32 offerId = _postSellOffer();
        bytes32 lot = _acceptSellOfferPartial(offerId, units);
        vm.prank(seller);
        dm.cancelOffer(offerId);

        _index(vm.getRecordedLogs());

        assertEq(idxOfferIds.length, 1, "one offer indexed");
        assertEq(idxSettlementIds.length, 1, "one settlement indexed");

        _assertOfferReconstructed(offerId);
        _assertSettlementReconstructed(lot);
        _assertSettlementDerived(lot, address(0), address(0), 0, 0, 0, address(0)); // never finalized

        assertEq(idxOffers[offerId].side, uint8(OfferSide.SELL), "sell side reconstructed");
        assertEq(idxOffers[offerId].status, uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(idxOffers[offerId].unitsAccepted, units, "committed lot still counted after cancel");
        assertEq(idxSettlements[lot].status, uint8(SecondaryEscrowStatus.ACCEPTED), "committed lot survives cancel");
    }

    // BUY offer, one partial fill, then cancel: the committed lot stays ACCEPTED while the offer goes
    // CANCELLED — reconstructed from OfferPosted / OfferAccepted / OfferCancelled.
    function test_Indexer_BuyLifecycle_PostAcceptCancel() public {
        uint256 units = 40;

        vm.recordLogs();
        bytes32 offerId = _postBuyOffer();
        bytes32 lot = _acceptBuyOfferPartial(offerId, units);
        vm.prank(buyer);
        dm.cancelOffer(offerId);

        _index(vm.getRecordedLogs());

        assertEq(idxOfferIds.length, 1, "one offer indexed");
        assertEq(idxSettlementIds.length, 1, "one settlement indexed");

        _assertOfferReconstructed(offerId);
        _assertSettlementReconstructed(lot);
        _assertSettlementDerived(lot, address(0), address(0), 0, 0, 0, address(0)); // never finalized

        assertEq(idxOffers[offerId].side, uint8(OfferSide.BUY), "buy side reconstructed");
        assertEq(idxOffers[offerId].status, uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(idxOffers[offerId].unitsAccepted, units, "committed lot still counted after cancel");
        assertEq(idxSettlements[lot].status, uint8(SecondaryEscrowStatus.ACCEPTED), "committed lot survives cancel");
    }

    // Non-zero fee finalize: the realized integrator/platform split is reconstructed from
    // SecondaryFeeDistributed alone and cross-checked against on-chain balances.
    function test_Indexer_FeeSplit_FromEventsAlone() public {
        address integrator = makeAddr("integrator");
        address platform = makeAddr("platform");

        vm.prank(owner);
        dmFactory.setIntegrator(integrator, true, 3000); // 30% of the fee to the integrator
        vm.prank(owner);
        dmFactory.setDefaultFeeRatio(1000); // 10% ticket fee
        vm.prank(owner);
        dmFactory.setPlatformPayable(platform);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Indexer_FeeSplit_FromEventsAlone"));
        p.integrator = integrator;

        vm.recordLogs();
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        AcceptOfferParams memory ap = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId = dm.acceptOffer(ap);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        _index(vm.getRecordedLogs());

        // Offer and settlement reconstruct, including the integrator captured at post time.
        _assertOfferReconstructed(offerId);
        _assertSettlementReconstructed(settlementId);
        assertEq(idxOffers[offerId].integrator, integrator, "integrator captured from OfferPosted");
        assertEq(idxOffers[offerId].status, uint8(OfferStatus.FINALIZED), "offer FINALIZED");

        // The fee split reconstructed from the event alone.
        uint256 fee = CONSIDERATION * 1000 / 10000; // 1 ether
        uint256 expectedIntegratorFee = fee * 3000 / 10000; // 0.3 ether
        uint256 expectedPlatformFee = fee - expectedIntegratorFee; // 0.7 ether
        // Sell offer finalized with a fee: seller=offeror, buyer=acceptor, split credited to the integrator.
        _assertSettlementDerived(settlementId, seller, buyer, fee, expectedIntegratorFee, expectedPlatformFee, integrator);

        IdxSettlement storage s = idxSettlements[settlementId];
        assertEq(s.integratorFee + s.platformFee, s.fee, "split sums to total");

        // Events agree with reality.
        assertEq(paymentToken.balanceOf(integrator), s.integratorFee, "integrator balance == reconstructed fee");
        assertEq(paymentToken.balanceOf(platform), s.platformFee, "platform balance == reconstructed fee");
    }
}
