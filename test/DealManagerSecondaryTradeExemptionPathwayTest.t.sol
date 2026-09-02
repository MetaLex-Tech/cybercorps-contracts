// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CertificateDetails, ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {
    K_INVESTOR_TYPE,
    K_INVESTOR_JURISDICTION,
    K_US_STATE,
    K_ACCREDITED,
    K_QIB,
    K_NON_US,
    K_SYNDICATE,
    InvestorType
} from "../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
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
import {HoldingPeriodCondition} from "../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {LexChexBadgeKindCondition} from "../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {RegSDistributionComplianceCondition} from "../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {Rule144DisclosureCondition} from "../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {Section4a7DisclosureCondition} from "../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {LegalOpinionCondition} from "../src/libs/conditions/secondary/LegalOpinionCondition.sol";
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

    bytes2 constant CA = "CA";

    uint256 public constant UNITS = 100;
    uint256 public constant CONSIDERATION = 10 ether;
    uint64 public constant HOLD = 365 days;

    address public owner;
    uint256 public ownerKey;
    address public seller;
    uint256 public sellerKey;
    address public keeper;
    // A second credentialing operator on the same badge, granted K_SYNDICATE and no BorgAuth role. Its
    // credentials are what the circle gate accepts; an identical one from anyone else does not clear it.
    address public legionIssuer;

    SecERC20Mock public paymentToken;
    BorgAuth public auth;
    MockCorpWithAuth public corp;
    IssuanceManager public im;
    ILedgerEntryToken public certPrinter;
    CyberAgreementRegistry public registry;
    DealManagerFactory public dmFactory;
    DealManager public dm;
    LeXcheXBadge public badge;

    // Real conditions.
    EligibilityCondition public eligibility;
    HolderCapCondition public holderCap;
    USStateOfResidenceCondition public usState;
    LexChexBadgeKindCondition public legion;
    HoldingPeriodCondition public holdingPeriod;
    LexChexBadgeKindCondition public accredited;
    LexChexBadgeKindCondition public qib;
    LexChexBadgeKindCondition public nonUsPerson;
    RegSDistributionComplianceCondition public regS;
    Rule144DisclosureCondition public rule144Disclosure;
    Section4a7DisclosureCondition public section4a7Disclosure;
    LegalOpinionCondition public legalOpinion;
    KillSwitchCondition public killSwitch;
    TimeSettlementPeriodCondition public timeSettlement;

    address public metalexKillAdmin;
    address public legionKillAdmin;

    uint256 public sellerTokenId;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (seller, sellerKey) = makeAddrAndKey("seller");
        keeper = makeAddr("keeper");
        legionIssuer = makeAddr("legion.issuer");

        paymentToken = new SecERC20Mock();
        auth = new BorgAuth(owner);
        corp = new MockCorpWithAuth(address(auth));

        // Real IssuanceManager + LedgerEntryToken via the factory beacon stack.
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

        _deployBadge();
        _deployConditions();
        _wireConditions();

        // Reg S per-SPV config: Category 3, one-year distribution compliance period.
        vm.prank(owner);
        regS.setRegSConfig(address(corp), 3, HOLD);

        // Seller Ledger Entry Token, minted now: its base acquisitionTimestamp is stamped at mint (§12B.3),
        // so we mint first and then warp forward to age the lot past the holding / Reg S compliance period —
        // the on-chain-faithful way to represent a seasoned position (no fakeable historical date).
        vm.startPrank(owner);
        certPrinter = ILedgerEntryToken(
            im.createCertPrinter(
                new string[](0),
                "Secondary Cert",
                "SCERT",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );
        // Open the register: legalTransferable is deny-by-default.
        certPrinter.setGlobalLegalTransferable(true);
        // The printer's tally and HolderCapCondition must read the same badge.
        LedgerEntryToken(address(certPrinter)).setLookThroughBadge(address(badge));
        sellerTokenId = im.createCertAndAssign(address(certPrinter), seller, _sellerCertDetails());
        vm.stopPrank();

        // Age the seller lot past HOLD, then issue "now" state (seller KYC badge, disclosure packages) so
        // those are current as of trade time.
        vm.warp(500 days);
        _mintCred(seller, CAT_KYC, "US", CA);
        vm.startPrank(owner);
        eligibility.setClearance(address(corp), seller, true);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, uint256(100), false, false);
        legion.updateIssuers(_list(legionIssuer));
        vm.stopPrank();
        _setRule144Info(true);
        _setSection4a7Package(true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SPV disclosure state — the two Diagram 5a decision nodes
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Rule 144(c)(2) "Current Public Info Available?". Aging the package out is the only way to answer
    /// no: the setter rejects a zero `asOf`, so a package can be staled but never removed, and the condition
    /// reads an absent record and a stale one the same way.
    function _setRule144Info(bool current) internal {
        vm.prank(owner);
        rule144Disclosure.setDisclosurePackage(address(corp), DISCLOSURE_URI, _asOf(current));
    }

    /// @dev "SPV Has GAAP Financials for 2 Years?" — the §4(a)(7) information package, staled the same way.
    function _setSection4a7Package(bool current) internal {
        vm.prank(owner);
        section4a7Disclosure.setDisclosurePackage(address(corp), DISCLOSURE_URI, _asOf(current), SECTION4A7_ACK);
    }

    /// @dev Freshness is measured from the call, so re-assert these after any warp that outruns the max age.
    function _asOf(bool current) internal view returns (uint64) {
        return uint64(current ? block.timestamp : block.timestamp - DISCLOSURE_MAX_AGE - 1);
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

    // Reg S turns on the attested fact, not on the buyer's recorded country: a foreign buyer whose
    // credential never asserts K_NON_US is refused the pathway.
    function test_RevertIf_RegulationS_BuyerNotAttestedNonUsPerson() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.regs.unattested");
        _commonBuyerSetup(buyer, "KY", bytes2(0)); // KYC only — jurisdiction KY, no K_NON_US

        bytes32 offerId = _postSellOffer(ExemptionPathway.REGULATION_S, uint256(keccak256("regs.unattested")));
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.REGULATION_S, UNITS);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(nonUsPerson))
        );
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

    // ─────────────────────────────────────────────────────────────────────────
    // Decision-tree leaves: a pathway that is closed falls through to one that settles
    // ─────────────────────────────────────────────────────────────────────────

    // Diagram 5a "Current Public Info? → No" (P2–P5). Rule 144 closes on a seasoned lot when the 144(c)(2)
    // package goes stale, and the buyer-type fork beneath it settles under each of the other three.
    function test_SeasonedLot_StaleInfo_ClosesRule144_ForkSettles() public {
        uint256[] memory lots = _mintSeasonedLots(4);
        _setRule144Info(false);
        _expectPostRefused(lots[0], ExemptionPathway.RULE_144, 0, address(rule144Disclosure));

        // P2 — accredited buyer, SPV carries its §4(a)(7) package
        // SPV has valid §4(a)(7) package already
        (address accredited_, uint256 accreditedKey) = _accreditedBuyer("stale.accredited");
        _settleUnder(lots[0], ExemptionPathway.SECTION_4A7, 1, accredited_, accreditedKey);

        // P4 — QIB
        (address qibBuyer, uint256 qibKey) = _qibBuyer("stale.qib");
        _settleUnder(lots[1], ExemptionPathway.RULE_144A, 2, qibBuyer, qibKey);

        // P5 — sophisticated but not accredited
        (address soph, uint256 sophKey) = _sophisticatedBuyer("stale.sophisticated");
        _settleUnder(lots[2], ExemptionPathway.SECTION_4A1HALF, 3, soph, sophKey);

        // P3 — the SPV loses its §4(a)(7) package too, cornering the accredited buyer onto §4(a)(1½)
        _setSection4a7Package(false);
        (address cornered, uint256 corneredKey) = _accreditedBuyer("stale.cornered");
        _expectPostRefused(lots[3], ExemptionPathway.SECTION_4A7, 4, address(section4a7Disclosure));
        _settleUnder(lots[3], ExemptionPathway.SECTION_4A1HALF, 5, cornered, corneredKey);
    }

    // Diagram 5a "Holding Period Elapsed? → No" (P6–P9). The one-year hold is Rule 144's alone, so an
    // unseasoned lot is refused there at posting and the same fork beneath it settles under the other three.
    function test_UnseasonedLot_ClosesRule144_ForkSettles() public {
        _expectPostRefused(_mintSellerLot(), ExemptionPathway.RULE_144, 10, address(holdingPeriod));

        // P6 — accredited buyer, SPV carries its §4(a)(7) package
        (address accredited_, uint256 accreditedKey) = _accreditedBuyer("unseasoned.accredited");
        _settleUnder(_mintSellerLot(), ExemptionPathway.SECTION_4A7, 11, accredited_, accreditedKey);

        // P8 — QIB
        (address qibBuyer, uint256 qibKey) = _qibBuyer("unseasoned.qib");
        _settleUnder(_mintSellerLot(), ExemptionPathway.RULE_144A, 12, qibBuyer, qibKey);

        // P9 — sophisticated but not accredited
        (address soph, uint256 sophKey) = _sophisticatedBuyer("unseasoned.sophisticated");
        _settleUnder(_mintSellerLot(), ExemptionPathway.SECTION_4A1HALF, 13, soph, sophKey);

        // P7 — no §4(a)(7) package either, so the accredited buyer has only §4(a)(1½) left
        _setSection4a7Package(false);
        (address cornered, uint256 corneredKey) = _accreditedBuyer("unseasoned.cornered");
        uint256 lot = _mintSellerLot();
        _expectPostRefused(lot, ExemptionPathway.SECTION_4A7, 14, address(section4a7Disclosure));
        _settleUnder(lot, ExemptionPathway.SECTION_4A1HALF, 15, cornered, corneredKey);
    }

    // Diagram 5b right branch: a U.S. buyer of a non-U.S. SPV runs the domestic analysis and, under the Touche
    // Remnant posture, takes one of the SPV's U.S.-resident seats — so a full count turns them away.
    function test_ToucheRemnant_UsBuyerConsumesAUsSeat() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.touche.us");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_ACCREDITED, "US", bytes2(0));

        // Non-U.S. SPV posture: only U.S. residents count, and the seller already holds the single seat.
        vm.prank(owner);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, uint256(1), true, false);
        assertEq(certPrinter.usLookThroughHolderCount(), 1, "seller is the only U.S. holder");

        // Each live offer reserves its lot's units, so the blocked and settling attempts use separate lots.
        bytes32 blocked =
            _postSellOffer(_mintSellerLot(), ExemptionPathway.SECTION_4A7, uint256(keccak256("touche.us.blocked")));
        AcceptOfferParams memory a = _sellAcceptParams(blocked, buyer, buyerKey, ExemptionPathway.SECTION_4A7, UNITS);
        vm.expectRevert(
            abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(holderCap))
        );
        vm.prank(buyer);
        dm.acceptOffer(a);

        // Raising the cap opens a second U.S. seat and the same buyer settles.
        vm.prank(owner);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, uint256(2), true, false);
        _settle(
            _postSellOffer(_mintSellerLot(), ExemptionPathway.SECTION_4A7, uint256(keccak256("touche.us.ok"))),
            buyer,
            buyerKey
        );
    }

    // Diagram 5b left branch: the same SPV with its U.S.-resident count already at cap still settles with a
    // non-U.S. buyer, who never increments that count.
    function test_ToucheRemnant_NonUsBuyerSettlesAtUsCap() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("buyer.touche.nonus");
        _commonBuyerSetup(buyer, "KY", bytes2(0));
        _mintCred(buyer, CAT_NONUS, "KY", bytes2(0));

        vm.prank(owner);
        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, uint256(1), true, false);
        assertEq(certPrinter.usLookThroughHolderCount(), 1, "U.S.-resident count already at cap");

        _settle(_postSellOffer(ExemptionPathway.REGULATION_S, uint256(keccak256("touche.nonus"))), buyer, buyerKey);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Per-pathway gates, each at the stage it must bite
    // ─────────────────────────────────────────────────────────────────────────

    // §4(a)(7) needs the buyer to confirm they received the information package. The confirmation is a signer
    // value on the settlement, so it can only be checked from acceptance onward.
    function test_RevertIf_Section4a7_BuyerOmitsAcknowledgment() public {
        (address buyer, uint256 buyerKey) = _accreditedBuyer("4a7.noack");
        bytes32 offerId = _postSellOffer(ExemptionPathway.SECTION_4A7, 20);

        AcceptOfferParams memory a = _sellAcceptParams(
            offerId, buyer, buyerKey, ExemptionPathway.SECTION_4A7, UNITS, _one("some other statement")
        );
        _expectAcceptRefused(a, buyer, address(section4a7Disclosure));
    }

    // §4(a)(1½)'s gate is the GP's sign-off, recorded per offer between posting and acceptance.
    function test_RevertIf_Section4a1Half_NoGpSignOff() public {
        (address buyer, uint256 buyerKey) = _sophisticatedBuyer("4a1half.nosignoff");
        bytes32 offerId = _postSellOffer(ExemptionPathway.SECTION_4A1HALF, 21);

        AcceptOfferParams memory a =
            _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.SECTION_4A1HALF, UNITS);
        _expectAcceptRefused(a, buyer, address(legalOpinion));
    }

    // Reg S measures its distribution compliance period from the seller's lot, so a lot still inside the
    // period is refused at posting — no buyer needed.
    function test_RevertIf_RegulationS_LotInsideCompliancePeriod() public {
        _expectPostRefused(_mintSellerLot(), ExemptionPathway.REGULATION_S, 22, address(regS));
    }

    // A QIB credential does not imply accreditation: the badge asserts discrete facts, not a status ladder.
    function test_RevertIf_Section4a7_QibIsNotAccreditedByImplication() public {
        (address buyer, uint256 buyerKey) = _qibBuyer("4a7.qibonly");
        bytes32 offerId = _postSellOffer(ExemptionPathway.SECTION_4A7, 23);

        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.SECTION_4A7, UNITS);
        _expectAcceptRefused(a, buyer, address(accredited));
    }

    // Pinning a pathway pulls its Layer 1 checks forward to posting. Left unpinned, the same defective lot
    // posts cleanly and is only caught once a buyer elects the pathway that cares.
    function test_UnpinnedOffer_DefersSellerSideCheckToAcceptance() public {
        (address buyer, uint256 buyerKey) = _sophisticatedBuyer("unpinned.unseasoned");
        uint256 lot = _mintSellerLot();

        _expectPostRefused(lot, ExemptionPathway.RULE_144, 24, address(holdingPeriod));

        bytes32 offerId = _postSellOffer(lot, ExemptionPathway.NONE, 25);
        AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, ExemptionPathway.RULE_144, UNITS);
        _expectAcceptRefused(a, buyer, address(holdingPeriod));
    }

    // The SPV layer is resolved for every pathway, so one uncleared buyer is turned away from all five.
    function test_RevertIf_SpvLayerFails_BlocksEveryPathway() public {
        (address buyer, uint256 buyerKey) = _sophisticatedBuyer("spvlayer.uncleared");
        _setClearance(buyer, false);

        uint256[] memory lots = _mintSeasonedLots(5);
        _setRule144Info(true);
        _setSection4a7Package(true);

        ExemptionPathway[5] memory pathways = [
            ExemptionPathway.RULE_144,
            ExemptionPathway.SECTION_4A7,
            ExemptionPathway.SECTION_4A1HALF,
            ExemptionPathway.RULE_144A,
            ExemptionPathway.REGULATION_S
        ];
        for (uint256 i; i < pathways.length; i++) {
            bytes32 offerId = _postSellOffer(lots[i], pathways[i], 30 + i);
            AcceptOfferParams memory a = _sellAcceptParams(offerId, buyer, buyerKey, pathways[i], UNITS);
            _expectAcceptRefused(a, buyer, address(eligibility));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Eligibility must still hold at settlement, not only at acceptance
    // ─────────────────────────────────────────────────────────────────────────

    // Finalize re-runs the threshold set, so a pathway credential that lapses in the settlement window
    // stops the transfer.
    function test_RevertIf_PathwayCredentialExpiresBeforeFinalize() public {
        (address buyer, uint256 buyerKey) = makeAddrAndKey("expiring.qib");
        _commonBuyerSetup(buyer, "US", CA);
        _mintCred(buyer, CAT_QIB, "US", bytes2(0), uint64(block.timestamp + 2 days));

        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144A, 40);
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);

        // Past the QIB badge's expiry and past the 24h settlement delay, still inside the 7d window.
        vm.warp(block.timestamp + 3 days);
        _expectFinalizeRefused(settlementId, address(qib));
    }

    // The same backstop for the SPV layer: clearance revoked after acceptance blocks settlement.
    function test_RevertIf_SpvClearanceRevokedBeforeFinalize() public {
        (address buyer, uint256 buyerKey) = _sophisticatedBuyer("revoked.midflight");
        bytes32 offerId = _postSellOffer(ExemptionPathway.RULE_144, 41);
        bytes32 settlementId = _acceptSellOffer(offerId, buyer, buyerKey);

        _setClearance(buyer, false);
        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);
        _expectFinalizeRefused(settlementId, address(eligibility));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Buy side: the offeror is the buyer, so buyer-facing gates move to posting
    // ─────────────────────────────────────────────────────────────────────────

    function test_BuyOffer_Rule144A_Settles() public {
        (address buyer,) = _qibBuyer("buy.qib");

        bytes32 offerId = _postBuyOffer(buyer, ExemptionPathway.RULE_144A, 50);
        bytes32 settlementId = _acceptBuyOffer(offerId, sellerTokenId);

        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "buy-side escrow FINALIZED"
        );
        assertGt(certPrinter.balanceOfLegalOwner(buyer), 0, "buy offeror holds a Ledger Entry Token");
    }

    // On a sell offer the QIB check waits for a buyer; here the offeror is the buyer, so it bites at posting.
    function test_RevertIf_BuyOffer_NonQibCannotPost144A() public {
        (address buyer,) = _accreditedBuyer("buy.notqib");

        PostOfferParams memory p = _buyOfferParams(ExemptionPathway.RULE_144A, 51);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, address(qib)));
        vm.prank(buyer);
        dm.postOffer(p);
    }

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

    function _postSellOffer(ExemptionPathway pathway, uint256 salt) internal returns (bytes32) {
        return _postSellOffer(sellerTokenId, pathway, salt);
    }

    function _postSellOffer(uint256 tokenId, ExemptionPathway pathway, uint256 salt)
        internal
        returns (bytes32 offerId)
    {
        PostOfferParams memory p = _sellOfferParams(tokenId, pathway, salt);
        vm.prank(seller);
        offerId = dm.postOffer(p);
    }

    /// @dev Kept separate from the call so revert tests can build the params before arming vm.expectRevert.
    function _sellOfferParams(uint256 tokenId, ExemptionPathway pathway, uint256 salt)
        internal
        view
        returns (PostOfferParams memory)
    {
        return PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(certPrinter),
            tokenId: tokenId,
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
    }

    /// @dev Mints the seller a fresh lot at the current timestamp — unseasoned for Rule 144 purposes.
    function _mintSellerLot() internal returns (uint256 tokenId) {
        vm.prank(owner);
        tokenId = im.createCertAndAssign(address(certPrinter), seller, _sellerCertDetails());
    }

    /// @dev `count` lots aged past HOLD in one warp. The warp outruns the disclosure max age, so callers
    /// re-assert the packages they need afterwards.
    function _mintSeasonedLots(uint256 count) internal returns (uint256[] memory lots) {
        lots = new uint256[](count);
        for (uint256 i; i < count; i++) lots[i] = _mintSellerLot();
        vm.warp(block.timestamp + HOLD + 1);
    }

    /// @dev Posts under `pathway` (adding the GP sign-off §4(a)(1½) needs) and settles.
    function _settleUnder(uint256 tokenId, ExemptionPathway pathway, uint256 salt, address buyer, uint256 buyerKey)
        internal
    {
        bytes32 offerId = _postSellOffer(tokenId, pathway, salt);
        if (pathway == ExemptionPathway.SECTION_4A1HALF) {
            vm.prank(owner);
            legalOpinion.recordGPSignOff(address(dm), offerId);
        }
        _settle(offerId, buyer, buyerKey);
    }

    /// @dev Asserts posting `tokenId` under `pathway` is refused by `condition`. A refused post reserves
    /// nothing, so the lot stays available for the pathway that does carry it.
    function _expectPostRefused(uint256 tokenId, ExemptionPathway pathway, uint256 salt, address condition) internal {
        PostOfferParams memory p = _sellOfferParams(tokenId, pathway, salt);
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, condition));
        vm.prank(seller);
        dm.postOffer(p);
    }

    /// @dev Params are built by the caller, since computing the acceptor signature makes registry view calls.
    function _expectAcceptRefused(AcceptOfferParams memory a, address buyer, address condition) internal {
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, condition));
        vm.prank(buyer);
        dm.acceptOffer(a);
    }

    function _expectFinalizeRefused(bytes32 settlementId, address condition) internal {
        vm.expectRevert(abi.encodeWithSelector(ISecondaryTradeStorage.SecondaryConditionsNotMet.selector, condition));
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
    }

    // Buyer profiles from Diagram 5a's "Buyer Type?" fork. All U.S., state CA; they differ only in the
    // status fact their credential asserts.

    function _accreditedBuyer(string memory label) internal returns (address buyer, uint256 key) {
        (buyer, key) = _sophisticatedBuyer(label);
        _mintCred(buyer, CAT_ACCREDITED, "US", bytes2(0));
    }

    function _qibBuyer(string memory label) internal returns (address buyer, uint256 key) {
        (buyer, key) = _sophisticatedBuyer(label);
        _mintCred(buyer, CAT_QIB, "US", bytes2(0));
    }

    /// @dev Sophisticated but not accredited: KYC and Legion only, no status fact.
    function _sophisticatedBuyer(string memory label) internal returns (address buyer, uint256 key) {
        (buyer, key) = makeAddrAndKey(label);
        _commonBuyerSetup(buyer, "US", CA);
    }

    function _setClearance(address account, bool cleared) internal {
        vm.prank(owner);
        eligibility.setClearance(address(corp), account, cleared);
    }

    /// @dev Accepts the offer's pinned pathway, clears the settlement period, finalizes.
    function _settle(bytes32 offerId, address buyer, uint256 buyerKey) internal returns (bytes32 settlementId) {
        settlementId = _acceptSellOffer(offerId, buyer, buyerKey);
        vm.warp(block.timestamp + timeSettlement.DEFAULT_DELAY() + 1);
        vm.prank(keeper);
        dm.finalizeSecondaryTradeAgreement(settlementId);
        assertEq(
            uint8(dm.getSecondaryEscrow(settlementId).status),
            uint8(SecondaryEscrowStatus.FINALIZED),
            "escrow FINALIZED"
        );
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
        return _sellAcceptParams(offerId, buyer, buyerKey, pathway, units, _one(SECTION4A7_ACK));
    }

    /// @dev Overload for tests that need to submit something other than the SPV's acknowledgment string.
    function _sellAcceptParams(
        bytes32 offerId,
        address buyer,
        uint256 buyerKey,
        ExemptionPathway pathway,
        uint256 units,
        string[] memory partyValues
    ) internal view returns (AcceptOfferParams memory) {
        return AcceptOfferParams({
            offerId: offerId,
            units: units,
            exemptionPathway: pathway,
            buyerName: "Bob",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: partyValues,
            acceptorAgreementSig: _acceptorSig(offerId, buyer, buyerKey, partyValues),
            openEndorsementSig: ""
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Buy-side lifecycle — the offeror is the buyer, the acceptor supplies the lot
    // ─────────────────────────────────────────────────────────────────────────

    function _postBuyOffer(address buyer, ExemptionPathway pathway, uint256 salt) internal returns (bytes32 offerId) {
        PostOfferParams memory p = _buyOfferParams(pathway, salt);
        vm.prank(buyer);
        offerId = dm.postOffer(p);
    }

    /// @dev A buy offer names no lot: the accepting seller supplies `sellerTokenId`, and the offeror's own
    /// party values carry the §4(a)(7) ack because on this side the offeror is the buyer.
    function _buyOfferParams(ExemptionPathway pathway, uint256 salt) internal view returns (PostOfferParams memory) {
        return PostOfferParams({
            side: OfferSide.BUY,
            certPrinter: address(certPrinter),
            tokenId: 0,
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
            offerorPartyValues: _one(SECTION4A7_ACK),
            offerorAgreementSig: "",
            openEndorsementSig: "",
            buyerName: "Bob",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
    }

    function _acceptBuyOffer(bytes32 offerId, uint256 tokenId) internal returns (bytes32 settlementId) {
        string[] memory pv = _one(SECTION4A7_ACK);
        AcceptOfferParams memory a = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            exemptionPathway: ExemptionPathway.NONE, // ignored on a buy offer: the offer's pin governs
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: tokenId,
            acceptorPartyValues: pv,
            acceptorAgreementSig: _acceptorSig(offerId, seller, sellerKey, pv),
            openEndorsementSig: "sellerEndorsement"
        });
        vm.prank(seller);
        settlementId = dm.acceptOffer(a);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Setup helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _deployBadge() internal {
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(
                    address(new LeXcheXBadge()),
                    abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))
                )
            )
        );
        // Legion issues on the shared badge, trusted for circle seats only. The grant is all it gets: no
        // BorgAuth role, so it picks up none of the admin power this auth carries over the rest of the stack.
        vm.prank(owner);
        badge.setIssuerKeys(legionIssuer, K_SYNDICATE);
    }

    function _deployConditions() internal {
        eligibility = EligibilityCondition(
            _proxy(address(new EligibilityCondition()), abi.encodeCall(EligibilityCondition.initialize, (address(auth))))
        );
        holderCap = HolderCapCondition(
            _proxy(
                address(new HolderCapCondition()),
                abi.encodeCall(HolderCapCondition.initialize, (address(auth)))
            )
        );
        usState = USStateOfResidenceCondition(
            _proxy(
                address(new USStateOfResidenceCondition()),
                abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(badge)))
            )
        );
        legion = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(
                    LexChexBadgeKindCondition.initialize, (address(auth), address(badge), K_SYNDICATE, false)
                )
            )
        );
        holdingPeriod = HoldingPeriodCondition(
            _proxy(
                address(new HoldingPeriodCondition()),
                abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), uint256(HOLD)))
            )
        );
        accredited = _deployKindCondition(K_ACCREDITED);
        qib = _deployKindCondition(K_QIB);
        nonUsPerson = _deployKindCondition(K_NON_US);
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
                    (address(auth), address(registry), DISCLOSURE_MAX_AGE)
                )
            )
        );
        legalOpinion = LegalOpinionCondition(
            _proxy(
                address(new LegalOpinionCondition()),
                abi.encodeCall(LegalOpinionCondition.initialize, (address(auth)))
            )
        );
        // Closing conditions are plain (non-proxied) singletons.
        metalexKillAdmin = makeAddr("metalexKillAdmin");
        legionKillAdmin = makeAddr("legionKillAdmin");
        killSwitch = new KillSwitchCondition(metalexKillAdmin, legionKillAdmin);
        timeSettlement = new TimeSettlementPeriodCondition();
    }

    function _deployKindCondition(uint256 kindKey) internal returns (LexChexBadgeKindCondition) {
        return LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(LexChexBadgeKindCondition.initialize, (address(auth), address(badge), kindKey, false))
            )
        );
    }

    /// @dev One call per list; the pathway calls also enable their pathway. This SPV supports all five.
    function _wireConditions() internal {
        // SPV-layer (every pathway).
        address[] memory spv = new address[](4);
        spv[0] = address(eligibility);
        spv[1] = address(holderCap);
        spv[2] = address(usState);
        spv[3] = address(legion);

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
        _mintSyndicate(buyer);
        vm.prank(owner);
        eligibility.setClearance(address(corp), buyer, true);

        paymentToken.mint(buyer, CONSIDERATION * 10);
        vm.prank(buyer);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    /// @dev Mints a credential whose facts follow `cat`: CAT_KYC carries the residence anchor (jurisdiction +
    /// state), CAT_ACCREDITED / CAT_QIB / CAT_NONUS assert the matching status fact-key. `cat` is a test-local
    /// way to name a profile — the badge has no such notion.
    // TODO make it closer to real-world scenarios
    function _mintCred(address to, bytes32 cat, string memory jurisdiction, bytes2 state) internal {
        _mintCred(to, cat, jurisdiction, state, uint64(block.timestamp + 3650 days));
    }

    /// @dev Overload for tests that need a credential to lapse mid-trade.
    function _mintCred(address to, bytes32 cat, string memory jurisdiction, bytes2 state, uint64 expiry)
        internal
    {
        Credential memory cred;
        cred.investorType = InvestorType.INDIVIDUAL;
        cred.investorJurisdiction = jurisdiction;
        cred.usState = state;
        cred.expiryDate = expiry;

        uint256 asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        if (state != bytes2(0)) asserts |= K_US_STATE;
        if (cat == CAT_ACCREDITED) asserts |= K_ACCREDITED;
        else if (cat == CAT_QIB) asserts |= K_QIB;
        else if (cat == CAT_NONUS) asserts |= K_NON_US;
        cred.asserts = asserts;

        vm.prank(owner);
        badge.mint(to, cred);
    }

    /// @dev A seat in Legion's circle for this SPV. Minted by Legion rather than the owner, because the gate
    /// takes only Legion's word for who is in the circle.
    function _mintSyndicate(address to) internal {
        Credential memory cred;
        cred.asserts = K_SYNDICATE;
        cred.scope = address(corp);
        cred.expiryDate = uint64(block.timestamp + 3650 days);

        vm.prank(legionIssuer);
        badge.mint(to, cred);
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
            // authoritative hold anchor; all FundInterestData fields stay default (unused here).
            extensionData: abi.encode(_defaultFundInterestData())
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Small utilities
    // ─────────────────────────────────────────────────────────────────────────

    function _defaultFundInterestData() internal pure returns (FundInterestData memory fid) {
        // Memory struct default-init: zero dates, empty strings/arrays
    }

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
        bytes32 settlementId = keccak256(abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties, bytes32(0), address(dm)));
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
