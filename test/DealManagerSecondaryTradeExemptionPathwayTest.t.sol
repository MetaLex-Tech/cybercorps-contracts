// SPDX-License-Identifier: AGPL-3.0-only
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
import {CertificateDetails, ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {BaseSecondaryTradingCondition} from "../src/libs/conditions/BaseSecondaryTradingCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {CategoryKind, Credential, CredentialCategory} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {FundInterestData} from "../src/storage/extensions/FundInterestExtension.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    Offer,
    OfferSide,
    PostOfferParams,
    SecondaryEscrow,
    SecondaryEscrowStatus
} from "../src/storage/SecondaryTradeStorage.sol";
// Real secondary-trading conditions under test.
import {KYCAMLCondition} from "../src/libs/conditions/secondary/KYCAMLCondition.sol";
import {TaxInfoCondition} from "../src/libs/conditions/secondary/TaxInfoCondition.sol";
import {HolderCapCondition} from "../src/libs/conditions/secondary/HolderCapCondition.sol";
import {ERISACondition} from "../src/libs/conditions/secondary/ERISACondition.sol";
import {USStateOfResidenceCondition} from "../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {LegionSoulboundCondition} from "../src/libs/conditions/secondary/LegionSoulboundCondition.sol";
import {HoldingPeriodCondition} from "../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {LexChexBadgeKindCondition} from "../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {RegSDistributionComplianceCondition} from "../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {MockUriBuilderForIM} from "./IssuanceManagerTest.t.sol";
import {Test} from "forge-std/Test.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

