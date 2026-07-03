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
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CertificateDetails, Endorsement, ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {BaseSecondaryTradingCondition} from "../src/libs/conditions/BaseSecondaryTradingCondition.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import {ISecondaryTradeStorage} from "../src/interfaces/ISecondaryTradeStorage.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {EscrowStatus} from "../src/storage/LexScrowStorage.sol";
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
// Minimal CyberCorp / uriBuilder fixtures for the real IssuanceManager, shared from IssuanceManagerTest.
import {
    MockCyberCorpForIM,
    MockUriBuilderForIM
} from "./IssuanceManagerTest.t.sol";
import {Test, console2} from "forge-std/Test.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract SecERC20Mock is ERC20 {
    constructor() ERC20("Payment Token", "PAY") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract SecConditionMock is BaseSecondaryTradingCondition {
    bool private _pass;

    constructor(bool pass_) {
        _pass = pass_;
    }

    function checkCondition(IDealManager, bytes4, bytes32, bytes32) external view override returns (bool) {
        return _pass;
    }
}

// Stateful threshold-condition mock: returns `pass`, which the test flips between acceptance and
// finalization. Used to prove the threshold set is re-checked at finalize — it passes through
// posting/acceptance, is then flipped to fail, and must block the asset transfer.
contract SecFlippableConditionMock is BaseSecondaryTradingCondition {
    bool public pass;

    constructor(bool pass_) {
        pass = pass_;
    }

    function setPass(bool v) external {
        pass = v;
    }

    function checkCondition(IDealManager, bytes4, bytes32, bytes32) external view override returns (bool) {
        return pass;
    }
}

// Mirrors a real seller-side threshold condition: Returns false if the
// offer is unreadable — which is what the pre-fix ordering produced, since the condition loop ran
// before the offer was stored.
contract SecOfferReadingConditionMock is BaseSecondaryTradingCondition {
    function checkCondition(IDealManager dealManager, bytes4, bytes32 offerId, bytes32) external view override returns (bool) {
        Offer memory o = dealManager.getOffer(offerId);
        return o.offeror != address(0) && o.certPrinter != address(0);
    }
}

// Mirrors a real buyer-facing threshold condition (KYC/accreditation/holder-cap): it short-circuits
// to `true` at posting when there is no settlement yet (agreementId == 0), and enforces once an acceptor
// exists. Used to prove acceptOffer re-evaluates threshold conditions (post-fix); pre-fix it never ran here.
contract SecBuyerFacingConditionMock is BaseSecondaryTradingCondition {
    bool private _acceptorAllowed;

    constructor(bool acceptorAllowed_) {
        _acceptorAllowed = acceptorAllowed_;
    }

    function checkCondition(IDealManager, bytes4, bytes32, bytes32 agreementId) external view override returns (bool) {
        if (agreementId == bytes32(0)) return true; // posting context: no buyer yet
        return _acceptorAllowed; // acceptance context: enforce
    }
}

contract SecCounterpartyRestrictionsConditionMock is BaseSecondaryTradingCondition {
    bytes private _expected;

    constructor(bytes memory expected_) {
        _expected = expected_;
    }

    function checkCondition(IDealManager dealManager, bytes4, bytes32 offerId, bytes32 agreementId) external view override returns (bool) {
        if (agreementId == bytes32(0)) return true; // short-circuit to pass if no acceptor yet
        Offer memory o = dealManager.getOffer(offerId);
        return keccak256(o.counterpartyRestrictions) == keccak256(_expected); // acceptance: enforce the blob
    }
}

// Does not implement ISecondaryTradingCondition (no ERC-165 support): the config setters must reject it.
contract SecNonConditionMock {}

