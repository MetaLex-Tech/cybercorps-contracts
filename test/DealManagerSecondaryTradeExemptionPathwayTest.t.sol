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
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {
    CategoryKind,
    Credential,
    CredentialCategory,
    ATTR_INVESTOR_JURISDICTION,
    ATTR_US_STATE
} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {FundInterestData} from "../src/storage/extensions/FundInterestExtension.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    ISecondaryTradeStorage,
    Offer,
    OfferSide,
    PostOfferParams,
    SecondaryEscrow,
    SecondaryEscrowStatus
} from "../src/storage/SecondaryTradeStorage.sol";
// Real secondary-trading conditions under test.
import {EligibilityCondition} from "../src/libs/conditions/secondary/EligibilityCondition.sol";
import {HolderCapCondition} from "../src/libs/conditions/secondary/HolderCapCondition.sol";
import {USStateOfResidenceCondition} from "../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {LegionSoulboundCondition} from "../src/libs/conditions/secondary/LegionSoulboundCondition.sol";
import {HoldingPeriodCondition} from "../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {LexChexBadgeKindCondition} from "../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {RegSDistributionComplianceCondition} from "../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {Rule144DisclosureCondition} from "../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {Section4a7DisclosureCondition} from "../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {LegalOpinionCondition} from "../src/libs/conditions/secondary/LegalOpinionCondition.sol";
import {AgreementSignedCondition} from "../src/libs/conditions/secondary/AgreementSignedCondition.sol";
import {KillSwitchCondition} from "../src/libs/conditions/secondary/KillSwitchCondition.sol";
import {TimeSettlementPeriodCondition} from "../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
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

// ─────────────────────────────────────────────────────────────────────────────
// Test contract
// ─────────────────────────────────────────────────────────────────────────────