contract SecERC20Mock is ERC20 {
    constructor() ERC20("Payment Token", "PAY") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// cyberCORP fixture for the real IssuanceManager/DealManager that ALSO exposes AUTH(), which the
// per-SPV condition setters (RegS.setRegSConfig, USState.setStateBlocked) resolve via
// IBorgAuthProvider(spv).AUTH(). offer.spvAddress == this corp.
contract MockCorpWithAuth {
    address public AUTH;

    constructor(address auth_) {
        AUTH = auth_;
    }

    function cyberCORPName() external pure returns (string memory) { return "TestCorp"; }
    function cyberCORPType() external pure returns (string memory) { return "C-Corp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function cyberCORPContactDetails() external pure returns (string memory) { return "test@corp.test"; }
    function dealManager() external pure returns (address) { return address(0); }
    function roundManager() external pure returns (address) { return address(0); }
}

// Pass-through stand-in for a spec condition that is not implemented yet (Rule144Disclosure,
// Section4a7Disclosure, LegalOpinion, AgreementSigned, GlobalKill, TimeSettlement). Always passes,
// so it represents the pathway's canonical condition-set shape without gating the happy path.
contract PassSecCondition is BaseSecondaryTradingCondition {
    function checkCondition(IDealManager, bytes4, bytes32, bytes32) external pure override returns (bool) {
        return true;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test contract
// ─────────────────────────────────────────────────────────────────────────────

contract DealManagerSecondaryTradeExemptionPathwayTest is Test {
    bytes32 constant corpSalt = keccak256("DealManagerSecondaryTradeExemptionPathwayTest.corp");
    bytes32 constant imSalt = keccak256("DealManagerSecondaryTradeExemptionPathwayTest.im");

    // Single template carrying ONE party field, so the buyer's ERISA attestation can be recorded as a
    // signer value on the settlement agreement (ERISACondition reads registry.getSignerValues).
    bytes32 public constant TEMPLATE_ID = bytes32(0);
    string public constant TEMPLATE_URI = "ipfs://exemption-template";
    string public constant ERISA_ATTESTATION = "ERISA:no-plan-assets";

    // Category ids for the credential layer.
    bytes32 constant CAT_KYC = keccak256("cat.kyc");
    bytes32 constant CAT_ACCREDITED = keccak256("cat.accredited");
    bytes32 constant CAT_QIB = keccak256("cat.qib");
    bytes32 constant CAT_NONUS = keccak256("cat.nonus");
    bytes32 constant CAT_LEGION = keccak256("cat.legion");

    bytes2 constant CA = "CA";

    uint256 public constant UNITS = 100;
    uint256 public constant CONSIDERATION = 10 ether;
    uint64 public constant HOLD = 365 days;

    address public owner;
    uint256 public ownerKey;
    address public seller;
    uint256 public sellerKey;
    address public keeper;

    SecERC20Mock public paymentToken;
    BorgAuth public auth;
    MockCorpWithAuth public corp;
    IssuanceManager public im;
    ICyberCertPrinter public certPrinter;
    CyberAgreementRegistry public registry;
    DealManagerFactory public dmFactory;
    DealManager public dm;
    LeXcheXBadge public badge;

    // Real conditions.
    KYCAMLCondition public kyc;
    TaxInfoCondition public taxInfo;
    HolderCapCondition public holderCap;
    ERISACondition public erisa;
    USStateOfResidenceCondition public usState;
    LegionSoulboundCondition public legion;
    HoldingPeriodCondition public holdingPeriod;
    LexChexBadgeKindCondition public accredited;
    LexChexBadgeKindCondition public qib;
    LexChexBadgeKindCondition public nonUsPerson;
    RegSDistributionComplianceCondition public regS;

    uint256 public sellerTokenId;

    function setUp() public {
        // Warp forward so the seller cert's acquisitionDate can sit comfortably in the past.
        vm.warp(500 days);

        (owner, ownerKey) = makeAddrAndKey("owner");
        (seller, sellerKey) = makeAddrAndKey("seller");
        keeper = makeAddr("keeper");

        paymentToken = new SecERC20Mock();
        auth = new BorgAuth(owner);
        corp = new MockCorpWithAuth(address(auth));

        // Real IssuanceManager + CyberCertPrinter via the factory beacon stack.
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

        // Real CyberAgreementRegistry with a one-party-field template (for the ERISA attestation).
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        string[] memory partyFields = _partyFields();
        vm.prank(owner);
        registry.createTemplate(TEMPLATE_ID, "Secondary", TEMPLATE_URI, new string[](0), partyFields);

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
        vm.prank(owner);
        auth.updateRole(address(dm), 99);

        _deployBadgeAndCategories();
        _deployConditions();
        _wireConditions();

        // Reg S per-SPV config: Category 3, one-year distribution compliance period.
        vm.prank(owner);
        regS.setRegSConfig(address(corp), 3, HOLD);

        // Seller: KYC badge + a Ledger Entry Token whose acquisitionDate is > HOLD in the past.
        _mintCred(seller, CAT_KYC, "US", CA);
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
        sellerTokenId = im.createCertAndAssign(address(certPrinter), seller, _sellerCertDetails());
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Happy-path tests — one full trade per exemption pathway
    // ─────────────────────────────────────────────────────────────────────────

    function test_Rule144_HappyPath() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.rule144");
        _commonBuyerSetup(buyer, "US", CA);
        // No buyer-side pathway credential: Rule 144 gates on the seller's elapsed holding period.
        _runHappyPath(ExemptionPathway.RULE_144, buyer, buyerKey, uint256(keccak256("rule144")));
    }

    function test_Section4a7_HappyPath() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.4a7");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_ACCREDITED, "US", bytes2(0));
        _runHappyPath(ExemptionPathway.SECTION_4A7, buyer, buyerKey, uint256(keccak256("4a7")));
    }

    function test_Section4a1Half_HappyPath() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.4a1half");
        _commonBuyerSetup(buyer, "US", CA);
        // Sophisticated-but-not-accredited: KYC + Legion only; the pathway gate is the GP sign-off mock.
        _runHappyPath(ExemptionPathway.SECTION_4A1HALF, buyer, buyerKey, uint256(keccak256("4a1half")));
    }

    function test_Rule144A_HappyPath() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.144a");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_QIB, "US", bytes2(0));
        _runHappyPath(ExemptionPathway.RULE_144A, buyer, buyerKey, uint256(keccak256("144a")));
    }

    function test_RegulationS_HappyPath() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.regs");
        // Non-U.S. person: jurisdiction KY, no usState (badge forbids usState for non-US holders).
        _commonBuyerSetup(buyer, "KY", bytes2(0));
        _mintCred(buyer, CAT_NONUS, "KY", bytes2(0));
        _runHappyPath(ExemptionPathway.REGULATION_S, buyer, buyerKey, uint256(keccak256("regs")));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle helper
    // ─────────────────────────────────────────────────────────────────────────

    function _runHappyPath(ExemptionPathway pathway, address buyer, uint256 buyerKey, uint256 salt) internal {
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        bytes32 offerId = _postSellOffer(pathway, salt);
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        SecondaryEscrow memory se = dm.getSecondaryEscrow(settlementId);
        assertEq(uint8(se.status), uint8(SecondaryEscrowStatus.FINALIZED), "escrow FINALIZED");
        assertGt(paymentToken.balanceOf(seller) - sellerBalanceBefore, 0, "seller received payment");
        assertGt(certPrinter.balanceOfLegalOwner(buyer), 0, "buyer holds a new Ledger Entry Token");
        assertEq(_consumed(sellerTokenId), UNITS, "seller units fully consumed");
    }

    function _postSellOffer(ExemptionPathway pathway, uint256 salt) internal returns (bytes32 offerId) {
        PostOfferParams memory p = PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(certPrinter),
            tokenId: sellerTokenId,
            units: UNITS,
            paymentToken: address(paymentToken),
            consideration: CONSIDERATION,
            exemptionPathway: pathway,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: TEMPLATE_ID,
            salt: salt,
            globalValues: new string[](0),
            offerorPartyValues: _one(""),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
        vm.prank(seller);
        offerId = dm.postOffer(p);
    }

    function _acceptSellOffer(bytes32 offerId, address buyer, uint256 buyerKey)
        internal
        returns (bytes32 settlementId)
    {
        string[] memory pv = _one(ERISA_ATTESTATION);
        AcceptOfferParams memory a = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            buyerName: "Bob",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: pv,
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey, pv),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        settlementId = dm.acceptOffer(a);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Setup helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _deployBadgeAndCategories() internal {
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(
                    address(new LeXcheXBadge()),
                    abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))
                )
            )
        );
        _createCategory(CAT_KYC, CategoryKind.KYC_AML);
        _createCategory(CAT_ACCREDITED, CategoryKind.ACCREDITED_INVESTOR);
        _createCategory(CAT_QIB, CategoryKind.QIB);
        _createCategory(CAT_NONUS, CategoryKind.NON_US_PERSON);
        _createCategory(CAT_LEGION, CategoryKind.CUSTOM);
    }

    function _deployConditions() internal {
        kyc = KYCAMLCondition(
            _proxy(address(new KYCAMLCondition()), abi.encodeCall(KYCAMLCondition.initialize, (address(auth), address(badge))))
        );
        taxInfo = TaxInfoCondition(
            _proxy(address(new TaxInfoCondition()), abi.encodeCall(TaxInfoCondition.initialize, (address(auth))))
        );
        holderCap = HolderCapCondition(
            _proxy(
                address(new HolderCapCondition()),
                abi.encodeCall(
                    HolderCapCondition.initialize,
                    (address(auth), address(badge), HolderCapCondition.IcaException.SECTION_3C1, uint256(100), false, false)
                )
            )
        );
        erisa = ERISACondition(
            _proxy(
                address(new ERISACondition()),
                abi.encodeCall(ERISACondition.initialize, (address(auth), address(registry), ERISA_ATTESTATION))
            )
        );
        usState = USStateOfResidenceCondition(
            _proxy(
                address(new USStateOfResidenceCondition()),
                abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(badge)))
            )
        );
        legion = LegionSoulboundCondition(
            _proxy(
                address(new LegionSoulboundCondition()),
                abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(badge), CAT_LEGION, false))
            )
        );
        holdingPeriod = HoldingPeriodCondition(
            _proxy(
                address(new HoldingPeriodCondition()),
                abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), uint256(HOLD)))
            )
        );
        accredited = _deployKindCondition(CategoryKind.ACCREDITED_INVESTOR);
        qib = _deployKindCondition(CategoryKind.QIB);
        nonUsPerson = _deployKindCondition(CategoryKind.NON_US_PERSON);
        regS = RegSDistributionComplianceCondition(
            _proxy(
                address(new RegSDistributionComplianceCondition()),
                abi.encodeCall(RegSDistributionComplianceCondition.initialize, (address(auth)))
            )
        );
    }

    function _deployKindCondition(CategoryKind kind) internal returns (LexChexBadgeKindCondition) {
        return LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(LexChexBadgeKindCondition.initialize, (address(auth), address(badge), kind, "", false))
            )
        );
    }

    function _wireConditions() internal {
        // SPV-layer (every pathway).
        _addSpv(address(kyc));
        _addSpv(address(taxInfo));
        _addSpv(address(holderCap));
        _addSpv(address(erisa));
        _addSpv(address(usState));
        _addSpv(address(legion));
        _addSpv(address(new PassSecCondition())); // AgreementSignedCondition (mock)

        // Pathway-layer.
        _addPathway(ExemptionPathway.RULE_144, address(holdingPeriod));
        _addPathway(ExemptionPathway.RULE_144, address(new PassSecCondition())); // Rule144Disclosure (mock)
        _addPathway(ExemptionPathway.SECTION_4A7, address(accredited));
        _addPathway(ExemptionPathway.SECTION_4A7, address(new PassSecCondition())); // Section4a7Disclosure (mock)
        _addPathway(ExemptionPathway.SECTION_4A1HALF, address(new PassSecCondition())); // LegalOpinion/GP sign-off (mock)
        _addPathway(ExemptionPathway.RULE_144A, address(qib));
        _addPathway(ExemptionPathway.REGULATION_S, address(nonUsPerson));
        _addPathway(ExemptionPathway.REGULATION_S, address(regS));

        // Closing set (all pathways). Deploy the mock BEFORE pranking: a `new` in the argument would
        // otherwise consume the prank (CREATE runs first), so the add would execute as the test contract.
        _addClosing(address(new PassSecCondition())); // GlobalKill (mock)
        _addClosing(address(new PassSecCondition())); // TimeSettlement (mock)
    }

    function _addClosing(address condition) internal {
        vm.prank(owner);
        dm.addClosingCondition(condition);
    }

    function _commonBuyerSetup(address buyer, string memory jurisdiction, bytes2 state) internal {
        _mintCred(buyer, CAT_KYC, jurisdiction, state);
        _mintCred(buyer, CAT_LEGION, jurisdiction, state);
        vm.prank(owner);
        taxInfo.setTaxForm(buyer, TaxInfoCondition.TaxFormType.W9, keccak256("form"));

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    function _createCategory(bytes32 id, CategoryKind kind) internal {
        CredentialCategory memory c = CredentialCategory({
            name: "cat",
            description: "",
            kind: kind,
            defaultValidityDuration: 3650 days,
            requiresUsState: false,
            requiresBeneficialOwnerCount: false,
            requiresEvidenceHash: false,
            burnAuth: IERC5484.BurnAuth.OwnerOnly,
            scope: address(0),
            active: true,
            exists: true
        });
        vm.prank(owner);
        badge.createCategory(id, c);
    }

    function _mintCred(address to, bytes32 categoryId, string memory jurisdiction, bytes2 state) internal {
        Credential memory cred = Credential({
            categoryId: categoryId,
            investorName: "Inv",
            investorType: "Individual",
            investorJurisdiction: jurisdiction,
            usState: state,
            beneficialOwnerCount: 0,
            issuanceDate: 0,
            expiryDate: 0,
            voided: "",
            agreementId: bytes32(0),
            evidenceHash: bytes32(0),
            extensionData: ""
        });
        vm.prank(owner);
        badge.mint(to, categoryId, cred);
    }

    function _sellerCertDetails() internal view returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: UNITS,
            legalDetails: "",
            extensionData: abi.encode(
                FundInterestData({
                    acquisitionDate: uint64(block.timestamp - 400 days),
                    tackedFromAcquisitionDate: 0,
                    customProvisions: ""
                })
            )
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Small utilities
    // ─────────────────────────────────────────────────────────────────────────

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function _addSpv(address condition) internal {
        vm.prank(owner);
        dm.addSpvThresholdCondition(condition);
    }

    function _addPathway(ExemptionPathway pathway, address condition) internal {
        vm.prank(owner);
        dm.addPathwayThresholdCondition(pathway, condition);
    }

    function _partyFields() internal pure returns (string[] memory f) {
        f = new string[](1);
        f[0] = "erisaAttestation";
    }

    function _one(string memory v) internal pure returns (string[] memory a) {
        a = new string[](1);
        a[0] = v;
    }

    /// @dev Cumulative units consumed from the seller cert: a full sale voids it, a partial decrements.
    function _consumed(uint256 tokenId) internal view returns (uint256) {
        if (certPrinter.isVoided(tokenId)) return UNITS;
        return UNITS - certPrinter.getCertificateDetails(tokenId).unitsRepresented;
    }

    /// @dev Recomputes the next settlement agreement id for an offer and returns the acceptor's EIP-712
    /// signature over it. partyValues must match what acceptOffer submits (the ERISA attestation).
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
        bytes32 settlementId = keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties));
        return _agreementSig(settlementId, partyValues, key);
    }

    /// @dev EIP-712 agreement signature over a settlement id, using the template's party fields.
    function _agreementSig(bytes32 settlementId, string[] memory partyValues, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            settlementId,
            TEMPLATE_URI,
            new string[](0), // globalFields (template has none)
            _partyFields(), // partyFields (must match the template)
            new string[](0), // globalValues
            partyValues,
            key
        );
    }
}
