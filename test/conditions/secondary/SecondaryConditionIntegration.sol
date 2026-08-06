// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../../../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../../../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../../../src/CyberCorpConstants.sol";
import {CyberScrip} from "../../../src/CyberScrip.sol";
import {DealManager} from "../../../src/DealManager.sol";
import {DealManagerFactory} from "../../../src/DealManagerFactory.sol";
import {IssuanceManager} from "../../../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../../../src/IssuanceManagerFactory.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {LeXcheXBadge} from "../../../src/creds/lexchexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {CertificateDetails, ILedgerEntryToken} from "../../../src/interfaces/ILedgerEntryToken.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {BorgAuth} from "../../../src/libs/auth.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    Offer,
    OfferSide,
    PostOfferParams
} from "../../../src/storage/SecondaryTradeStorage.sol";
import {CyberAgreementUtils} from "../../libs/CyberAgreementUtils.sol";
import {MockUriBuilderForIM} from "../../IssuanceManagerTest.t.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal SPV/CyberCorp fixture. It exposes AUTH() (per-SPV secondary conditions gate their
/// configuration on the SPV's own BorgAuth via offer.spvAddress) plus the CyberCorp getters the real
/// IssuanceManager reads. offer.spvAddress resolves to this address in the real DealManager.
contract SpvFixture {
    address public AUTH;
    address public dealManager;
    address public roundManager;

    constructor(address auth_) {
        AUTH = auth_;
    }

    function setManagers(address dm_, address rm_) external {
        dealManager = dm_;
        roundManager = rm_;
    }

    function cyberCORPName() external pure returns (string memory) { return "TestCorp"; }
    function cyberCORPType() external pure returns (string memory) { return "C-Corp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function cyberCORPContactDetails() external pure returns (string memory) { return "test@corp.test"; }
}

/// @title  SecondaryConditionIntegrationBase - shared real-stack harness for secondary-trading condition tests
/// @author MetaLeX Labs, Inc.
/// @notice Replaces the mock base with real contracts: IssuanceManager + LedgerEntryToken (via the beacon
/// factory), CyberAgreementRegistry, DealManager (via its factory), and LeXcheXBadge — all under one BorgAuth
/// whose owner/admin is the test contract, so owner-gated calls run unpranked. Conditions read a genuine
/// Offer/SecondaryEscrow: `_postSell` posts a real sell offer; `_acceptSell` accepts it (materializing the
/// escrow with counterparty = buyer, no transfer — that happens at finalize). Payment/badge/cert state is
/// all real; credentials are minted, not mocked.
abstract contract SecondaryConditionIntegrationBase is Test {
    BorgAuth internal auth;
    IssuanceManager internal im;
    ILedgerEntryToken internal printer;
    CyberAgreementRegistry internal registry;
    SpvFixture internal corp;
    DealManager internal dm;
    LeXcheXBadge internal badge;
    MockERC20 internal paymentToken;

    address internal seller;
    uint256 internal sellerKey;
    address internal buyer;
    uint256 internal buyerKey;
    address internal stranger = makeAddr("stranger");

    uint256 internal sellerTokenId;

    bytes32 internal constant TEMPLATE_ID = bytes32(0);
    string internal constant TEMPLATE_URI = "ipfs://secondary-template";
    uint256 internal constant UNITS = 100;
    uint256 internal constant CONSIDERATION = 10 ether;

    // ── Agreement-template shape (override to opt into party fields) ───────────
    // The default settlement template has no party fields, so cyberAgreement stays field-less for every
    // condition. A condition that needs a per-party value on the settlement (e.g. Section4a7's disclosure
    // acknowledgment) overrides `_partyFields` (and its own template id/uri); the base then registers that
    // template and every party-value array / acceptor signature is sized and hashed to match automatically.
    function _offerTemplateId() internal view virtual returns (bytes32) {
        return TEMPLATE_ID;
    }

    function _offerTemplateUri() internal view virtual returns (string memory) {
        return TEMPLATE_URI;
    }

    function _partyFields() internal view virtual returns (string[] memory) {
        return new string[](0);
    }

    /// @dev An all-empty party-values array sized to the current template's party fields.
    function _emptyPartyValues() internal view returns (string[] memory) {
        return new string[](_partyFields().length);
    }

    function _setUpIntegration() internal {
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey) = makeAddrAndKey("buyer");

        auth = new BorgAuth(address(this));
        corp = new SpvFixture(address(auth));
        paymentToken = new MockERC20("Payment Token", "PAY", 9);

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        new IssuanceManager(),
                        new LedgerEntryToken(),
                        new CyberScrip()
                    )
                )
            )
        );
        im = IssuanceManager(imFactory.deployIssuanceManager(keccak256("SecondaryConditionIntegration.im")));
        im.initialize(address(auth), address(corp), address(new MockUriBuilderForIM()), address(imFactory));

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        // Register the settlement template with whatever party fields the (possibly overridden) shape declares.
        registry.createTemplate(_offerTemplateId(), "Secondary", _offerTemplateUri(), new string[](0), _partyFields());

        DealManagerFactory dmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new DealManagerFactory()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector, address(auth), address(new DealManager())
                    )
                )
            )
        );
        dm = DealManager(dmFactory.deployDealManager(keccak256("SecondaryConditionIntegration.corp")));
        dm.initialize(address(auth), address(corp), address(registry), address(im), address(dmFactory));
        corp.setManagers(address(dm), address(0));
        auth.updateRole(address(dm), 99); // role real onboarding grants the DM for IM/printer reservations
        dm.setPathwayThresholdConditions(ExemptionPathway.RULE_144, new address[](0), true);

        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(
                    address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))
                )
            )
        );

        printer = ILedgerEntryToken(
            im.createCertPrinter(
                new string[](0), "Cert", "CERT", "ipfs://cert",
                SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0), bytes("")
            )
        );
        LedgerEntryToken(address(printer)).setLookThroughBadge(address(badge));
        sellerTokenId = im.createCertAndAssign(address(printer), seller, _certDetails(UNITS));

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    // ── Cert / badge helpers ─────────────────────────────────────────────────

    function _certDetails(uint256 units) internal pure returns (CertificateDetails memory) {
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

    /// @dev Mints an immutable credential asserting `asserts` (the K_* fact-key mask from ILexChexBadge);
    /// stamps a far expiry if the caller left it unset.
    function _mintCred(address to, uint256 asserts, Credential memory c) internal returns (uint256) {
        c.asserts = asserts;
        if (c.expiryDate == 0) c.expiryDate = uint64(block.timestamp + 3650 days);
        return badge.mint(to, c);
    }

    /// @dev Mints a live cert on the real printer to `owner` (used to seed a legal holder / look-through weight).
    function _makeHolder(address owner) internal returns (uint256) {
        return im.createCertAndAssign(address(printer), owner, _certDetails(1));
    }

    // ── Real offer / settlement helpers ──────────────────────────────────────

    function _sellOfferParams() internal view returns (PostOfferParams memory p) {
        p = PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(printer),
            tokenId: sellerTokenId,
            units: UNITS,
            paymentToken: address(paymentToken),
            consideration: CONSIDERATION,
            exemptionPathway: ExemptionPathway.NONE, // unpinned; the buyer elects at acceptance
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: _offerTemplateId(),
            salt: uint256(keccak256("secondaryConditionSellOffer")),
            globalValues: new string[](0),
            offerorPartyValues: _emptyPartyValues(),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
    }

    function _postSell() internal returns (bytes32 offerId) {
        vm.prank(seller);
        offerId = dm.postOffer(_sellOfferParams());
    }

    /// @dev Posts a sell offer against an explicit cert printer + tokenId (e.g. a printer configured with a
    /// FundInterest extension), rather than the default printer/sellerTokenId.
    function _postSellOn(address certPrinter, uint256 tokenId) internal returns (bytes32 offerId) {
        PostOfferParams memory p = _sellOfferParams();
        p.certPrinter = certPrinter;
        p.tokenId = tokenId;
        p.salt = uint256(keccak256(abi.encode(certPrinter, tokenId)));
        vm.prank(seller);
        offerId = dm.postOffer(p);
    }

    /// @dev Posts a real BUY offer (offeror = buyer, who funds the escrow up front); pinned to RULE_144.
    function _postBuy() internal returns (bytes32 offerId) {
        PostOfferParams memory p = _sellOfferParams();
        p.side = OfferSide.BUY;
        p.tokenId = 0;
        p.exemptionPathway = ExemptionPathway.RULE_144;
        p.salt = uint256(keccak256("secondaryConditionBuyOffer"));
        p.buyerName = "Buyer";
        vm.prank(buyer);
        offerId = dm.postOffer(p);
    }

    /// @dev Acceptor's EIP-712 signature over the pending settlement id (verified by the registry in acceptOffer).
    function _acceptorSig(bytes32 offerId, address acceptor, uint256 key, string[] memory partyValues)
        internal
        view
        returns (bytes memory)
    {
        Offer memory o = dm.getOffer(offerId);
        bytes32 settlementSalt = keccak256(abi.encodePacked(o.salt, o.settlementAgreementIds.length));
        address[] memory parties = new address[](2);
        parties[0] = o.offeror;
        parties[1] = acceptor;
        bytes32 settlementId =
            keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties, bytes32(0), address(dm)));
        return CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            settlementId, _offerTemplateUri(), new string[](0), _partyFields(), new string[](0), partyValues, key
        );
    }

    function _acceptSell(bytes32 offerId) internal returns (bytes32 settlementId) {
        return _acceptSell(offerId, _emptyPartyValues());
    }

    /// @dev Buyer accepts the sell offer electing RULE_144, optionally carrying acceptor party values (e.g. a
    /// disclosure acknowledgment). Creates the escrow (counterparty = buyer) + pulls payment; no transfer.
    function _acceptSell(bytes32 offerId, string[] memory acceptorPartyValues) internal returns (bytes32 settlementId) {
        AcceptOfferParams memory a = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            exemptionPathway: ExemptionPathway.RULE_144,
            buyerName: "Bob",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: acceptorPartyValues,
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey, acceptorPartyValues),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementId = dm.acceptOffer(a);
    }

    function _postAndAcceptSell() internal returns (bytes32 offerId, bytes32 settlementId) {
        offerId = _postSell();
        settlementId = _acceptSell(offerId);
    }

    /// @dev Mints a fresh seller cert (for a second, independent settlement on a distinct tokenId).
    function _newSellerCert() internal returns (uint256) {
        return im.createCertAndAssign(address(printer), seller, _certDetails(UNITS));
    }

    /// @dev Posts + accepts a sell offer for an explicit seller tokenId and salt seed (a second lot needs a
    /// distinct cert and salt from the default offer).
    function _postAndAcceptSellToken(uint256 tokenId, uint256 saltSeed)
        internal
        returns (bytes32 offerId, bytes32 settlementId)
    {
        PostOfferParams memory p = _sellOfferParams();
        p.tokenId = tokenId;
        p.salt = saltSeed;
        vm.prank(seller);
        offerId = dm.postOffer(p);
        settlementId = _acceptSell(offerId);
    }

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function _one(string memory v) internal pure returns (string[] memory a) {
        a = new string[](1);
        a[0] = v;
    }
}