contract DealManagerSecondaryTradeExemptionPathwayTest is Test {
    bytes32 constant corpSalt = keccak256("DealManagerSecondaryTradeExemptionPathwayTest.corp");
    bytes32 constant imSalt = keccak256("DealManagerSecondaryTradeExemptionPathwayTest.im");

    // Single template carrying the buyer's §4(a)(7) acknowledgment-of-receipt, recorded as a signer
    // value on the settlement agreement (Section4a7DisclosureCondition reads registry.getSignerValues).
    bytes32 public constant TEMPLATE_ID = bytes32(0);
    string public constant TEMPLATE_URI = "ipfs://exemption-template";
    string public constant SECTION4A7_ACK = "4a7:information-package-received";
    string public constant DISCLOSURE_URI = "ipfs://disclosure-package";
    // Freshness policy for both disclosure conditions (Rule 144(c)(2) practice: 16 months)
    uint256 public constant DISCLOSURE_MAX_AGE = 480 days;

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
    EligibilityCondition public eligibility;
    HolderCapCondition public holderCap;
    USStateOfResidenceCondition public usState;
    LegionSoulboundCondition public legion;
    HoldingPeriodCondition public holdingPeriod;
    LexChexBadgeKindCondition public accredited;
    LexChexBadgeKindCondition public qib;
    LexChexBadgeKindCondition public nonUsPerson;
    RegSDistributionComplianceCondition public regS;
    Rule144DisclosureCondition public rule144Disclosure;
    Section4a7DisclosureCondition public section4a7Disclosure;
    LegalOpinionCondition public legalOpinion;
    AgreementSignedCondition public agreementSigned;
    KillSwitchCondition public killSwitch;
    TimeSettlementPeriodCondition public timeSettlement;

    address public metalexKillAdmin;
    address public legionKillAdmin;

    uint256 public sellerTokenId;

    function setUp() public {
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

        // Real CyberAgreementRegistry with a one-party-field template (for the §4(a)(7) ack).
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

        // Seller Ledger Entry Token, minted now: its base acquisitionTimestamp is stamped at mint (§12B.3),
        // so we mint first and then warp forward to age the lot past the holding / Reg S compliance period —
        // the on-chain-faithful way to represent a seasoned position (no fakeable historical date).
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

        // Age the seller lot past HOLD, then issue "now" state (seller KYC badge, disclosure packages) so
        // those are current as of trade time.
        vm.warp(500 days);
        _mintCred(seller, CAT_KYC, "US", CA);
        vm.startPrank(owner);
        eligibility.setClearance(seller, true);
        rule144Disclosure.setDisclosurePackage(address(corp), DISCLOSURE_URI, uint64(block.timestamp));
        section4a7Disclosure.setDisclosurePackage(address(corp), DISCLOSURE_URI, uint64(block.timestamp));
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
        // Sophisticated-but-not-accredited: KYC + Legion only; the pathway gate is the GP's recorded
        // compliance sign-off (LegalOpinionCondition, GP_SIGNOFF-or-opinion default mechanism).
        // Sign-off is per-deal: silent at posting, then the GP pre-approves the offer (covering every
        // settlement of it) before any acceptance.
        bytes32 offerId = _postSellOffer(ExemptionPathway.SECTION_4A1HALF, uint256(keccak256("4a1half")));
        vm.prank(owner);
        legalOpinion.recordGPSignOff(address(dm), offerId);
        _acceptAndFinalize(offerId, buyer, buyerKey);
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
    // Closing-condition behavior (the two platform-wide closing conditions)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice A raised kill flag suspends finalization of an in-flight settlement; the two-call
    /// lower (one admin proposes, the other confirms) restores it.
    function test_KillSwitch_BlocksFinalize_UntilLowered() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.kill");
        _commonBuyerSetup(buyer, "US", CA);

        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144, uint256(keccak256("kill")));
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);
        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);

        // Either admin can raise unilaterally — after acceptance, mid-deal.
        vm.prank(legionKillAdmin);
        killSwitch.raiseKill();

        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(killSwitch))
        );
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        // Lowering takes both admins: the proposer alone cannot confirm.
        vm.prank(legionKillAdmin);
        killSwitch.proposeLower();
        vm.expectRevert(KillSwitchCondition.ProposerCannotConfirm.selector);
        vm.prank(legionKillAdmin);
        killSwitch.confirmLower();
        vm.prank(metalexKillAdmin);
        killSwitch.confirmLower();

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "escrow FINALIZED after kill lowered"
        );
    }

    /// @notice A per-settlement kill blocks that single agreement's finalize end-to-end, and the
    /// two-admin lower clears it. (Targeted isolation across settlements is covered by the unit suite.)
    function test_SettlementKill_BlocksFinalize_UntilLowered() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.settkill");
        _commonBuyerSetup(buyer, "US", CA);

        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144, uint256(keccak256("settkill")));
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);
        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);

        // Either admin can raise a single settlement's kill unilaterally, mid-deal.
        vm.prank(legionKillAdmin);
        killSwitch.raiseSettlementKill(settlementId);

        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(killSwitch))
        );
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        // Lowering takes both admins: the proposer alone cannot confirm.
        vm.prank(legionKillAdmin);
        killSwitch.proposeSettlementLower(settlementId);
        vm.expectRevert(KillSwitchCondition.ProposerCannotConfirm.selector);
        vm.prank(legionKillAdmin);
        killSwitch.confirmSettlementLower(settlementId);
        vm.prank(metalexKillAdmin);
        killSwitch.confirmSettlementLower(settlementId);

        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "killed settlement finalizes after its kill lowered"
        );
    }

    /// @notice Finalization before the 24h minimum settlement period fails; after the window it passes.
    function test_TimeSettlement_BlocksEarlyFinalize() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.timing");
        _commonBuyerSetup(buyer, "US", CA);

        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144, uint256(keccak256("timing")));
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);

        assertEq(
            timeSettlement.finalizableAt(IDealManager(address(dm)), settlementId),
            block.timestamp + timeSettlement.DEFAULT_DELAY(),
            "finalizableAt = acceptance + 24h"
        );

        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(timeSettlement))
        );
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "escrow FINALIZED after settlement period"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Buyer-elected pathway on an unpinned offer
    // ─────────────────────────────────────────────────────────────────────────

    // One unpinned offer, two buyers, two exemptions: each lot pulls in only its own pathway's Layer 1
    // conditions and settles independently.
    function test_UnpinnedOffer_BuyersElectDifferentPathways() public {
        (address qibBuyer, uint256 qibKey) = makeAddrAndKey("buyer.144a.split");
        _commonBuyerSetup(qibBuyer, "US", CA);
        _mintCred(qibBuyer, CAT_QIB, "US", bytes2(0));

        (address accreditedBuyer, uint256 accreditedKey) = makeAddrAndKey("buyer.4a7.split");
        _commonBuyerSetup(accreditedBuyer, "US", CA);
        _mintCred(accreditedBuyer, CAT_ACCREDITED, "US", bytes2(0));

        bytes32 offerId = _postSellOffer(ExemptionPathway.NONE, uint256(keccak256("unpinned.split")));
        assertEq(uint8(dm.getOffer(offerId).expectedExemptionPathway), uint8(ExemptionPathway.NONE), "offer left unpinned");

        AcceptOfferParams memory qibAccept =
            _sellAcceptParams(offerId, qibBuyer, qibKey, ExemptionPathway.RULE_144A, UNITS / 2);
        vm.prank(qibBuyer);
        bytes32 qibSettlement = dm.acceptOffer(qibAccept);

        AcceptOfferParams memory accreditedAccept =
            _sellAcceptParams(offerId, accreditedBuyer, accreditedKey, ExemptionPathway.SECTION_4A7, UNITS / 2);
        vm.prank(accreditedBuyer);
        bytes32 accreditedSettlement = dm.acceptOffer(accreditedAccept);

        SecondaryEscrow memory qibEscrow = dm.getSecondaryEscrow(qibSettlement);
        SecondaryEscrow memory accreditedEscrow = dm.getSecondaryEscrow(accreditedSettlement);
        assertEq(uint8(qibEscrow.exemptionPathway), uint8(ExemptionPathway.RULE_144A), "144A settlement pathway");
        assertEq(
            uint8(accreditedEscrow.exemptionPathway), uint8(ExemptionPathway.SECTION_4A7), "4(a)(7) settlement pathway"
        );
        // Each election resolves its own Layer 1 set, so one offer settled two lots under different regimes.
        assertTrue(
            keccak256(abi.encode(dm.getPathwayThresholdConditions(ExemptionPathway.RULE_144A)))
                != keccak256(abi.encode(dm.getPathwayThresholdConditions(ExemptionPathway.SECTION_4A7))),
            "elections resolve different Layer 1 sets"
        );

        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);
        vm.startPrank(keeper);
        dm.finalizeSecondaryTradeAgreement(qibSettlement);
        dm.finalizeSecondaryTradeAgreement(accreditedSettlement);
        vm.stopPrank();

        assertEq(
            uint8(dm.getSecondaryEscrow(qibSettlement).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "144A settlement FINALIZED"
        );
        assertEq(
            uint8(dm.getSecondaryEscrow(accreditedSettlement).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "4(a)(7) settlement FINALIZED"
        );
        assertGt(certPrinter.balanceOfLegalOwner(qibBuyer), 0, "144A buyer holds a Ledger Entry Token");
        assertGt(certPrinter.balanceOfLegalOwner(accreditedBuyer), 0, "4(a)(7) buyer holds a Ledger Entry Token");
        assertEq(_consumed(sellerTokenId), UNITS, "both lots consumed the seller's units");
    }

    // The election is a claim the buyer must back: an accredited (non-QIB) buyer electing 144A is stopped by
    // that pathway's own condition, which an unpinned offer would never have run at posting.
    function test_RevertIf_UnpinnedOffer_BuyerElectsPathwayTheyDoNotQualifyFor() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.notqib");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_ACCREDITED, "US", bytes2(0));

        bytes32 offerId = _postSellOffer(ExemptionPathway.NONE, uint256(keccak256("unpinned.notqib")));
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.RULE_144A, UNITS);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(qib)));
        dm.acceptOffer(a);
    }

    function test_RevertIf_UnpinnedOffer_BuyerElectsNoPathway() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.nopathway");
        _commonBuyerSetup(buyer, "US", CA);

        bytes32 offerId = _postSellOffer(ExemptionPathway.NONE, uint256(keccak256("unpinned.nopathway")));
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.NONE, UNITS);

        vm.prank(buyer);
        vm.expectRevert(ISecondaryTradeStorage.ExemptionPathwayRequired.selector);
        dm.acceptOffer(a);
    }

    // A seller who pins a pathway restricts the election to it, even for a buyer who qualifies elsewhere.
    function test_RevertIf_PinnedOffer_BuyerElectsAnotherPathway() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.qib.pinned");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_QIB, "US", bytes2(0));

        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144, uint256(keccak256("pinned.mismatch")));
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.RULE_144A, UNITS);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecondaryTradeStorage.ExemptionPathwayMismatch.selector,
                ExemptionPathway.RULE_144,
                ExemptionPathway.RULE_144A
            )
        );
        dm.acceptOffer(a);
    }

    /// @dev Asserts a settlement's recorded set is the SPV layer followed by `pathway`'s exemption layer.
    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle helper
    // ─────────────────────────────────────────────────────────────────────────

    function _runHappyPath(ExemptionPathway pathway, address buyer, uint256 buyerKey, uint256 salt) internal {
        bytes32 offerId = _postSellOffer(pathway, salt);
        _acceptAndFinalize(offerId, buyer, buyerKey);
    }

    function _acceptAndFinalize(bytes32 offerId, address buyer, uint256 buyerKey)
        internal
        returns (bytes32 settlementId)
    {
        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);

        settlementId = _acceptSellOffer(offerId, buyer, buyerKey);

        // TimeSettlementPeriodCondition (closing): the 24h minimum settlement period must elapse
        // between acceptance and finalization before the keeper can finalize.
        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);

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

    /// @dev Buyer elects the offer's pinned pathway; for an unpinned offer use the 4-arg overload.
    function _acceptSellOffer(bytes32 offerId, address buyer, uint256 buyerKey)
        internal
        returns (bytes32 settlementId)
    {
        return _acceptSellOffer(offerId, buyer, buyerKey, dm.getOffer(offerId).expectedExemptionPathway);
    }

    function _acceptSellOffer(bytes32 offerId, address buyer, uint256 buyerKey, ExemptionPathway pathway)
        internal
        returns (bytes32 settlementId)
    {
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, pathway, UNITS);
        vm.prank(buyer);
        settlementId = dm.acceptOffer(a);
    }

    /// @dev Builds a buyer's acceptance params. Kept separate from the call so revert tests can compute the
    /// acceptor signature (which makes registry view calls) before arming vm.expectRevert.
    function _sellAcceptParams(
        bytes32 offerId,
        address buyer,
        uint256 buyerKey,
        ExemptionPathway pathway,
        uint256 units
    ) internal view returns (AcceptOfferParams memory) {
        // The buyer records the §4(a)(7) ack as a signer value; the condition scans for its marker,
        // so carrying it on non-4a7 pathways is harmless.
        string[] memory pv = _one(SECTION4A7_ACK);
        return AcceptOfferParams({
            offerId: offerId,
            units: units,
            exemptionPathway: pathway,
            buyerName: "Bob",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: pv,
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey, pv),
            openEndorsementSig: ""
        });
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
        eligibility = EligibilityCondition(
            _proxy(address(new EligibilityCondition()), abi.encodeCall(EligibilityCondition.initialize, (address(auth))))
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
        rule144Disclosure = Rule144DisclosureCondition(
            _proxy(
                address(new Rule144DisclosureCondition()),
                abi.encodeCall(Rule144DisclosureCondition.initialize, (address(auth), DISCLOSURE_MAX_AGE))
            )
        );
        section4a7Disclosure = Section4a7DisclosureCondition(
            _proxy(
                address(new Section4a7DisclosureCondition()),
                abi.encodeCall(
                    Section4a7DisclosureCondition.initialize,
                    (address(auth), address(registry), SECTION4A7_ACK, DISCLOSURE_MAX_AGE)
                )
            )
        );
        legalOpinion = LegalOpinionCondition(
            _proxy(
                address(new LegalOpinionCondition()),
                abi.encodeCall(LegalOpinionCondition.initialize, (address(auth)))
            )
        );
        agreementSigned = AgreementSignedCondition(
            _proxy(
                address(new AgreementSignedCondition()),
                abi.encodeCall(AgreementSignedCondition.initialize, (address(auth), address(registry)))
            )
        );
        // Closing conditions are plain (non-proxied) singletons.
        metalexKillAdmin = makeAddr("metalexKillAdmin");
        legionKillAdmin = makeAddr("legionKillAdmin");
        killSwitch = new KillSwitchCondition(metalexKillAdmin, legionKillAdmin);
        timeSettlement = new TimeSettlementPeriodCondition();
    }

    function _deployKindCondition(CategoryKind kind) internal returns (LexChexBadgeKindCondition) {
        return LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(LexChexBadgeKindCondition.initialize, (address(auth), address(badge), kind, "", false))
            )
        );
    }

    /// @dev One call per list; the pathway calls also enable their pathway. This SPV supports all five.
    function _wireConditions() internal {
        // SPV-layer (every pathway).
        address[] memory spv = new address[](5);
        spv[0] = address(eligibility);
        spv[1] = address(holderCap);
        spv[2] = address(usState);
        spv[3] = address(legion);
        spv[4] = address(agreementSigned);

        vm.startPrank(owner);
        dm.setSpvThresholdConditions(spv);

        // Pathway-layer.
        dm.setPathwayThresholdConditions(
            ExemptionPathway.RULE_144, _list(address(holdingPeriod), address(rule144Disclosure)), true
        );
        dm.setPathwayThresholdConditions(
            ExemptionPathway.SECTION_4A7, _list(address(accredited), address(section4a7Disclosure)), true
        );
        dm.setPathwayThresholdConditions(ExemptionPathway.SECTION_4A1HALF, _list(address(legalOpinion)), true);
        dm.setPathwayThresholdConditions(ExemptionPathway.RULE_144A, _list(address(qib)), true);
        dm.setPathwayThresholdConditions(
            ExemptionPathway.REGULATION_S, _list(address(nonUsPerson), address(regS)), true
        );

        // Closing set (all pathways).
        dm.setClosingConditions(_list(address(killSwitch), address(timeSettlement)));
        vm.stopPrank();
    }

    function _commonBuyerSetup(address buyer, string memory jurisdiction, bytes2 state) internal {
        _mintCred(buyer, CAT_KYC, jurisdiction, state);
        _mintCred(buyer, CAT_LEGION, jurisdiction, state);
        vm.prank(owner);
        eligibility.setClearance(buyer, true);

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    function _createCategory(bytes32 id, CategoryKind kind) internal {
        bool isAnchor = kind == CategoryKind.KYC_AML; // KYC is the residence/identity anchor for these tests
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
            exists: true,
            governedAttributes: isAnchor ? (ATTR_INVESTOR_JURISDICTION | ATTR_US_STATE) : 0
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
            extensionData: "",
            regulatoryJurisdiction: "",
            lastUpdated: 0
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
            // acquisitionDate left 0: the base per-lot acquisitionTimestamp (stamped at mint) is now the
            // authoritative hold anchor; extensionData carries only the tacking anchor (unused here).
            extensionData: abi.encode(
                FundInterestData({acquisitionDate: 0, tackedFromAcquisitionDate: 0, customProvisions: ""})
            )
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Small utilities
    // ─────────────────────────────────────────────────────────────────────────

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function _list(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _list(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function _partyFields() internal pure returns (string[] memory f) {
        f = new string[](1);
        f[0] = "section4a7Ack";
    }

    function _one(string memory v0) internal pure returns (string[] memory a) {
        a = new string[](1);
        a[0] = v0;
    }

    /// @dev Cumulative units consumed from the seller cert: a full sale voids it, a partial decrements.
    function _consumed(uint256 tokenId) internal view returns (uint256) {
        if (certPrinter.isVoided(tokenId)) return UNITS;
        return UNITS - certPrinter.getCertificateDetails(tokenId).unitsRepresented;
    }

    /// @dev Recomputes the next settlement agreement id for an offer and returns the acceptor's EIP-712
    /// signature over it. partyValues must match what acceptOffer submits (the §4(a)(7) ack).
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
        bytes32 settlementId = keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties, bytes32(0), address(dm), block.timestamp + dm.getSettlementWindow()));
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
