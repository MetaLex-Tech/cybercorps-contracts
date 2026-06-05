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
    Offer,
    SecondaryEscrow,
    PostOfferParams,
    AcceptOfferParams
} from "../src/storage/SecondaryTradeStorage.sol";
import {EscrowStatus, Token, TokenType} from "../src/storage/LexScrowStorage.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract SecERC20Mock is ERC20 {
    constructor() ERC20("Payment Token", "PAY") {}
    function mint(address to, uint256 amount) public { _mint(to, amount); }
}

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

    function createOpenContract(
        bytes32, uint256, string[] memory, address[] memory,
        string[][] memory, bytes calldata, address, uint256
    ) external returns (bytes32 agreementId) {
        agreementId = keccak256(abi.encodePacked("offer", _nonce++));
    }

    function attachAndSignAsPartyB(
        bytes32 offerAgreementId, address, string[] calldata, bytes calldata, address
    ) external returns (bytes32 settlementAgreementId) {
        settlementAgreementId = keccak256(abi.encodePacked("settlement", offerAgreementId));
    }

    function signContractFor(
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

// ─────────────────────────────────────────────────────────────────────────────
// Test contract
// ─────────────────────────────────────────────────────────────────────────────

contract DealManagerSecondaryTradeTest is Test {

    bytes32 constant SALT = keccak256("DealManagerSecondaryTradeTest");

    address public owner    = vm.addr(1);
    address public seller   = vm.addr(2);  // alice
    address public buyer    = vm.addr(3);  // bob
    address public keeper   = vm.addr(4);
    address public company  = address(0xC0);

    SecERC20Mock      public paymentToken;
    SecCertPrinterMock public certPrinter;
    SecIssuanceManagerMock public im;
    SecAgreementRegistryMock public registry;
    SecCorpMock        public corp;
    DealManagerFactory public dmFactory;
    DealManager        public dm;
    BorgAuth           public auth;

    uint256 public constant CONSIDERATION = 10 ether;
    uint256 public constant UNITS         = 100;
    uint256 public sellerTokenId;

    function setUp() public {
        paymentToken = new SecERC20Mock();
        certPrinter  = new SecCertPrinterMock();
        im           = new SecIssuanceManagerMock();
        registry     = new SecAgreementRegistryMock();
        corp         = new SecCorpMock(company);

        auth = new BorgAuth(owner);

        dmFactory = DealManagerFactory(
            address(new ERC1967Proxy(
                address(new DealManagerFactory()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            ))
        );

        dm = DealManager(
            address(new ERC1967Proxy(
                address(new DealManager()),
                abi.encodeWithSelector(
                    DealManager.initialize.selector,
                    address(auth),
                    address(corp),
                    address(registry),
                    address(im),
                    address(dmFactory)
                )
            ))
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
            exemptionPathway: 1,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: bytes32(0),
            salt: 1,
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            thresholdConditions: new address[](0)
        });
    }

    function _defaultBuyOfferParams() internal view returns (PostOfferParams memory p) {
        p = PostOfferParams({
            side: OfferSide.BUY,
            certPrinter: address(0),
            tokenId: 0,
            units: UNITS,
            paymentToken: address(paymentToken),
            consideration: CONSIDERATION,
            exemptionPathway: 1,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: bytes32(0),
            salt: 2,
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "",
            thresholdConditions: new address[](0)
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
            offerAgreementId: offerAgreementId,
            units: UNITS,
            buyer: buyer,
            buyerName: "Bob",
            fullSale: true,
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerCertPrinter: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "",
            closingConditions: new address[](0),
            thresholdConditions: new address[](0)
        });
        vm.prank(buyer);
        settlementAgreementId = dm.acceptOffer(p);
    }

    function _acceptBuyOffer(bytes32 offerAgreementId) internal returns (bytes32 settlementAgreementId) {
        AcceptOfferParams memory p = AcceptOfferParams({
            offerAgreementId: offerAgreementId,
            units: UNITS,
            buyer: buyer,
            buyerName: "Bob",
            fullSale: true,
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerCertPrinter: address(certPrinter),
            sellerTokenId: sellerTokenId,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            closingConditions: new address[](0),
            thresholdConditions: new address[](0)
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
        assertEq(offer.offeror, seller, "offeror should be seller");
        assertEq(uint8(offer.side), uint8(OfferSide.SELL));
        assertEq(offer.units, UNITS);
        assertEq(offer.consideration, CONSIDERATION);
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE));
        assertEq(offer.unitsAccepted, 0);
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
        assertEq(offer.offeror, buyer, "offeror should be buyer");
        assertEq(uint8(offer.side), uint8(OfferSide.BUY));
        assertEq(uint8(offer.status), uint8(OfferStatus.LIVE));
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

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — sell
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_Sell_ReleasesReservation() public {
        bytes32 offerId = _postSellOffer();
        Offer memory offer = dm.getOffer(offerId);
        bytes32 resId = offer.unitReservationId;

        vm.prank(seller);
        dm.cancelOffer(offerId, "");

        assertFalse(certPrinter.reservationActive(resId), "reservation should be released");
        assertTrue(certPrinter.reservationReleased(resId), "reservation should be marked released");
    }

    function test_Secondary_CancelOffer_Sell_MarksOfferCancelled() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(seller);
        dm.cancelOffer(offerId, "");

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    function test_Secondary_RevertIf_CancelOffer_NotOfferor() public {
        bytes32 offerId = _postSellOffer();

        vm.prank(buyer);
        vm.expectRevert(DealManager.NotOfferor.selector);
        dm.cancelOffer(offerId, "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_CancelOffer_BuyOffer_RefundsHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        dm.cancelOffer(offerId, "");

        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore + CONSIDERATION,
            "buyer should be refunded"
        );
    }

    function test_Secondary_CancelOffer_BuyOffer_MarksOfferCancelled() public {
        bytes32 offerId = _postBuyOffer();

        vm.prank(buyer);
        dm.cancelOffer(offerId, "");

        Offer memory offer = dm.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(OfferStatus.CANCELLED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — sell offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_AcceptOffer_Sell_CreatesSettlementEscrowInLexScrowStorage() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        // Settlement escrow should be PAID (funds pulled from buyer)
        assertEq(
            uint8(dm.getEscrowDetails(settlementId).status),
            uint8(EscrowStatus.PAID),
            "settlement escrow should be PAID"
        );
        assertEq(
            dm.getEscrowDetails(settlementId).buyerAssets[0].amount,
            CONSIDERATION,
            "consideration in settlement escrow"
        );
        assertEq(
            dm.getEscrowDetails(settlementId).corpAssets.length,
            0,
            "corpAssets should be empty"
        );
    }

    function test_Secondary_AcceptOffer_Sell_StoresSecondaryEscrow() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(se.sellerAddress, seller, "seller address should be set");
        assertEq(se.offerId, offerId, "offerId back-link should be set");
        assertTrue(se.dealMetadata.length > 0, "deal metadata should be encoded");
    }

    function test_Secondary_AcceptOffer_Sell_PullsBuyerFunds() public {
        bytes32 offerId = _postSellOffer();
        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        _acceptSellOffer(offerId);

        assertEq(paymentToken.balanceOf(buyer), buyerBefore - CONSIDERATION, "buyer funds pulled");
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds in escrow");
    }

    function test_Secondary_AcceptOffer_Sell_UpdatesOfferFillState() public {
        bytes32 offerId = _postSellOffer();
        _acceptSellOffer(offerId);

        Offer memory offer = dm.getOffer(offerId);
        assertEq(offer.unitsAccepted, UNITS);
        assertEq(uint8(offer.status), uint8(OfferStatus.FULLY_ACCEPTED));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // acceptOffer — buy offer
    // ─────────────────────────────────────────────────────────────────────────

    function test_Secondary_AcceptBuyOffer_CreatesSettlementEscrowAlreadyPaid() public {
        bytes32 offerId = _postBuyOffer();
        bytes32 settlementId = _acceptBuyOffer(offerId);

        assertEq(
            uint8(dm.getEscrowDetails(settlementId).status),
            uint8(EscrowStatus.PAID),
            "settlement escrow should open PAID (migrated from holding)"
        );
    }

    function test_Secondary_AcceptBuyOffer_MigratesFundsFromHoldingEscrow() public {
        bytes32 offerId = _postBuyOffer();

        // Funds are in holding escrow (offerId) before acceptance
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION);

        bytes32 settlementId = _acceptBuyOffer(offerId);

        // Funds remain in DealManager but are now attributed to settlement escrow
        assertEq(paymentToken.balanceOf(address(dm)), CONSIDERATION, "funds still in DealManager");
        assertEq(
            dm.getEscrowDetails(settlementId).buyerAssets[0].amount,
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

    function test_Secondary_VoidExpiredDeal_ReleasesUnitReservation() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        bytes32 resId = se.unitReservationId;

        uint256 expiry = dm.getEscrowDetails(settlementId).expiry;
        vm.warp(expiry + 1);

        vm.prank(keeper);
        dm.voidExpiredDeal(settlementId, keeper, "");

        assertFalse(certPrinter.reservationActive(resId), "reservation should be released on void");
        assertTrue(certPrinter.reservationReleased(resId));
    }

    function test_Secondary_VoidExpiredDeal_RefundsBuyer() public {
        bytes32 offerId = _postSellOffer();
        bytes32 settlementId = _acceptSellOffer(offerId);

        uint256 buyerBefore = paymentToken.balanceOf(buyer);

        uint256 expiry = dm.getEscrowDetails(settlementId).expiry;
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
    // Min trade threshold
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
            offerAgreementId: offerId,
            units: UNITS - 1, // partial fill, below min
            buyer: buyer,
            buyerName: "Bob",
            fullSale: false,
            buyerHostingMode: 0,
            adminMultisig: address(0),
            sellerCertPrinter: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: "",
            openEndorsementSig: "",
            closingConditions: new address[](0),
            thresholdConditions: new address[](0)
        });

        vm.prank(buyer);
        vm.expectRevert(DealManager.PartialFillBelowMinThreshold.selector);
        dm.acceptOffer(p);
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
