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

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {ISecondaryTradeStorage} from "../src/interfaces/ISecondaryTradeStorage.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    Offer,
    OfferSide,
    OfferStatus,
    PostOfferParams,
    SecondaryEscrow,
    SecondaryEscrowStatus
} from "../src/storage/SecondaryTradeStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
// Real contract stack for the IssuanceManager + CyberCertPrinter side.
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CertificateDetails, ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
// Reuse the payment-token mock and the minimal CyberCorp / uriBuilder fixtures from sibling test files.
import {SecERC20Mock} from "./DealManagerSecondaryTradeTest.t.sol";
import {
    MockCyberCorpForIM,
    MockUriBuilderForIM
} from "./IssuanceManagerTest.t.sol";

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
        bytes32 offerId; // from OfferPosted's indexed topic
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
        uint8 status; // OfferStatus
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
        uint256 tokenId; // seller's Ledger Entry Token (from OfferAccepted; acceptor-supplied for buy offers)
        uint256 expiry; // escrow settlement deadline (agreementExpiry from OfferAccepted)
        string buyerName; // per-settlement materialization (from OfferAccepted)
        uint8 buyerHostingMode;
        address adminMultisig;
        bytes openEndorsementSig; // per-settlement endorsement used (from OfferAccepted)
        uint8 status; // SecondaryEscrowStatus
        address feeDestination; // escrow routing: snapshotted from the offer's integrator
        address seller; // from Finalized
        address buyer; // from Finalized
        uint256 fee; // realized total fee (from SecondaryFeeDistributed; 0 if none)
        uint256 integratorFee;
        uint256 platformFee;
        address creditedIntegrator; // realized fee recipient (zero = platform-only)
        // Stock-ledger columns, populated from SecondaryTransferExecuted (emitted by the IssuanceManager).
        bool transferred; // a secondary-transfer fired for this settlement
        uint256 surrenderedTokenId; // seller's Ledger Entry Token (CERTIFICATES SURRENDERED → CERTIF NO.)
        uint256 issuedTokenId; // buyer's newly minted Ledger Entry Token (CERTIFICATES ISSUED → CERTIF NO.)
        bool sellerVoided; // full sale (seller cert voided) vs partial (decremented)
    }

    // Per-certificate issuance row — one per minted Ledger Entry Token, whether a primary issue or a
    // secondary-trade mint. Together with sharesHeld this turns the settlement log into a full stock-transfer
    // ledger: issuance rows open positions, SecondaryTransferExecuted moves them between holders.
    struct IdxIssuance {
        bool exists;
        uint256 tokenId; // CERTIFICATES ISSUED → CERTIF NO.
        address holder; // registered owner at mint (NAME OF SHAREHOLDER, address) — from CertificateAssigned
        string holderName; // registered owner name at mint — from CertificateAssigned
        uint256 units; // NO. OF SHARES — from CertificateCreated.details.unitsRepresented
        address certPrinter;
        bool originalIssue; // true until a SecondaryTransferExecuted claims this as a buyer's new cert
    }

    // A row of the Stock Transfer Ledger itself — the column set a Delaware corporation keeps, minus the
    // shareholder's off-chain mailing address and the tax-stamp value (neither lives on chain). One row per
    // certificate: opened from the issuance (CERTIFICATES ISSUED side + the new holder's running balance),
    // then enriched with the surrender side from the matching SecondaryTransferExecuted.
    struct IdxLedgerRow {
        uint256 rowNo; // NO. (sequential)
        bool originalIssue; // FROM WHOM — "If Original Issue Enter As Such"
        string shareholderName; // NAME OF SHAREHOLDER (the issuee/new holder)
        address shareholder; // new holder (TO WHOM TRANSFERRED); off-chain ADDRESS intentionally omitted
        uint256 issuedCertNo; // CERTIFICATES ISSUED → CERTIF NO.
        uint256 issuedShares; // CERTIFICATES ISSUED → NO. OF SHARES
        address fromWhom; // FROM WHOM TRANSFERRED (seller); 0 for an original issue
        uint256 amountPaid; // AMOUNT PAID THEREON
        address paymentToken; // token the consideration was paid in
        uint256 surrenderedCertNo; // CERTIFICATES SURRENDERED → CERTIF NO. (0 for an original issue)
        uint256 surrenderedShares; // CERTIFICATES SURRENDERED → NO. SHARES
        bool sellerVoided; // full (voided) vs partial (decremented) surrender
        uint256 sharesHeldByShareholder; // NUMBER OF SHARES HELD (issued side) — new holder's balance after this row
        uint256 sharesHeldBySeller; // NUMBER OF SHARES HELD (surrender side) — seller's balance after this row; 0 for an original issue
        uint256 transferDate; // DATE OF TRANSFER (index-time block timestamp; a real indexer reads the log's)
    }

    mapping(bytes32 => IdxOffer) internal idxOffers;
    mapping(bytes32 => IdxSettlement) internal idxSettlements;
    mapping(uint256 => IdxIssuance) internal idxIssuances;
    IdxLedgerRow[] internal idxTransferLedger;
    bytes32[] internal idxOfferIds;
    bytes32[] internal idxSettlementIds;
    uint256[] internal idxIssuedTokenIds;
    mapping(address => uint256) internal sharesHeld; // NUMBER OF SHARES HELD (running per-holder balance)
    // +1-based row slots into idxTransferLedger (0 == absent), keyed by tokenId for the internal open→enrich
    // linkage. Reads address the ledger by row index directly.
    mapping(uint256 => uint256) internal idxLedgerRowByToken;

    // Event topic0 hashes taken straight from the declarations, so they can't drift from the emitted signatures.
    bytes32 immutable TOPIC_OFFER_POSTED = ISecondaryTradeStorage.OfferPosted.selector;
    bytes32 immutable TOPIC_OFFER_CANCELLED = ISecondaryTradeStorage.OfferCancelled.selector;
    bytes32 immutable TOPIC_OFFER_ACCEPTED = ISecondaryTradeStorage.OfferAccepted.selector;
    bytes32 immutable TOPIC_FINALIZED = ISecondaryTradeStorage.SecondaryTradeAgreementFinalized.selector;
    bytes32 immutable TOPIC_VOIDED = ISecondaryTradeStorage.SecondaryTradeAgreementVoided.selector;
    bytes32 immutable TOPIC_FEE = ISecondaryTradeStorage.SecondaryFeeDistributed.selector;
    // Emitted by the IssuanceManager (not the DealManager), so the indexer also watches that emitter.
    bytes32 immutable TOPIC_SECONDARY_TRANSFER = IIssuanceManager.SecondaryTransferExecuted.selector;
    // Primary/secondary mint events that seed the issuance rows + shares-held balance. CertificateCreated
    // (units, emitter = IssuanceManager) is paired with CertificateAssigned (holder, emitter = CyberCertPrinter).
    bytes32 immutable TOPIC_CERT_CREATED = IIssuanceManager.CertificateCreated.selector;
    bytes32 immutable TOPIC_CERT_ASSIGNED = ICyberCertPrinter.CertificateAssigned.selector;

    // ─────────────────────────────────────────────────────────────────────────
    // Chain fixtures (mirrors DealManagerSecondaryTradeTest setUp)
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 constant corpSalt = keccak256("DealManagerSecondaryTradeIndexerTest.corp");

    bytes32 constant imSalt = keccak256("DealManagerSecondaryTradeIndexerTest.im");

    address public owner;
    uint256 public ownerKey;
    address public seller;
    uint256 public sellerKey;
    address public buyer;
    uint256 public buyerKey;
    address public keeper;

    SecERC20Mock public paymentToken;
    ICyberCertPrinter public certPrinter;
    IssuanceManager public im;
    CyberAgreementRegistry public registry;
    MockCyberCorpForIM public corp;
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

        paymentToken = new SecERC20Mock();
        auth = new BorgAuth(owner);
        corp = new MockCyberCorpForIM();

        // Real IssuanceManager + CyberCertPrinter, deployed through the IssuanceManagerFactory beacon stack
        // (mirrors IssuanceManagerSecondaryTransferTest), so the secondary-transfer logs are the real ones.
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
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
        im = IssuanceManager(imFactory.deployIssuanceManager(imSalt));
        im.initialize(address(auth), address(corp), address(new MockUriBuilderForIM()), address(imFactory));

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        vm.prank(owner);
        registry.createTemplate(TEMPLATE_ID, "Secondary", TEMPLATE_URI, new string[](0), new string[](0));

        dmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new DealManagerFactory()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector, address(auth), address(new DealManager())
                    )
                )
            )
        );

        dm = DealManager(dmFactory.deployDealManager(corpSalt));
        dm.initialize(address(auth), address(corp), address(registry), address(im), address(dmFactory));
        // The DealManager invokes the IssuanceManager's owner-gated reservation and secondary-transfer
        // entry points, so it needs the same role the real onboarding grants it.
        vm.prank(owner);
        auth.updateRole(address(dm), 99);

        // Real seller Ledger Entry Token, minted through the IssuanceManager with UNITS represented.
        // Record the primary-issuance logs and index them, so the ledger opens with the original-issue row
        // (the seller's founding cert) and the shares-held baseline before any secondary trading.
        vm.recordLogs();
        vm.startPrank(owner);
        certPrinter = ICyberCertPrinter(
            im.createCertPrinter(
                new string[](0),
                "Indexer Cert",
                "ICERT",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
        sellerTokenId =
            im.createCertAndAssignWithName(address(certPrinter), seller, _sellerCertDetails(UNITS), "Alice", "", block.timestamp);
        vm.stopPrank();
        _index(vm.getRecordedLogs());

        // The ledger must open with the original-issue row — the founding grant, before any trading:
        //
        //  NO. |              CERTIFICATE ISSUED              |              CERTIFICATE SURRENDERED
        //      | SHAREHOLDER | CERT# | SHARES | HELD |  PAID  | FROM WHOM       | CERT# | SHARES | VOIDED? | HELD
        // -----+-------------+-------+--------+------+--------+-----------------+-------+--------+---------+-----
        //   0  | Alice       |   0   |  100   | 100  |   0    | — (orig. issue) |   —   |   0    |   no    |  —
        _assertLedgerRow(0, true, seller, "Alice", sellerTokenId, UNITS, address(0), 0, 0, false, 0, address(0), UNITS, 0);

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);

        paymentToken.mint(seller, CONSIDERATION * 10);
        vm.prank(seller);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    function _sellerCertDetails(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: bytes("")
        });
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
            buyerHostingMode: HostingMode.DIRECT,
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
            buyerHostingMode: HostingMode.DIRECT,
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
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementId = dm.acceptOffer(p);
    }

    function _acceptSellOfferPartialAdministered(bytes32 offerId, uint256 units, address adminMultisig)
        internal
        returns (bytes32 settlementId)
    {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: units,
            buyerName: "Bob",
            buyerHostingMode: HostingMode.ADMINISTERED,
            adminMultisig: adminMultisig,
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
            buyerHostingMode: HostingMode.DIRECT,
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
        internal
        view
        returns (bytes memory)
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
            // The DealManager's offer/settlement events, the IssuanceManager's secondary-transfer and
            // certificate-creation events, and the CyberCertPrinter's assignment events; everything else
            // (ERC20, registry, …) is ignored.
            if (
                (log.emitter != address(dm) && log.emitter != address(im) && log.emitter != address(certPrinter))
                    || log.topics.length == 0
            ) continue;
            bytes32 topic = log.topics[0];
            if (topic == TOPIC_OFFER_POSTED) _handleOfferPosted(log);
            else if (topic == TOPIC_OFFER_ACCEPTED) _handleOfferAccepted(log);
            else if (topic == TOPIC_OFFER_CANCELLED) _handleOfferCancelled(log);
            else if (topic == TOPIC_FINALIZED) _handleFinalized(log);
            else if (topic == TOPIC_VOIDED) _handleVoided(log);
            else if (topic == TOPIC_FEE) _handleFee(log);
            else if (topic == TOPIC_SECONDARY_TRANSFER) _handleSecondaryTransfer(log);
            else if (topic == TOPIC_CERT_ASSIGNED) _handleCertificateAssigned(log);
            else if (topic == TOPIC_CERT_CREATED) _handleCertificateCreated(log);
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
            o.spvAddress,
            o.side,
            o.tokenId,
            o.units,
            o.paymentToken,
            o.consideration,
            o.exemptionPathway,
            o.validUntil,
            o.integrator,
            o.templateId,
            o.buyerName,
            o.buyerHostingMode,
            o.adminMultisig,
            o.counterpartyRestrictions,
            o.thresholdConditions,
            o.closingConditions
        ) =
            abi.decode(
                log.data,
                (
                    address,
                    uint8,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    uint8,
                    uint256,
                    address,
                    bytes32,
                    string,
                    uint8,
                    address,
                    bytes,
                    address[],
                    address[]
                )
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
        (
            uint256 units,
            address payToken,
            uint256 paymentAmount,
            uint256 tokenId,
            uint256 expiry,
            string memory buyerName,
            uint8 buyerHostingMode,
            address adminMultisig,
            bytes memory openEndorsementSig
        ) = abi.decode(log.data, (uint256, address, uint256, uint256, uint256, string, uint8, address, bytes));

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
        o.status =
            o.unitsAccepted >= o.units ? uint8(OfferStatus.FULLY_ACCEPTED) : uint8(OfferStatus.PARTIALLY_ACCEPTED);
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

    function _handleSecondaryTransfer(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=agreementId, [2]=certPrinter, [3]=buyer
        IdxSettlement storage s = idxSettlements[log.topics[1]];
        address buyerAddr = _addr(log.topics[3]);
        // data: sellerTokenId, buyerTokenId, seller, units, sellerUnitsAfter, buyerUnitsAfter, sellerVoided, buyerTokenIsMinted
        (uint256 surrenderedTokenId, uint256 issuedTokenId, address sellerAddr, uint256 units,,, bool sellerVoided, bool buyerTokenIsMinted) =
            abi.decode(log.data, (uint256, uint256, address, uint256, uint256, uint256, bool, bool));
        s.transferred = true;
        s.surrenderedTokenId = surrenderedTokenId;
        s.issuedTokenId = issuedTokenId;
        s.sellerVoided = sellerVoided;
        // NUMBER OF SHARES HELD: the seller surrenders `units` on every fill.
        sharesHeld[sellerAddr] -= units;

        uint256 slot = idxLedgerRowByToken[issuedTokenId];
        require(slot != 0, "indexer: transfer before issuance");

        if (buyerTokenIsMinted) {
            // The cert was just minted for this fill (a fresh secondary issue): update the row
            // CertificateCreated created first (with buyer info) with the SURRENDER side info, turning a
            // presumed primary issuance into a secondary transfer.
            idxIssuances[issuedTokenId].originalIssue = false;
            IdxLedgerRow storage r = idxTransferLedger[slot - 1];
            r.originalIssue = false;
            r.fromWhom = sellerAddr;
            r.surrenderedCertNo = surrenderedTokenId;
            r.surrenderedShares = units;
            r.sellerVoided = sellerVoided;
            r.amountPaid = s.paymentAmount;
            r.paymentToken = s.paymentToken;
            r.sharesHeldBySeller = sharesHeld[sellerAddr];
        } else {
            // Accumulation into a pre-existing cert — the buyer's earlier secondary cert OR their pre-existing
            // PRIMARY cert: no new cert was minted (so no CertificateCreated credited the buyer) and the
            // existing issue row keeps its original-issue status, but the units still moved — open a fresh
            // transfer row onto the same issued cert number and credit the buyer here.
            sharesHeld[buyerAddr] += units;
            uint256 rowIndex = idxTransferLedger.length;
            idxTransferLedger.push(
                IdxLedgerRow({
                    rowNo: rowIndex,
                    originalIssue: false,
                    shareholderName: s.buyerName,
                    shareholder: buyerAddr,
                    issuedCertNo: issuedTokenId,
                    issuedShares: units,
                    fromWhom: sellerAddr,
                    amountPaid: s.paymentAmount,
                    paymentToken: s.paymentToken,
                    surrenderedCertNo: surrenderedTokenId,
                    surrenderedShares: units,
                    sellerVoided: sellerVoided,
                    sharesHeldByShareholder: sharesHeld[buyerAddr],
                    sharesHeldBySeller: sharesHeld[sellerAddr],
                    transferDate: block.timestamp
                })
            );
        }
    }

    function _handleCertificateAssigned(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=tokenId, [2]=newOwner; data: (newOwnerName, issuerName). Fires before the
        // paired CertificateCreated, so it stashes the holder for that handler to credit.
        uint256 tokenId = uint256(log.topics[1]);
        (string memory ownerName,) = abi.decode(log.data, (string, string));
        IdxIssuance storage iss = idxIssuances[tokenId];
        iss.holder = _addr(log.topics[2]);
        iss.holderName = ownerName;
    }

    function _handleCertificateCreated(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=tokenId, [2]=certificate; data: (amount, cap, CertificateDetails).
        uint256 tokenId = uint256(log.topics[1]);
        (,, CertificateDetails memory details) = abi.decode(log.data, (uint256, uint256, CertificateDetails));
        IdxIssuance storage iss = idxIssuances[tokenId];
        // The primary-issue path emits CertificateCreated twice for the same cert; credit/record it once.
        if (iss.exists) return;
        iss.exists = true;
        iss.tokenId = tokenId;
        iss.certPrinter = _addr(log.topics[2]);
        iss.units = details.unitsRepresented;
        iss.originalIssue = true; // flipped to false if a later SecondaryTransferExecuted claims this cert
        idxIssuedTokenIds.push(tokenId);
        sharesHeld[iss.holder] += details.unitsRepresented;

        // Open the Stock Transfer Ledger row for this cert: the CERTIFICATES ISSUED side and the holder's
        // running balance. A secondary mint's row is later enriched with the surrender side; an original issue
        // stays a standalone opening row.
        uint256 rowIndex = idxTransferLedger.length;
        idxLedgerRowByToken[tokenId] = rowIndex + 1;
        idxTransferLedger.push(
            IdxLedgerRow({
                rowNo: rowIndex,
                originalIssue: true,
                shareholderName: iss.holderName,
                shareholder: iss.holder,
                issuedCertNo: tokenId,
                issuedShares: details.unitsRepresented,
                fromWhom: address(0),
                amountPaid: 0,
                paymentToken: address(0),
                surrenderedCertNo: 0,
                surrenderedShares: 0,
                sellerVoided: false,
                sharesHeldByShareholder: sharesHeld[iss.holder],
                sharesHeldBySeller: 0, // no surrender on an original issue
                transferDate: block.timestamp
            })
        );
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
        assertEq(o.buyerHostingMode, uint8(c.buyerHostingMode), "buyerHostingMode");
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
        assertEq(s.buyerHostingMode, uint8(c.buyerHostingMode), "settlement buyerHostingMode");
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
            buyerHostingMode: HostingMode.DIRECT,
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
        _assertSettlementDerived(
            settlementId, seller, buyer, fee, expectedIntegratorFee, expectedPlatformFee, integrator
        );

        IdxSettlement storage s = idxSettlements[settlementId];
        assertEq(s.integratorFee + s.platformFee, s.fee, "split sums to total");

        // Events agree with reality.
        assertEq(paymentToken.balanceOf(integrator), s.integratorFee, "integrator balance == reconstructed fee");
        assertEq(paymentToken.balanceOf(platform), s.platformFee, "platform balance == reconstructed fee");
    }

    // Stock-ledger reconstruction: a SELL offer filled in two lots (partial then closing) yields two transfer
    // rows. Under fresh-mint-per-lot each fill mints its OWN cert, so the two transfer rows carry DISTINCT issued
    // cert numbers (one holding-period clock per lot), while the buyer's running balance still sums across them.
    function test_Indexer_StockLedger_DirectHosting_MultipleFills() public {
        uint256 unitsA = 40;
        uint256 unitsB = 60;

        vm.recordLogs();
        bytes32 offerId = _postSellOffer();
        bytes32 lotA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 lotB = _acceptSellOfferPartial(offerId, unitsB);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotA);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotB);

        _index(vm.getRecordedLogs());

        // Amount paid (consideration) prorates with the units of each partial fill.
        uint256 paidA = CONSIDERATION * unitsA / UNITS; // 4 ether
        uint256 paidB = CONSIDERATION * unitsB / UNITS; // 6 ether

        // The full expected Stock Transfer Ledger once both lots settle — row 0 the founding issue (from
        // setUp), rows 1–2 the two transfers. NUMBER OF SHARES HELD is the row holder's running balance after
        // that row; the seller's whole position ends up with the buyer, held across one cert per lot (#1, #2).
        //
        //  NO. |              CERTIFICATE ISSUED              |              CERTIFICATE SURRENDERED
        //      | SHAREHOLDER | CERT# | SHARES | HELD |  PAID  | FROM WHOM       | CERT# | SHARES | VOIDED? | HELD
        // -----+-------------+-------+--------+------+--------+-----------------+-------+--------+---------+-----
        //   0  | Alice       |   0   |  100   | 100  |   0    | — (orig. issue) |   —   |   0    |   no    |  —
        //   1  | Bob         |   1   |   40   |  40  | 4 eth  | Alice           |   0   |   40   |   no    |  60
        //   2  | Bob         |   2   |   60   | 100  | 6 eth  | Alice           |   0   |   60   |   yes   |  0
        assertEq(idxTransferLedger.length, 3, "ledger has the original issue + two transfers");
        // Row 0 — the original issue is unchanged by the trading that followed.
        _assertLedgerRow(0, true, seller, "Alice", sellerTokenId, UNITS, address(0), 0, 0, false, 0, address(0), UNITS, 0);
        // Row 1 — lot A, partial sale of 40: seller cert decremented (not voided), buyer's new cert (#1) holds 40.
        _assertLedgerRow(
            1, false, buyer, "Bob", 1, unitsA, seller, sellerTokenId, unitsA, false, paidA, address(paymentToken), unitsA, UNITS - unitsA
        );
        // Row 2 — lot B, closing the position: the seller cert is voided, and the 60 units are delivered as Bob's
        // OWN second lot (a distinct cert #2); his running balance across both lots is the full 100.
        _assertLedgerRow(
            2, false, buyer, "Bob", 2, unitsB, seller, sellerTokenId, unitsB, true, paidB, address(paymentToken), UNITS, UNITS - unitsA - unitsB
        );

        // Both lots surrender the same origin cert but land in DISTINCT buyer certs (one per lot) — a coherent
        // chain of title with per-lot holding-period clocks.
        assertEq(idxSettlements[lotA].surrenderedTokenId, idxSettlements[lotB].surrenderedTokenId, "same origin cert");
        assertTrue(idxSettlements[lotA].issuedTokenId != idxSettlements[lotB].issuedTokenId, "each fill mints its own lot");

        // NUMBER OF SHARES HELD: the whole position moved from the seller to the buyer across the two lots.
        assertEq(sharesHeld[seller], 0, "seller fully divested");
        assertEq(sharesHeld[buyer], UNITS, "buyer holds the entire position");
    }

    // Administered-hosting counterpart of the direct-hosting fills: the same SELL offer filled in two lots,
    // but the buyer custodies through an admin multisig. The Stock Transfer Ledger must still record the BUYER
    // as the shareholder of record in every row — not the custodian — because the printer registers the buyer
    // as legal owner while the multisig only holds the NFT.
    function test_Indexer_StockLedger_AdministeredHosting_MultipleFills() public {
        address adminMultisig = makeAddr("adminMultisig");
        uint256 unitsA = 40;
        uint256 unitsB = 60;

        vm.recordLogs();
        bytes32 offerId = _postSellOffer();
        bytes32 lotA = _acceptSellOfferPartialAdministered(offerId, unitsA, adminMultisig);
        bytes32 lotB = _acceptSellOfferPartialAdministered(offerId, unitsB, adminMultisig);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotA);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lotB);

        _index(vm.getRecordedLogs());

        // Amount paid (consideration) prorates with the units of each partial fill.
        uint256 paidA = CONSIDERATION * unitsA / UNITS; // 4 ether
        uint256 paidB = CONSIDERATION * unitsB / UNITS; // 6 ether

        // On-chain split: the multisig custodies the buyer's certs, but the buyer is the registered legal owner.
        // Each fill mints its own lot, so the two lookups address distinct tokens.
        assertEq(
            CyberCertPrinter(address(certPrinter)).ownerOf(idxSettlements[lotA].issuedTokenId),
            adminMultisig,
            "lot A custodied by multisig"
        );
        assertEq(
            CyberCertPrinter(address(certPrinter)).ownerOf(idxSettlements[lotB].issuedTokenId),
            adminMultisig,
            "lot B custodied by multisig"
        );
        assertEq(certPrinter.legalOwnerOf(idxSettlements[lotA].issuedTokenId), buyer, "lot A buyer is legal owner");
        assertEq(certPrinter.legalOwnerOf(idxSettlements[lotB].issuedTokenId), buyer, "lot B buyer is legal owner");

        // The full expected Stock Transfer Ledger — identical to direct hosting, because the buyer (not the
        // custodian) is the shareholder of record. Row 0 the founding issue, rows 1–2 the two transfers.
        //
        //  NO. |              CERTIFICATE ISSUED              |              CERTIFICATE SURRENDERED
        //      | SHAREHOLDER | CERT# | SHARES | HELD |  PAID  | FROM WHOM       | CERT# | SHARES | VOIDED? | HELD
        // -----+-------------+-------+--------+------+--------+-----------------+-------+--------+---------+-----
        //   0  | Alice       |   0   |  100   | 100  |   0    | — (orig. issue) |   —   |   0    |   no    |  —
        //   1  | Bob         |   1   |   40   |  40  | 4 eth  | Alice           |   0   |   40   |   no    |  60
        //   2  | Bob         |   2   |   60   | 100  | 6 eth  | Alice           |   0   |   60   |   yes   |  0
        assertEq(idxTransferLedger.length, 3, "ledger has the original issue + two transfers");
        // Row 0 — the original issue is unchanged by the trading that followed.
        _assertLedgerRow(0, true, seller, "Alice", sellerTokenId, UNITS, address(0), 0, 0, false, 0, address(0), UNITS, 0);
        // Row 1 — lot A, partial sale of 40: seller cert decremented (not voided), buyer's new cert (#1) holds 40.
        _assertLedgerRow(
            1, false, buyer, "Bob", 1, unitsA, seller, sellerTokenId, unitsA, false, paidA, address(paymentToken), unitsA, UNITS - unitsA
        );
        // Row 2 — lot B, closing the position: the seller cert is voided, and the 60 units are delivered as Bob's
        // OWN second lot (a distinct cert #2); his running balance across both lots is the full 100.
        _assertLedgerRow(
            2, false, buyer, "Bob", 2, unitsB, seller, sellerTokenId, unitsB, true, paidB, address(paymentToken), UNITS, UNITS - unitsA - unitsB
        );

        // Both lots surrender the same origin cert but land in DISTINCT buyer certs (one per lot) — a coherent
        // chain of title with per-lot holding-period clocks.
        assertEq(idxSettlements[lotA].surrenderedTokenId, idxSettlements[lotB].surrenderedTokenId, "same origin cert");
        assertTrue(idxSettlements[lotA].issuedTokenId != idxSettlements[lotB].issuedTokenId, "each fill mints its own lot");

        // NUMBER OF SHARES HELD: the whole position moved to the buyer of record; the custodian holds none.
        assertEq(sharesHeld[seller], 0, "seller fully divested");
        assertEq(sharesHeld[buyer], UNITS, "buyer holds the entire position of record");
        assertEq(sharesHeld[adminMultisig], 0, "custodian holds no shares of record");
    }

    // A buyer with a PRE-EXISTING PRIMARY cert who then buys a lot from the seller: under fresh-mint-per-lot the
    // purchase is delivered as a NEW cert, never folded into the primary. The indexer keeps the primary issue row
    // an ORIGINAL ISSUE (untouched) and opens a secondary-transfer row on the newly minted cert number.
    function test_Indexer_StockLedger_DoesNotFoldIntoPreexistingPrimaryCert() public {
        uint256 buyerPrimaryUnits = 50;
        uint256 tradeUnits = 40;

        vm.recordLogs();
        // Bob already holds a founding (primary) cert on this printer, minted before any secondary trade.
        vm.prank(owner);
        uint256 buyerPrimaryTokenId = im.createCertAndAssignWithName(
            address(certPrinter), buyer, _sellerCertDetails(buyerPrimaryUnits), "Bob", "", block.timestamp
        );
        uint256 secondaryLotTokenId = buyerPrimaryTokenId + 1; // the purchase mints the next id

        bytes32 offerId = _postSellOffer();
        bytes32 lot = _acceptSellOfferPartial(offerId, tradeUnits);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(lot);

        _index(vm.getRecordedLogs());

        uint256 paid = CONSIDERATION * tradeUnits / UNITS; // 4 ether

        // The purchase mints Bob a fresh lot (#2); his PRIMARY cert (#1) stays an untouched original issue, and
        // the purchase opens its own secondary-transfer row on the new cert number.
        //
        //  NO. |              CERTIFICATE ISSUED              |              CERTIFICATE SURRENDERED
        //      | SHAREHOLDER | CERT# | SHARES | HELD |  PAID  | FROM WHOM       | CERT# | SHARES | VOIDED? | HELD
        // -----+-------------+-------+--------+------+--------+-----------------+-------+--------+---------+-----
        //   0  | Alice       |   0   |  100   | 100  |   0    | — (orig. issue) |   —   |   0    |   no    |  —
        //   1  | Bob         |   1   |   50   |  50  |   0    | — (orig. issue) |   —   |   0    |   no    |  —
        //   2  | Bob         |   2   |   40   |  90  | 4 eth  | Alice           |   0   |   40   |   no    |  60
        assertEq(idxTransferLedger.length, 3, "ledger has Alice's + Bob's original issues + one transfer");
        _assertLedgerRow(0, true, seller, "Alice", sellerTokenId, UNITS, address(0), 0, 0, false, 0, address(0), UNITS, 0);
        // Row 1 — Bob's founding cert stays an original issue, untouched by the later purchase.
        _assertLedgerRow(
            1, true, buyer, "Bob", buyerPrimaryTokenId, buyerPrimaryUnits, address(0), 0, 0, false, 0, address(0), buyerPrimaryUnits, 0
        );
        // Row 2 — the purchase: seller cert decremented (not voided), 40 units delivered as Bob's own new lot.
        _assertLedgerRow(
            2, false, buyer, "Bob", secondaryLotTokenId, tradeUnits, seller, sellerTokenId, tradeUnits, false, paid, address(paymentToken), buyerPrimaryUnits + tradeUnits, UNITS - tradeUnits
        );

        // The issued cert is a fresh lot, distinct from Bob's primary cert; only the surrender names the seller's.
        assertEq(idxSettlements[lot].issuedTokenId, secondaryLotTokenId, "purchase minted a new lot");
        assertTrue(idxSettlements[lot].issuedTokenId != buyerPrimaryTokenId, "purchase not folded into the primary cert");
        assertEq(idxSettlements[lot].surrenderedTokenId, sellerTokenId, "seller surrendered the founding cert");
        // The primary cert keeps its original-issue status; the purchase never touched it.
        assertTrue(idxIssuances[buyerPrimaryTokenId].originalIssue, "buyer's primary cert remains an original issue");

        // NUMBER OF SHARES HELD: the seller's lot moved into Bob's position (across two certs now).
        assertEq(sharesHeld[seller], UNITS - tradeUnits, "seller decremented by the sold lot");
        assertEq(sharesHeld[buyer], buyerPrimaryUnits + tradeUnits, "buyer's position grew by the purchase");
    }

    /// @dev Asserts one Stock Transfer Ledger row (idxTransferLedger[row]) matches expected across every
    /// reconstructable column. Handles both an original-issue row (no transferor / surrender) and a
    /// secondary-transfer row. For an original issue pass fromWhom = address(0) and surrendered = (0, 0).
    function _assertLedgerRow(
        uint256 row,
        bool expectedOriginalIssue,
        address expectedShareholder,
        string memory expectedShareholderName,
        uint256 expectedIssuedCert,
        uint256 expectedIssuedShares,
        address expectedFromWhom,
        uint256 expectedSurrenderedCert,
        uint256 expectedSurrenderedShares,
        bool expectedVoided,
        uint256 expectedAmountPaid,
        address expectedPaymentToken,
        uint256 expectedSharesHeld,
        uint256 expectedSellerHeld
    ) internal view {
        IdxLedgerRow storage r = idxTransferLedger[row];
        assertEq(r.rowNo, row, "ledger row no.");
        assertEq(r.originalIssue, expectedOriginalIssue, "original-issue flag");
        // NAME OF SHAREHOLDER / TO WHOM TRANSFERRED (the new holder).
        assertEq(r.shareholder, expectedShareholder, "shareholder (to-whom)");
        assertEq(r.shareholderName, expectedShareholderName, "shareholder name");
        // CERTIFICATES ISSUED → CERTIF NO. / NO. OF SHARES.
        assertEq(r.issuedCertNo, expectedIssuedCert, "issued cert number");
        assertEq(r.issuedShares, expectedIssuedShares, "issued shares");
        // FROM WHOM TRANSFERRED (seller; address(0) for an original issue).
        assertEq(r.fromWhom, expectedFromWhom, "from-whom (seller)");
        // CERTIFICATES SURRENDERED → CERTIF NO. / NO. SHARES (both 0 for an original issue).
        assertEq(r.surrenderedCertNo, expectedSurrenderedCert, "surrendered cert number");
        assertEq(r.surrenderedShares, expectedSurrenderedShares, "surrendered shares");
        assertEq(r.sellerVoided, expectedVoided, "full-vs-partial flag");
        // AMOUNT PAID THEREON (consideration) and the token it was paid in.
        assertEq(r.amountPaid, expectedAmountPaid, "amount paid (consideration)");
        assertEq(r.paymentToken, expectedPaymentToken, "payment token");
        // NUMBER OF SHARES HELD (issued side: new holder's balance; surrender side: seller's balance after the
        // surrender, 0 for an original issue) and DATE OF TRANSFER (recorded).
        assertEq(r.sharesHeldByShareholder, expectedSharesHeld, "number of shares held (issued side)");
        assertEq(r.sharesHeldBySeller, expectedSellerHeld, "number of shares held (surrender side)");
        assertGt(r.transferDate, 0, "transfer date recorded");
    }
}