// Passes when handed any of the selectors it was configured with. Models a real phase-gating condition:
// each of post/accept has a direct and a relayer overload with distinct selectors, so a condition that gates
// "the post phase" registers both. Selectors are the library-internal ones conditions actually receive
// (struct kept by name, not tuple-expanded), e.g. keccak256("postOffer(PostOfferParams)").
contract SecSelectorAssertingConditionMock is BaseSecondaryTradingCondition {
    mapping(bytes4 => bool) public accepted;

    constructor(bytes4[] memory selectors) {
        for (uint256 i = 0; i < selectors.length; i++) accepted[selectors[i]] = true;
    }

    function checkCondition(IDealManager, bytes4 functionSignature, bytes32, bytes32) external view override returns (bool) {
        return accepted[functionSignature];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test contract
// ─────────────────────────────────────────────────────────────────────────────

contract DealManagerSecondaryTradeTest is Test {
    bytes32 constant corpSalt = keccak256("DealManagerSecondaryTradeTest.corp");

    address public owner;
    uint256 public ownerKey;
    address public seller;
    uint256 public sellerKey;
    address public buyer;
    uint256 public buyerKey;
    address public keeper;
    // Unrelated payee used only to assert the secondary path never routes funds to the company payable.
    address public company;

    bytes32 constant imSalt = keccak256("DealManagerSecondaryTradeTest.im");

    SecERC20Mock public paymentToken;
    ICyberCertPrinter public certPrinter;
    IssuanceManager public im;
    CyberAgreementRegistry public registry;
    MockCyberCorpForIM public corp;
    DealManagerFactory public dmFactory;
    DealManager public dm;
    BorgAuth public auth;

    // Single template (empty global/party fields) reused for every offer and the primary regression deals.
    bytes32 public constant TEMPLATE_ID = bytes32(0);
    string public constant TEMPLATE_URI = "ipfs://secondary-template";

    uint256 public constant CONSIDERATION = 10 ether;
    uint256 public constant UNITS = 100;
    uint256 public sellerTokenId;

    // Placeholder counterpartyRestrictions blob (spec §8.1); real encoding is not implemented yet, so any
    // non-empty value the SecCounterpartyRestrictionsConditionMock can match on suffices.
    bytes public constant COUNTERPARTY_RESTRICTIONS = "mock counterparty restrictions";

    // Supplemental fields blob (spec §8.1): memorialized only, never enforced — carried by the default
    // offers purely to prove it round-trips through postOffer/getOffer unchanged.
    bytes public constant ADDITIONAL_TERMS = "mock additional terms";

    // Seller's open-endorsement signature (spec §7.3.1): opaque blob, not recovered yet.
    bytes public constant OPEN_ENDORSEMENT_SIG = "sellerEndorsement";

    // Buyer name the acceptor supplies when filling a sell offer (memorialized on the settlement escrow).
    string public constant SELL_ACCEPT_BUYER_NAME = "Bob";

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        keeper = makeAddr("keeper");
        company = makeAddr("company");

        paymentToken = new SecERC20Mock();
        auth = new BorgAuth(owner);
        corp = new MockCyberCorpForIM();

        // Real IssuanceManager + CyberCertPrinter, deployed through the IssuanceManagerFactory beacon stack.
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

        // Real CyberAgreementRegistry behind a proxy, sharing the same BorgAuth.
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        // Single reusable template with no global/party fields (matches the empty values used below).
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
        // entry points, so it needs the role real onboarding grants it.
        vm.prank(owner);
        auth.updateRole(address(dm), 99);

        // Mint the seller's Ledger Entry Token through the real IssuanceManager, with UNITS represented.
        vm.startPrank(owner);
        certPrinter = ICyberCertPrinter(
            im.createCertPrinter(
                new string[](0),
                "Secondary Cert",
                "SCERT",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
        sellerTokenId = im.createCertAndAssign(address(certPrinter), seller, _sellerCertDetails(UNITS));
        vm.stopPrank();

        // Fund buyer
        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);

        // Fund seller (for buy-offer tests where seller receives nothing upfront)
        paymentToken.mint(seller, CONSIDERATION * 10);
        vm.prank(seller);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

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

    /// @dev Cumulative units consumed (transferred out) from the seller cert. Consumption is the only thing
    /// that shrinks the seller cert — a partial sale decrements unitsRepresented, a full sale voids the cert —
    /// so consumed == initial (UNITS) minus what remains. Replaces the old mock's `consumedUnits` counter.
    function _consumed(uint256 tokenId) internal view returns (uint256) {
        if (certPrinter.isVoided(tokenId)) return UNITS;
        return UNITS - certPrinter.getCertificateDetails(tokenId).unitsRepresented;
    }

    /// @dev Cumulative units released back to the seller's free pool (cancel/void), for a SELL offer that
    /// reserves the whole UNITS at postOffer: released == reserved-ever (UNITS) − consumed − still-reserved.
    /// The real CyberCertPrinter tracks only net `unitsReserved`, so this reconstructs the old mock counter.
    /// Not valid for buy offers (which reserve per-lot, not UNITS); those assert live `unitsReserved` directly.
    function _released(uint256 tokenId) internal view returns (uint256) {
        return UNITS - _consumed(tokenId) - certPrinter.unitsReserved(tokenId);
    }

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
            additionalTerms: ADDITIONAL_TERMS,
            integrator: address(0),
            templateId: bytes32(0),
            salt: uint256(keccak256("defaultSellOffer")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: OPEN_ENDORSEMENT_SIG,
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
            additionalTerms: ADDITIONAL_TERMS,
            integrator: address(0),
            templateId: bytes32(0),
            salt: uint256(keccak256("defaultBuyOffer")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "",
            buyerName: "Test Buyer",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
    }

    function _postSellOffer() internal returns (bytes32 offerAgreementId) {
        vm.prank(seller);
        offerAgreementId = dm.postOffer(_defaultSellOfferParams());
    }

    // Creates a primary issuance deal (has a LexScrow escrow, no SecondaryEscrow). Used to verify
    // secondary functions reject a primary id.
    function _proposePrimaryDeal(uint256 salt) internal returns (bytes32 agreementId) {
        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        address[] memory parties = new address[](2);
        parties[0] = owner;
        parties[1] = buyer;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);
        address[] memory printers = new address[](1);
        printers[0] = address(certPrinter);

        vm.prank(owner);
        (agreementId,) = dm.proposeDeal(
            printers,
            address(paymentToken),
            CONSIDERATION,
            bytes32(0),
            salt,
            new string[](0),
            parties,
            certDetails,
            partyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1 days
        );
    }

    function _postBuyOffer() internal returns (bytes32 offerAgreementId) {
        vm.prank(buyer);
        offerAgreementId = dm.postOffer(_defaultBuyOfferParams());
    }

    function _acceptSellOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerAgreementId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    function _acceptBuyOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        return _acceptBuyOfferPartial(offerAgreementId, UNITS);
    }

    function _acceptBuyOfferPartial(bytes32 offerAgreementId, uint256 units)
        internal
        returns (bytes32 settlementAgreementId)
    {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: units,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerAgreementId, seller, sellerKey),
            openEndorsementSig: OPEN_ENDORSEMENT_SIG
        });
        vm.prank(seller);
        settlementAgreementId = dm.acceptOffer(p);
    }

    /// @dev Assert every critical SecondaryEscrow field for a freshly ACCEPTED lot, so the stored
    /// status enum is backed by correct custody/routing data — i.e. the escrow's true state matches
    /// its ACCEPTED enum. tokenId is always the seller's Ledger Entry Token (sell: offer.tokenId;
    /// buy: acceptor-supplied sellerTokenId); feeDestination is zero because no integrator is set.
    function _assertAcceptedEscrow(
        bytes32 settlementId,
        bytes32 offerId,
        address acceptor,
        uint256 units,
        uint256 payment
    ) internal view {
        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(uint8(se.status), uint8(SecondaryEscrowStatus.ACCEPTED), "escrow status ACCEPTED");
        assertEq(se.counterparty, acceptor, "counterparty is the acceptor");
        assertEq(se.offerId, offerId, "offerId back-link");
        assertEq(se.paymentToken, address(paymentToken), "payment token");
        assertEq(se.paymentAmount, payment, "payment amount for this lot");
        assertEq(se.units, units, "units in this lot");
        assertEq(se.expiry, block.timestamp + 7 days, "expiry runs the settlement window from acceptance, not offer validUntil");
        assertEq(se.feeDestination, address(0), "no integrator set -> fees route to platform");
        assertEq(se.tokenId, sellerTokenId, "reservation target is the seller's tokenId");

        // Per-settlement materialization fields, recorded for both sides (redundant for the side that
        // already carries the value on the Offer). Sourced per offer side:
        //  - buy offer: buyer info from the offer (the offeror is the buyer); endorsement from the acceptance params
        //  - sell: buyer info from the acceptance params; endorsement copied from the offer's pre-signed one
        Offer memory o = dm.getOffer(offerId);
        assertEq(uint8(se.buyerHostingMode), uint8(HostingMode.DIRECT), "buyerHostingMode");
        assertEq(se.adminMultisig, address(0), "adminMultisig");
        if (o.side == OfferSide.BUY) {
            assertEq(se.buyerName, o.buyerName, "buyerName from the buy offer");
            assertEq(se.openEndorsementSig, OPEN_ENDORSEMENT_SIG, "endorsement from the acceptance params");
        } else {
            assertEq(se.buyerName, SELL_ACCEPT_BUYER_NAME, "buyerName from the acceptance params");
            assertEq(se.openEndorsementSig, o.openEndorsementSig, "endorsement copied from the offer");
        }
    }

    /// @dev Asserts every field of a freshly posted Offer matches the post params and DealManager config,
    /// so the stored record is known complete and clean.
    function _assertPostedOffer(bytes32 offerId, PostOfferParams memory p, address offeror) internal view {
        Offer memory offer = dm.getOffer(offerId);

        // identity & classification
        assertEq(offer.offerId, offerId, "offerId self-reference");
        assertEq(offer.spvAddress, address(corp), "spvAddress");
        assertEq(offer.offeror, offeror, "offeror");
        assertEq(uint8(offer.side), uint8(p.side), "side");
        assertEq(offer.certPrinter, p.certPrinter, "certPrinter");
        assertEq(offer.tokenId, p.tokenId, "tokenId");

        // economics
        assertEq(offer.units, p.units, "units");
        assertEq(offer.paymentToken, p.paymentToken, "paymentToken");
        assertEq(offer.consideration, p.consideration, "consideration");
        assertEq(uint8(offer.exemptionPathway), uint8(p.exemptionPathway), "exemptionPathway");
        assertEq(offer.validUntil, p.validUntil, "validUntil");
        address expectedIntegrator = p.integrator != address(0) ? p.integrator : dm.getDefaultIntegrator();
        assertEq(offer.integrator, expectedIntegrator, "integrator");

        // §8.1 opaque blobs
        assertEq(offer.counterpartyRestrictions, p.counterpartyRestrictions, "counterpartyRestrictions");
        assertEq(offer.additionalTerms, p.additionalTerms, "additionalTerms");

        // fresh offer: LIVE, zeroed counters, no settlements
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE), "status LIVE");
        assertEq(offer.unitsAccepted, 0, "unitsAccepted");
        assertEq(offer.paymentAccepted, 0, "paymentAccepted");
        assertEq(offer.unitsFinalized, 0, "unitsFinalized");
        assertEq(offer.settlementAgreementIds.length, 0, "no settlements at post");

        // agreement-template fields
        assertEq(offer.templateId, p.templateId, "templateId");
        assertEq(offer.salt, p.salt, "salt");
        assertEq(offer.globalValues.length, p.globalValues.length, "globalValues length");
        for (uint256 i = 0; i < p.globalValues.length; i++) {
            assertEq(offer.globalValues[i], p.globalValues[i], "globalValues element");
        }
        assertEq(offer.offerorPartyValues.length, p.offerorPartyValues.length, "offerorPartyValues length");
        for (uint256 i = 0; i < p.offerorPartyValues.length; i++) {
            assertEq(offer.offerorPartyValues[i], p.offerorPartyValues[i], "offerorPartyValues element");
        }
        assertEq(offer.offerorAgreementSig, p.offerorAgreementSig, "offerorAgreementSig");
        assertEq(offer.openEndorsementSig, p.openEndorsementSig, "openEndorsementSig");

        // buyer fields: carried on BUY, empty on SELL
        if (p.side == OfferSide.BUY) {
            assertEq(offer.buyerName, p.buyerName, "buyerName");
            assertEq(uint8(offer.buyerHostingMode), uint8(p.buyerHostingMode), "buyerHostingMode");
            assertEq(offer.adminMultisig, p.adminMultisig, "adminMultisig");
        } else {
            assertEq(offer.buyerName, "", "sell offers carry no buyerName");
            assertEq(uint8(offer.buyerHostingMode), uint8(HostingMode.DIRECT), "sell offers carry no buyerHostingMode");
            assertEq(offer.adminMultisig, address(0), "sell offers carry no adminMultisig");
        }

        // condition snapshots from DealManager config
        address[] memory spv = dm.getSpvThresholdConditions();
        address[] memory pathway = dm.getPathwayThresholdConditions(p.exemptionPathway);
        assertEq(offer.thresholdConditions.length, spv.length + pathway.length, "thresholdConditions length");
        for (uint256 i = 0; i < spv.length; i++) {
            assertEq(offer.thresholdConditions[i], spv[i], "thresholdConditions SPV element");
        }
        for (uint256 i = 0; i < pathway.length; i++) {
            assertEq(offer.thresholdConditions[spv.length + i], pathway[i], "thresholdConditions pathway element");
        }
        address[] memory closing = dm.getClosingConditions();
        assertEq(offer.closingConditions.length, closing.length, "closingConditions length");
        for (uint256 i = 0; i < closing.length; i++) {
            assertEq(offer.closingConditions[i], closing[i], "closingConditions element");
        }
    }

    /// @dev Asserts an offer's whole record after a state change: the mutable fields (status, the three
    /// accounting counters, the settlement nonce) match the expected values, and its identity fields are
    /// unchanged from the post-time baseline. Capture `baseline` right after postOffer and reuse it.
    function _assertOfferState(
        bytes32 offerId,
        Offer memory baseline,
        OfferStatus status,
        uint256 unitsAccepted,
        uint256 paymentAccepted,
        uint256 unitsFinalized,
        uint256 settlementCount
    ) internal view {
        Offer memory o = dm.getOffer(offerId);

        // mutable fields
        assertEq(uint8(o.status), uint8(status), "status");
        assertEq(o.unitsAccepted, unitsAccepted, "unitsAccepted");
        assertEq(o.paymentAccepted, paymentAccepted, "paymentAccepted");
        assertEq(o.unitsFinalized, unitsFinalized, "unitsFinalized");
        assertEq(o.settlementAgreementIds.length, settlementCount, "settlementAgreementIds length");

        _assertOfferImmutableUnchanged(o, baseline);
    }

    /// @dev Asserts the offer's identity fields still equal the post-time baseline `b`.
    function _assertOfferImmutableUnchanged(Offer memory o, Offer memory b) internal pure {
        assertEq(o.offerId, b.offerId, "offerId immutable");
        assertEq(o.spvAddress, b.spvAddress, "spvAddress immutable");
        assertEq(o.offeror, b.offeror, "offeror immutable");
        assertEq(uint8(o.side), uint8(b.side), "side immutable");
        assertEq(o.certPrinter, b.certPrinter, "certPrinter immutable");
        assertEq(o.tokenId, b.tokenId, "tokenId immutable");
        assertEq(o.units, b.units, "units immutable");
        assertEq(o.paymentToken, b.paymentToken, "paymentToken immutable");
        assertEq(o.consideration, b.consideration, "consideration immutable");
        assertEq(uint8(o.exemptionPathway), uint8(b.exemptionPathway), "exemptionPathway immutable");
        assertEq(o.validUntil, b.validUntil, "validUntil immutable");
        assertEq(o.integrator, b.integrator, "integrator immutable");
        assertEq(o.counterpartyRestrictions, b.counterpartyRestrictions, "counterpartyRestrictions immutable");
        assertEq(o.additionalTerms, b.additionalTerms, "additionalTerms immutable");
        assertEq(o.templateId, b.templateId, "templateId immutable");
        assertEq(o.salt, b.salt, "salt immutable");
        assertEq(o.offerorAgreementSig, b.offerorAgreementSig, "offerorAgreementSig immutable");
        assertEq(o.openEndorsementSig, b.openEndorsementSig, "openEndorsementSig immutable");
        // Buyer fields stay as posted on the Offer for both sides; the per-settlement buyer info and the
        // endorsement actually used live on each SecondaryEscrow, not here.
        assertEq(o.buyerName, b.buyerName, "buyerName immutable");
        assertEq(uint8(o.buyerHostingMode), uint8(b.buyerHostingMode), "buyerHostingMode immutable");
        assertEq(o.adminMultisig, b.adminMultisig, "adminMultisig immutable");
        assertEq(o.globalValues.length, b.globalValues.length, "globalValues length immutable");
        for (uint256 i = 0; i < b.globalValues.length; i++) {
            assertEq(o.globalValues[i], b.globalValues[i], "globalValues element immutable");
        }
        assertEq(o.offerorPartyValues.length, b.offerorPartyValues.length, "offerorPartyValues length immutable");
        for (uint256 i = 0; i < b.offerorPartyValues.length; i++) {
            assertEq(o.offerorPartyValues[i], b.offerorPartyValues[i], "offerorPartyValues element immutable");
        }
        assertEq(o.thresholdConditions.length, b.thresholdConditions.length, "thresholdConditions length immutable");
        for (uint256 i = 0; i < b.thresholdConditions.length; i++) {
            assertEq(o.thresholdConditions[i], b.thresholdConditions[i], "thresholdConditions element immutable");
        }
        assertEq(o.closingConditions.length, b.closingConditions.length, "closingConditions length immutable");
        for (uint256 i = 0; i < b.closingConditions.length; i++) {
            assertEq(o.closingConditions[i], b.closingConditions[i], "closingConditions element immutable");
        }
    }

    /// @dev Both parties of a settlement are always {seller, buyer} regardless of offer side. A
    /// settlement only reaches VOIDED once both have requested the void (registry quorum), so the
    /// escrow flips on the second call.
    function _voidSettlementBothParties(bytes32 settlementId) internal {
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");
        vm.prank(seller);
        dm.voidSecondaryTradeAgreement(settlementId, seller, "");
    }

    /// @dev EIP-712 agreement signature over a contractId for a signer with the given party values.
    /// All offers/deals here use the empty-field template, so global/party fields and global values are empty.
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
            new string[](0), // globalFields
            new string[](0), // partyFields
            new string[](0), // globalValues
            partyValues,
            key
        );
    }

    /// @dev Recomputes the next settlement agreement id for an offer and returns the acceptor's
    /// EIP-712 signature over it (the real registry verifies the acceptor via signContractFor).
    function _acceptorSig(bytes32 offerId, address acceptor, uint256 key) internal view returns (bytes memory) {
        Offer memory o = dm.getOffer(offerId);
        bytes32 settlementSalt = keccak256(abi.encodePacked(o.salt, o.settlementAgreementIds.length));
        address[] memory parties = new address[](2);
        parties[0] = o.offeror;
        parties[1] = acceptor;
        bytes32 settlementId = keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties));
        return _agreementSig(settlementId, new string[](0), key);
    }

    /// @dev EIP-712 void signature over a contractId (needed only for direct registry void calls,
    /// i.e. not routed through DealManager, which is the finalizer and skips verification).
    function _voidSig(bytes32 agreementId, address party, uint256 key) internal view returns (bytes memory) {
        return CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), agreementId, party, key
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_PostOffer_Sell() public {
        // ∅ → LIVE: stores the offer record, reserves the offered units, and emits OfferPosted.
        vm.expectEmit(false, true, true, true); // skip offerId (computed inside); check offeror, certPrinter, and all data
        emit ISecondaryTradeStorage.OfferPosted(
            bytes32(0),
            seller,
            address(certPrinter),
            address(corp),
            OfferSide.SELL,
            sellerTokenId,
            UNITS,
            address(paymentToken),
            CONSIDERATION,
            ExemptionPathway.SECTION_4A7,
            block.timestamp + 1 days,
            address(0),
            bytes32(0),
            "",
            HostingMode.DIRECT,
            address(0),
            "",
            new address[](0),
            new address[](0)
        );
        bytes32 offerId = _postSellOffer();

        // Assert every Offer field is stored clean (see _assertPostedOffer).
        _assertPostedOffer(offerId, _defaultSellOfferParams(), seller);

        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "units should be reserved");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_PostOffer_Buy() public {
        // ∅ → LIVE: stores the offer record (no units reserved) and pulls consideration into holding escrow.
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);
        vm.expectEmit(false, true, true, true); // skip offerId; check offeror, certPrinter, and all data
        emit ISecondaryTradeStorage.OfferPosted(
            bytes32(0),
            buyer,
            address(certPrinter),
            address(corp),
            OfferSide.BUY,
            0,
            UNITS,
            address(paymentToken),
            CONSIDERATION,
            ExemptionPathway.SECTION_4A7,
            block.timestamp + 1 days,
            address(0),
            bytes32(0),
            "Test Buyer",
            HostingMode.DIRECT,
            address(0),
            "",
            new address[](0),
            new address[](0)
        );
        bytes32 offerId = _postBuyOffer();

        // Assert every Offer field is stored clean (see _assertPostedOffer).
        _assertPostedOffer(offerId, _defaultBuyOfferParams(), buyer);

        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "buy offer should reserve no units at post");

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore - CONSIDERATION,
            "buyer consideration should be in holding escrow"
        );
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds should be in DealManager");
    }

    function test_RevertIf_PostOffer_MissingCertPrinter_Sell() public {
        PostOfferParams memory p = _defaultSellOfferParams();
        p.certPrinter = address(0);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.MissingCertPrinter.selector);
        dm.postOffer(p);
    }

    function test_RevertIf_PostOffer_MissingCertPrinter_BuyOffer() public {
        PostOfferParams memory p = _defaultBuyOfferParams();
        p.certPrinter = address(0);

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.MissingCertPrinter.selector);
        dm.postOffer(p);
    }

    // An offer cannot point at a printer this SPV's IssuanceManager did not create: without the check a buyer
    // could pay real tokens for a cert minted on a fake/foreign printer (0xBEEF is not in the registry).
    function test_RevertIf_PostOffer_Sell_UnknownCertPrinter() public {
        PostOfferParams memory p = _defaultSellOfferParams();
        p.certPrinter = address(0xBEEF);
        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.UnknownCertPrinter.selector);
        dm.postOffer(p);
    }

    function test_RevertIf_PostOffer_Buy_UnknownCertPrinter() public {
        PostOfferParams memory p = _defaultBuyOfferParams();
        p.certPrinter = address(0xBEEF);
        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.UnknownCertPrinter.selector);
        dm.postOffer(p);
    }

    // A non-owner cannot list someone else's Ledger Entry Token for sale: without the ownership guard the
    // attacker would be paid at finalize while the real owner's cert is decremented (buyer does not own
    // sellerTokenId, which belongs to `seller`).
    function test_RevertIf_PostOffer_Sell_NotCertOwner() public {
        PostOfferParams memory p = _defaultSellOfferParams();
        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.NotCertOwner.selector);
        dm.postOffer(p);
    }

    // BUY counterpart: a non-owner acceptor cannot sell someone else's Ledger Entry Token into a buy offer
    // (attacker supplies sellerTokenId, owned by `seller`).
    function test_RevertIf_AcceptBuyOffer_NotCertOwner() public {
        (address attacker, uint256 attackerKey) = makeAddrAndKey("attacker");
        bytes32 offerId = _postBuyOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, attacker, attackerKey),
            openEndorsementSig: OPEN_ENDORSEMENT_SIG
        });
        vm.prank(attacker);
        vm.expectRevert(ISecondaryTradeStorage.NotCertOwner.selector);
        dm.acceptOffer(p);
    }

    // Posting a SELL offer reserves (escrows) the seller's units, freezing legal ownership: an attempt to
    // re-register the cert to a new legal owner while the offer is live reverts at the source.
    function test_RevertIf_AssignReservedCert_AfterPostSellOffer() public {
        address newOwner = makeAddr("newLegalOwner");
        _postSellOffer();

        vm.prank(owner);
        vm.expectRevert(CyberCertPrinter.CertificateReserved.selector);
        im.assignCert(address(certPrinter), seller, sellerTokenId, newOwner, _sellerCertDetails(UNITS));

        // Below verifies DealManager does double-check the legal ownership at every step, but we will never reach there if
        // the cert's reserve rule works as expected
//        AcceptOfferParams memory p = AcceptOfferParams({
//            offerId: offerId,
//            units: UNITS,
//            buyerName: SELL_ACCEPT_BUYER_NAME,
//            buyerHostingMode: HostingMode.DIRECT,
//            adminMultisig: address(0),
//            sellerTokenId: 0,
//            acceptorPartyValues: new string[](0),
//            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
//            openEndorsementSig: ""
//        });
//        vm.prank(buyer);
//        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeSellerOwnershipChanged.selector);
//        dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // threshold conditions in an Offer
    // ─────────────────────────────────────────────────────────────────────────

    // Conditions are owner-managed DealManager config (snapshotted onto the offer at postOffer), not
    // offeror-supplied. Register them as fund-specific (Layer 2 / per-SPV) conditions so they apply to
    // every one of the test's offers regardless of exemption pathway.
    function _registerThresholdConditions(address[] memory conds) internal {
        for (uint256 i = 0; i < conds.length; i++) {
            vm.prank(owner);
            dm.addSpvThresholdCondition(conds[i]);
        }
    }

    function test_PostOffer_Sell_MultipleThresholdConditionsAllPass() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(true));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_PostOffer_Sell_MultipleThresholdConditionsAllPass"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertTrue(offerId != bytes32(0));
    }

    function test_RevertIf_PostOffer_FirstThresholdConditionFails() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(false));
        conds[1] = address(new SecConditionMock(true));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_RevertIf_PostOffer_FirstThresholdConditionFails"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[0]));
        dm.postOffer(p);
    }

    function test_RevertIf_PostOffer_SecondThresholdConditionFails() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(false));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_RevertIf_PostOffer_SecondThresholdConditionFails"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[1]));
        dm.postOffer(p);
    }

    function test_PostOffer_OfferHasThresholdConditions() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecOfferReadingConditionMock());
        _registerThresholdConditions(conds);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_PostOffer_OfferHasThresholdConditions"));

        vm.prank(seller);
        // SecOfferReadingConditionMock.checkCondition() would fail if `Offer` is not updated
        bytes32 offerId = dm.postOffer(p);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.offeror, seller, "offeror must be readable by conditions");
        assertEq(offer.certPrinter, address(certPrinter), "certPrinter must be readable by conditions");
        assertEq(offer.tokenId, sellerTokenId, "tokenId must be readable by conditions");
    }

    function test_RevertIf_AcceptOffer_BuyerFacingThresholdConditionFails() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecBuyerFacingConditionMock(false)); // posting passes, acceptance fails
        _registerThresholdConditions(conds);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_RevertIf_AcceptOffer_BuyerFacingThresholdConditionFails"));

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p); // posting succeeds: condition short-circuits with no acceptor

        AcceptOfferParams memory ap = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[0]));
        dm.acceptOffer(ap);
    }

    // Counterpart to the above: when the acceptor satisfies the buyer-facing condition, the re-evaluation
    // passes and acceptance proceeds — proving the re-check runs and is not an unconditional block.
    function test_AcceptOffer_BuyerFacingThresholdConditionPasses() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecBuyerFacingConditionMock(true)); // passes at posting and acceptance
        _registerThresholdConditions(conds);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_AcceptOffer_BuyerFacingThresholdConditionPasses"));

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertTrue(settlementId != bytes32(0), "acceptance should succeed when the acceptor passes conditions");
    }

    // counterpartyRestrictions (spec §8.1): an acceptor-side threshold condition reads the offer's blob and
    // gates acceptance on it. Posting short-circuits (no acceptor yet), so the check bites at acceptOffer.
    function test_AcceptOffer_CounterpartyRestrictionsConditionPasses() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecCounterpartyRestrictionsConditionMock(COUNTERPARTY_RESTRICTIONS));
        _registerThresholdConditions(conds);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_AcceptOffer_CounterpartyRestrictionsConditionPasses"));
        p.counterpartyRestrictions = COUNTERPARTY_RESTRICTIONS; // matches the condition's expected blob

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertTrue(settlementId != bytes32(0), "acceptance should succeed when restrictions match");
    }

    // Counterpart: when the offer's blob does not match what the condition requires, posting still succeeds
    // (the gate short-circuits with no acceptor) but acceptance reverts — the spec's acceptance-time failure.
    function test_RevertIf_AcceptOffer_CounterpartyRestrictionsConditionFails() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecCounterpartyRestrictionsConditionMock(COUNTERPARTY_RESTRICTIONS));
        _registerThresholdConditions(conds);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_RevertIf_AcceptOffer_CounterpartyRestrictionsConditionFails"));
        // counterpartyRestrictions left empty -> mismatch against the condition's expected blob

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p); // posting succeeds: condition short-circuits with no acceptor

        AcceptOfferParams memory ap = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[0]));
        dm.acceptOffer(ap);
    }

    function test_ThresholdConditions_PathwayConditionAppliesToMatchingPathway() public {
        address succeeding = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, succeeding);

        // RULE_144 offer: should have the L3 condition
        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Config_Pathway_144"));
        p.exemptionPathway = ExemptionPathway.RULE_144;
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertEq(
            dm.getOffer(offerId).thresholdConditions.length, 1, "pathway condition should be applied to Rule 144 offer"
        );
    }

    function test_ThresholdConditions_PathwayConditionNotAppliesToOtherPathway() public {
        address failing = address(new SecConditionMock(false));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, failing);

        // SECTION_4A7 offer: the RULE_144 condition is not in its resolved set, so posting succeeds.
        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Config_Pathway_4a7"));
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertEq(dm.getOffer(offerId).thresholdConditions.length, 0, "no pathway condition applied to 4(a)(7) offer");
    }

    function test_RevertIf_ThresholdConditions_PathwayConditionFailsForMatchingPathway() public {
        address failing = address(new SecConditionMock(false));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, failing);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Config_Pathway_144"));
        p.exemptionPathway = ExemptionPathway.RULE_144;
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, failing));
        dm.postOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // threshold condition configurations
    // ─────────────────────────────────────────────────────────────────────────

    // The two §7.2 threshold layers — fund-specific (Layer 2 / per-SPV) ++ exemption-specific (Layer 1 /
    // per-pathway) — are concatenated in order and snapshotted onto the offer at postOffer; the offeror
    // supplies only the pathway, never the addresses.
    function test_Config_ResolvesSpvAndPathwayOntoOffer() public {
        address spv = address(new SecConditionMock(true));
        address pathway = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addSpvThresholdCondition(spv);
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.SECTION_4A7, pathway);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Config_ResolvesSpvAndPathwayOntoOffer"));
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        address[] memory resolved = dm.getOffer(offerId).thresholdConditions;
        assertEq(resolved.length, 2, "fund-specific + exemption-specific both resolved");
        assertEq(resolved[0], spv, "fund-specific (Layer 2) first");
        assertEq(resolved[1], pathway, "exemption-specific (Layer 1) last");
    }

    function test_RevertIf_Config_AddSpvZeroAddressCondition() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryCondition.selector);
        dm.addSpvThresholdCondition(address(0));
    }

    function test_RevertIf_Config_AddPathwayZeroAddressCondition() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryCondition.selector);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, address(0));
    }

    // Closing-set zero-address rejection (same guarded add path as the threshold layers).
    function test_RevertIf_Config_AddClosingZeroAddressCondition() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryCondition.selector);
        dm.addClosingCondition(address(0));
    }

    // Interface rejection — a condition that doesn't advertise ISecondaryTradingCondition via ERC-165 is
    // rejected at config time (shared _addCondition guard), per threshold layer and the closing set.
    function test_RevertIf_Config_AddSpvUnsupportedInterfaceCondition() public {
        address c = address(new SecNonConditionMock());
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionInterfaceUnsupported.selector, c));
        dm.addSpvThresholdCondition(c);
    }

    function test_RevertIf_Config_AddPathwayUnsupportedInterfaceCondition() public {
        address c = address(new SecNonConditionMock());
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionInterfaceUnsupported.selector, c));
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, c);
    }

    function test_RevertIf_Config_AddClosingUnsupportedInterfaceCondition() public {
        address c = address(new SecNonConditionMock());
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionInterfaceUnsupported.selector, c));
        dm.addClosingCondition(c);
    }

    // Duplicate rejection — per threshold layer (fund-specific / exemption-specific).
    function test_RevertIf_Config_AddSpvDuplicateCondition() public {
        address c = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addSpvThresholdCondition(c);

        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionAlreadyExists.selector);
        dm.addSpvThresholdCondition(c);
    }

    function test_RevertIf_Config_AddPathwayDuplicateCondition() public {
        address c = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, c);

        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionAlreadyExists.selector);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, c);
    }

    // Closing-set duplicate rejection (same guarded add path as the threshold layers).
    function test_RevertIf_Config_AddClosingDuplicateCondition() public {
        address c = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addClosingCondition(c);

        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionAlreadyExists.selector);
        dm.addClosingCondition(c);
    }

    // Out-of-bounds removal reverts — per threshold layer (fund-specific / exemption-specific).
    function test_RevertIf_Config_RemoveSpvIndexOutOfBounds() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionIndexOutOfBounds.selector);
        dm.removeSpvThresholdConditionAt(0);
    }

    function test_RevertIf_Config_RemovePathwayIndexOutOfBounds() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionIndexOutOfBounds.selector);
        dm.removePathwayThresholdConditionAt(ExemptionPathway.RULE_144, 0);
    }

    function test_RevertIf_Config_RemoveClosingIndexOutOfBounds() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionIndexOutOfBounds.selector);
        dm.removeClosingConditionAt(0);
    }

    // Swap-pop removal (Layer 2 fund-specific / per-SPV): removing index 0 of [a,b] leaves [b].
    function test_Config_RemoveSpvConditionSwapPop() public {
        address a = address(new SecConditionMock(true));
        address b = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addSpvThresholdCondition(a);
        vm.prank(owner);
        dm.addSpvThresholdCondition(b);

        vm.prank(owner);
        dm.removeSpvThresholdConditionAt(0);

        address[] memory remaining = dm.getSpvThresholdConditions();
        assertEq(remaining.length, 1, "one condition remains");
        assertEq(remaining[0], b, "swap-pop moved the last element into the hole");
    }

    // Swap-pop removal (Layer 1 exemption-specific / per-pathway): removing index 0 of [a,b] leaves [b]; keyed by pathway.
    function test_Config_RemovePathwayConditionSwapPop() public {
        address a = address(new SecConditionMock(true));
        address b = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, a);
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, b);

        vm.prank(owner);
        dm.removePathwayThresholdConditionAt(ExemptionPathway.RULE_144, 0);

        address[] memory remaining = dm.getPathwayThresholdConditions(ExemptionPathway.RULE_144);
        assertEq(remaining.length, 1, "one condition remains");
        assertEq(remaining[0], b, "swap-pop moved the last element into the hole");
    }

    // Swap-pop removal (closing set): removing index 0 of [a,b] leaves [b].
    function test_Config_RemoveClosingConditionSwapPop() public {
        address a = address(new SecConditionMock(true));
        address b = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addClosingCondition(a);
        vm.prank(owner);
        dm.addClosingCondition(b);

        vm.prank(owner);
        dm.removeClosingConditionAt(0);

        address[] memory remaining = dm.getClosingConditions();
        assertEq(remaining.length, 1, "one condition remains");
        assertEq(remaining[0], b, "swap-pop moved the last element into the hole");
    }

    function test_Config_GetMinTradeThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS, CONSIDERATION);

        (uint256 units, uint256 consideration) = dm.getMinTradeThreshold();
        assertEq(units, UNITS, "min trade units");
        assertEq(consideration, CONSIDERATION, "min trade consideration");
    }

    function test_Config_GetDefaultIntegrator() public {
        address integrator = makeAddr("defaultIntegrator");
        vm.prank(owner);
        dmFactory.setIntegrator(integrator, true, 0);

        vm.prank(owner);
        dm.setDefaultIntegrator(integrator);

        assertEq(dm.getDefaultIntegrator(), integrator, "default integrator");
    }

    function test_RevertIf_SetDefaultIntegrator_NotWhitelisted() public {
        // Integrator never whitelisted on the factory (default mapping is false).
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.IntegratorNotWhitelisted.selector);
        dm.setDefaultIntegrator(makeAddr("integrator"));
    }

    // Every onlyAdmin secondary-trade config function must reject a non-admin caller.
    function test_RevertIf_ConfigByNonAdmin() public {
        address c = address(new SecConditionMock(true));
        vm.startPrank(makeAddr("stranger"));

        vm.expectRevert();
        dm.setMinTradeThreshold(1, 1);

        vm.expectRevert();
        dm.setSettlementWindow(7 days);

        vm.expectRevert();
        dm.setDefaultIntegrator(address(0));

        vm.expectRevert();
        dm.addSpvThresholdCondition(c);

        vm.expectRevert();
        dm.removeSpvThresholdConditionAt(0);

        vm.expectRevert();
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, c);

        vm.expectRevert();
        dm.removePathwayThresholdConditionAt(ExemptionPathway.RULE_144, 0);

        vm.expectRevert();
        dm.addClosingCondition(c);

        vm.expectRevert();
        dm.removeClosingConditionAt(0);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — integrator whitelist
    // ─────────────────────────────────────────────────────────────────────────

    function test_RevertIf_PostOffer_IntegratorNotWhitelisted() public {
        // Integrator never whitelisted on the factory (default mapping is false).
        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_RevertIf_PostOffer_IntegratorNotWhitelisted"));
        p.integrator = makeAddr("integrator");

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.IntegratorNotWhitelisted.selector);
        dm.postOffer(p);
    }

    function test_PostOffer_WhitelistedIntegratorPasses() public {
        address integrator = makeAddr("integrator");
        vm.prank(owner);
        dmFactory.setIntegrator(integrator, true, 0);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_PostOffer_WhitelistedIntegratorPasses"));
        p.integrator = integrator;

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertTrue(offerId != bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer - Min trade thresholds
    // ─────────────────────────────────────────────────────────────────────────

    function test_RevertIf_PostOffer_BelowMinUnits() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS + 1, 0);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly UNITS
    }

    function test_RevertIf_PostOffer_BelowMinConsideration() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION + 1);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly CONSIDERATION
    }

    function test_RevertIf_PostOffer_ZeroUnitsWithFloorsDisabled() public {
        // Floors left disabled (never set), so the min-threshold check is a no-op. A zero-unit offer
        // must still revert — otherwise it would mint an empty, un-acceptable offer.
        PostOfferParams memory p = _defaultSellOfferParams();
        p.units = 0;

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.postOffer(p);
    }

    function test_PostOffer_PassesAtMinThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS, CONSIDERATION);

        {
            vm.prank(seller);
            bytes32 offerId = dm.postOffer(_defaultSellOfferParams()); // exactly at threshold
            assertTrue(offerId != bytes32(0));
        }

        {
            vm.prank(seller);
            bytes32 offerId = dm.postOffer(_defaultBuyOfferParams()); // exactly at threshold
            assertTrue(offerId != bytes32(0));
        }
    }

    function test_RevertIf_AcceptOffer_PartialFillBelowMinUnit() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS, 0); // require full fill

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS - 1, // partial fill, below min
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_PartialFillBelowMinConsideration() public {
        // Units floor disabled, but a half fill's pro-rata consideration (CONSIDERATION/2)
        // is below the admin-set minimum ticket value — acceptance must revert.
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION / 2 + 1);

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2, // pro-rata consideration = CONSIDERATION / 2, below min
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_ZeroUnitsWithFloorsDisabled() public {
        // Floors left disabled (never set), so the min-threshold check is a no-op. A zero-unit fill
        // must still revert — otherwise it would mint an empty settlement.
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: 0,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_PartialFillLeavesSubFloorRemainderUnits() public {
        // Floors below the full offer (postOffer passes) but the fill would leave a units remainder below
        // the floor. Rejecting it keeps the offer's tail above the floor, so no exhausting-lot exemption
        // is ever needed.
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS / 4, CONSIDERATION / 4); // 25 units / 2.5 ether

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: (UNITS * 9) / 10, // 90 units → 10-unit remainder, below the 25-unit floor
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_PartialFillLeavesSubFloorRemainderConsideration() public {
        // Units floor disabled; the fill clears its own consideration floor but would leave a consideration
        // remainder below it. The remainder check must reject it.
        vm.prank(owner);
        dm.setMinTradeThreshold(0, (CONSIDERATION * 3) / 10); // 3 ether floor

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: (UNITS * 8) / 10, // 80 units → pro-rata 8 ether (ok), remainder 2 ether < 3 ether floor
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.acceptOffer(p);
    }

    function test_AcceptOffer_ExhaustingFinalLotNeedsNoExemption() public {
        // With the remainder kept above the floor on every partial fill, the lot that finally exhausts the
        // offer is provably above the floor and settles with no exemption. Splitting 100 as 75 + 25 (vs the
        // old 90 + sub-floor 10) keeps both lots — and the remainder between them — above the floor.
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS / 4, CONSIDERATION / 4); // 25 units / 2.5 ether

        bytes32 offerId = _postSellOffer();

        // First fill: 75 units / 7.5 ether, leaving a 25-unit / 2.5-ether remainder (exactly at the floor).
        _acceptSellOfferPartial(offerId, (UNITS * 3) / 4);

        // Final lot exhausts the offer; no remainder check runs on it.
        bytes32 settlementId = _acceptSellOfferPartial(offerId, UNITS - (UNITS * 3) / 4);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED), "final lot should fully accept the offer");
        assertEq(offer.unitsAccepted, UNITS);
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            CONSIDERATION - (CONSIDERATION * 3) / 4,
            "final lot settles the leftover consideration"
        );
    }

    function test_AcceptOffer_PartialFill_NoThresholds_AllowsTinyLotAndRemainder() public {
        // Floors left disabled (never set): partial fills of any size are allowed, including a tiny lot that
        // leaves a large remainder and a tail fill that leaves a single-unit remainder. Neither the accepted
        // lot nor the remainder is floored, so the only guard is the zero-unit reject.
        bytes32 offerId = _postSellOffer();

        // Tiny first lot leaves a 99-unit remainder.
        _acceptSellOfferPartial(offerId, 1);
        // Next lot leaves a single-unit remainder.
        _acceptSellOfferPartial(offerId, UNITS - 2);
        // Exhaust the single-unit tail.
        bytes32 settlementId = _acceptSellOfferPartial(offerId, 1);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED), "tiny fills should fully accept with no floors");
        assertEq(offer.unitsAccepted, UNITS);
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            CONSIDERATION - (CONSIDERATION * 1) / UNITS - (CONSIDERATION * (UNITS - 2)) / UNITS,
            "final lot takes the leftover consideration"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_CancelOffer_Sell_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "reservation should be released");
        assertEq(_released(sellerTokenId), UNITS, "all units should be marked released");
    }

    function test_CancelOffer_Sell_AfterExpiry_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        // Expiry only blocks acceptOffer; the offeror can still cancel and reclaim the free pool.
        vm.warp(block.timestamp + 2 days);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "reservation should be released");
        assertEq(_released(sellerTokenId), UNITS, "all units should be marked released");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED));
    }

    function test_CancelOffer_Sell_Uncommited() public {
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // LIVE → CANCELLED with nothing committed
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, 0, 0, 0, 0);
    }

    function test_RevertIf_CancelOffer_NotOfferor() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.NotOfferor.selector);
        dm.cancelOffer(offerId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_CancelOffer_BuyOffer_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(paymentToken.balanceOf(buyer), buyerBalanceBefore + CONSIDERATION, "buyer should be refunded");
    }

    function test_CancelOffer_BuyOffer_AfterExpiry_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        // Expiry only blocks acceptOffer; the offeror can still cancel and reclaim the free pool.
        vm.warp(block.timestamp + 2 days);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(paymentToken.balanceOf(buyer), buyerBalanceBefore + CONSIDERATION, "buyer should be refunded");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED));
    }

    function test_CancelOffer_Buy_Uncommited() public {
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // LIVE → CANCELLED with nothing committed
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, 0, 0, 0, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — outstanding settlements stay active
    // ─────────────────────────────────────────────────────────────────────────

    function test_CancelOffer_Sell_PartiallyFilled() public {
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        uint256 lotUnits = UNITS / 2;
        bytes32 settlementId = _acceptSellOfferPartial(offerId, lotUnits);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // → CANCELLED with a lot outstanding: the committed lot's counters stay
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, lotUnits, CONSIDERATION * lotUnits / UNITS, 0, 1);

        // Cancel returns only the free pool; the accepted lot stays ACCEPTED and resolvable.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "active lot not refunded by cancel");
        assertEq(certPrinter.unitsReserved(sellerTokenId), lotUnits, "committed lot stays reserved");
        assertEq(_released(sellerTokenId), UNITS - lotUnits, "only free units released");
    }

    function test_CancelOffer_Buy_PartiallyFilled() public {
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementId = _acceptBuyOfferPartial(offerId, 40);
        uint256 lotPayment = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // → CANCELLED with a lot outstanding: the committed lot's counters stay
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, 40, lotPayment, 0, 1);

        // Cancel refunds only the free pool; the accepted lot's funds stay in custody.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + (CONSIDERATION - lotPayment),
            "only free pool refunded at cancel"
        );
        assertEq(paymentToken.balanceOf(address(dm)), lotPayment, "committed lot's funds stay in custody");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 40, "seller's lot reservation held");
    }

    function test_CancelOffer_Sell_FullyFilled() public {
        // Fully-filled variant of the partial case: no free pool to release; the committed lot
        // stays ACCEPTED and its units stay reserved.
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // → CANCELLED while fully accepted: the full fill's counters stay committed
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, UNITS, CONSIDERATION, 0, 1);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "committed lot not refunded by cancel");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "no free units: full reservation held");
        assertEq(_released(sellerTokenId), 0, "nothing released: offer was fully accepted");
    }

    function test_CancelOffer_Buy_FullyFilled() public {
        // Fully-filled variant of the partial case: no free pool to refund; the committed lot's
        // funds stay in custody.
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementId = _acceptBuyOffer(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // → CANCELLED while fully accepted: the full fill's counters stay committed
        _assertOfferState(offerId, baseline, OfferStatus.CANCELLED, UNITS, CONSIDERATION, 0, 1);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "no free pool to refund: fully accepted");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "committed lot's funds stay in custody");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "seller's full reservation held");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — sell offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_AcceptOffer_Sell_SingleFullyFills() public {
        // LIVE → FULLY_ACCEPTED directly in a single fill, with no PARTIALLY_ACCEPTED step.
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        bytes32 settlementId = _acceptSellOffer(offerId);

        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 1);

        // ∅ → ACCEPTED: every escrow field is populated for the full lot.
        _assertAcceptedEscrow(settlementId, offerId, buyer, UNITS, CONSIDERATION);

        // True state behind the enum: the buyer's funds are pulled into custody and the seller's
        // units stay reserved (reservation is taken at postOffer for sell offers).
        assertEq(paymentToken.balanceOf(buyer), buyerBefore - CONSIDERATION, "buyer funds pulled");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration held in escrow");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "seller units reserved");

        // Sell: the seller's pre-signed open-endorsement signature is captured on the escrow (asserted by
        // _assertAcceptedEscrow above), not written to the token until secondaryTransfer materializes it at finalize.
    }

    function test_AcceptOffer_Sell_MultipleFills() public {
        // Walks the full LIVE → PARTIALLY_ACCEPTED → FULLY_ACCEPTED lifecycle in two fills.
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        uint256 firstUnits = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;
        uint256 expectedFirst = CONSIDERATION * firstUnits / UNITS;
        uint256 expectedSecond = CONSIDERATION * secondUnits / UNITS;
        uint256 buyerStart = paymentToken.balanceOf(buyer);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: firstUnits,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId1 = dm.acceptOffer(p);

        // LIVE → PARTIALLY_ACCEPTED on the first fill
        _assertOfferState(offerId, baseline, OfferStatus.PARTIALLY_ACCEPTED, firstUnits, expectedFirst, 0, 1);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "partial fill keeps the offer's full reservation");
        _assertAcceptedEscrow(settlementId1, offerId, buyer, firstUnits, expectedFirst);
        assertEq(
            paymentToken.balanceOf(buyer), buyerStart - expectedFirst, "buyer pays pro-rata for the first lot only"
        );

        p.units = secondUnits;
        p.acceptorAgreementSig = _acceptorSig(offerId, buyer, buyerKey); // settlement id changes with each fill
        vm.prank(buyer);
        bytes32 settlementId2 = dm.acceptOffer(p);

        // PARTIALLY_ACCEPTED → FULLY_ACCEPTED: each fill is its own pro-rata settlement
        assertTrue(settlementId1 != settlementId2, "each fill gets its own settlement escrow");
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 2);
        // Each lot's escrow is independent and immutable: the second fill leaves the first untouched.
        _assertAcceptedEscrow(settlementId1, offerId, buyer, firstUnits, expectedFirst);
        _assertAcceptedEscrow(settlementId2, offerId, buyer, secondUnits, expectedSecond);
        assertEq(paymentToken.balanceOf(buyer), buyerStart - CONSIDERATION, "buyer has now paid the full consideration");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "both lots held in custody");
    }

    // TODO WIP: should test buy-offer, too
    function test_AcceptOffer_Sell_FinalLotTakesRoundingRemainder() public {
        // 3 units for 100 tokens: 100 * 1 / 3 floors to 33, so three 1-unit fills would pay
        // 33 + 33 + 33 = 99 and strand 1 token. The final lot must take the leftover consideration.
        PostOfferParams memory params = _defaultSellOfferParams();
        params.units = 3;
        params.consideration = 100;
        params.salt = uint256(keccak256("roundingRemainderOffer"));
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(params);

        bytes32 s1 = _acceptSellOfferPartial(offerId, 1);
        bytes32 s2 = _acceptSellOfferPartial(offerId, 1);
        bytes32 s3 = _acceptSellOfferPartial(offerId, 1);

        assertEq(dm.getSecondaryEscrow(s1).paymentAmount, 33, "first fill floored pro-rata");
        assertEq(dm.getSecondaryEscrow(s2).paymentAmount, 33, "second fill floored pro-rata");
        assertEq(dm.getSecondaryEscrow(s3).paymentAmount, 34, "final lot takes the rounding remainder");

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(
            dm.getSecondaryEscrow(s1).paymentAmount + dm.getSecondaryEscrow(s2).paymentAmount
                + dm.getSecondaryEscrow(s3).paymentAmount,
            100,
            "settlements sum to the full offer consideration"
        );
    }

    function test_RevertIf_AcceptOffer_Sell_UnitsExceedOffer() public {
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS + 1,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_Sell_OverfillAfterPartialFill() public {
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        dm.acceptOffer(p);

        p.units = UNITS / 2 + 1; // one more than remaining (reverts before signature check)
        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_RevertIf_AcceptOffer_Buy_CannotAcceptTwice() public {
        bytes32 offerId = _postBuyOffer();

        // Full fill — succeeds
        _acceptBuyOffer(offerId);

        // Second attempt reverts because offer is now FULLY_ACCEPTED
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: OPEN_ENDORSEMENT_SIG
        });
        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferNotAvailable.selector);
        dm.acceptOffer(p);
    }

    function test_RevertIf_AcceptOffer_Buy_UnitsExceedOffer() public {
        bytes32 offerId = _postBuyOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS + 1,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: OPEN_ENDORSEMENT_SIG
        });

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    function test_AcceptOffer_Buy_SingleFullyFills() public {
        // LIVE → FULLY_ACCEPTED directly in a single fill, with no PARTIALLY_ACCEPTED step.
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);

        // Buy offer is pre-funded at postOffer; acceptance must migrate, not pull additional funds.
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "buy offer pre-funded at postOffer");

        bytes32 settlementId = _acceptBuyOffer(offerId);

        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 1);

        // ∅ → ACCEPTED: the escrow opens already-funded, migrated from the holding escrow (acceptor = seller).
        _assertAcceptedEscrow(settlementId, offerId, seller, UNITS, CONSIDERATION);

        // True state behind the enum: funds stay in custody (no second transfer) and the seller's
        // units are reserved at acceptance (buy offers reserve on accept, not at postOffer).
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds remain in DealManager");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "seller units reserved at buy-offer acceptance");

        // Buy offer: the acceptor (seller) signs the open endorsement at acceptance; the signature is captured on the
        // escrow (asserted by _assertAcceptedEscrow above), not written to the token until finalize.
    }

    function test_AcceptOffer_Buy_MultipleFills() public {
        // Walks the full LIVE → PARTIALLY_ACCEPTED → FULLY_ACCEPTED lifecycle in two fills.
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);
        uint256 firstUnits = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;
        uint256 expectedFirst = CONSIDERATION * firstUnits / UNITS;
        uint256 expectedSecond = CONSIDERATION * secondUnits / UNITS;

        bytes32 settlementId1 = _acceptBuyOfferPartial(offerId, firstUnits);

        // LIVE → PARTIALLY_ACCEPTED on the first fill
        _assertOfferState(offerId, baseline, OfferStatus.PARTIALLY_ACCEPTED, firstUnits, expectedFirst, 0, 1);
        _assertAcceptedEscrow(settlementId1, offerId, seller, firstUnits, expectedFirst);
        assertEq(certPrinter.unitsReserved(sellerTokenId), firstUnits, "first lot reserves its own units at acceptance");

        bytes32 settlementId2 = _acceptBuyOfferPartial(offerId, secondUnits);

        // PARTIALLY_ACCEPTED → FULLY_ACCEPTED: each fill is its own pro-rata settlement
        assertTrue(settlementId1 != settlementId2, "each fill gets its own settlement escrow");
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 2);
        // Each lot's escrow is independent and immutable: the second fill leaves the first untouched.
        _assertAcceptedEscrow(settlementId1, offerId, seller, firstUnits, expectedFirst);
        _assertAcceptedEscrow(settlementId2, offerId, seller, secondUnits, expectedSecond);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "both lots now reserved");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "pre-funded consideration stays in custody");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalizeSecondaryTradeAgreement — secondary settlements
    // ─────────────────────────────────────────────────────────────────────────

    function test_FinalizeSecondaryTrade_Sell() public {
        // The offer stays FULLY_ACCEPTED until every lot settles; it only reaches FINALIZED once the
        // last outstanding lot is finalized.
        uint256 unitsA = 40;
        uint256 unitsB = 60;
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;

        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, unitsB);

        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 companyBefore = paymentToken.balanceOf(company);
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "both lots funded in custody");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "all units reserved at postOffer");
        assertEq(certPrinter.balanceOf(buyer), 0, "no buyer cert minted before finalize");

        // Finalize lot A: only this lot settles. The offer stays FULLY_ACCEPTED (unitsFinalized lags
        // unitsAccepted), lot A's units are consumed while lot B stays reserved, seller paid pro-rata.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        // lot A settles: unitsFinalized advances, offer stays FULLY_ACCEPTED until every lot settles
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, unitsA, 2);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot A escrow FINALIZED"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "lot B still ACCEPTED"
        );
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller paid lot A");
        assertEq(_consumed(sellerTokenId), unitsA, "lot A units consumed at finalize");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "lot B units stay reserved while in-flight");
        assertEq(certPrinter.balanceOf(buyer), 1, "buyer cert minted: secondaryTransfer fired on finalize");
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "only lot B's payment remains in custody");
        // secondaryTransfer materializes the seller's endorsement on the Ledger Entry Token at finalize
        // (spec §7.4A): the signature signed in blank now carries the now-known buyer as endorsee, bound to the
        // settlement agreement. Index 1 — index 0 is the issuer endorsement written at mint.
        // (Concrete CyberCertPrinter cast: the ICyberCertPrinter interface's getEndorsementHistory return is stale.)
        Endorsement memory sellerEndorsement =
            CyberCertPrinter(address(certPrinter)).getEndorsementHistory(sellerTokenId, 1);
        assertEq(sellerEndorsement.endorser, seller, "endorser is the seller");
        assertEq(sellerEndorsement.endorsee, buyer, "endorsee is the now-known buyer");
        assertEq(sellerEndorsement.agreementId, settlementIdA, "endorsement bound to the settlement agreement");
        assertEq(sellerEndorsement.endorseeName, SELL_ACCEPT_BUYER_NAME, "buyer name materialized on the endorsement");
        assertEq(sellerEndorsement.signatureHash, OPEN_ENDORSEMENT_SIG, "seller's open-endorsement signature");

        // Finalize lot B (the last lot): offer reaches FINALIZED, reservation fully consumed, custody drained.
        vm.expectEmit(true, false, false, true);
        emit ISecondaryTradeStorage.SecondaryTradeAgreementFinalized(settlementIdB, seller, buyer, unitsB, lotB);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);

        // FULLY_ACCEPTED → FINALIZED once the last lot settles
        _assertOfferState(offerId, baseline, OfferStatus.FINALIZED, UNITS, CONSIDERATION, UNITS, 2);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot B escrow FINALIZED"
        );
        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + CONSIDERATION,
            "seller received full consideration across lots"
        );
        assertEq(_consumed(sellerTokenId), UNITS, "all units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after last lot finalized");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
        assertEq(paymentToken.balanceOf(company), companyBefore, "company payable untouched on secondary path");
    }

    // Accepting a SELL offer keeps the seller's units reserved (escrowed) through settlement, so legal ownership
    // stays frozen between acceptance and finalize: re-registering the seller's Ledger Entry Token reverts at the
    // source.
    function test_RevertIf_AssignReservedCert_AfterAcceptSell() public {
        address newOwner = makeAddr("newLegalOwner");
        bytes32 offerId = _postSellOffer();
        _acceptSellOffer(offerId);

        vm.prank(owner);
        vm.expectRevert(CyberCertPrinter.CertificateReserved.selector);
        im.assignCert(address(certPrinter), seller, sellerTokenId, newOwner, _sellerCertDetails(UNITS));

        // Below verifies DealManager does double-check the legal ownership at every step, but we will never reach there if
        // the cert's reserve rule works as expected
//        assertEq(certPrinter.legalOwnerOf(sellerTokenId), newOwner, "legal owner moved off the seller");
//
//        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeSellerOwnershipChanged.selector);
//        vm.prank(keeper);
//        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // BUY mirror: accepting a buy offer reserves the acceptor's (seller-of-record) units, so re-registering their
    // Ledger Entry Token before finalize likewise reverts at the source.
    function test_RevertIf_AssignReservedCert_AfterAcceptBuy() public {
        address newOwner = makeAddr("newLegalOwner");
        bytes32 offerId = _postBuyOffer();
        _acceptBuyOffer(offerId);

        vm.prank(owner);
        vm.expectRevert(CyberCertPrinter.CertificateReserved.selector);
        im.assignCert(address(certPrinter), seller, sellerTokenId, newOwner, _sellerCertDetails(UNITS));

        // Below verifies DealManager does double-check the legal ownership at every step, but we will never reach there if
        // the cert's reserve rule works as expected
//        assertEq(certPrinter.legalOwnerOf(sellerTokenId), newOwner, "legal owner moved off the acceptor");
//
//        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeSellerOwnershipChanged.selector);
//        vm.prank(keeper);
//        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    function test_FinalizeSecondaryTrade_Buy() public {
        // BUY mirror: the buy offer stays FULLY_ACCEPTED until every lot settles, reaching FINALIZED only
        // once the last outstanding lot is finalized.
        uint256 unitsA = 40;
        uint256 unitsB = 60;
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;

        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementIdA = _acceptBuyOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptBuyOfferPartial(offerId, unitsB);

        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 companyBefore = paymentToken.balanceOf(company);
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "buy offer pre-funded in custody");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "both lots reserved at acceptance");
        assertEq(certPrinter.balanceOf(buyer), 0, "no buyer cert minted before finalize");

        // Finalize lot A: only this lot settles. The buy offer stays FULLY_ACCEPTED, lot A's units are
        // consumed while lot B stays reserved, the acceptor (seller) is paid pro-rata.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        // lot A settles: unitsFinalized advances, buy offer stays FULLY_ACCEPTED until every lot settles
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, unitsA, 2);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot A escrow FINALIZED"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "lot B still ACCEPTED"
        );
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "acceptor (seller) paid lot A");
        assertEq(_consumed(sellerTokenId), unitsA, "lot A units consumed at finalize");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "lot B units stay reserved while in-flight");
        assertEq(certPrinter.balanceOf(buyer), 1, "buyer cert minted: secondaryTransfer fired on finalize");
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "only lot B's payment remains in custody");
        // secondaryTransfer materializes the seller's endorsement on the Ledger Entry Token at finalize
        // (spec §7.4A): the acceptor (seller) is the endorser; the buyer/offeror is the now-known endorsee.
        // Index 1 — index 0 is the issuer endorsement written at mint. The buy offer carries the buyer name; the
        // acceptance carries the signature. (Concrete CyberCertPrinter cast: the interface return is stale.)
        Endorsement memory sellerEndorsement =
            CyberCertPrinter(address(certPrinter)).getEndorsementHistory(sellerTokenId, 1);
        assertEq(sellerEndorsement.endorser, seller, "endorser is the acceptor (seller)");
        assertEq(sellerEndorsement.endorsee, buyer, "endorsee is the buyer");
        assertEq(sellerEndorsement.agreementId, settlementIdA, "endorsement bound to the settlement agreement");
        assertEq(sellerEndorsement.endorseeName, dm.getOffer(offerId).buyerName, "buyer name from the buy offer");
        assertEq(sellerEndorsement.signatureHash, OPEN_ENDORSEMENT_SIG, "signature from the buy-offer acceptance");

        // Finalize lot B (the last lot): buy offer reaches FINALIZED, reservation fully consumed, custody drained.
        vm.expectEmit(true, false, false, true);
        emit ISecondaryTradeStorage.SecondaryTradeAgreementFinalized(settlementIdB, seller, buyer, unitsB, lotB);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);

        // FULLY_ACCEPTED → FINALIZED once the last lot settles
        _assertOfferState(offerId, baseline, OfferStatus.FINALIZED, UNITS, CONSIDERATION, UNITS, 2);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot B escrow FINALIZED"
        );
        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + CONSIDERATION,
            "acceptor received full consideration across lots"
        );
        assertEq(_consumed(sellerTokenId), UNITS, "all units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after last lot finalized");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
        assertEq(paymentToken.balanceOf(company), companyBefore, "company payable untouched on secondary path");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalize after offer cancellation — accepted lots remain finalizable
    // ─────────────────────────────────────────────────────────────────────────

    function test_FinalizeSecondaryTrade_Sell_AfterOfferCancellation() public {
        // Cancelling a SELL offer does not disturb its accepted lots: an already-finalized lot is left
        // untouched, a still-ACCEPTED lot stays reserved and remains finalizable after the cancel, and
        // cancel releases only the free (uncommitted) units. Folds the SELL CancelKeepingLots /
        // KeepsActiveLots cases.
        uint256 unitsA = 40; // finalized before cancel
        uint256 unitsB = 30; // still ACCEPTED at cancel, finalized after
        uint256 freeUnits = UNITS - unitsA - unitsB; // 30, released at cancel
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;

        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller);

        // Finalize lot A before the cancel so we can prove the cancel leaves it untouched.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // Cancel: offer CANCELLED, finalized lot untouched, active lot survives, only free units released.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "finalized lot untouched by cancel"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "active lot stays ACCEPTED after cancel"
        );
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller keeps the finalized payout");
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "active lot's payment stays in custody");
        assertEq(_consumed(sellerTokenId), unitsA, "finalized lot's units consumed exactly once");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "active lot stays reserved");
        assertEq(_released(sellerTokenId), freeUnits, "only the free units released at cancel");

        // The active lot is still finalizable after the offer was cancelled.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "CANCELLED stays sticky");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "active lot finalized after cancel"
        );
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA + lotB, "active lot settles after cancel");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
        assertEq(_consumed(sellerTokenId), unitsA + unitsB, "both finalized lots' units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after last lot finalized");
    }

    function test_FinalizeSecondaryTrade_Buy_AfterOfferCancellation() public {
        // BUY mirror: cancelling a buy offer refunds only the free (uncommitted) consideration to the buyer;
        // an already-finalized lot is untouched and a still-ACCEPTED lot remains finalizable after the
        // cancel, paying the acceptor (seller). Folds the BUY CancelKeepingLots / KeepsActiveLots cases.
        uint256 unitsA = 40; // finalized before cancel
        uint256 unitsB = 30; // still ACCEPTED at cancel, finalized after
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;
        uint256 freePool = CONSIDERATION - lotA - lotB; // refunded to buyer at cancel

        bytes32 offerId = _postBuyOffer();
        bytes32 settlementIdA = _acceptBuyOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptBuyOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        // Finalize lot A before the cancel so we can prove the cancel leaves it untouched.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // Cancel: offer CANCELLED, finalized lot untouched, active lot survives, only the free pool refunded.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "finalized lot untouched by cancel"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "active lot stays ACCEPTED after cancel"
        );
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "acceptor keeps the finalized payout");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBefore + freePool,
            "cancel refunds only the free pool, excludes finalized and active lots"
        );
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "active lot's funds stay in custody");
        assertEq(_consumed(sellerTokenId), unitsA, "finalized lot's units consumed exactly once");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "active lot stays reserved");

        // The active lot is still finalizable after the offer was cancelled.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "CANCELLED stays sticky");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "active lot finalized after cancel"
        );
        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + lotA + lotB,
            "active lot settles after cancel, paid to acceptor"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
        assertEq(_consumed(sellerTokenId), unitsA + unitsB, "both finalized lots' units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after last lot finalized");
    }

    function test_RevertIf_CancelOffer_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferNotAvailable.selector);
        dm.cancelOffer(offerId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // voidExpiredSecondaryTradeAgreement — secondary settlements
    // ─────────────────────────────────────────────────────────────────────────

    function test_VoidExpiredSecondaryTradeAgreement() public {
        // Representative for the expiry path: voidExpired converges on the same _voidSecondaryTradeAgreement as the
        // void/sync paths, so one peer-level case suffices (the before/after-cancel branches are covered
        // through the void path). On a non-cancelled offer the expired settlement voids → offer reverts
        // to LIVE, the acceptor (buyer) is refunded, custody drains, and the SELL reservation is HELD
        // (returned to the free pool, not released) so future acceptors stay protected — the seller must
        // cancelOffer() to release it.
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.expectEmit(true, false, false, false);
        emit ISecondaryTradeStorage.SecondaryTradeAgreementVoided(settlementId);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        // settlement VOIDED, offer reverts to LIVE
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.VOIDED),
            "expired settlement VOIDED"
        );
        _assertOfferState(offerId, baseline, OfferStatus.LIVE, 0, 0, 0, 1);
        // units: reservation held, nothing released or consumed
        assertEq(
            certPrinter.unitsReserved(sellerTokenId), UNITS, "reservation held: offer LIVE, future acceptors protected"
        );
        assertEq(_released(sellerTokenId), 0, "reservation not released while the offer stays open");
        assertEq(_consumed(sellerTokenId), 0, "voided lot never consumed");
        // money: acceptor refunded, custody drained
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "acceptor refunded on expiry void");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    function test_RevertIf_VoidExpiredSecondaryTradeAgreement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided.selector);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_RevertIf_VoidExpiredSecondaryTradeAgreement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");
    }

    function test_RevertIf_VoidExpiredSecondaryTradeAgreement_NotExpired() public {
        // voidExpired only applies past the settlement's expiry — the distinct guard of the expiry path.
        // Before expiry it must refuse and leave the settlement intact and finalizable.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        // Not warped past expiry.
        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementNotExpired.selector);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        // Untouched and still finalizable.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "escrow stays ACCEPTED"
        );
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "units stay reserved");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration stays in custody");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable before expiry"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasSecondaryEscrow discriminator
    // ─────────────────────────────────────────────────────────────────────────

    function test_HasSecondaryEscrow_TrueAfterAccept() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertTrue(se.counterparty != address(0), "SecondaryEscrow should exist after accept");
    }

    // A secondary settlement function rejects a primary deal id (no SecondaryEscrow exists for it).
    // The reverse direction — primary functions rejecting a secondary/unknown id — is a primary-function
    // concern and lives in DealManagerTest.t.sol.
    function test_RevertIf_FinalizeSecondaryTradeAgreement_OnPrimaryDeal() public {
        bytes32 agreementId = _proposePrimaryDeal(995);

        vm.prank(keeper);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryEscrowNotFound.selector);
        dm.finalizeSecondaryTradeAgreement(agreementId);
    }

    function _acceptSellOfferPartial(bytes32 offerAgreementId, uint256 units)
        internal
        returns (bytes32 settlementAgreementId)
    {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: units,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerAgreementId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // voidSecondaryTradeAgreement — reusability + void around offer cancellation
    // ─────────────────────────────────────────────────────────────────────────

    function test_VoidSecondaryTradeAgreement_Sell_FullyAcceptedToLive() public {
        // Walks FULLY_ACCEPTED → PARTIALLY_ACCEPTED → LIVE by voiding the accepted lots one at a
        // time, then proves the offer is genuinely reusable by running a fresh acceptance lifecycle.
        // Each void refunds its buyer immediately and returns units to the free pool, but the SELL
        // reservation stays held throughout — the offer is never cancelled.
        bytes32 offerId = _postSellOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 lotA = _acceptSellOfferPartial(offerId, 40);
        bytes32 lotB = _acceptSellOfferPartial(offerId, 60);
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 2);

        // FULLY_ACCEPTED → PARTIALLY_ACCEPTED: void one of the two lots, the other survives.
        uint256 buyerBeforeB = paymentToken.balanceOf(buyer);
        _voidSettlementBothParties(lotB);

        _assertOfferState(offerId, baseline, OfferStatus.PARTIALLY_ACCEPTED, 40, CONSIDERATION * 40 / UNITS, 0, 2);
        assertEq(
            certPrinter.unitsReserved(sellerTokenId), UNITS, "voided lot returns to free pool, reservation stays held"
        );
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBeforeB + CONSIDERATION * 60 / UNITS,
            "voided lot's buyer is refunded immediately"
        );

        // PARTIALLY_ACCEPTED → LIVE: void the last surviving lot, unitsAccepted → 0.
        uint256 buyerBeforeA = paymentToken.balanceOf(buyer);
        _voidSettlementBothParties(lotA);

        _assertOfferState(offerId, baseline, OfferStatus.LIVE, 0, 0, 0, 2);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "reservation held: offer is LIVE, not cancelled");
        assertEq(_released(sellerTokenId), 0);
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBeforeA + CONSIDERATION * 40 / UNITS,
            "last lot's buyer refunded the pro-rata payment"
        );

        // Ready for another lifecycle: the reverted-to-LIVE offer accepts a fresh full fill.
        bytes32 reaccept = _acceptSellOffer(offerId);
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 3);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "held reservation backs the fresh fill");
        assertEq(
            uint8(dm.getSecondaryEscrow(reaccept).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "fresh settlement opens ACCEPTED"
        );
        assertTrue(reaccept != lotA && reaccept != lotB, "fresh settlement is distinct from the voided lots");
    }

    function test_VoidSecondaryTradeAgreement_Buy_FullyAcceptedToLive() public {
        // BUY mirror: a void releases the acceptor's (seller's) per-lot reservation immediately, and
        // the consideration returns to the offer's free pool and stays in custody (no buyer refund
        // while the offer is open). The buy offer walks FULLY_ACCEPTED → PARTIALLY_ACCEPTED → LIVE and
        // then accepts a fresh lifecycle.
        bytes32 offerId = _postBuyOffer();
        Offer memory baseline = dm.getOffer(offerId);
        bytes32 lotA = _acceptBuyOfferPartial(offerId, 40);
        bytes32 lotB = _acceptBuyOfferPartial(offerId, 60);
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 2);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "both lots reserve the seller's units");

        uint256 buyerBalance = paymentToken.balanceOf(buyer);

        // FULLY_ACCEPTED → PARTIALLY_ACCEPTED: void one lot; the seller's lot reservation is released.
        _voidSettlementBothParties(lotB);

        _assertOfferState(offerId, baseline, OfferStatus.PARTIALLY_ACCEPTED, 40, CONSIDERATION * 40 / UNITS, 0, 2);
        assertEq(certPrinter.unitsReserved(sellerTokenId), 40, "voided lot's seller reservation released");
        assertEq(paymentToken.balanceOf(buyer), buyerBalance, "no buyer refund while offer is open");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration stays whole in custody");

        // PARTIALLY_ACCEPTED → LIVE: void the last lot, unitsAccepted → 0.
        _voidSettlementBothParties(lotA);

        _assertOfferState(offerId, baseline, OfferStatus.LIVE, 0, 0, 0, 2);
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "all seller reservations released");
        assertEq(paymentToken.balanceOf(buyer), buyerBalance, "still no buyer refund: offer open, not cancelled");
        assertEq(
            paymentToken.balanceOf(address(dm)),
            CONSIDERATION,
            "full consideration in custody, ready to back a fresh fill"
        );

        // Ready for another lifecycle: the reverted-to-LIVE buy offer accepts a fresh full fill.
        bytes32 reaccept = _acceptBuyOffer(offerId);
        _assertOfferState(offerId, baseline, OfferStatus.FULLY_ACCEPTED, UNITS, CONSIDERATION, 0, 3);
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "fresh fill re-reserves the seller's units");
        assertEq(
            uint8(dm.getSecondaryEscrow(reaccept).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "fresh settlement opens ACCEPTED"
        );
        assertTrue(reaccept != lotA && reaccept != lotB, "fresh settlement is distinct from the voided lots");
    }

    function test_VoidSecondaryTradeAgreement_Sell_AfterOfferCancellation() public {
        // Mixed-state exactly-once accounting for a cancelled SELL offer that holds one FINALIZED lot,
        // one ACCEPTED lot, and a free pool. The point is not that voiding lot B leaves the already-
        // terminal lot A alone (it trivially does — void only touches B's escrow); it is that across
        // finalize → cancel → void, every unit and every token nets out exactly once: cancel releases
        // only the free units, the void releases lot B's reservation and refunds its consideration to
        // the acceptor (buyer), and lot A's consumed units / disbursed payout are double-counted by
        // neither. Folds the SELL AfterCancel case.
        uint256 unitsA = 40; // finalized before cancel
        uint256 unitsB = 30; // ACCEPTED at cancel, voided after
        uint256 freeUnits = UNITS - unitsA - unitsB; // 30, released at cancel
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;

        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 buyerBefore = paymentToken.balanceOf(buyer); // buyer is the acceptor on a sell offer

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // After cancel: offer CANCELLED, lots intact; only the free units are released.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot A FINALIZED"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "lot B still ACCEPTED"
        );
        // units
        assertEq(_consumed(sellerTokenId), unitsA, "only the finalized lot's units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "active lot stays reserved");
        assertEq(_released(sellerTokenId), freeUnits, "cancel releases only the free units");
        // money
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller holds the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBefore, "acceptor not refunded at cancel (active lot still held)");
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "active lot's consideration stays in custody");

        // Void the remaining ACCEPTED lot after cancellation.
        _voidSettlementBothParties(settlementIdB);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status), uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED"
        );
        // units: voided lot's reservation released; finalized lot's consumed units counted exactly once
        assertEq(_consumed(sellerTokenId), unitsA, "finalized units counted once; voided lot never consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "voided lot's reservation released");
        assertEq(
            _released(sellerTokenId), freeUnits + unitsB, "released == free units + voided lot, finalized excluded"
        );
        // money: voided lot refunded to acceptor; finalized payout untouched; custody fully drained
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller still holds only the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + lotB, "acceptor refunded the voided lot");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained: every token left exactly once");
    }

    function test_VoidSecondaryTradeAgreement_Sell_BeforeOfferCancellation() public {
        // Pairs with VoidSecondaryTradeAgreement_Sell_AfterOfferCancellation: same finalized + voided +
        // free mixed state, but here the void happens BEFORE the cancel. The order flips the offeror-
        // asset branch (SecondaryTradeStorage `_voidSecondaryTradeAgreement`). A SELL offer's units are reserved at
        // postOffer, so while the offer is still open the voided lot's units stay reserved (return to the
        // offer's free pool, NOT released); the later cancel releases them. The acceptor's asset is
        // returned immediately either way — here the buyer's consideration is refunded at the void. This
        // is the SELL mirror of Buy_BeforeOfferCancellation, with the units/payment roles swapped: for
        // SELL the money settles at the void and the units settle at the cancel.
        uint256 unitsA = 40; // finalized
        uint256 unitsB = 30; // voided while offer still open
        uint256 freeUnits = UNITS - unitsA - unitsB; // 30, never accepted
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;

        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 buyerBefore = paymentToken.balanceOf(buyer); // buyer is the acceptor on a sell offer

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        // Void the active lot while the offer is still open: offeror units stay reserved (false arm),
        // acceptor's consideration refunded immediately.
        _voidSettlementBothParties(settlementIdB);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status), uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED"
        );
        // units: voided lot's units return to the free pool but stay reserved while the offer is open
        assertEq(_consumed(sellerTokenId), unitsA, "only the finalized lot's units consumed");
        assertEq(
            certPrinter.unitsReserved(sellerTokenId),
            UNITS - unitsA,
            "voided lot's units stay reserved while offer open"
        );
        assertEq(_released(sellerTokenId), 0, "void while open releases no units (offer can still re-accept)");
        // money: acceptor (buyer) refunded the voided lot immediately; finalized payout untouched; custody drained
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller keeps only the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + lotB, "acceptor refunded the voided lot at void");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "voided lot refunded; only the finalized lot had left custody");

        vm.prank(seller);
        dm.cancelOffer(offerId);

        // Cancel now releases the whole free pool (original remainder + the voided lot's returned units);
        // the money is already settled, so it stays put.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(_consumed(sellerTokenId), unitsA, "finalized units counted exactly once");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "all free units released at cancel");
        assertEq(_released(sellerTokenId), freeUnits + unitsB, "released == free units + voided lot's returned units");
        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + lotA,
            "money already settled at void: seller unchanged by cancel"
        );
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBefore + lotB,
            "money already settled at void: buyer unchanged by cancel"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody stays empty: every token left exactly once");
    }

    function test_VoidSecondaryTradeAgreement_Buy_AfterOfferCancellation() public {
        // BUY mirror, structurally identical to the SELL case above: mixed-state exactly-once
        // accounting for a cancelled buy offer that holds one FINALIZED lot, one ACCEPTED lot, and a free
        // pool. Across finalize → cancel → void every unit and every token nets out once. The
        // side-specific differences are commented inline: a buy offer's offeror asset is money, so cancel
        // refunds the free *consideration* (rather than releasing free units), and the acceptor here is
        // the seller. Folds the BUY AfterCancel case.
        uint256 unitsA = 40; // finalized before cancel
        uint256 unitsB = 30; // ACCEPTED at cancel, voided after
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;
        uint256 freePool = CONSIDERATION - lotA - lotB; // free consideration, refunded at cancel

        bytes32 offerId = _postBuyOffer();
        bytes32 settlementIdA = _acceptBuyOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptBuyOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller); // seller is the acceptor on a buy offer
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // After cancel: offer CANCELLED, lots intact; only the free consideration is refunded.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdA).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "lot A FINALIZED"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "lot B still ACCEPTED"
        );
        // units
        assertEq(_consumed(sellerTokenId), unitsA, "only the finalized lot's units consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), unitsB, "active lot stays reserved");
        // (buy offer reserves per-lot, so "no units released on cancel" is captured by the active lot staying reserved above)
        // money
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "acceptor holds the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + freePool, "buyer refunded only the free consideration");
        assertEq(paymentToken.balanceOf(address(dm)), lotB, "active lot's consideration stays in custody");

        // Void the remaining ACCEPTED lot after cancellation.
        _voidSettlementBothParties(settlementIdB);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status), uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED"
        );
        // units: voided lot's reservation released; finalized lot's consumed units counted exactly once
        assertEq(_consumed(sellerTokenId), unitsA, "finalized units counted once; voided lot never consumed");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "voided lot's reservation released");
        // (buy offer: only the voided lot's reservation is freed — captured by reserved dropping to 0 with consumed==unitsA)
        // money: voided lot refunded to buyer; finalized payout untouched; custody fully drained
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "acceptor still holds only the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + freePool + lotB, "buyer refunded free pool + voided lot");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained: every token left exactly once");
    }

    function test_VoidSecondaryTradeAgreement_Buy_BeforeOfferCancellation() public {
        // Pairs with VoidSecondaryTradeAgreement_Buy_AfterOfferCancellation: same finalized + voided +
        // free mixed state, but here the void happens BEFORE the cancel. The order flips the void refund
        // branch (SecondaryTradeStorage `_voidSecondaryTradeAgreement`): while the offer is still open the voided
        // lot's consideration returns to the free pool and stays in custody (no direct refund); the
        // later cancel then sweeps it out. Either way every unit of consideration leaves custody exactly
        // once — finalized lot via payout, voided lot via the free pool then the cancel refund.
        uint256 unitsA = 40; // finalized
        uint256 unitsB = 30; // voided while offer still open
        uint256 lotA = CONSIDERATION * unitsA / UNITS;
        uint256 lotB = CONSIDERATION * unitsB / UNITS;
        uint256 freePool = CONSIDERATION - lotA - lotB; // never-accepted remainder

        bytes32 offerId = _postBuyOffer();
        bytes32 settlementIdA = _acceptBuyOfferPartial(offerId, unitsA);
        bytes32 settlementIdB = _acceptBuyOfferPartial(offerId, unitsB);
        uint256 sellerBefore = paymentToken.balanceOf(seller); // seller is the acceptor on a buy offer
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        // Void the active lot while the offer is still open: the false arm of the refund branch.
        _voidSettlementBothParties(settlementIdB);

        // No direct refund yet — the voided lot's consideration joins the free pool and stays in custody.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementIdB).status), uint8(SecondaryEscrowStatus.VOIDED), "lot B VOIDED"
        );
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBefore,
            "void while open does not refund; consideration returns to free pool"
        );
        assertEq(
            paymentToken.balanceOf(address(dm)), lotB + freePool, "voided lot + free pool held in custody until cancel"
        );

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        // Cancel sweeps the whole free pool (original remainder + the voided lot) out to the buyer,
        // excluding only the finalized lot's disbursed payout.
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotA, "seller keeps only the finalized payout");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBefore + freePool + lotB,
            "refund covers free pool plus voided lot, excludes finalized lot"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained: every token left exactly once");
    }

    function test_CancelOffer_BuyOffer_AfterFinalizedFill_RefundsOnlyFreePool() public {
        // A finalized lot's payment is disbursed to the seller and must never return to the
        // offer's free pool: paymentAccepted keeps counting it (decrements on void only).
        bytes32 offerId = _postBuyOffer();
        bytes32 settlementId = _acceptBuyOfferPartial(offerId, 40);
        uint256 lotPayment = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(dm.getOffer(offerId).paymentAccepted, lotPayment, "finalized lot stays counted as accepted");

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + (CONSIDERATION - lotPayment),
            "cancel refunds only the free pool, not the disbursed lot"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained, nothing over-refunded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Terminal-state guards on settled escrows
    // ─────────────────────────────────────────────────────────────────────────

    function test_RevertIf_VoidSecondaryTradeAgreement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided.selector);
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_RevertIf_VoidSecondaryTradeAgreement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyFinalized.selector);
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");
    }

    function test_RevertIf_SyncVoidedSecondaryTradeAgreement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided.selector);
        dm.syncVoidedSecondaryTradeAgreement(settlementId);
    }

    function test_RevertIf_SyncVoidedSecondaryTradeAgreement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyFinalized.selector);
        dm.syncVoidedSecondaryTradeAgreement(settlementId);
    }

    function test_RevertIf_SyncVoidedSecondaryTradeAgreement_NotVoided() public {
        // sync is only a mirror: with no registry-side void (or only a lone, sub-quorum request) it must
        // refuse and leave the settlement fully intact and finalizable — the sync counterpart of the
        // two-party quorum guard. Here one party voids at the registry, which is not enough for quorum.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        registry.voidContractFor(settlementId, buyer, _voidSig(settlementId, buyer, buyerKey));
        assertFalse(registry.isVoided(settlementId), "lone registry request: not voided yet");

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementNotVoided.selector);
        dm.syncVoidedSecondaryTradeAgreement(settlementId);

        // Untouched and still finalizable.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "escrow stays ACCEPTED"
        );
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "units stay reserved");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration stays in custody");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable after a refused sync"
        );
    }

    function test_RevertIf_FinalizeSecondaryTrade_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    function test_RevertIf_FinalizeSecondaryTrade_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided.selector);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    function test_VoidSecondaryTradeAgreement_Sell_SingleRequest_StillFinalizable() public {
        // A void needs a two-party quorum: one party's request records intent only and must leave the
        // settlement fully intact and finalizable. Asserts the escrow/offer state and custody both
        // before and after the lone request, then a clean finalize. SELL: the acceptor (buyer) requests.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 sellerBefore = paymentToken.balanceOf(seller);

        // One party's void request only records intent; it must not void locally or touch any assets.
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "single request must not void the escrow"
        );
        assertFalse(registry.isVoided(settlementId), "registry not voided on a single request");
        assertEq(
            uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED), "offer unchanged by the lone request"
        );
        assertEq(dm.getOffer(offerId).paymentAccepted, CONSIDERATION, "committed consideration unchanged");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "units stay reserved after a lone request");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration stays in custody, nothing refunded");

        // The counterparty can still finalize, and it settles exactly like an untouched settlement.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable after a lone void request"
        );
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FINALIZED), "offer reaches FINALIZED");
        assertEq(paymentToken.balanceOf(seller), sellerBefore + CONSIDERATION, "seller paid in full at finalize");
        assertEq(_consumed(sellerTokenId), UNITS, "all units consumed at finalize");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after finalize");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    function test_VoidSecondaryTradeAgreement_Buy_SingleRequest_StillFinalizable() public {
        // BUY mirror: same two-party quorum rule. A buy offer pre-funds consideration at postOffer and the
        // acceptor (seller) is reserved at accept; a lone void request must leave all of that intact and
        // finalizable. BUY: the acceptor (seller) requests.
        bytes32 offerId = _postBuyOffer();
        bytes32 settlementId = _acceptBuyOffer(offerId);
        uint256 sellerBefore = paymentToken.balanceOf(seller); // seller is the acceptor on a buy offer

        // One party's void request only records intent; it must not void locally or touch any assets.
        vm.prank(seller);
        dm.voidSecondaryTradeAgreement(settlementId, seller, "");

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "single request must not void the escrow"
        );
        assertFalse(registry.isVoided(settlementId), "registry not voided on a single request");
        assertEq(
            uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED), "offer unchanged by the lone request"
        );
        assertEq(dm.getOffer(offerId).paymentAccepted, CONSIDERATION, "committed consideration unchanged");
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "units stay reserved after a lone request");
        assertEq(
            paymentToken.balanceOf(address(dm)),
            CONSIDERATION,
            "pre-funded consideration stays in custody, nothing refunded"
        );

        // The counterparty can still finalize, and it settles exactly like an untouched settlement.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable after a lone void request"
        );
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FINALIZED), "offer reaches FINALIZED");
        assertEq(
            paymentToken.balanceOf(seller), sellerBefore + CONSIDERATION, "acceptor (seller) paid in full at finalize"
        );
        assertEq(_consumed(sellerTokenId), UNITS, "all units consumed at finalize");
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0, "no units reserved after finalize");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    function test_SyncVoidedSecondaryTradeAgreement() public {
        // The sync path's one job: detect a void done directly at the registry (bypassing DealManager)
        // and mirror it into the local escrow via the shared _voidSecondaryTradeAgreement. Asserted to peer level
        // so we're confident the synced settlement lands in the same state as a DealManager-driven void:
        // escrow VOIDED, acceptor (buyer) refunded, SELL reservation returned to the free pool but kept
        // (offer still open, not cancelled), custody drained. The before/after-cancel branches of
        // _voidSecondaryTradeAgreement are exhaustively covered through the void path.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 sellerBefore = paymentToken.balanceOf(seller);
        uint256 buyerBefore = paymentToken.balanceOf(buyer); // buyer is the acceptor on a sell offer

        // Both parties void directly at the registry (bypassing DealManager). Calls don't go through
        // the finalizer, so each needs a real EIP-712 void signature.
        registry.voidContractFor(settlementId, buyer, _voidSig(settlementId, buyer, buyerKey));
        registry.voidContractFor(settlementId, seller, _voidSig(settlementId, seller, sellerKey));
        assertTrue(registry.isVoided(settlementId), "registry voided by both parties directly");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "DealManager escrow not yet synced"
        );

        dm.syncVoidedSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.VOIDED),
            "escrow synced to VOIDED"
        );
        assertEq(
            uint8(dm.getOffer(offerId).status),
            uint8(OfferStatus.LIVE),
            "offer reverts to LIVE on void (open, not cancelled)"
        );
        // money: acceptor refunded in full; offeror (seller) untouched; custody drained
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "buyer refunded on sync");
        assertEq(paymentToken.balanceOf(seller), sellerBefore, "seller (offeror) untouched");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
        // units: voided while offer open → reservation returns to the free pool but stays held, not released
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS, "reservation held: offer open, not cancelled");
        assertEq(_released(sellerTokenId), 0, "no units released while the offer stays open");
        assertEq(_consumed(sellerTokenId), 0, "voided lot never consumed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasSecondaryEscrow discriminator
    // ─────────────────────────────────────────────────────────────────────────

    function test_HasSecondaryEscrow_FalseForPrimaryDeal() public {
        // A primary deal should have no SecondaryEscrow entry
        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        address[] memory parties = new address[](2);
        parties[0] = owner;
        parties[1] = buyer;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);
        address[] memory printers = new address[](1);
        printers[0] = address(certPrinter);

        vm.prank(owner);
        (bytes32 agreementId,) = dm.proposeDeal(
            printers,
            address(paymentToken),
            CONSIDERATION,
            bytes32(0),
            997,
            new string[](0),
            parties,
            certDetails,
            partyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1 days
        );

        SecondaryEscrow memory se = dm.getSecondaryEscrow(agreementId);
        assertEq(se.counterparty, address(0), "primary deal should have no SecondaryEscrow");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Coverage gaps (see specs/analysis/dealManager secondary trades — test coverage map.md)
    // ─────────────────────────────────────────────────────────────────────────

    // Offer-level expiry: acceptOffer past offer.validUntil reverts with OfferExpired. The check runs
    // before any signature/condition work, so an empty acceptor sig still reverts here first.
    function test_RevertIf_AcceptOffer_OfferExpired() public {
        bytes32 offerId = _postSellOffer(); // validUntil = block.timestamp + 1 days

        vm.warp(block.timestamp + 2 days);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.OfferExpired.selector);
        dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Settlement window — settlement expiry runs from acceptance, not offer expiry
    // ─────────────────────────────────────────────────────────────────────────

    function test_GetSettlementWindow_DefaultsWhenUnset() public view {
        assertEq(dm.getSettlementWindow(), 7 days, "unset window falls back to the 7-day default");
    }

    function test_SetSettlementWindow_UpdatesEffectiveWindow() public {
        vm.expectEmit(false, false, false, true, address(dm));
        emit DealManager.SettlementWindowSet(45 days, owner);
        vm.prank(owner);
        dm.setSettlementWindow(45 days);
        assertEq(dm.getSettlementWindow(), 45 days, "configured window overrides the default");
    }

    // Core regression for the truncated-settlement-window finding: a lot accepted moments before the offer
    // expires still gets the full settlement window measured from acceptance, not the offer's imminent validUntil.
    function test_AcceptOffer_SettlementExpiry_RunsFromAcceptance_NotOfferExpiry() public {
        bytes32 offerId = _postSellOffer(); // validUntil = block.timestamp + 1 days
        uint256 offerValidUntil = dm.getOffer(offerId).validUntil;

        // Accept one minute before the offer expires.
        vm.warp(offerValidUntil - 1 minutes);
        bytes32 settlementId = _acceptSellOffer(offerId);

        assertEq(
            dm.getSecondaryEscrow(settlementId).expiry,
            block.timestamp + 7 days,
            "settlement expiry is acceptance time + window, independent of the near offer expiry"
        );
        assertGt(
            dm.getSecondaryEscrow(settlementId).expiry,
            offerValidUntil,
            "settlement outlives the offer it was accepted against"
        );
    }

    function test_AcceptOffer_SettlementExpiry_UsesConfiguredWindow() public {
        vm.prank(owner);
        dm.setSettlementWindow(45 days);

        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(
            dm.getSecondaryEscrow(settlementId).expiry,
            block.timestamp + 45 days,
            "settlement expiry honors the configured window over the default"
        );
    }

    // The compounding case from the finding: an acceptance late in the offer's life used to be
    // unfinalizeable once block.timestamp passed offer.validUntil. With the window running from acceptance,
    // the lot stays finalizeable well past the original offer expiry.
    function test_FinalizeSecondaryTrade_LateAcceptance_StaysFinalizeable() public {
        bytes32 offerId = _postSellOffer(); // validUntil = block.timestamp + 1 days
        uint256 offerValidUntil = dm.getOffer(offerId).validUntil;

        vm.warp(offerValidUntil - 1 minutes);
        bytes32 settlementId = _acceptSellOffer(offerId);

        // Advance past the original offer expiry (but within the settlement window).
        vm.warp(offerValidUntil + 1 days);
        assertLt(block.timestamp, dm.getSecondaryEscrow(settlementId).expiry, "still inside the settlement window");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "late-accepted lot finalizes past the original offer expiry"
        );
    }

    // Voiding one of several lots on a FULLY_ACCEPTED offer leaves unitsAccepted > 0, so the offer
    // reverts to PARTIALLY_ACCEPTED (not LIVE). The SELL lot returns to the offer's free pool and
    // stays reserved (offer not cancelled); only the voided lot's buyer payment is refunded.
    // Nonzero fee path: finalize pays the seller amount minus fee, and the fee splits into an
    // integrator portion (to the offer's integrator/feeDestination) and a platform portion, summing
    // to the total fee. Default tests run fee=0, so this is the only exercise of the split branch.
    function test_FinalizeSecondaryTrade_NonzeroFee_SplitsIntegratorAndPlatform() public {
        address integrator = makeAddr("integrator");
        address platform = makeAddr("platform");

        vm.prank(owner);
        dmFactory.setIntegrator(integrator, true, 3000); // 30% of the fee routes to the integrator
        vm.prank(owner);
        dmFactory.setDefaultFeeRatio(1000); // 10% ticket fee
        vm.prank(owner);
        dmFactory.setPlatformPayable(platform);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_FinalizeSecondaryTrade_NonzeroFee_SplitsIntegratorAndPlatform"));
        p.integrator = integrator;
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        uint256 fee = CONSIDERATION * 1000 / 10000; // 1 ether
        uint256 integratorFee = fee * 3000 / 10000; // 0.3 ether
        uint256 platformFee = fee - integratorFee; // 0.7 ether

        // The event reports the realized split: credited integrator (feeDestination) + the two portions.
        vm.expectEmit(true, true, true, true);
        emit ISecondaryTradeStorage.SecondaryFeeDistributed(
            settlementId, address(paymentToken), integrator, fee, integratorFee, platformFee
        );
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(paymentToken.balanceOf(seller), sellerBefore + CONSIDERATION - fee, "seller paid amount minus fee");
        assertEq(paymentToken.balanceOf(integrator), integratorFee, "integrator gets its fee share");
        assertEq(paymentToken.balanceOf(platform), platformFee, "platform gets the remaining fee");
        assertEq(integratorFee + platformFee, fee, "split is exact: integrator + platform == total fee");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    // Spec §12B.4 fall-through: the integrator is validated at posting, but if it is removed from the
    // factory whitelist before settlement the split must fall through to the unsplit MetaLeX-only flow
    // (full fee to platform, integrator gets nothing) rather than revert — settlement is never blocked.
    function test_FinalizeSecondaryTrade_DewhitelistedIntegrator_FallsThroughToPlatform() public {
        address integrator = makeAddr("integrator");
        address platform = makeAddr("platform");

        vm.prank(owner);
        dmFactory.setIntegrator(integrator, true, 3000);
        vm.prank(owner);
        dmFactory.setDefaultFeeRatio(1000);
        vm.prank(owner);
        dmFactory.setPlatformPayable(platform);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_FinalizeSecondaryTrade_DewhitelistedIntegrator_FallsThroughToPlatform"));
        p.integrator = integrator;
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);

        // Integrator loses whitelist status after the binding contract has formed.
        vm.prank(owner);
        dmFactory.setIntegrator(integrator, false, 0);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        uint256 fee = CONSIDERATION * 1000 / 10000; // 1 ether

        // Fall-through: feeDestination zero, no integrator share, full fee to the platform.
        vm.expectEmit(true, true, true, true);
        emit ISecondaryTradeStorage.SecondaryFeeDistributed(
            settlementId, address(paymentToken), address(0), fee, 0, fee
        );
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(paymentToken.balanceOf(seller), sellerBefore + CONSIDERATION - fee, "seller paid amount minus fee");
        assertEq(paymentToken.balanceOf(integrator), 0, "de-whitelisted integrator gets nothing");
        assertEq(paymentToken.balanceOf(platform), fee, "full fee falls through to platform");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    // Closing conditions are owner-managed DealManager config, snapshotted onto the offer at postOffer and
    // evaluated at finalizeDeal — distinct from the threshold conditions checked at post/accept. A failing
    // closing condition must block finalize.
    function test_RevertIf_FinalizeSecondaryTrade_ClosingConditionFails() public {
        // Register the closing condition before posting so it is snapshotted onto the offer.
        // Deploy before vm.prank: the CREATE would otherwise consume the prank for addClosingCondition.
        address failing = address(new SecConditionMock(false));
        vm.prank(owner);
        dm.addClosingCondition(failing);

        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, failing));
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // TODO rename and refactor legacy `FinalizeDeal_` tests
    // Counterpart: a passing closing condition lets finalize through, proving the finalize-time
    // check runs and is not an unconditional block.
    function test_FinalizeSecondaryTrade_ClosingConditionPasses() public {
        // Register the closing condition before posting so it is snapshotted onto the offer.
        // Deploy before vm.prank: the CREATE would otherwise consume the prank for addClosingCondition.
        address passing = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addClosingCondition(passing);

        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "finalize proceeds when the closing condition passes"
        );
    }

    // Threshold conditions are re-checked at finalization (spec §7.3.3): a buyer eligible at acceptance
    // who loses eligibility before settlement must be blocked. The flippable condition passes through
    // posting and acceptance, is flipped to fail, and the finalize call must revert.
    function test_RevertIf_FinalizeSecondaryTrade_ThresholdConditionLapsesAfterAcceptance() public {
        SecFlippableConditionMock cond = new SecFlippableConditionMock(true);
        address[] memory conds = new address[](1);
        conds[0] = address(cond);
        _registerThresholdConditions(conds);

        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId); // passes while eligible

        cond.setPass(false); // eligibility lapses in the settlement window

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(cond))
        );
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // Counterpart: a threshold condition that still passes at finalize lets the settlement close,
    // proving the re-check runs and is not an unconditional block.
    function test_FinalizeSecondaryTrade_ThresholdConditionStillPasses() public {
        SecFlippableConditionMock cond = new SecFlippableConditionMock(true);
        address[] memory conds = new address[](1);
        conds[0] = address(cond);
        _registerThresholdConditions(conds);

        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "finalize proceeds when the re-checked threshold condition still passes"
        );
    }

    // Re-posting the same offeror/template/salt collides on the derived offerId and reverts.
    function test_RevertIf_PostOffer_OfferAlreadyExists() public {
        _postSellOffer();

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferAlreadyExists.selector);
        dm.postOffer(_defaultSellOfferParams()); // same salt → same offerId
    }

    // voidSecondaryTradeAgreement requires the declared signer to equal msg.sender.
    function test_RevertIf_VoidSecondaryTradeAgreement_SignerNotCaller() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.NotSigner.selector);
        dm.voidSecondaryTradeAgreement(settlementId, seller, ""); // signer=seller, caller=buyer
    }

    // A caller who is neither the offeror nor the settlement counterparty cannot request a void.
    function test_RevertIf_VoidSecondaryTradeAgreement_NotPartyToAgreement() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(ISecondaryTradeStorage.NotPartyToAgreement.selector);
        dm.voidSecondaryTradeAgreement(settlementId, stranger, "");
    }

    // finalizeSecondaryTradeAgreement past the settlement's expiry reverts. The settlement agreement's
    // registry expiry equals secEscrow.expiry (both = acceptance time + settlement window), so the registry
    // finalizeContract call reverts ContractExpired before the escrow's own SecondaryTradeAgreementExpired guard is
    // reached — that guard is defensive/unreachable for secondary settlements in normal flow.
    function test_RevertIf_FinalizeSecondaryTrade_PastSettlementExpiry() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);

        vm.prank(keeper);
        vm.expectRevert(CyberAgreementRegistry.ContractExpired.selector);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // Voiding the single partial lot of a PARTIALLY_ACCEPTED offer drops unitsAccepted to 0, so the
    // offer returns to LIVE. The reservation is held (offer not cancelled) and the buyer is refunded.
    // acceptOffer emits OfferAccepted with the offer id, acceptor, and units (settlement id is
    // computed inside, so its topic is not checked).
    function test_AcceptOffer_EmitsOfferAccepted() public {
        bytes32 offerId = _postSellOffer();
        // Compute the acceptor sig before vm.expectEmit/vm.prank: its registry view calls would
        // otherwise consume the prank.
        bytes memory sig = _acceptorSig(offerId, buyer, buyerKey);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: sig,
            openEndorsementSig: ""
        });

        // Check offerId + acceptor topics and the full data; skip only the settlement id topic, which is
        // computed internally and can't be predicted here.
        vm.expectEmit(true, false, true, true);
        emit ISecondaryTradeStorage.OfferAccepted(
            offerId,
            bytes32(0),
            buyer,
            UNITS,
            address(paymentToken),
            CONSIDERATION,
            sellerTokenId,
            block.timestamp + 7 days,
            SELL_ACCEPT_BUYER_NAME,
            HostingMode.DIRECT,
            address(0),
            OPEN_ENDORSEMENT_SIG
        );
        vm.prank(buyer);
        dm.acceptOffer(p);
    }

    // cancelOffer emits OfferCancelled with the offer id and offeror.
    function test_CancelOffer_EmitsOfferCancelled() public {
        bytes32 offerId = _postSellOffer();

        vm.expectEmit(true, true, false, false);
        emit ISecondaryTradeStorage.OfferCancelled(offerId, seller);
        vm.prank(seller);
        dm.cancelOffer(offerId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Relayer overloads — EIP-712 authorization on behalf of `forAddr`
    // ─────────────────────────────────────────────────────────────────────────

    // The two param-type strings must byte-match SecondaryTradeStorage's typehash literals.
    string constant _POST_PARAMS_TYPE =
        "PostOfferParams(uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,address integrator,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues,bytes offerorAgreementSig,bytes openEndorsementSig,string buyerName,uint8 buyerHostingMode,address adminMultisig)";
    string constant _ACCEPT_PARAMS_TYPE =
        "AcceptOfferParams(bytes32 offerId,uint256 units,string buyerName,uint8 buyerHostingMode,address adminMultisig,uint256 sellerTokenId,string[] acceptorPartyValues,bytes acceptorAgreementSig,bytes openEndorsementSig)";

    function _dmDomainSep() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("DealManager")),
            keccak256(bytes("1")),
            block.chainid,
            address(dm)
        ));
    }

    function _hashStrs(string[] memory arr) internal pure returns (bytes32) {
        bytes32[] memory h = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) h[i] = keccak256(bytes(arr[i]));
        return keccak256(abi.encodePacked(h));
    }

    function _hashPostParams(PostOfferParams memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256(bytes(_POST_PARAMS_TYPE)),
            uint8(p.side), p.certPrinter, p.tokenId, p.units, p.paymentToken, p.consideration,
            uint8(p.exemptionPathway), p.validUntil, keccak256(p.counterpartyRestrictions),
            keccak256(p.additionalTerms), p.integrator, p.templateId, p.salt,
            _hashStrs(p.globalValues), _hashStrs(p.offerorPartyValues), keccak256(p.offerorAgreementSig),
            keccak256(p.openEndorsementSig), keccak256(bytes(p.buyerName)), uint8(p.buyerHostingMode), p.adminMultisig
        ));
    }

    function _hashAcceptParams(AcceptOfferParams memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256(bytes(_ACCEPT_PARAMS_TYPE)),
            p.offerId, p.units, keccak256(bytes(p.buyerName)), uint8(p.buyerHostingMode),
            p.adminMultisig, p.sellerTokenId, _hashStrs(p.acceptorPartyValues),
            keccak256(p.acceptorAgreementSig), keccak256(p.openEndorsementSig)
        ));
    }

    function _sign(bytes32 structHash, uint256 key) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _dmDomainSep(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _postAuthSig(PostOfferParams memory p, address forAddr, uint256 nonce, uint256 key)
        internal view returns (bytes memory)
    {
        bytes32 typeHash = keccak256(bytes(string.concat(
            "PostOfferAuth(PostOfferParams params,address forAddr,uint256 nonce)", _POST_PARAMS_TYPE)));
        return _sign(keccak256(abi.encode(typeHash, _hashPostParams(p), forAddr, nonce)), key);
    }

    function _acceptAuthSig(AcceptOfferParams memory p, address forAddr, uint256 nonce, uint256 key)
        internal view returns (bytes memory)
    {
        bytes32 typeHash = keccak256(bytes(string.concat(
            "AcceptOfferAuth(AcceptOfferParams params,address forAddr,uint256 nonce)", _ACCEPT_PARAMS_TYPE)));
        return _sign(keccak256(abi.encode(typeHash, _hashAcceptParams(p), forAddr, nonce)), key);
    }

    function _cancelAuthSig(bytes32 offerId, address forAddr, uint256 nonce, uint256 key)
        internal view returns (bytes memory)
    {
        bytes32 typeHash = keccak256("CancelOfferAuth(bytes32 offerId,address forAddr,uint256 nonce)");
        return _sign(keccak256(abi.encode(typeHash, offerId, forAddr, nonce)), key);
    }

    function _voidAuthSig(bytes32 agreementId, address signer, bytes memory signature, uint256 nonce, uint256 key)
        internal view returns (bytes memory)
    {
        bytes32 typeHash = keccak256("VoidSecondaryTradeAuth(bytes32 agreementId,address signer,bytes32 signatureHash,uint256 nonce)");
        return _sign(keccak256(abi.encode(typeHash, agreementId, signer, keccak256(signature), nonce)), key);
    }

    function _sellAcceptParams(bytes32 offerId) internal view returns (AcceptOfferParams memory) {
        return AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: SELL_ACCEPT_BUYER_NAME,
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
    }

    // A relayer posts a SELL offer for the seller: identity + reservation attribute to `forAddr`.
    function test_PostOffer_Relayer_SellAttributesToForAddr() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p = _defaultSellOfferParams();
        bytes memory sig = _postAuthSig(p, seller, 7, sellerKey);

        vm.prank(relayer);
        bytes32 offerId = dm.postOffer(p, seller, 7, sig);

        assertEq(dm.getOffer(offerId).offeror, seller);
        assertEq(offerId, keccak256(abi.encode(seller, p.templateId, p.salt)));
        assertEq(certPrinter.unitsReserved(sellerTokenId), UNITS);
    }

    // A relayer posts a BUY offer for the buyer: consideration is pulled from `forAddr`, not the relayer
    // (the relayer holds no tokens/allowance, so success proves the pull came from `forAddr`).
    function test_PostOffer_Relayer_BuyPullsFromForAddr() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p = _defaultBuyOfferParams();
        uint256 buyerBefore = paymentToken.balanceOf(buyer);
        bytes memory sig = _postAuthSig(p, buyer, 1, buyerKey);

        vm.prank(relayer);
        bytes32 offerId = dm.postOffer(p, buyer, 1, sig);

        assertEq(dm.getOffer(offerId).offeror, buyer);
        assertEq(paymentToken.balanceOf(buyer), buyerBefore - CONSIDERATION);
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION);
    }

    // A relayer cancels the seller's offer: status flips and the reservation is released.
    function test_CancelOffer_Relayer() public {
        bytes32 offerId = _postSellOffer();
        address relayer = makeAddr("relayer");
        bytes memory sig = _cancelAuthSig(offerId, seller, 3, sellerKey);

        vm.prank(relayer);
        dm.cancelOffer(offerId, seller, 3, sig);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED));
        assertEq(certPrinter.unitsReserved(sellerTokenId), 0);
    }

    // A relayer accepts a SELL offer for the buyer: escrow counterparty is `forAddr` and payment is pulled
    // from `forAddr`.
    function test_AcceptOffer_Relayer_AttributesToForAddr() public {
        bytes32 offerId = _postSellOffer();
        address relayer = makeAddr("relayer");
        AcceptOfferParams memory p = _sellAcceptParams(offerId);
        uint256 buyerBefore = paymentToken.balanceOf(buyer);
        bytes memory sig = _acceptAuthSig(p, buyer, 9, buyerKey);

        vm.prank(relayer);
        bytes32 settlementId = dm.acceptOffer(p, buyer, 9, sig);

        assertEq(dm.getSecondaryEscrow(settlementId).counterparty, buyer);
        assertEq(paymentToken.balanceOf(buyer), buyerBefore - CONSIDERATION);
    }

    // A signature by the wrong key does not recover to `forAddr`.
    function test_RevertIf_Relayer_WrongSigner() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p = _defaultSellOfferParams();
        bytes memory sig = _postAuthSig(p, seller, 1, buyerKey); // signed by buyer, not seller

        vm.prank(relayer);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryAuthSignature.selector);
        dm.postOffer(p, seller, 1, sig);
    }

    // Tampering with an authorized field (here `forAddr`) breaks recovery.
    function test_RevertIf_Relayer_TamperedForAddr() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p = _defaultSellOfferParams();
        bytes memory sig = _postAuthSig(p, seller, 1, sellerKey);

        vm.prank(relayer);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryAuthSignature.selector);
        dm.postOffer(p, buyer, 1, sig); // forAddr swapped to buyer; sig was over seller
    }

    // Reusing a consumed nonce is rejected at the auth layer (before any downstream state check).
    function test_RevertIf_Relayer_ReplayNonce() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p = _defaultSellOfferParams();
        bytes memory sig = _postAuthSig(p, seller, 5, sellerKey);

        vm.prank(relayer);
        dm.postOffer(p, seller, 5, sig);

        vm.prank(relayer);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryAuthReplayed.selector);
        dm.postOffer(p, seller, 5, sig);
    }

    // Unordered nonces: two authorizations with different, out-of-order nonces both succeed.
    function test_Relayer_UnorderedNonces() public {
        address relayer = makeAddr("relayer");
        PostOfferParams memory p1 = _defaultSellOfferParams();
        p1.salt = uint256(keccak256("relayerUnordered1"));
        p1.units = 30;
        PostOfferParams memory p2 = _defaultSellOfferParams();
        p2.salt = uint256(keccak256("relayerUnordered2"));
        p2.units = 30;
        bytes memory sig1 = _postAuthSig(p1, seller, 100, sellerKey);
        bytes memory sig2 = _postAuthSig(p2, seller, 5, sellerKey);

        vm.prank(relayer);
        dm.postOffer(p1, seller, 100, sig1);
        vm.prank(relayer);
        dm.postOffer(p2, seller, 5, sig2);

        assertEq(certPrinter.unitsReserved(sellerTokenId), 60);
    }

    // The direct and relayer postOffer overloads present distinct selectors to conditions. A phase-gating
    // threshold condition registers both, so it is satisfied whether the offer is posted directly or via the
    // relayer overload — the real-world pattern documented on ISecondaryTradingCondition.
    function test_ThresholdCondition_HandlesBothPostOfferOverloads() public {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = bytes4(keccak256("postOffer(PostOfferParams)"));                       // direct
        sels[1] = bytes4(keccak256("postOffer(PostOfferParams,address,uint256,bytes)")); // relayer
        SecSelectorAssertingConditionMock cond = new SecSelectorAssertingConditionMock(sels);
        vm.prank(owner);
        dm.addSpvThresholdCondition(address(cond));

        // direct path
        PostOfferParams memory pd = _defaultSellOfferParams();
        pd.salt = uint256(keccak256("bothOverloadsDirect"));
        pd.units = 30;
        vm.prank(seller);
        dm.postOffer(pd);

        // relayer path
        PostOfferParams memory pr = _defaultSellOfferParams();
        pr.salt = uint256(keccak256("bothOverloadsRelayer"));
        pr.units = 30;
        bytes memory sig = _postAuthSig(pr, seller, 2, sellerKey);
        vm.prank(makeAddr("relayer"));
        dm.postOffer(pr, seller, 2, sig);

        // both offers cleared the same phase condition
        assertEq(certPrinter.unitsReserved(sellerTokenId), 60);
    }

    // A relayer submits each party's void request on their behalf via the nonce'd overload; once both
    // parties have requested, the settlement is voided (a subsequent void reverts AlreadyVoided).
    function test_Relayer_VoidSecondaryTradeAgreement() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        address relayer = makeAddr("relayer");

        bytes memory buyerAuth = _voidAuthSig(settlementId, buyer, "", 11, buyerKey);
        vm.prank(relayer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "", 11, buyerAuth);

        bytes memory sellerAuth = _voidAuthSig(settlementId, seller, "", 12, sellerKey);
        vm.prank(relayer);
        dm.voidSecondaryTradeAgreement(settlementId, seller, "", 12, sellerAuth);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided.selector);
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");
    }

    // The relayer void auth must recover to `signer`; a signature by anyone else is rejected.
    function test_RevertIf_Relayer_VoidSecondaryTradeAgreement_WrongSigner() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        bytes memory badAuth = _voidAuthSig(settlementId, buyer, "", 1, sellerKey); // signed by seller, claims buyer
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryAuthSignature.selector);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "", 1, badAuth);
    }

    // Reusing a consumed nonce for the same signer is rejected as a replay.
    function test_RevertIf_Relayer_VoidSecondaryTradeAgreement_ReplayNonce() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        bytes memory auth = _voidAuthSig(settlementId, buyer, "", 4, buyerKey);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "", 4, auth);

        bytes memory replay = _voidAuthSig(settlementId, buyer, "", 4, buyerKey);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryAuthReplayed.selector);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "", 4, replay);
    }
}
