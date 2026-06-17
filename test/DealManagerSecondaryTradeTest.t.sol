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

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DealManager} from "../src/DealManager.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {ISecondaryTradeStorage} from "../src/interfaces/ISecondaryTradeStorage.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails, Endorsement} from "../src/storage/CyberCertPrinterStorage.sol";
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
import {EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract SecERC20Mock is ERC20 {
    constructor() ERC20("Payment Token", "PAY") {}
    function mint(address to, uint256 amount) public { _mint(to, amount); }
}

// TODO review after CyberCertPrinter updated
contract SecCertPrinterMock is ERC721Enumerable {
    mapping(uint256 => uint256) public reservedUnits;
    mapping(uint256 => uint256) public releasedUnits;  // cumulative
    mapping(uint256 => uint256) public consumedUnits;  // cumulative
    mapping(uint256 => Endorsement[]) private _endorsements;

    constructor() ERC721("Ledger Entry Token", "LET") {}

    function mint(address to) public returns (uint256 tokenId) {
        tokenId = totalSupply();
        _safeMint(to, tokenId);
    }

    function reserveUnits(uint256 tokenId, uint256 units) external {
        reservedUnits[tokenId] += units;
    }

    function releaseUnits(uint256 tokenId, uint256 units) external {
        reservedUnits[tokenId] -= units;
        releasedUnits[tokenId] += units;
    }

    function consumeUnits(uint256 tokenId, uint256 units) external {
        reservedUnits[tokenId] -= units;
        consumedUnits[tokenId] += units;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory e) external {
        _endorsements[tokenId].push(e);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract SecIssuanceManagerMock {
    bool public secondaryTransferCalled;
    bool public attachOpenEndorsementCalled;

    function createCert(address certAddress, address to, CertificateDetails memory) external returns (uint256) {
        return SecCertPrinterMock(certAddress).mint(to);
    }

    function secondaryTransfer(bytes calldata dealMetadata) external {
        secondaryTransferCalled = true;
        // Mirror the pending real implementation: consume this lot's reserved units
        (address certPrinter, uint256 tokenId, uint256 units,,,,,,) = abi.decode(
            dealMetadata,
            (address, uint256, uint256, address, string, uint8, address, ExemptionPathway, bytes32)
        );
        SecCertPrinterMock(certPrinter).consumeUnits(tokenId, units);
    }

    function attachOpenEndorsement(
        address, uint256, address, address, bytes calldata, bytes32
    ) external {
        attachOpenEndorsementCalled = true;
    }

    function voidCertificate(address certAddress, uint256 tokenId) external {
        SecCertPrinterMock(certAddress).burn(tokenId);
    }
}

contract SecCorpMock {
    address public companyPayable;
    constructor(address _cp) { companyPayable = _cp; }
}

contract SecConditionMock {
    bool private _pass;
    constructor(bool pass_) { _pass = pass_; }
    function checkCondition(address, bytes4, bytes memory) external view returns (bool) { return _pass; }
}

// Mirrors a real seller-side threshold condition: it reads the offer back via getOffer(offerId)
// (per specs/analysis/conditions.md) and derives eligibility from its fields. Returns false if the
// offer is unreadable — which is what the pre-fix ordering produced, since the condition loop ran
// before the offer was stored.
contract SecOfferReadingConditionMock {
    function checkCondition(address _contract, bytes4, bytes memory data) external view returns (bool) {
        bytes32 offerId = abi.decode(data, (bytes32));
        Offer memory o = IDealManager(_contract).getOffer(offerId);
        return o.offeror != address(0) && o.certPrinter != address(0);
    }
}

// Mirrors a real buyer-facing threshold condition (KYC/accreditation/holder-cap): it short-circuits
// to `true` at posting when the offer has no settlements yet, and enforces once an acceptor exists.
// Used to prove acceptOffer re-evaluates threshold conditions (post-fix); pre-fix it never ran here.
contract SecBuyerFacingConditionMock {
    bool private _acceptorAllowed;
    constructor(bool acceptorAllowed_) { _acceptorAllowed = acceptorAllowed_; }
    function checkCondition(address _contract, bytes4, bytes memory data) external view returns (bool) {
        bytes32 offerId = abi.decode(data, (bytes32));
        Offer memory o = IDealManager(_contract).getOffer(offerId);
        if (o.settlementAgreementIds.length == 0) return true; // posting context: no buyer yet
        return _acceptorAllowed;                               // acceptance context: enforce
    }
}

contract DealManagerFactoryHelper is DealManagerFactory {
    bool private _integWhitelisted;
    uint256 private _integratorFeeRatio;

    function setIsIntegratorWhitelisted(bool v) external { _integWhitelisted = v; }
    function isIntegratorWhitelisted(address) external view returns (bool) { return _integWhitelisted; }
    function setIntegratorFeeRatio(uint256 v) external { _integratorFeeRatio = v; }
    function getIntegratorFeeRatio() external view returns (uint256) { return _integratorFeeRatio; }
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
    address public company;

    SecERC20Mock      public paymentToken;
    SecCertPrinterMock public certPrinter;
    SecIssuanceManagerMock public im;
    CyberAgreementRegistry public registry;
    SecCorpMock        public corp;
    DealManagerFactoryHelper   public dmFactory;
    DealManager        public dm;
    BorgAuth           public auth;

    // Single template (empty global/party fields) reused for every offer and the primary regression deals.
    bytes32 public constant TEMPLATE_ID = bytes32(0);
    string public constant TEMPLATE_URI = "ipfs://secondary-template";

    uint256 public constant CONSIDERATION = 10 ether;
    uint256 public constant UNITS         = 100;
    uint256 public sellerTokenId;

    function setUp() public {
        (owner, ownerKey)   = makeAddrAndKey("owner");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey)   = makeAddrAndKey("buyer");
        keeper = makeAddr("keeper");
        company = makeAddr("company");

        paymentToken = new SecERC20Mock();
        certPrinter  = new SecCertPrinterMock();
        im           = new SecIssuanceManagerMock();
        corp         = new SecCorpMock(company);

        auth = new BorgAuth(owner);

        // Real CyberAgreementRegistry behind a proxy, sharing the same BorgAuth.
        registry = CyberAgreementRegistry(address(new ERC1967Proxy(
            address(new CyberAgreementRegistry()),
            abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
        )));
        // Single reusable template with no global/party fields (matches the empty values used below).
        vm.prank(owner);
        registry.createTemplate(TEMPLATE_ID, "Secondary", TEMPLATE_URI, new string[](0), new string[](0));

        dmFactory = DealManagerFactoryHelper(
            address(new ERC1967Proxy(
                address(new DealManagerFactoryHelper()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            ))
        );

        dm = DealManager(dmFactory.deployDealManager(corpSalt));
        dm.initialize(
            address(auth),
            address(corp),
            address(registry),
            address(im),
            address(dmFactory)
        );

        // Mint seller's Ledger Entry Token
        vm.prank(seller);
        sellerTokenId = certPrinter.mint(seller);

        // Fund buyer
        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);

        // Fund seller (for bid tests where seller receives nothing upfront)
        paymentToken.mint(seller, CONSIDERATION * 10);
        vm.prank(seller);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
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
            salt: uint256(keccak256("defaultSellOffer")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            buyerName: "",
            buyerHostingMode: 0,
            adminMultisig: address(0)
        });
    }

    function _defaultBidParams() internal view returns (PostOfferParams memory p) {
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
            salt: uint256(keccak256("defaultBid")),
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "",
            buyerName: "Test Buyer",
            buyerHostingMode: 0,
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
            printers, address(paymentToken), CONSIDERATION, bytes32(0), salt,
            new string[](0), parties, certDetails, partyValues, new address[](0), bytes32(0), block.timestamp + 1 days
        );
    }

    function _postBid() internal returns (bytes32 offerAgreementId) {
        vm.prank(buyer);
        offerAgreementId = dm.postOffer(_defaultBidParams());
    }

    function _acceptSellOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerAgreementId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    function _acceptBid(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        return _acceptBidPartial(offerAgreementId, UNITS);
    }

    function _acceptBidPartial(bytes32 offerAgreementId, uint256 units) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: units,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerAgreementId, seller, sellerKey),
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        settlementAgreementId = dm.acceptOffer(p);
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
        internal view returns (bytes memory)
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
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            agreementId,
            party,
            key
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_PostOffer_Sell() public {
        // ∅ → LIVE: stores the offer record, reserves the offered units, and emits OfferPosted.
        vm.expectEmit(false, true, false, false); // don't check offerAgreementId (computed inside)
        emit ISecondaryTradeStorage.OfferPosted(bytes32(0), seller, OfferSide.SELL, UNITS, CONSIDERATION);
        bytes32 offerId = _postSellOffer();

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.spvAddress, address(corp), "spvAddress should be corp");
        assertEq(offer.offeror, seller, "offeror should be seller");
        assertEq(uint8(offer.side), uint8(OfferSide.SELL));
        assertEq(offer.certPrinter, address(certPrinter));
        assertEq(offer.tokenId, sellerTokenId);
        assertEq(offer.units, UNITS);
        assertEq(offer.paymentToken, address(paymentToken));
        assertEq(offer.consideration, CONSIDERATION);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE));
        assertEq(offer.unitsAccepted, 0);
        assertEq(offer.paymentAccepted, 0);
        assertEq(offer.unitsFinalized, 0);

        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "units should be reserved");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — bid
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_PostOffer_Buy() public {
        // ∅ → LIVE: stores the offer record (no units reserved) and pulls consideration into holding escrow.
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);
        bytes32 offerId = _postBid();

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.spvAddress, address(corp), "spvAddress should be corp");
        assertEq(offer.offeror, buyer, "offeror should be buyer");
        assertEq(uint8(offer.side), uint8(OfferSide.BUY));
        assertEq(offer.certPrinter, address(certPrinter), "bid certPrinter should be set at post");
        assertEq(offer.tokenId, 0, "bid should have no tokenId");
        assertEq(offer.units, UNITS);
        assertEq(offer.paymentToken, address(paymentToken));
        assertEq(offer.consideration, CONSIDERATION);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE));
        assertEq(offer.unitsAccepted, 0);
        assertEq(offer.paymentAccepted, 0);
        assertEq(offer.unitsFinalized, 0);
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "bid should reserve no units at post");

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore - CONSIDERATION,
            "buyer consideration should be in holding escrow"
        );
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds should be in DealManager");
    }

    function test_Secondary_RevertIf_PostOffer_MissingCertPrinter_Sell() public {
        PostOfferParams memory p = _defaultSellOfferParams();
        p.certPrinter = address(0);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.MissingCertPrinter.selector);
        dm.postOffer(p);
    }

    function test_Secondary_RevertIf_PostOffer_MissingCertPrinter_Bid() public {
        PostOfferParams memory p = _defaultBidParams();
        p.certPrinter = address(0);

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.MissingCertPrinter.selector);
        dm.postOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — threshold conditions
    // ─────────────────────────────────────────────────────────────────────────

    // Conditions are owner-managed DealManager config (snapshotted onto the offer at postOffer), not
    // offeror-supplied. Register them as universal (L1) conditions so they apply to the test's offer.
    function _registerThresholdConditions(address[] memory conds) internal {
        for (uint256 i = 0; i < conds.length; i++) {
            vm.prank(owner);
            dm.addUniversalThresholdCondition(conds[i]);
        }
    }

    function test_Secondary_PostOffer_Sell_MultipleThresholdConditionsAllPass() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(true));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_PostOffer_Sell_MultipleThresholdConditionsAllPass"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertTrue(offerId != bytes32(0));
    }

    function test_Secondary_RevertIf_PostOffer_FirstThresholdConditionFails() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(false));
        conds[1] = address(new SecConditionMock(true));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_RevertIf_PostOffer_FirstThresholdConditionFails"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[0]));
        dm.postOffer(p);
    }

    function test_Secondary_RevertIf_PostOffer_SecondThresholdConditionFails() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(false));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_RevertIf_PostOffer_SecondThresholdConditionFails"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[1]));
        dm.postOffer(p);
    }

    // Regression: threshold conditions must see the populated offer via getOffer(offerId).
    // The condition mock reads the offer back during checkCondition and rejects an empty one;
    // before the fix the loop ran ahead of the store, so it observed a zeroed offer and reverted.
    function test_Secondary_PostOffer_ThresholdConditionSeesPopulatedOffer() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecOfferReadingConditionMock());

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_PostOffer_ThresholdConditionSeesPopulatedOffer"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        // SecOfferReadingConditionMock.checkCondition() would fail if `Offer` is not updated
        bytes32 offerId = dm.postOffer(p);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.offeror, seller, "offeror must be readable by conditions");
        assertEq(offer.certPrinter, address(certPrinter), "certPrinter must be readable by conditions");
        assertEq(offer.tokenId, sellerTokenId, "tokenId must be readable by conditions");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — threshold conditions re-evaluated for the acceptor
    // ─────────────────────────────────────────────────────────────────────────

    // A buyer-facing threshold condition short-circuits at posting (no acceptor yet) and enforces at
    // acceptance. Pre-fix, acceptOffer never re-ran threshold conditions, so a disallowed acceptor
    // could finalize a trade. The condition must now reject the acceptance.
    function test_Secondary_RevertIf_AcceptOffer_BuyerFacingThresholdConditionFails() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecBuyerFacingConditionMock(false)); // posting passes, acceptance fails

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_RevertIf_AcceptOffer_BuyerFacingThresholdConditionFails"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p); // posting succeeds: condition short-circuits with no acceptor

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
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, conds[0]));
        dm.acceptOffer(ap);
    }

    // Counterpart to the above: when the acceptor satisfies the buyer-facing condition, the re-evaluation
    // passes and acceptance proceeds — proving the re-check runs and is not an unconditional block.
    function test_Secondary_AcceptOffer_BuyerFacingThresholdConditionPasses() public {
        address[] memory conds = new address[](1);
        conds[0] = address(new SecBuyerFacingConditionMock(true)); // passes at posting and acceptance

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_AcceptOffer_BuyerFacingThresholdConditionPasses"));
        _registerThresholdConditions(conds);

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertTrue(settlementId != bytes32(0), "acceptance should succeed when the acceptor passes conditions");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // condition config — owner-managed threshold/closing sets, resolved onto each offer at postOffer
    // ─────────────────────────────────────────────────────────────────────────

    // L1 ++ L2 ++ L3 are concatenated in order and snapshotted onto the offer at postOffer; the offeror
    // supplies only the pathway, never the addresses.
    function test_Secondary_Config_ResolvesL1L2L3OntoOffer() public {
        address l1 = address(new SecConditionMock(true));
        address l2 = address(new SecConditionMock(true));
        address l3 = address(new SecConditionMock(true));
        vm.prank(owner); dm.addUniversalThresholdCondition(l1);
        vm.prank(owner); dm.addSpvThresholdCondition(l2);
        vm.prank(owner); dm.addPathwayThresholdCondition(ExemptionPathway.SECTION_4A7, l3);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_Config_ResolvesL1L2L3OntoOffer"));
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        address[] memory resolved = dm.getOffer(offerId).thresholdConditions;
        assertEq(resolved.length, 3, "L1+L2+L3 all resolved");
        assertEq(resolved[0], l1, "L1 first");
        assertEq(resolved[1], l2, "L2 second");
        assertEq(resolved[2], l3, "L3 last");
    }

    // L3 is keyed by the offer's exemption pathway: a condition registered for a different pathway
    // must not apply. RULE_144's failing condition leaves a SECTION_4A7 offer unaffected.
    function test_Secondary_Config_PathwayConditionOnlyAppliesToMatchingPathway() public {
        address failing = address(new SecConditionMock(false));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, failing);

        // SECTION_4A7 offer: the RULE_144 condition is not in its resolved set, so posting succeeds.
        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_Config_Pathway_4a7"));
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertEq(dm.getOffer(offerId).thresholdConditions.length, 0, "no pathway condition applied to 4(a)(7)");
    }

    function test_Secondary_RevertIf_Config_PathwayConditionFailsForMatchingPathway() public {
        address failing = address(new SecConditionMock(false));
        vm.prank(owner);
        dm.addPathwayThresholdCondition(ExemptionPathway.RULE_144, failing);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_Config_Pathway_144"));
        p.exemptionPathway = ExemptionPathway.RULE_144;
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, failing));
        dm.postOffer(p);
    }

    function test_Secondary_RevertIf_Config_AddZeroAddressCondition() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.InvalidSecondaryCondition.selector);
        dm.addUniversalThresholdCondition(address(0));
    }

    function test_Secondary_RevertIf_Config_AddDuplicateCondition() public {
        address c = address(new SecConditionMock(true));
        vm.prank(owner);
        dm.addClosingCondition(c);

        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionAlreadyExists.selector);
        dm.addClosingCondition(c);
    }

    function test_Secondary_RevertIf_Config_RemoveIndexOutOfBounds() public {
        vm.prank(owner);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryConditionIndexOutOfBounds.selector);
        dm.removeUniversalThresholdConditionAt(0);
    }

    // Swap-pop removal: removing index 0 of [a,b] leaves [b].
    function test_Secondary_Config_RemoveConditionSwapPop() public {
        address a = address(new SecConditionMock(true));
        address b = address(new SecConditionMock(true));
        vm.prank(owner); dm.addUniversalThresholdCondition(a);
        vm.prank(owner); dm.addUniversalThresholdCondition(b);

        vm.prank(owner);
        dm.removeUniversalThresholdConditionAt(0);

        address[] memory remaining = dm.getUniversalThresholdConditions();
        assertEq(remaining.length, 1, "one condition remains");
        assertEq(remaining[0], b, "swap-pop moved the last element into the hole");
    }

    function test_Secondary_RevertIf_Config_AddByNonAdmin() public {
        address c = address(new SecConditionMock(true));
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        dm.addUniversalThresholdCondition(c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — integrator whitelist
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_RevertIf_PostOffer_IntegratorNotWhitelisted() public {
        dmFactory.setIsIntegratorWhitelisted(false);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_RevertIf_PostOffer_IntegratorNotWhitelisted"));
        p.integrator = makeAddr("integrator");

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.IntegratorNotWhitelisted.selector);
        dm.postOffer(p);
    }

    function test_Secondary_PostOffer_WhitelistedIntegratorPasses() public {
        dmFactory.setIsIntegratorWhitelisted(true);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_PostOffer_WhitelistedIntegratorPasses"));
        p.integrator = makeAddr("integrator");

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);
        assertTrue(offerId != bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer - Min trade thresholds
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_RevertIf_PostOffer_BelowMinUnitsThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS + 1, 0);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly UNITS
    }

    function test_Secondary_RevertIf_PostOffer_BelowMinConsiderationThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION + 1);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.BelowMinTradeThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly CONSIDERATION
    }

    function test_Secondary_PostOffer_PassesAtMinThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS, CONSIDERATION);

        vm.prank(seller);
        bytes32 offerId = dm.postOffer(_defaultSellOfferParams()); // exactly at threshold
        assertTrue(offerId != bytes32(0));
    }

    function test_Secondary_RevertIf_AcceptOffer_PartialFillBelowMinThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS, 0); // require full fill

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS - 1, // partial fill, below min
            buyerName: "Bob",
            buyerHostingMode: 0,
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

    function test_Secondary_RevertIf_AcceptOffer_PartialFillBelowMinConsideration() public {
        // Units floor disabled, but a half fill's pro-rata consideration (CONSIDERATION/2)
        // is below the admin-set minimum ticket value — acceptance must revert.
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION / 2 + 1);

        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2, // pro-rata consideration = CONSIDERATION / 2, below min
            buyerName: "Bob",
            buyerHostingMode: 0,
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

    function test_Secondary_AcceptOffer_FinalLotExemptFromMinThreshold() public {
        // Floors below the full offer (so postOffer passes) but above the tail remainder. The lot that
        // exhausts the remaining units must be exempt, otherwise the offer's tail would be stranded.
        vm.prank(owner);
        dm.setMinTradeThreshold(UNITS / 4, CONSIDERATION / 4);

        bytes32 offerId = _postSellOffer();

        // First fill clears the floors, leaving a tail below both.
        _acceptSellOfferPartial(offerId, (UNITS * 9) / 10); // 90 units, 9 ether

        // Final lot: 10 units / 1 ether — under both floors but exempt as the remaining lot.
        bytes32 settlementId = _acceptSellOfferPartial(offerId, UNITS - (UNITS * 9) / 10);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED), "final lot should fully accept the offer");
        assertEq(offer.unitsAccepted, UNITS);
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            CONSIDERATION - (CONSIDERATION * 9) / 10,
            "final lot settles its sub-floor pro-rata consideration"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Sell_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "reservation should be released");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS, "all units should be marked released");
    }

    function test_Secondary_CancelOffer_Sell_AfterExpiry_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        // Expiry only blocks acceptOffer; the offeror can still cancel and reclaim the free pool.
        vm.warp(block.timestamp + 2 days);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "reservation should be released");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS, "all units should be marked released");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED));
    }

    function test_Secondary_CancelOffer_Sell_Uncommited() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(seller);
        dm.cancelOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    function test_Secondary_RevertIf_CancelOffer_NotOfferor() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.NotOfferor.selector);
        dm.cancelOffer(offerId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — bid
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Bid_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBid();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore + CONSIDERATION,
            "buyer should be refunded"
        );
    }

    function test_Secondary_CancelOffer_Bid_AfterExpiry_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBid();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        // Expiry only blocks acceptOffer; the offeror can still cancel and reclaim the free pool.
        vm.warp(block.timestamp + 2 days);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore + CONSIDERATION,
            "buyer should be refunded"
        );
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED));
    }

    function test_Secondary_CancelOffer_Buy_Uncommited() public {
        bytes32 offerId = _postBid();

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — outstanding settlements stay active
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Sell_PartiallyFilled() public {
        bytes32 offerId = _postSellOffer();
        uint256 lotUnits = UNITS / 2;
        bytes32 settlementId = _acceptSellOfferPartial(offerId, lotUnits);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED with a lot outstanding");

        // Cancel returns only the free pool; the accepted lot stays ACCEPTED and resolvable.
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "active lot not refunded by cancel");
        assertEq(certPrinter.reservedUnits(sellerTokenId), lotUnits, "committed lot stays reserved");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS - lotUnits, "only free units released");
    }

    function test_Secondary_CancelOffer_Buy_PartiallyFilled() public {
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBidPartial(offerId, 40);
        uint256 lotPayment = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED with a lot outstanding");

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
        assertEq(certPrinter.reservedUnits(sellerTokenId), 40, "seller's lot reservation held");
    }

    function test_Secondary_CancelOffer_Sell_FullyFilled() public {
        // Fully-filled variant of the partial case: no free pool to release; the committed lot
        // stays ACCEPTED and its units stay reserved.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED while fully accepted");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "committed lot not refunded by cancel");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "no free units: full reservation held");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0, "nothing released: offer was fully accepted");
    }

    function test_Secondary_CancelOffer_Buy_FullyFilled() public {
        // Fully-filled variant of the partial case: no free pool to refund; the committed lot's
        // funds stay in custody.
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED while fully accepted");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "outstanding settlement stays ACCEPTED after cancel"
        );
        assertFalse(registry.isVoided(settlementId), "cancel must not request a settlement void");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "no free pool to refund: fully accepted");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "committed lot's funds stay in custody");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "seller's full reservation held");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — sell offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_AcceptSellOffer_CreatesSettlementEscrow() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(uint8(se.status), uint8(SecondaryEscrowStatus.ACCEPTED), "settlement escrow should be ACCEPTED");
        assertEq(se.paymentAmount, CONSIDERATION, "consideration in settlement escrow");
        assertEq(se.counterparty, buyer, "counterparty is the acceptor (the buyer on a sell offer)");
    }

    function test_Secondary_AcceptSellOffer_StoresSecondaryEscrow() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.counterparty, buyer, "counterparty should be the acceptor");
        assertEq(se.offerId, offerId, "offerId back-link should be set");
        assertTrue(se.dealMetadata.length > 0, "deal metadata should be encoded");
    }

    function test_Secondary_AcceptSellOffer_PullsBuyerFunds() public {
        bytes32 offerId = _postSellOffer();
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        _acceptSellOffer(offerId);

        assertEq(paymentToken.balanceOf(buyer), buyerBefore - CONSIDERATION, "buyer funds pulled");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds in escrow");
    }

    function test_Secondary_AcceptOffer_Sell_SingleFullyFills() public {
        // LIVE → FULLY_ACCEPTED directly in a single fill, with no PARTIALLY_ACCEPTED step.
        bytes32 offerId = _postSellOffer();
        _acceptSellOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(offer.unitsAccepted, UNITS);
    }

    function test_Secondary_AcceptSellOffer_PartialFill_ProRataConsideration() public {
        bytes32 offerId = _postSellOffer();
        uint256 partialUnits = UNITS / 4;
        uint256 expectedConsideration = CONSIDERATION * partialUnits / UNITS;

        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: partialUnits,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId = dm.acceptOffer(p);

        assertEq(paymentToken.balanceOf(buyer), buyerBefore - expectedConsideration, "buyer pays pro-rata only");
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            expectedConsideration,
            "settlement escrow holds pro-rata amount"
        );
    }

    function test_Secondary_AcceptOffer_Sell_MultipleFills() public {
        // Walks the full LIVE → PARTIALLY_ACCEPTED → FULLY_ACCEPTED lifecycle in two fills.
        bytes32 offerId = _postSellOffer();
        uint256 firstUnits = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;
        uint256 expectedFirst  = CONSIDERATION * firstUnits / UNITS;
        uint256 expectedSecond = CONSIDERATION * secondUnits / UNITS;

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: firstUnits,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId1 = dm.acceptOffer(p);

        // LIVE → PARTIALLY_ACCEPTED: the partial fill keeps the offer's full reservation.
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));
        assertEq(dm.getOffer(offerId).unitsAccepted, firstUnits);
        assertEq(dm.getOffer(offerId).paymentAccepted, expectedFirst, "offer tracks committed consideration");
        assertEq(dm.getSecondaryEscrow(settlementId1).tokenId, sellerTokenId, "settlement records the seller's tokenId");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "partial fill keeps the offer's full reservation");

        p.units = secondUnits;
        p.acceptorAgreementSig = _acceptorSig(offerId, buyer, buyerKey); // settlement id changes with each fill
        vm.prank(buyer);
        bytes32 settlementId2 = dm.acceptOffer(p);

        // PARTIALLY_ACCEPTED → FULLY_ACCEPTED: each fill is its own pro-rata settlement.
        assertTrue(settlementId1 != settlementId2, "each fill gets its own settlement escrow");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(dm.getOffer(offerId).unitsAccepted, UNITS);
        assertEq(dm.getOffer(offerId).paymentAccepted, CONSIDERATION, "committed consideration sums to the full offer");
        assertEq(dm.getSecondaryEscrow(settlementId1).paymentAmount, expectedFirst);
        assertEq(dm.getSecondaryEscrow(settlementId2).paymentAmount, expectedSecond);
    }

    function test_Secondary_AcceptSellOffer_FinalLotTakesRoundingRemainder() public {
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
            dm.getSecondaryEscrow(s1).paymentAmount
                + dm.getSecondaryEscrow(s2).paymentAmount
                + dm.getSecondaryEscrow(s3).paymentAmount,
            100,
            "settlements sum to the full offer consideration"
        );
    }

    function test_Secondary_RevertIf_AcceptSellOffer_UnitsExceedOffer() public {
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS + 1,
            buyerName: "Bob",
            buyerHostingMode: 0,
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

    function test_Secondary_RevertIf_AcceptSellOffer_OverfillAfterPartialFill() public {
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2,
            buyerName: "Bob",
            buyerHostingMode: 0,
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

    function test_Secondary_AcceptBuyOffer_CreatesSettlementEscrowAlreadyPaid() public {
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "settlement escrow should open ACCEPTED (migrated from holding)"
        );
    }

    function test_Secondary_AcceptBuyOffer_MigratesFundsFromHoldingEscrow() public {
        bytes32 offerId = _postBid();

        // Funds are in contract from postOffer() before acceptance
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION);

        bytes32 settlementId = _acceptBid(offerId);

        // Funds remain in DealManager, now attributed to the settlement SecondaryEscrow
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds still in DealManager");
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            CONSIDERATION,
            "consideration attributed to settlement escrow"
        );
    }

    function test_Secondary_AcceptBuyOffer_ReservesSellerUnits() public {
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.tokenId, sellerTokenId, "settlement should record the seller's tokenId");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "seller units should be reserved at bid acceptance");
    }

    function test_Secondary_RevertIf_AcceptBuyOffer_CannotAcceptTwice() public {
        bytes32 offerId = _postBid();

        // Full fill — succeeds
        _acceptBid(offerId);

        // Second attempt reverts because offer is now FULLY_ACCEPTED
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferNotAvailable.selector);
        dm.acceptOffer(p);
    }

    function test_Secondary_RevertIf_AcceptOffer_Buy_UnitsExceedOffer() public {
        bytes32 offerId = _postBid();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS + 1,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement"
        });

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    function test_Secondary_AcceptOffer_Buy_SingleFullyFills() public {
        // LIVE → FULLY_ACCEPTED directly in a single fill, with no PARTIALLY_ACCEPTED step.
        bytes32 offerId = _postBid();
        _acceptBid(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(offer.unitsAccepted, UNITS);
    }

    function test_Secondary_AcceptOffer_Buy_MultipleFills() public {
        // Walks the full LIVE → PARTIALLY_ACCEPTED → FULLY_ACCEPTED lifecycle in two fills.
        bytes32 offerId = _postBid();
        uint256 firstUnits = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;
        uint256 expectedFirst  = CONSIDERATION * firstUnits / UNITS;
        uint256 expectedSecond = CONSIDERATION * secondUnits / UNITS;

        bytes32 settlementId1 = _acceptBidPartial(offerId, firstUnits);

        // LIVE → PARTIALLY_ACCEPTED
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));
        assertEq(dm.getOffer(offerId).unitsAccepted, firstUnits);
        assertEq(dm.getOffer(offerId).paymentAccepted, expectedFirst, "offer tracks committed consideration");

        bytes32 settlementId2 = _acceptBidPartial(offerId, secondUnits);

        // PARTIALLY_ACCEPTED → FULLY_ACCEPTED: each fill is its own pro-rata settlement.
        assertTrue(settlementId1 != settlementId2, "each fill gets its own settlement escrow");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(dm.getOffer(offerId).unitsAccepted, UNITS);
        assertEq(dm.getOffer(offerId).paymentAccepted, CONSIDERATION, "committed consideration sums to the full offer");
        assertEq(dm.getSecondaryEscrow(settlementId1).paymentAmount, expectedFirst);
        assertEq(dm.getSecondaryEscrow(settlementId2).paymentAmount, expectedSecond);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalizeSecondaryTradeAgreement — secondary settlements
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_FinalizeDeal_SendsPaymentToSeller() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + CONSIDERATION,
            "seller should receive payment"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "escrow should be empty after finalize");
    }

    function test_Secondary_FinalizeDeal_Bid_SendsPaymentToAcceptor() public {
        // BUY path: the seller is derived as the settlement's counterparty (the acceptor)
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + CONSIDERATION,
            "acceptor (seller) should receive payment"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "escrow should be empty after finalize");
    }

    function test_Secondary_FinalizeSecondaryTrade_Sell() public {
        // The offer stays FULLY_ACCEPTED until every lot settles; it only reaches FINALIZED once the
        // last outstanding lot is finalized.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, 40);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, 60);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);
        Offer memory afterA = dm.getOffer(offerId);
        assertEq(
            uint8(afterA.status),
            uint8(OfferStatus.FULLY_ACCEPTED),
            "offer not terminal until every lot settles"
        );
        // The terminal gate is unitsFinalized == units: after the first lot it lags unitsAccepted,
        // which is exactly why the offer is still FULLY_ACCEPTED, not FINALIZED.
        assertEq(afterA.unitsFinalized, 40, "first lot's units counted as finalized");
        assertEq(afterA.unitsAccepted, UNITS, "unitsFinalized lags unitsAccepted while a lot is outstanding");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);
        Offer memory afterB = dm.getOffer(offerId);
        assertEq(uint8(afterB.status), uint8(OfferStatus.FINALIZED), "all offered units settled");
        assertEq(afterB.unitsFinalized, UNITS, "gate met: unitsFinalized == units");
    }

    function test_Secondary_FinalizeSecondaryTrade_Buy() public {
        // BUY mirror: the bid stays FULLY_ACCEPTED until every lot settles, reaching FINALIZED only
        // once the last outstanding lot is finalized.
        bytes32 offerId = _postBid();
        bytes32 settlementIdA = _acceptBidPartial(offerId, 40);
        bytes32 settlementIdB = _acceptBidPartial(offerId, 60);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);
        Offer memory afterA = dm.getOffer(offerId);
        assertEq(
            uint8(afterA.status),
            uint8(OfferStatus.FULLY_ACCEPTED),
            "offer not terminal until every lot settles"
        );
        assertEq(afterA.unitsFinalized, 40, "first lot's units counted as finalized");
        assertEq(afterA.unitsAccepted, UNITS, "unitsFinalized lags unitsAccepted while a lot is outstanding");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);
        Offer memory afterB = dm.getOffer(offerId);
        assertEq(uint8(afterB.status), uint8(OfferStatus.FINALIZED), "all offered units settled");
        assertEq(afterB.unitsFinalized, UNITS, "gate met: unitsFinalized == units");
    }

    function test_Secondary_RevertIf_CancelOffer_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferNotAvailable.selector);
        dm.cancelOffer(offerId);
    }

    function test_Secondary_FinalizeDeal_DoesNotPayCompanyPayable() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 companyBefore = paymentToken.balanceOf(company);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(paymentToken.balanceOf(company), companyBefore, "company should NOT receive payment on secondary");
    }

    function test_Secondary_FinalizeDeal_CallsIssuanceManagerSecondaryTransfer() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        assertFalse(im.secondaryTransferCalled());

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertTrue(im.secondaryTransferCalled(), "secondaryTransfer should be called");
    }

    function test_Secondary_FinalizeDeal_EmitsSecondaryDealFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.expectEmit(true, false, false, false);
        emit ISecondaryTradeStorage.SecondaryDealFinalized(settlementId, seller, buyer, CONSIDERATION);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalizeDeal — primary path regression
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_FinalizeDeal_PrimaryPath_SendsPaymentToCompanyNotSeller() public {
        // Set up a primary issuance deal (no SecondaryEscrow entry)
        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        address[] memory parties = new address[](2);
        parties[0] = owner;
        parties[1] = buyer;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        address[] memory printers = new address[](1);
        printers[0] = address(certPrinter);

        bytes32 expectedAgreementId = keccak256(abi.encode(bytes32(0), uint256(999), new string[](0), parties));
        // Precompute sigs before vm.prank: the helper's registry view calls would otherwise consume the prank.
        bytes memory ownerSig = _agreementSig(expectedAgreementId, partyValues[0], ownerKey);

        vm.prank(owner);
        (bytes32 agreementId,) = dm.proposeAndSignDeal(
            printers,
            address(paymentToken),
            CONSIDERATION,
            bytes32(0),
            999,
            new string[](0),
            parties,
            certDetails,
            owner,
            ownerSig,
            partyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1 days
        );

        bytes memory buyerSig = _agreementSig(agreementId, new string[](0), buyerKey);
        vm.prank(buyer);
        dm.signDealAndPay(buyer, agreementId, buyerSig, new string[](0), false, "Bob", "");

        uint256 companyBefore = paymentToken.balanceOf(company);
        uint256 sellerBefore  = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeDeal(agreementId);

        assertGt(paymentToken.balanceOf(company), companyBefore, "primary: company should receive payment");
        assertEq(paymentToken.balanceOf(seller), sellerBefore, "primary: seller should NOT receive payment");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // voidExpiredSecondaryTradeAgreement — secondary settlements
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_VoidExpiredDeal_DoesNotReleaseReservation_OfferGoesBackToLive() public {
        // Voiding an expired settlement on a non-cancelled offer reverts the offer to LIVE.
        // The reservation must be held so future acceptors are still protected.
        // The seller must call cancelOffer() to release it.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);

        vm.warp(se.expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.LIVE), "offer should be LIVE after void");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "reservation must stay active: offer is LIVE");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0, "reservation must not have been released");
    }

    function test_Secondary_VoidExpiredDeal_ReleasesReservation_WhenCancelKeepingLots() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "reservation held after cancel with active settlement");

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "reservation released: offer CANCELLED, last settlement voided");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_VoidExpiredDeal_RefundsBuyer() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        uint256 expiry = dm.getSecondaryEscrow(settlementId).expiry;
        vm.warp(expiry + 1);

        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "buyer should be refunded");
    }

    function test_Secondary_RevertIf_VoidExpiredDeal_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyVoided.selector);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_Secondary_RevertIf_VoidExpiredDeal_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.voidExpiredSecondaryTradeAgreement(settlementId, buyer, "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // voidExpiredDeal — primary path regression
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_VoidExpiredDeal_PrimaryPath_VoidsCert() public {
        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        address[] memory parties = new address[](2);
        parties[0] = owner;
        parties[1] = buyer;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        address[] memory printers = new address[](1);
        printers[0] = address(certPrinter);

        uint256 expiry = block.timestamp + 1 days;

        bytes32 expectedAgreementId = keccak256(abi.encode(bytes32(0), uint256(998), new string[](0), parties));
        // Precompute sig before vm.prank: the helper's registry view calls would otherwise consume the prank.
        bytes memory ownerSig = _agreementSig(expectedAgreementId, partyValues[0], ownerKey);

        vm.prank(owner);
        (bytes32 agreementId, uint256[] memory certIds) = dm.proposeAndSignDeal(
            printers,
            address(paymentToken),
            CONSIDERATION,
            bytes32(0),
            998,
            new string[](0),
            parties,
            certDetails,
            owner,
            ownerSig,
            partyValues,
            new address[](0),
            bytes32(0),
            expiry
        );

        // Cert is now in escrow (owned by DealManager)
        assertEq(certPrinter.ownerOf(certIds[0]), address(dm));

        vm.warp(expiry + 1);

        // signer must be a party to the agreement (owner); DealManager is the finalizer so no void sig is needed
        vm.prank(keeper);
        dm.voidExpiredDeal(agreementId, owner, "");

        // Cert should be burned (voided) via IssuanceManager.voidCertificate
        vm.expectRevert();
        certPrinter.ownerOf(certIds[0]); // burned token should revert on ownerOf
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasSecondaryEscrow discriminator
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_HasSecondaryEscrow_TrueAfterAccept() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertTrue(se.counterparty != address(0), "SecondaryEscrow should exist after accept");
    }

    // A secondary settlement function rejects a primary deal id (no SecondaryEscrow exists for it).
    // The reverse direction — primary functions rejecting a secondary/unknown id — is a primary-function
    // concern and lives in DealManagerTest.t.sol.
    function test_Secondary_RevertIf_FinalizeSecondaryTradeAgreement_OnPrimaryDeal() public {
        bytes32 agreementId = _proposePrimaryDeal(995);

        vm.prank(keeper);
        vm.expectRevert(ISecondaryTradeStorage.SecondaryEscrowNotFound.selector);
        dm.finalizeSecondaryTradeAgreement(agreementId);
    }

    function _acceptSellOfferPartial(bytes32 offerAgreementId, uint256 units) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: units,
            buyerName: "Bob",
            buyerHostingMode: 0,
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
    // Reservation release guards — SELL offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_FinalizeDeal_PartialFill_RemainingUnitsStayReserved_OfferStillOpen() public {
        // Finalizing a partial fill consumes only that lot's units; the offer is still
        // PARTIALLY_ACCEPTED with remaining units, which must stay reserved.
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOfferPartial(offerId, UNITS / 2);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS / 2, "finalized lot should be consumed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS - UNITS / 2, "remaining units must stay reserved: offer still open");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0);
    }

    function test_Secondary_FinalizeDeal_FullFill_ConsumesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no units reserved after full-fill finalized");
        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS, "all units consumed by the transfer");
    }

    function test_Secondary_FinalizeDeal_TwoPartialFills_EachLotConsumedAtFinalize() public {
        bytes32 offerId = _postSellOffer();

        uint256 firstUnits  = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;

        bytes32 sid1 = _acceptSellOfferPartial(offerId, firstUnits);
        bytes32 sid2 = _acceptSellOfferPartial(offerId, secondUnits);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(sid1);
        assertEq(certPrinter.reservedUnits(sellerTokenId), secondUnits, "second lot still reserved while in-flight");
        assertEq(certPrinter.consumedUnits(sellerTokenId), firstUnits);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(sid2);
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no units reserved after last settlement finalized");
        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_FinalizeDeal_Sell_CancelKeepingLots_ConsumesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED while fully accepted");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "in-flight lot held after cancel (no free units)");

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no units reserved: CANCELLED + last settlement finalized");
        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_FinalizeDeal_Bid_CancelKeepingLots_PaysOutLot() public {
        // BUY mirror of the SELL case above: after cancel(false), the in-flight lot stays ACCEPTED
        // and still settles — payout to the acceptor (seller), lot units consumed, free pool
        // already refunded to the offeror at cancel.
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBidPartial(offerId, 40);
        uint256 lotPayment = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        vm.prank(buyer);
        dm.cancelOffer(offerId);
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + (CONSIDERATION - lotPayment),
            "free pool refunded at cancel, in-flight lot held"
        );

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPayment, "lot paid out to the acceptor");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "no payment left in custody");
        assertEq(certPrinter.consumedUnits(sellerTokenId), 40, "lot's reserved units consumed at finalize");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no reservation left");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "CANCELLED stays sticky");
    }

    function test_Secondary_FinalizeDeal_Sell_KeepsActiveLots_FinalizedUntouched() public {
        // The finalized lot's units stay consumed and its payout stays with the seller; the still
        // ACCEPTED lot is left active (not voided) and only the free units come back at cancel.
        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, 40);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, 30);
        uint256 lotPaymentA = CONSIDERATION * 40 / UNITS;
        uint256 lotPaymentB = CONSIDERATION * 30 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(seller);
        dm.cancelOffer(offerId);

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
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA, "seller keeps the finalized payout");
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "active lot not refunded by cancel");
        assertEq(paymentToken.balanceOf(address(dm)), lotPaymentB, "active lot's payment stays in custody");
        assertEq(certPrinter.consumedUnits(sellerTokenId), 40, "finalized lot's units consumed exactly once");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 30, "active lot stays reserved; free units released");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS - 70, "only the free units released at cancel");

        // The active lot still settles after the offer is cancelled.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA + lotPaymentB, "active lot settles after cancel");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody drained");
    }

    function test_Secondary_FinalizeDeal_Bid_KeepsActiveLots_FinalizedUntouched() public {
        bytes32 offerId = _postBid();
        bytes32 settlementIdA = _acceptBidPartial(offerId, 40);
        bytes32 settlementIdB = _acceptBidPartial(offerId, 30);
        uint256 lotPaymentA = CONSIDERATION * 40 / UNITS;
        uint256 lotPaymentB = CONSIDERATION * 30 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

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
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA, "seller keeps the finalized payout");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + (CONSIDERATION - lotPaymentA - lotPaymentB),
            "cancel refunds only the free pool, excludes finalized and active lots"
        );
        assertEq(paymentToken.balanceOf(address(dm)), lotPaymentB, "active lot's funds stay in custody");

        // The active lot still settles after the offer is cancelled.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdB);
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA + lotPaymentB, "active lot settles after cancel");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    function test_Secondary_VoidSecondaryTradeAgreement_Sell_FullyAcceptedToLive() public {
        // Walks FULLY_ACCEPTED → PARTIALLY_ACCEPTED → LIVE by voiding the accepted lots one at a
        // time, then proves the offer is genuinely reusable by running a fresh acceptance lifecycle.
        // Each void refunds its buyer immediately and returns units to the free pool, but the SELL
        // reservation stays held throughout — the offer is never cancelled.
        bytes32 offerId = _postSellOffer();
        bytes32 lotA = _acceptSellOfferPartial(offerId, 40);
        bytes32 lotB = _acceptSellOfferPartial(offerId, 60);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        // FULLY_ACCEPTED → PARTIALLY_ACCEPTED: void one of the two lots, the other survives.
        uint256 buyerBeforeB = paymentToken.balanceOf(buyer);
        _voidSettlementBothParties(lotB);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.PARTIALLY_ACCEPTED), "offer drops to PARTIALLY_ACCEPTED, not LIVE");
        assertEq(offer.unitsAccepted, 40, "only the surviving lot's units remain accepted");
        assertEq(offer.paymentAccepted, CONSIDERATION * 40 / UNITS, "voided lot's consideration decremented from committed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "voided lot returns to free pool, reservation stays held");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBeforeB + CONSIDERATION * 60 / UNITS,
            "voided lot's buyer is refunded immediately"
        );

        // PARTIALLY_ACCEPTED → LIVE: void the last surviving lot, unitsAccepted → 0.
        uint256 buyerBeforeA = paymentToken.balanceOf(buyer);
        _voidSettlementBothParties(lotA);

        offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE), "last lot voided reverts the offer to LIVE");
        assertEq(offer.unitsAccepted, 0, "no units remain accepted");
        assertEq(offer.paymentAccepted, 0, "no consideration remains committed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "reservation held: offer is LIVE, not cancelled");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0);
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBeforeA + CONSIDERATION * 40 / UNITS,
            "last lot's buyer refunded the pro-rata payment"
        );

        // Ready for another lifecycle: the reverted-to-LIVE offer accepts a fresh full fill.
        bytes32 reaccept = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED), "LIVE offer runs a fresh acceptance");
        assertEq(dm.getOffer(offerId).unitsAccepted, UNITS, "fresh fill re-accepts the full quantity");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "held reservation backs the fresh fill");
        assertEq(
            uint8(dm.getSecondaryEscrow(reaccept).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "fresh settlement opens ACCEPTED"
        );
        assertTrue(reaccept != lotA && reaccept != lotB, "fresh settlement is distinct from the voided lots");
    }

    function test_Secondary_VoidSecondaryTradeAgreement_Buy_FullyAcceptedToLive() public {
        // BUY mirror: a void releases the acceptor's (seller's) per-lot reservation immediately, and
        // the consideration returns to the offer's free pool and stays in custody (no buyer refund
        // while the offer is open). The bid walks FULLY_ACCEPTED → PARTIALLY_ACCEPTED → LIVE and
        // then accepts a fresh lifecycle.
        bytes32 offerId = _postBid();
        bytes32 lotA = _acceptBidPartial(offerId, 40);
        bytes32 lotB = _acceptBidPartial(offerId, 60);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "both lots reserve the seller's units");

        uint256 buyerBalance = paymentToken.balanceOf(buyer);

        // FULLY_ACCEPTED → PARTIALLY_ACCEPTED: void one lot; the seller's lot reservation is released.
        _voidSettlementBothParties(lotB);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.PARTIALLY_ACCEPTED), "offer drops to PARTIALLY_ACCEPTED, not LIVE");
        assertEq(offer.unitsAccepted, 40, "only the surviving lot's units remain accepted");
        assertEq(offer.paymentAccepted, CONSIDERATION * 40 / UNITS, "voided lot's consideration decremented from committed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 40, "voided lot's seller reservation released");
        assertEq(paymentToken.balanceOf(buyer), buyerBalance, "no buyer refund while offer is open");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "consideration stays whole in custody");

        // PARTIALLY_ACCEPTED → LIVE: void the last lot, unitsAccepted → 0.
        _voidSettlementBothParties(lotA);

        offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE), "last lot voided reverts the offer to LIVE");
        assertEq(offer.unitsAccepted, 0, "no units remain accepted");
        assertEq(offer.paymentAccepted, 0, "no consideration remains committed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "all seller reservations released");
        assertEq(paymentToken.balanceOf(buyer), buyerBalance, "still no buyer refund: offer open, not cancelled");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "full consideration in custody, ready to back a fresh fill");

        // Ready for another lifecycle: the reverted-to-LIVE bid accepts a fresh full fill.
        bytes32 reaccept = _acceptBid(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED), "LIVE bid runs a fresh acceptance");
        assertEq(dm.getOffer(offerId).unitsAccepted, UNITS, "fresh fill re-accepts the full quantity");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "fresh fill re-reserves the seller's units");
        assertEq(
            uint8(dm.getSecondaryEscrow(reaccept).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "fresh settlement opens ACCEPTED"
        );
        assertTrue(reaccept != lotA && reaccept != lotB, "fresh settlement is distinct from the voided lots");
    }

    function test_Secondary_VoidSecondaryTradeAgreement_Sell_AfterCancel_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "offer CANCELLED while fully accepted");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "in-flight lot held after cancel (no free units)");

        _voidSettlementBothParties(settlementId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "lot released: CANCELLED + last settlement voided");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_VoidSecondaryTradeAgreement_Bid_OfferStillOpen_NoRefund_FundsStayInCustody() public {
        // Symmetric to the SELL reservation rule: the bid's consideration returns to the offer's
        // free pool and stays in custody; only the seller's per-settlement reservation is released.
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        _voidSettlementBothParties(settlementId);

        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "no refund while offer still open");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.LIVE), "offer should revert to LIVE");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "seller's per-settlement reservation released");

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + CONSIDERATION,
            "full consideration refunded exactly once, at cancel"
        );
    }

    function test_Secondary_VoidSecondaryTradeAgreement_Bid_AfterCancel_RefundsLot() public {
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBid(offerId);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceAfterAccept, "no free pool to refund: fully accepted");

        _voidSettlementBothParties(settlementId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + CONSIDERATION,
            "lot refunded at void: offer CANCELLED, can never be re-accepted"
        );
    }

    function test_Secondary_CancelOffer_Bid_AfterFinalizedFill_RefundsOnlyFreePool() public {
        // A finalized lot's payment is disbursed to the seller and must never return to the
        // offer's free pool: paymentAccepted keeps counting it (decrements on void only).
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBidPartial(offerId, 40);
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

    function test_Secondary_CancelOffer_Bid_FinalizedAndVoidedLots_ExactlyOnceInvariant() public {
        // Every unit of consideration leaves custody exactly once: finalized lot via payout,
        // voided lot back to the free pool and out via the cancel refund.
        bytes32 offerId = _postBid();
        bytes32 settlementIdA = _acceptBidPartial(offerId, 40);
        bytes32 settlementIdB = _acceptBidPartial(offerId, 30);
        uint256 lotPaymentA = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementIdA);

        _voidSettlementBothParties(settlementIdB);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA, "seller paid the finalized lot");
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceAfterAccept + (CONSIDERATION - lotPaymentA),
            "refund covers free pool plus voided lot, excludes finalized lot"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained, nothing over-refunded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Terminal-state guards on settled escrows
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_RevertIf_VoidSecondaryTradeAgreement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyVoided.selector);
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_Secondary_RevertIf_VoidSecondaryTradeAgreement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyFinalized.selector);
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");
    }

    function test_Secondary_RevertIf_SyncVoidedSecondaryTradeAgreement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyVoided.selector);
        dm.syncVoidedSecondaryTradeAgreement(settlementId);
    }

    function test_Secondary_RevertIf_SyncVoidedSecondaryTradeAgreement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyFinalized.selector);
        dm.syncVoidedSecondaryTradeAgreement(settlementId);
    }

    function test_Secondary_RevertIf_FinalizeDeal_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    function test_Secondary_RevertIf_FinalizeDeal_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(ISecondaryTradeStorage.SecondaryDealAlreadyVoided.selector);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    function test_Secondary_VoidSecondaryTradeAgreement_SingleRequest_KeepsPaid_StillFinalizable() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        // One party's void request only records intent; it must not void locally.
        vm.prank(buyer);
        dm.voidSecondaryTradeAgreement(settlementId, buyer, "");

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "single request must not void the escrow"
        );
        assertFalse(registry.isVoided(settlementId), "registry not voided on a single request");

        // The counterparty can still finalize.
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable after a lone void request"
        );
    }

    function test_Secondary_SyncVoidedSecondaryTradeAgreement_MirrorsRegistryVoid() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

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
        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "buyer refunded on sync");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasSecondaryEscrow discriminator
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_HasSecondaryEscrow_FalseForPrimaryDeal() public {
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
            printers, address(paymentToken), CONSIDERATION, bytes32(0), 997,
            new string[](0), parties, certDetails, partyValues, new address[](0), bytes32(0), block.timestamp + 1 days
        );

        SecondaryEscrow memory se = dm.getSecondaryEscrow(agreementId);
        assertEq(se.counterparty, address(0), "primary deal should have no SecondaryEscrow");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Coverage gaps (see specs/analysis/dealManager secondary trades — test coverage map.md)
    // ─────────────────────────────────────────────────────────────────────────

    // Offer-level expiry: acceptOffer past offer.validUntil reverts with OfferExpired. The check runs
    // before any signature/condition work, so an empty acceptor sig still reverts here first.
    function test_Secondary_RevertIf_AcceptOffer_OfferExpired() public {
        bytes32 offerId = _postSellOffer(); // validUntil = block.timestamp + 1 days

        vm.warp(block.timestamp + 2 days);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: 0,
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

    // Voiding one of several lots on a FULLY_ACCEPTED offer leaves unitsAccepted > 0, so the offer
    // reverts to PARTIALLY_ACCEPTED (not LIVE). The SELL lot returns to the offer's free pool and
    // stays reserved (offer not cancelled); only the voided lot's buyer payment is refunded.
    // Nonzero fee path: finalize pays the seller amount minus fee, and the fee splits into an
    // integrator portion (to the offer's integrator/feeDestination) and a platform portion, summing
    // to the total fee. Default tests run fee=0, so this is the only exercise of the split branch.
    function test_Secondary_FinalizeDeal_NonzeroFee_SplitsIntegratorAndPlatform() public {
        address integrator = makeAddr("integrator");
        address platform   = makeAddr("platform");

        dmFactory.setIsIntegratorWhitelisted(true);
        dmFactory.setIntegratorFeeRatio(3000); // 30% of the fee routes to the integrator
        vm.prank(owner);
        dmFactory.setDefaultFeeRatio(1000);    // 10% ticket fee
        vm.prank(owner);
        dmFactory.setPlatformPayable(platform);

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_FinalizeDeal_NonzeroFee_SplitsIntegratorAndPlatform"));
        p.integrator = integrator;
        vm.prank(seller);
        bytes32 offerId = dm.postOffer(p);

        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        uint256 fee           = CONSIDERATION * 1000 / 10000; // 1 ether
        uint256 integratorFee = fee * 3000 / 10000;           // 0.3 ether
        uint256 platformFee   = fee - integratorFee;          // 0.7 ether

        assertEq(paymentToken.balanceOf(seller), sellerBefore + CONSIDERATION - fee, "seller paid amount minus fee");
        assertEq(paymentToken.balanceOf(integrator), integratorFee, "integrator gets its fee share");
        assertEq(paymentToken.balanceOf(platform), platformFee, "platform gets the remaining fee");
        assertEq(integratorFee + platformFee, fee, "split is exact: integrator + platform == total fee");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
    }

    // Closing conditions are owner-managed DealManager config, snapshotted onto the offer at postOffer and
    // evaluated at finalizeDeal — distinct from the threshold conditions checked at post/accept. A failing
    // closing condition must block finalize.
    function test_Secondary_RevertIf_FinalizeDeal_ClosingConditionFails() public {
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

    // Counterpart: a passing closing condition lets finalize through, proving the finalize-time
    // check runs and is not an unconditional block.
    function test_Secondary_FinalizeDeal_ClosingConditionPasses() public {
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

    // Re-posting the same offeror/template/salt collides on the derived offerId and reverts.
    function test_Secondary_RevertIf_PostOffer_OfferAlreadyExists() public {
        _postSellOffer();

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferAlreadyExists.selector);
        dm.postOffer(_defaultSellOfferParams()); // same salt → same offerId
    }

    // voidSecondaryTradeAgreement requires the declared signer to equal msg.sender.
    function test_Secondary_RevertIf_VoidSecondaryTradeAgreement_SignerNotCaller() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.NotSigner.selector);
        dm.voidSecondaryTradeAgreement(settlementId, seller, ""); // signer=seller, caller=buyer
    }

    // A caller who is neither the offeror nor the settlement counterparty cannot request a void.
    function test_Secondary_RevertIf_VoidSecondaryTradeAgreement_NotPartyToAgreement() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(ISecondaryTradeStorage.NotPartyToAgreement.selector);
        dm.voidSecondaryTradeAgreement(settlementId, stranger, "");
    }

    // finalizeSecondaryTradeAgreement past the settlement's expiry reverts. The settlement agreement's
    // registry expiry equals secEscrow.expiry (both = offer.validUntil), so the registry
    // finalizeContract call reverts ContractExpired before the escrow's own SecondaryDealExpired guard is
    // reached — that guard is defensive/unreachable for secondary settlements in normal flow.
    function test_Secondary_RevertIf_FinalizeDeal_PastSettlementExpiry() public {
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
    function test_Secondary_AcceptOffer_EmitsOfferAccepted() public {
        bytes32 offerId = _postSellOffer();
        // Compute the acceptor sig before vm.expectEmit/vm.prank: its registry view calls would
        // otherwise consume the prank.
        bytes memory sig = _acceptorSig(offerId, buyer, buyerKey);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: sig,
            openEndorsementSig: ""
        });

        vm.expectEmit(true, false, true, true); // check offerId + acceptor + units; skip computed settlement id
        emit ISecondaryTradeStorage.OfferAccepted(offerId, bytes32(0), buyer, UNITS);
        vm.prank(buyer);
        dm.acceptOffer(p);
    }

    // cancelOffer emits OfferCancelled with the offer id and offeror.
    function test_Secondary_CancelOffer_EmitsOfferCancelled() public {
        bytes32 offerId = _postSellOffer();

        vm.expectEmit(true, true, false, false);
        emit ISecondaryTradeStorage.OfferCancelled(offerId, seller);
        vm.prank(seller);
        dm.cancelOffer(offerId);
    }
}
