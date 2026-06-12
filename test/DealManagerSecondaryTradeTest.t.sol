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
import {DealManager, LexScroWLite} from "../src/DealManager.sol";
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

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract SecERC20Mock is ERC20 {
    constructor() ERC20("Payment Token", "PAY") {}
    function mint(address to, uint256 amount) public { _mint(to, amount); }
}

// TODO review after CyberCertPrinter updated
contract SecCertPrinterMock is ERC721Enumerable {
    mapping(bytes32 => bool) public reservationActive;
    mapping(bytes32 => bool) public reservationReleased;
    mapping(uint256 => Endorsement[]) private _endorsements;

    constructor() ERC721("Ledger Entry Token", "LET") {}

    function mint(address to) public returns (uint256 tokenId) {
        tokenId = totalSupply();
        _safeMint(to, tokenId);
    }

    function reserveUnits(uint256, bytes32 reservationId, uint256) external {
        reservationActive[reservationId] = true;
    }

    function releaseUnits(bytes32 reservationId) external {
        reservationActive[reservationId] = false;
        reservationReleased[reservationId] = true;
    }

    function consumeUnits(bytes32 reservationId) external {
        reservationActive[reservationId] = false;
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

    function secondaryTransfer(bytes calldata) external {
        secondaryTransferCalled = true;
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

contract SecAgreementRegistryMock {
    mapping(bytes32 => bool) public isVoided;
    mapping(bytes32 => bool) public isFinalized;
    uint256 private _nonce;

    function createContract(
        bytes32, uint256, string[] memory, address[] memory,
        string[][] memory, bytes32, address, uint256
    ) external returns (bytes32) {
        return keccak256(abi.encodePacked("primary", _nonce++));
    }

    function signContractFor(
        address, bytes32, string[] memory, bytes calldata, bool, string memory
    ) external {}

    function signContractWithEscrow(
        address, bytes32, string[] memory, bytes calldata, bool, string memory
    ) external {}

    function voidContractFor(bytes32 contractId, address, bytes calldata) external {
        isVoided[contractId] = true;
    }

    function finalizeContract(bytes32 contractId) external {
        isFinalized[contractId] = true;
    }

    function allPartiesSigned(bytes32) external pure returns (bool) { return true; }
    function hasSigned(bytes32, address) external pure returns (bool) { return false; }
    function getSignerValues(bytes32, address) external pure returns (string[] memory) {
        return new string[](0);
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
    address public seller;
    address public buyer;
    address public keeper;
    address public company;

    SecERC20Mock      public paymentToken;
    SecCertPrinterMock public certPrinter;
    SecIssuanceManagerMock public im;
    SecAgreementRegistryMock public registry;
    SecCorpMock        public corp;
    DealManagerFactoryHelper   public dmFactory;
    DealManager        public dm;
    BorgAuth           public auth;

    uint256 public constant CONSIDERATION = 10 ether;
    uint256 public constant UNITS         = 100;
    uint256 public sellerTokenId;

    function setUp() public {
        owner  = makeAddr("owner");
        seller = makeAddr("seller");
        buyer  = makeAddr("buyer");
        keeper = makeAddr("keeper");
        company = makeAddr("company");

        paymentToken = new SecERC20Mock();
        certPrinter  = new SecCertPrinterMock();
        im           = new SecIssuanceManagerMock();
        registry     = new SecAgreementRegistryMock();
        corp         = new SecCorpMock(company);

        auth = new BorgAuth(owner);

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

        // Fund seller (for buy-offer tests where seller receives nothing upfront)
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
            salt: uint256(keccak256("defaultBuyOffer")),
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

    function _postBuyOffer() internal returns (bytes32 offerAgreementId) {
        vm.prank(buyer);
        offerAgreementId = dm.postOffer(_defaultBuyOfferParams());
    }

    function _acceptSellOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: UNITS,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    function _acceptBuyOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: UNITS,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        settlementAgreementId = dm.acceptOffer(p);
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
        assertTrue(offer.unitReservationId != bytes32(0), "sell offer should have a unitReservationId");
    }

    function test_Secondary_PostOffer_Sell_ReservesUnits() public {
        bytes32 offerId = _postSellOffer();

        Offer memory offer = dm.getOffer(offerId);
        assertTrue(certPrinter.reservationActive(offer.unitReservationId), "units should be reserved");
    }

    function test_Secondary_PostOffer_Sell_EmitsEvent() public {
        vm.expectEmit(false, true, false, false); // don't check offerAgreementId (computed inside)
        emit DealManager.OfferPosted(bytes32(0), seller, OfferSide.SELL, UNITS, CONSIDERATION);
        vm.prank(seller);
        dm.postOffer(_defaultSellOfferParams());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // postOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_PostOffer_BuyOffer_StoresOfferRecord() public {
        bytes32 offerId = _postBuyOffer();

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.spvAddress, address(corp), "spvAddress should be corp");
        assertEq(offer.offeror, buyer, "offeror should be buyer");
        assertEq(uint8(offer.side), uint8(OfferSide.BUY));
        assertEq(offer.certPrinter, address(certPrinter), "buy offer certPrinter should be set at post");
        assertEq(offer.tokenId, 0, "buy offer should have no tokenId");
        assertEq(offer.units, UNITS);
        assertEq(offer.paymentToken, address(paymentToken));
        assertEq(offer.consideration, CONSIDERATION);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE));
        assertEq(offer.unitsAccepted, 0);
        assertEq(offer.unitReservationId, bytes32(0), "buy offer should have no unitReservationId");
    }

    function test_Secondary_PostOffer_BuyOffer_CreatesHoldingEscrow() public {
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);
        _postBuyOffer();
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
        vm.expectRevert(DealManager.MissingCertPrinter.selector);
        dm.postOffer(p);
    }

    function test_Secondary_RevertIf_PostOffer_MissingCertPrinter_BuyOffer() public {
        PostOfferParams memory p = _defaultBuyOfferParams();
        p.certPrinter = address(0);

        vm.prank(buyer);
        vm.expectRevert(DealManager.MissingCertPrinter.selector);
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
        vm.expectRevert(DealManager.AgreementConditionsNotMet.selector);
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
        vm.expectRevert(DealManager.AgreementConditionsNotMet.selector);
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
        vm.expectRevert(DealManager.IntegratorNotWhitelisted.selector);
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
        vm.expectRevert(DealManager.OfferBelowMinThreshold.selector);
        dm.postOffer(_defaultSellOfferParams()); // offers exactly UNITS
    }

    function test_Secondary_RevertIf_PostOffer_BelowMinConsiderationThreshold() public {
        vm.prank(owner);
        dm.setMinTradeThreshold(0, CONSIDERATION + 1);

        vm.prank(seller);
        vm.expectRevert(DealManager.OfferBelowMinThreshold.selector);
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
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(DealManager.PartialFillBelowMinThreshold.selector);
        dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Sell_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();
        Offer memory offer = dm.getOffer(offerId);
        bytes32 resId = offer.unitReservationId;

        vm.prank(seller);
        dm.cancelOffer(offerId);

        assertFalse(certPrinter.reservationActive(resId), "reservation should be released");
        assertTrue(certPrinter.reservationReleased(resId), "reservation should be marked released");
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
        vm.expectRevert(DealManager.NotOfferor.selector);
        dm.cancelOffer(offerId);
    }

    // TODO add cases when offer is filled (or partially filled)

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_BuyOffer_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore + CONSIDERATION,
            "buyer should be refunded"
        );
    }

    function test_Secondary_CancelOffer_BuyOffer_MarksOfferCancelled() public {
        bytes32 offerId = _postBuyOffer();

        vm.prank(buyer);
        dm.cancelOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — sell offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_AcceptSellOffer_CreatesSettlementEscrow() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(uint8(se.status), uint8(SecondaryEscrowStatus.PAID), "settlement escrow should be PAID");
        assertEq(se.paymentAmount, CONSIDERATION, "consideration in settlement escrow");
        assertEq(se.buyer, buyer, "buyer set correctly");
    }

    function test_Secondary_AcceptSellOffer_StoresSecondaryEscrow() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.sellerAddress, seller, "seller address should be set");
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
        bytes32 expectedResId = dm.getOffer(offerId).unitReservationId;

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId = dm.acceptOffer(p);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.PARTIALLY_ACCEPTED));
        assertEq(offer.unitsAccepted, UNITS / 2);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.sellerAddress, seller, "seller address should be set");
        assertEq(se.offerId, offerId, "offerId back-link should be set");
        assertEq(se.unitReservationId, expectedResId, "sell partial fill reuses the offer's unit reservation");
    }

    function test_Secondary_AcceptSellOffer_PartialFill_ProRataConsideration() public {
        bytes32 offerId = _postSellOffer();
        uint256 partialUnits = UNITS / 4;
        uint256 expectedConsideration = CONSIDERATION * partialUnits / UNITS;

        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: partialUnits,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
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
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId1 = dm.acceptOffer(p);

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));

        p.units = secondUnits;
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
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });

        vm.prank(buyer);
        vm.expectRevert(DealManager.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    function test_Secondary_RevertIf_AcceptSellOffer_OverfillAfterPartialFill() public {
        bytes32 offerId = _postSellOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS / 2,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        dm.acceptOffer(p);

        p.units = UNITS / 2 + 1; // one more than remaining
        vm.prank(buyer);
        vm.expectRevert(DealManager.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_AcceptBuyOffer_CreatesSettlementEscrowAlreadyPaid() public {
        bytes32 offerId = _postBuyOffer();
        bytes32 settlementId = _acceptBuyOffer(offerId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.PAID),
            "settlement escrow should open PAID (migrated from holding)"
        );
    }

    function test_Secondary_AcceptBuyOffer_MigratesFundsFromHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();

        // Funds are in contract from postOffer() before acceptance
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION);

        bytes32 settlementId = _acceptBuyOffer(offerId);

        // Funds remain in DealManager, now attributed to the settlement SecondaryEscrow
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds still in DealManager");
        assertEq(
            dm.getSecondaryEscrow(settlementId).paymentAmount,
            CONSIDERATION,
            "consideration attributed to settlement escrow"
        );
    }

    function test_Secondary_AcceptBuyOffer_ReservesSellerUnits() public {
        bytes32 offerId = _postBuyOffer();
        bytes32 settlementId = _acceptBuyOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertTrue(certPrinter.reservationActive(se.unitReservationId), "seller units should be reserved at buy-offer acceptance");
    }

    function test_Secondary_RevertIf_AcceptBuyOffer_CannotAcceptTwice() public {
        bytes32 offerId = _postBuyOffer();

        // Full fill — succeeds
        _acceptBuyOffer(offerId);

        // Second attempt reverts because offer is now FULLY_ACCEPTED
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        vm.expectRevert(DealManager.OfferNotAvailable.selector);
        dm.acceptOffer(p);
    }

    function test_Secondary_RevertIf_AcceptOffer_Buy_UnitsExceedOffer() public {
        bytes32 offerId = _postBuyOffer();

        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerId,
            units: UNITS + 1,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement"
        });

        vm.prank(seller);
        vm.expectRevert(DealManager.UnitsExceedOffer.selector);
        dm.acceptOffer(p);
    }

    function test_Secondary_AcceptBuyOffer_FullFill_StatusIsFullyAccepted() public {
        bytes32 offerId = _postBuyOffer();
        _acceptBuyOffer(offerId);

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
        emit DealManager.SecondaryDealFinalized(settlementId, seller, buyer, CONSIDERATION);

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
            "",
            partyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1 days
        );

        // registry mock already validates "" as a valid sig via the mock's any-sig behavior
        // (SecAgreementRegistryMock.signContractFor is a no-op)
        vm.prank(buyer);
        dm.signDealAndPay(buyer, agreementId, "", new string[](0), false, "Bob", "");

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
        bytes32 resId = se.unitReservationId;

        vm.warp(se.expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, keeper, "");

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.LIVE), "offer should be LIVE after void");
        assertTrue(certPrinter.reservationActive(resId), "reservation must stay active: offer is LIVE");
        assertFalse(certPrinter.reservationReleased(resId), "reservation must not have been released");
    }

    function test_Secondary_VoidExpiredDeal_ReleasesReservation_WhenOfferCancelled() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertTrue(certPrinter.reservationActive(resId), "reservation held after cancel with active settlement");

        vm.warp(dm.getSecondaryEscrow(settlementId).expiry + 1);
        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, keeper, "");

        assertFalse(certPrinter.reservationActive(resId), "reservation released: offer CANCELLED, last settlement voided");
        assertTrue(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_VoidExpiredDeal_RefundsBuyer() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        uint256 expiry = dm.getSecondaryEscrow(settlementId).expiry;
        vm.warp(expiry + 1);

        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, keeper, "");

        assertEq(paymentToken.balanceOf(buyer), buyerBefore + CONSIDERATION, "buyer should be refunded");
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
            "",
            partyValues,
            new address[](0),
            bytes32(0),
            expiry
        );

        // Cert is now in escrow (owned by DealManager)
        assertEq(certPrinter.ownerOf(certIds[0]), address(dm));

        vm.warp(expiry + 1);

        vm.prank(keeper);
        dm.voidExpiredDeal(agreementId, keeper, "");

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
        assertTrue(se.sellerAddress != address(0), "SecondaryEscrow should exist after accept");
    }

    function _acceptSellOfferPartial(bytes32 offerAgreementId, uint256 units) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerId: offerAgreementId,
            units: units,
            buyer: buyer,
            buyerName: "Bob",
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reservation release guards — SELL offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_FinalizeDeal_PartialFill_ReservationHeld_OfferStillOpen() public {
        // Bug guard: paymentAccepted drops to 0 after a partial fill finalizes, but the offer
        // is still PARTIALLY_ACCEPTED with remaining units — reservation must NOT be released.
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        bytes32 settlementId = _acceptSellOfferPartial(offerId, UNITS / 2);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.PARTIALLY_ACCEPTED));

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        assertTrue(certPrinter.reservationActive(resId), "reservation must stay active: offer still open");
        assertFalse(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_FinalizeDeal_FullFill_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        assertFalse(certPrinter.reservationActive(resId), "reservation released after full-fill finalized");
        assertTrue(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_FinalizeDeal_TwoPartialFills_ReservationReleasedOnlyAfterLast() public {
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        uint256 firstUnits  = UNITS / 2;
        uint256 secondUnits = UNITS - firstUnits;

        bytes32 sid1 = _acceptSellOfferPartial(offerId, firstUnits);
        bytes32 sid2 = _acceptSellOfferPartial(offerId, secondUnits);

        vm.prank(keeper);
        dm.finalizeDeal(sid1);
        assertTrue(certPrinter.reservationActive(resId), "reservation held while second settlement in-flight");

        vm.prank(keeper);
        dm.finalizeDeal(sid2);
        assertFalse(certPrinter.reservationActive(resId), "reservation released after last settlement finalized");
        assertTrue(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_FinalizeDeal_CancelledOffer_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertTrue(certPrinter.reservationActive(resId), "reservation held after cancel with active settlement");

        vm.prank(keeper);
        dm.finalizeDeal(settlementId);

        assertFalse(certPrinter.reservationActive(resId), "reservation released: CANCELLED + last settlement finalized");
        assertTrue(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_VoidSettlement_FullyAccepted_ReservationHeld_OfferGoesLive() public {
        // Bug guard: voiding the only settlement of a FULLY_ACCEPTED offer reverts it to LIVE.
        // The reservation must NOT be released — future acceptors still need it.
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        bytes32 settlementId = _acceptSellOffer(offerId);
        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.FULLY_ACCEPTED));

        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");

        assertEq(uint8(dm.getOffer(offerId).status), uint8(OfferStatus.LIVE), "offer should revert to LIVE");
        assertTrue(certPrinter.reservationActive(resId), "reservation must stay active: offer is LIVE");
        assertFalse(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_VoidSettlement_CancelledOffer_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();
        bytes32 resId = dm.getOffer(offerId).unitReservationId;

        bytes32 settlementId = _acceptSellOffer(offerId);

        vm.prank(seller);
        dm.cancelOffer(offerId);
        assertTrue(certPrinter.reservationActive(resId), "reservation held after cancel with active settlement");

        vm.prank(buyer);
        dm.voidSecondaryAgreement(settlementId, buyer, "");

        assertFalse(certPrinter.reservationActive(resId), "reservation released: CANCELLED + last settlement voided");
        assertTrue(certPrinter.reservationReleased(resId));
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
        assertEq(se.sellerAddress, address(0), "primary deal should have no SecondaryEscrow");
    }
}
