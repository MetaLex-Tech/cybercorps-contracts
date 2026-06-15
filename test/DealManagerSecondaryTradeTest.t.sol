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
import {DealManager, LexScrowStorage} from "../src/DealManager.sol";
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

contract DealManagerFactoryHelper is DealManagerFactory {
    bool private _integWhitelisted;

    function setIsIntegratorWhitelisted(bool v) external { _integWhitelisted = v; }
    function isIntegratorWhitelisted(address) external view returns (bool) { return _integWhitelisted; }
    function getIntegratorFeeRatio() external pure returns (uint256) { return 0; }
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
            thresholdConditions: new address[](0),
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
            thresholdConditions: new address[](0),
            buyerName: "Test Buyer",
            buyerHostingMode: 0,
            adminMultisig: address(0)
        });
    }

    function _postSellOffer() internal returns (bytes32 offerAgreementId) {
        vm.prank(seller);
        offerAgreementId = dm.postOffer(_defaultSellOfferParams());
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
        dm.voidSecondaryAgreement(settlementId, buyer, "");
        vm.prank(seller);
        dm.voidSecondaryAgreement(settlementId, seller, "");
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

    function test_Secondary_PostOffer_Sell_StoresOfferRecord() public {
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
    }

    function test_Secondary_PostOffer_Sell_ReservesUnits() public {
        _postSellOffer();

        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "units should be reserved");
    }

    function test_Secondary_PostOffer_Sell_EmitsEvent() public {
        vm.expectEmit(false, true, false, false); // don't check offerAgreementId (computed inside)
        emit ISecondaryTradeStorage.OfferPosted(bytes32(0), seller, OfferSide.SELL, UNITS, CONSIDERATION);
        vm.prank(seller);
        dm.postOffer(_defaultSellOfferParams());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — bid
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_PostOffer_Bid_StoresOfferRecord() public {
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
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "bid should reserve no units at post");
    }

    function test_Secondary_PostOffer_Bid_CreatesHoldingEscrow() public {
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);
        _postBid();
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

    function test_Secondary_PostOffer_Sell_MultipleThresholdConditionsAllPass() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(true));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_PostOffer_Sell_MultipleThresholdConditionsAllPass"));
        p.thresholdConditions = conds;

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
        p.thresholdConditions = conds;

        vm.prank(seller);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        dm.postOffer(p);
    }

    function test_Secondary_RevertIf_PostOffer_SecondThresholdConditionFails() public {
        address[] memory conds = new address[](2);
        conds[0] = address(new SecConditionMock(true));
        conds[1] = address(new SecConditionMock(false));

        PostOfferParams memory p = _defaultSellOfferParams();
        p.salt = uint256(keccak256("test_Secondary_RevertIf_PostOffer_SecondThresholdConditionFails"));
        p.thresholdConditions = conds;

        vm.prank(seller);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        dm.postOffer(p);
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
        vm.expectRevert(ISecondaryTradeStorage.OfferBelowMinThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly UNITS
    }

    function test_Secondary_RevertIf_PostOffer_BelowMinConsiderationThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION + 1);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferBelowMinThreshold.selector);
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
        vm.expectRevert(ISecondaryTradeStorage.PartialFillBelowMinThreshold.selector);
        dm.acceptOffer(p);
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

    function test_Secondary_CancelOffer_Sell_MarksOfferCancelled() public {
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

    function test_Secondary_CancelOffer_Bid_MarksOfferCancelled() public {
        bytes32 offerId = _postBid();

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — outstanding settlements stay active
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Sell_KeepsOutstandingSettlements() public {
        bytes32 offerId = _postSellOffer();
        uint256 lotUnits = UNITS / 2;
        bytes32 settlementId = _acceptSellOfferPartial(offerId, lotUnits);
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(seller);
        dm.cancelOffer(offerId);

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

        // The active lot is still finalizable after the offer is cancelled.
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "active lot still finalizable after cancel"
        );
    }

    function test_Secondary_CancelOffer_Bid_KeepsOutstandingSettlements() public {
        bytes32 offerId = _postBid();
        bytes32 settlementId = _acceptBidPartial(offerId, 40);
        uint256 lotPayment = CONSIDERATION * 40 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

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

        // The active lot is still finalizable after the offer is cancelled.
        uint256 sellerBefore = paymentToken.balanceOf(seller);
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
        assertEq(paymentToken.balanceOf(seller), sellerBefore + lotPayment, "active lot settles to the acceptor");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody drained after finalize");
    }

    function test_Secondary_CancelOffer_Sell_KeepsActiveLots_FinalizedUntouched() public {
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
        dm.finalizeDeal(settlementIdA);

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
        dm.finalizeDeal(settlementIdB);
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA + lotPaymentB, "active lot settles after cancel");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody drained");
    }

    function test_Secondary_CancelOffer_Bid_KeepsActiveLots_FinalizedUntouched() public {
        bytes32 offerId = _postBid();
        bytes32 settlementIdA = _acceptBidPartial(offerId, 40);
        bytes32 settlementIdB = _acceptBidPartial(offerId, 30);
        uint256 lotPaymentA = CONSIDERATION * 40 / UNITS;
        uint256 lotPaymentB = CONSIDERATION * 30 / UNITS;
        uint256 buyerBalanceAfterAccept = paymentToken.balanceOf(buyer);
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeDeal(settlementIdA);

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
        dm.finalizeDeal(settlementIdB);
        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPaymentA + lotPaymentB, "active lot settles after cancel");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "custody fully drained");
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

    function test_Secondary_AcceptSellOffer_UpdatesOfferFillState() public {
        bytes32 offerId = _postSellOffer();
        _acceptSellOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.unitsAccepted, UNITS);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED));
    }

    function test_Secondary_AcceptSellOffer_PartialFill_UpdatesStateCorrectly() public {
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
        bytes32 settlementId = dm.acceptOffer(p);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.PARTIALLY_ACCEPTED));
        assertEq(offer.unitsAccepted, UNITS / 2);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.counterparty, buyer, "counterparty should be the acceptor");
        assertEq(se.offerId, offerId, "offerId back-link should be set");
        assertEq(se.tokenId, sellerTokenId, "settlement should record the seller's tokenId");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "partial fill keeps the offer's full reservation");
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

    function test_Secondary_AcceptSellOffer_MultipleFillsFully() public {
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

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));

        p.units = secondUnits;
        p.acceptorAgreementSig = _acceptorSig(offerId, buyer, buyerKey); // settlement id changes with each fill
        vm.prank(buyer);
        bytes32 settlementId2 = dm.acceptOffer(p);

        assertTrue(settlementId1 != settlementId2, "each fill gets its own settlement escrow");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(dm.getOffer(offerId).unitsAccepted, UNITS);
        assertEq(dm.getSecondaryEscrow(settlementId1).paymentAmount, expectedFirst);
        assertEq(dm.getSecondaryEscrow(settlementId2).paymentAmount, expectedSecond);
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

    function test_Secondary_AcceptBuyOffer_FullFill_StatusIsFullyAccepted() public {
        bytes32 offerId = _postBid();
        _acceptBid(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED));
        assertEq(offer.unitsAccepted, UNITS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalizeDeal — secondary path
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_FinalizeDeal_SendsPaymentToSeller() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 sellerBefore = paymentToken.balanceOf(seller);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

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
        dm.finalizeDeal(settlementId);

        assertEq(
            paymentToken.balanceOf(seller),
            sellerBefore + CONSIDERATION,
            "acceptor (seller) should receive payment"
        );
        assertEq(paymentToken.balanceOf(address(dm)), 0, "escrow should be empty after finalize");
    }

    function test_Secondary_Offer_FinalizedAfterAllLotsFinalize() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementIdA = _acceptSellOfferPartial(offerId, 40);
        bytes32 settlementIdB = _acceptSellOfferPartial(offerId, 60);

        vm.prank(keeper);
        dm.finalizeDeal(settlementIdA);
        assertEq(
            uint8(dm.getOffer(offerId).status),
            uint8(OfferStatus.FULLY_ACCEPTED),
            "offer not terminal until every lot settles"
        );

        vm.prank(keeper);
        dm.finalizeDeal(settlementIdB);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FINALIZED), "all offered units settled");
    }

    function test_Secondary_RevertIf_CancelOffer_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        vm.prank(seller);
        vm.expectRevert(ISecondaryTradeStorage.OfferNotAvailable.selector);
        dm.cancelOffer(offerId);
    }

    function test_Secondary_FinalizeDeal_DoesNotPayCompanyPayable() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 companyBefore = paymentToken.balanceOf(company);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        assertEq(paymentToken.balanceOf(company), companyBefore, "company should NOT receive payment on secondary");
    }

    function test_Secondary_FinalizeDeal_CallsIssuanceManagerSecondaryTransfer() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        assertFalse(im.secondaryTransferCalled());

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        assertTrue(im.secondaryTransferCalled(), "secondaryTransfer should be called");
    }

    function test_Secondary_FinalizeDeal_EmitsSecondaryDealFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.expectEmit(true, false, false, false);
        emit ISecondaryTradeStorage.SecondaryDealFinalized(settlementId, seller, buyer, CONSIDERATION);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
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
    // voidExpiredDeal — secondary path
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
        dm.voidExpiredDeal(settlementId, buyer, "");

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
        dm.voidExpiredDeal(settlementId, buyer, "");

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
        dm.voidExpiredDeal(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "buyer should be refunded");
    }

    function test_Secondary_RevertIf_VoidExpiredDeal_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, buyer, "");

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(LexScrowStorage.DealVoided.selector);
        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_Secondary_RevertIf_VoidExpiredDeal_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);

        vm.expectRevert(LexScrowStorage.DealAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, buyer, "");
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
        dm.finalizeDeal(settlementId);

        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS / 2, "finalized lot should be consumed");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS - UNITS / 2, "remaining units must stay reserved: offer still open");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0);
    }

    function test_Secondary_FinalizeDeal_FullFill_ConsumesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

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
        dm.finalizeDeal(sid1);
        assertEq(certPrinter.reservedUnits(sellerTokenId), secondUnits, "second lot still reserved while in-flight");
        assertEq(certPrinter.consumedUnits(sellerTokenId), firstUnits);

        vm.prank(keeper);
        dm.finalizeDeal(sid2);
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no units reserved after last settlement finalized");
        assertEq(certPrinter.consumedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_FinalizeDeal_CancelKeepingLots_ConsumesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "in-flight lot held after cancel (no free units)");

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

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
        dm.finalizeDeal(settlementId);

        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + lotPayment, "lot paid out to the acceptor");
        assertEq(paymentToken.balanceOf(address(dm)), 0, "no payment left in custody");
        assertEq(certPrinter.consumedUnits(sellerTokenId), 40, "lot's reserved units consumed at finalize");
        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "no reservation left");
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.CANCELLED), "CANCELLED stays sticky");
    }

    function test_Secondary_CancelOffer_KeepingLots_PartialFill_ReleasesOnlyFreeUnits() public {
        // Cancel releases the uncommitted units immediately; the in-flight lot stays reserved.
        bytes32 offerId = _postSellOffer();
        uint256 lotUnits = UNITS / 2;
        _acceptSellOfferPartial(offerId, lotUnits);

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS - lotUnits, "free units released at cancel");
        assertEq(certPrinter.reservedUnits(sellerTokenId), lotUnits, "in-flight lot stays reserved");
    }

    function test_Secondary_VoidSettlement_FullyAccepted_ReservationHeld_OfferGoesLive() public {
        // Bug guard: voiding the only settlement of a FULLY_ACCEPTED offer reverts it to LIVE.
        // The reservation must NOT be released — future acceptors still need it.
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        // One party's request only records intent: escrow stays ACCEPTED, offer unchanged.
        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "single request must not void the escrow"
        );
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED), "offer unchanged after lone request");

        // Second party completes the void.
        vm.prank(seller);
        dm.voidSecondaryAgreement(settlementId, seller, "");

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.LIVE), "offer should revert to LIVE");
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "reservation must stay active: offer is LIVE");
        assertEq(certPrinter.releasedUnits(sellerTokenId), 0);
    }

    function test_Secondary_VoidSettlement_AfterCancel_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertEq(certPrinter.reservedUnits(sellerTokenId), UNITS, "in-flight lot held after cancel (no free units)");

        _voidSettlementBothParties(settlementId);

        assertEq(certPrinter.reservedUnits(sellerTokenId), 0, "lot released: CANCELLED + last settlement voided");
        assertEq(certPrinter.releasedUnits(sellerTokenId), UNITS);
    }

    function test_Secondary_VoidSettlement_Bid_OfferStillOpen_NoRefund_FundsStayInCustody() public {
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

    function test_Secondary_VoidSettlement_Bid_AfterCancel_RefundsLot() public {
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
        dm.finalizeDeal(settlementId);

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
        dm.finalizeDeal(settlementIdA);

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

    function test_Secondary_RevertIf_VoidSettlement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        uint256 buyerAfterVoid = paymentToken.balanceOf(buyer);

        vm.expectRevert(LexScrowStorage.DealVoided.selector);
        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");

        assertEq(paymentToken.balanceOf(buyer), buyerAfterVoid, "buyer must not be refunded twice");
    }

    function test_Secondary_RevertIf_VoidSettlement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        vm.expectRevert(LexScrowStorage.DealAlreadyFinalized.selector);
        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");
    }

    function test_Secondary_RevertIf_SyncVoidedSettlement_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(LexScrowStorage.DealVoided.selector);
        dm.syncVoidedSettlement(settlementId);
    }

    function test_Secondary_RevertIf_SyncVoidedSettlement_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        vm.expectRevert(LexScrowStorage.DealAlreadyFinalized.selector);
        dm.syncVoidedSettlement(settlementId);
    }

    function test_Secondary_RevertIf_FinalizeDeal_AlreadyFinalized() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        vm.expectRevert(LexScrowStorage.DealAlreadyFinalized.selector);
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
    }

    function test_Secondary_RevertIf_FinalizeDeal_AlreadyVoided() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        _voidSettlementBothParties(settlementId);

        vm.expectRevert(LexScrowStorage.DealVoided.selector);
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
    }

    function test_Secondary_VoidSettlement_SingleRequest_KeepsPaid_StillFinalizable() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        // One party's void request only records intent; it must not void locally.
        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.ACCEPTED),
            "single request must not void the escrow"
        );
        assertFalse(registry.isVoided(settlementId), "registry not voided on a single request");

        // The counterparty can still finalize.
        vm.prank(keeper);
        dm.finalizeDeal(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "still finalizable after a lone void request"
        );
    }

    function test_Secondary_SyncVoidedSettlement_MirrorsRegistryVoid() public {
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

        dm.syncVoidedSettlement(settlementId);

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
}
