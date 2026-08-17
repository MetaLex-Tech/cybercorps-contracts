// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SecurityClass, SecuritySeries} from "../../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../../src/LedgerEntryToken.sol";
import {Credential} from "../../src/creds/storage/lexchexBadgeStorage.sol";
import {CertificateDetails, ILedgerEntryToken} from "../../src/interfaces/ILedgerEntryToken.sol";
import {
    InvestorType,
    K_ACCREDITED,
    K_BO_COUNT,
    K_INVESTOR_JURISDICTION,
    K_INVESTOR_TYPE,
    K_LOOKTHROUGH_JURISDICTION,
    K_NON_US,
    K_SPV_WHITELIST,
    K_US_STATE
} from "../../src/interfaces/ILexChexBadge.sol";
import {CFIUSCondition} from "../../src/libs/conditions/secondary/CFIUSCondition.sol";
import {EligibilityCondition} from "../../src/libs/conditions/secondary/EligibilityCondition.sol";
import {GPLPApprovalCondition} from "../../src/libs/conditions/secondary/GPLPApprovalCondition.sol";
import {HolderCapCondition} from "../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {HoldingPeriodCondition} from "../../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {KillSwitchCondition} from "../../src/libs/conditions/secondary/KillSwitchCondition.sol";
import {LegalOpinionCondition} from "../../src/libs/conditions/secondary/LegalOpinionCondition.sol";
import {LexChexBadgeKindCondition} from "../../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {
    RegSDistributionComplianceCondition
} from "../../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {Rule144DisclosureCondition} from "../../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {Section4a7DisclosureCondition} from "../../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {TimeSettlementPeriodCondition} from "../../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
import {USStateOfResidenceCondition} from "../../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    OfferSide,
    PostOfferParams
} from "../../src/storage/SecondaryTradeStorage.sol";
import {SecondaryConditionIntegrationBase} from "../conditions/secondary/SecondaryConditionIntegration.sol";
import {console2} from "forge-std/Test.sol";

/// @title  SecondaryTradeGasBase - shared scenario for the two secondary-trade gas baselines
/// @author MetaLeX Labs, Inc.
/// @notice Everything except the printer is identical in both baselines: the same trade size, the same
/// price, the same 15 real conditions, the same credentials, the same settlement-agreement shape and the
/// same fee split. Only `_deployPrinter` differs. Thus any gas difference between the two suites is
/// attributable to the security's own data — its legend block and its certificate payload.
///
/// Condition stack, all real deployments, read live at post, accept and finalize:
/// | layer                   | conditions                                                                         |
/// |-------------------------|------------------------------------------------------------------------------------|
/// | fund-specific           | Eligibility, SpvWhitelist badge, USStateOfResidence, CFIUS, HolderCap, GPLPApproval |
/// | Rule 144                | HoldingPeriod, Rule144Disclosure                                                    |
/// | Section 4(a)(7)         | Section4a7Disclosure, Accredited badge                                              |
/// | Section 4(a)(1/2)       | LegalOpinion, Accredited badge                                                      |
/// | Regulation S            | RegSDistributionCompliance, NonUSPerson badge                                       |
/// | closing (finalize only) | TimeSettlementPeriod, KillSwitch                                                    |
///
/// The sell offer is posted unpinned, so each buyer elects the exemption at acceptance. Posting therefore
/// evaluates the fund-specific layer alone. Acceptance and finalization evaluate that layer plus the
/// elected pathway's, and finalization adds the closing set.
abstract contract SecondaryTradeGasBase is SecondaryConditionIntegrationBase {
    uint256 internal constant EIP7825_GAS_LIMIT = 16_777_216;
    uint256 internal constant GAS_LIMIT_90_PCT = 15_099_494; // 90% of EIP-7825 block gas limit

    // ── Trade parameters, identical in both baselines ─────────────────────────
    uint256 internal constant POSITION_UNITS = 76_297;
    uint256 internal constant PRICE_PER_UNIT = 26_213_301_000; // 9-decimal payment token
    uint256 internal constant FIRST_LOT_UNITS = 30_000;

    uint256 internal constant SCENARIO_START = 1_780_075_297; // the mainnet issuance epoch
    uint256 internal constant SEASONING = 400 days; // past the one-year hold Rule 144 and Reg S both need
    uint256 internal constant HOLD_PERIOD = 365 days;
    uint256 internal constant DISCLOSURE_MAX_AGE = 480 days; // Rule 144(c)(2): 16-month balance sheet
    uint256 internal constant INCUMBENT_HOLDERS = 12;
    uint256 internal constant INCUMBENT_BO_COUNT = 3;
    uint256 internal constant PLATFORM_FEE_BPS = 100; // 1%
    uint256 internal constant INTEGRATOR_FEE_SHARE_BPS = 3_000; // 30% of the platform fee

    string internal constant DISCLOSURE_ACK = "Information package received and reviewed; Rule 144(c)(2) and "
        "Section 4(a)(7)(d)(3) materials delivered prior to execution";
    string internal constant SETTLEMENT_URI = "ipfs://bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";
    bytes32 internal constant SETTLEMENT_TEMPLATE_ID = bytes32("metalex_cybertrade_secondary_v1");

    // ── Fund-specific (Layer 2) conditions ────────────────────────────────────
    EligibilityCondition internal eligibility;
    LexChexBadgeKindCondition internal spvWhitelist;
    USStateOfResidenceCondition internal blueSky;
    CFIUSCondition internal cfius;
    HolderCapCondition internal holderCap;
    GPLPApprovalCondition internal gpApproval;

    // ── Exemption (Layer 1) conditions ────────────────────────────────────────
    HoldingPeriodCondition internal holdingPeriod;
    Rule144DisclosureCondition internal rule144Disclosure;
    Section4a7DisclosureCondition internal section4a7;
    LexChexBadgeKindCondition internal accredited;
    LegalOpinionCondition internal legalOpinion;
    RegSDistributionComplianceCondition internal regS;
    LexChexBadgeKindCondition internal nonUsPerson;

    // ── Closing conditions ────────────────────────────────────────────────────
    TimeSettlementPeriodCondition internal settlementDelay;
    KillSwitchCondition internal killSwitch;

    address internal gp = makeAddr("generalPartner");
    address internal keeper = makeAddr("settlementKeeper");
    address internal integrator = makeAddr("integrator");
    address internal platformPayable = makeAddr("platformPayable");
    address internal metalexAdmin = makeAddr("metalexAdmin");
    address internal legionAdmin = makeAddr("legionAdmin");

    /// @dev Cayman feeder that buys under Regulation S
    address internal offshoreBuyer;
    uint256 internal offshoreBuyerKey;

    // ── Hooks each baseline implements ────────────────────────────────────────

    /// @dev Must set `printer`, wire the look-through badge, and mint the seller's lot into `sellerTokenId`.
    function _deployPrinter() internal virtual;

    /// @dev Names the security in the settlement agreement's global values.
    function _securityDescription() internal pure virtual returns (string memory);

    // ── Settlement agreement shape ────────────────────────────────────────────

    function _offerTemplateId() internal pure override returns (bytes32) {
        return SETTLEMENT_TEMPLATE_ID;
    }

    function _offerTemplateUri() internal pure override returns (string memory) {
        return SETTLEMENT_URI;
    }

    function _globalFields() internal pure override returns (string[] memory f) {
        f = new string[](4);
        f[0] = "Security";
        f[1] = "Price per unit (USD)";
        f[2] = "Transfer agent";
        f[3] = "Governing law";
    }

    function _globalValues() internal pure override returns (string[] memory v) {
        v = new string[](4);
        v[0] = _securityDescription();
        v[1] = "26.213301";
        v[2] = "MetaLeX Labs, Inc. (tokenized ledger, DGCL 219/224)";
        v[3] = "Delaware";
    }

    function _partyFields() internal pure override returns (string[] memory f) {
        f = new string[](4);
        f[0] = "Party name";
        f[1] = "Party address";
        f[2] = "Party type";
        f[3] = "Information delivery acknowledgment";
    }

    // ── Setup ─────────────────────────────────────────────────────────────────

    function _setUpGasScenario() internal {
        // Start at a real epoch. Lots are minted first and seasoned by warping forward, so a default
        // timestamp of 1 would leave no room for an anchor earlier than a lot's own acquisition.
        vm.warp(SCENARIO_START);
        _setUpIntegration();
        (offshoreBuyer, offshoreBuyerKey) = makeAddrAndKey("offshoreBuyer");

        _issueCredentials();
        _deployPrinter();
        _seedIncumbents();
        _deployConditions();
        _wireConditionLayers();
        _configureConditions();
        _configureFees();
        _seasonPosition();
        _fundBuyers();
    }

    /// @dev Credentials come first so the printer folds each holder's look-through weight into its tally
    /// as the register fills.
    function _issueCredentials() internal {
        // Seller: a U.S. natural person resident in Delaware.
        Credential memory sellerCred;
        sellerCred.investorName = "teh investOOOr";
        sellerCred.investorType = InvestorType.INDIVIDUAL;
        sellerCred.investorJurisdiction = "US";
        sellerCred.usState = bytes2("DE");
        _mintCred(seller, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_US_STATE, sellerCred);
        _grantWhitelist(seller);

        // Buyer: a U.S. family-office LLC organized in Delaware with three beneficial owners.
        Credential memory buyerCred;
        buyerCred.investorName = "Meridian Family Office LLC";
        buyerCred.investorType = InvestorType.ENTITY;
        buyerCred.investorJurisdiction = "US";
        buyerCred.lookThroughJurisdiction = "US";
        buyerCred.usState = bytes2("DE");
        buyerCred.beneficialOwnerCount = 3;
        _mintCred(
            buyer,
            K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE | K_BO_COUNT,
            buyerCred
        );
        _mintStatus(buyer, K_ACCREDITED);
        _grantWhitelist(buyer);

        // Offshore buyer: a Cayman feeder, attested non-U.S. person for the Reg S pathway. It carries no
        // U.S. state, which is what keeps it out of blue-sky reach.
        Credential memory offshoreCred;
        offshoreCred.investorName = "Blue Harbour Feeder Fund (Cayman) Ltd.";
        offshoreCred.investorType = InvestorType.ENTITY;
        offshoreCred.investorJurisdiction = "KY";
        offshoreCred.lookThroughJurisdiction = "KY";
        offshoreCred.beneficialOwnerCount = 4;
        _mintCred(
            offshoreBuyer,
            K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_BO_COUNT,
            offshoreCred
        );
        _mintStatus(offshoreBuyer, K_NON_US);
        _mintStatus(offshoreBuyer, K_ACCREDITED);
        _grantWhitelist(offshoreBuyer);
    }

    function _mintStatus(address to, uint256 statusKey) internal {
        Credential memory c;
        _mintCred(to, statusKey, c);
    }

    function _grantWhitelist(address to) internal {
        Credential memory c;
        c.scope = address(corp);
        _mintCred(to, K_SPV_WHITELIST, c);
    }

    /// @dev Incumbents only need to occupy the register: the holder cap reads the printer's O(1)
    /// look-through tally, never their cert payloads, so they are issued bare lots.
    function _seedIncumbents() internal {
        for (uint256 i = 0; i < INCUMBENT_HOLDERS; i++) {
            address holder = makeAddr(string.concat("incumbent", vm.toString(i)));
            Credential memory c;
            c.investorType = InvestorType.ENTITY;
            c.investorJurisdiction = "US";
            c.lookThroughJurisdiction = "US";
            c.beneficialOwnerCount = uint32(INCUMBENT_BO_COUNT);
            _mintCred(holder, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_BO_COUNT, c);
            _makeHolder(holder);
        }
    }

    /// @dev The base half of a seller lot. Each baseline fills `extensionData` with its own payload.
    function _baseCertDetails(uint256 units, bytes memory extensionData)
        internal
        pure
        returns (CertificateDetails memory)
    {
        return CertificateDetails({
            signingOfficerName: "Test Officer Name",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 2_000_000_000,
            issuerUSDValuationAtTimeOfInvestment: 35_000_000_000_000_000_000_000_000,
            unitsRepresented: units,
            legalDetails: "Dispute resolution method: Binding Arbitration|Governing law: Delaware",
            extensionData: extensionData
        });
    }

    function _deployConditions() internal {
        eligibility = EligibilityCondition(
            _proxy(
                address(new EligibilityCondition()), abi.encodeCall(EligibilityCondition.initialize, (address(auth)))
            )
        );
        spvWhitelist = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(
                    LexChexBadgeKindCondition.initialize, (address(auth), address(badge), K_SPV_WHITELIST, true)
                )
            )
        );
        blueSky = USStateOfResidenceCondition(
            _proxy(
                address(new USStateOfResidenceCondition()),
                abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(badge)))
            )
        );
        cfius = CFIUSCondition(
            _proxy(
                address(new CFIUSCondition()),
                abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(badge)))
            )
        );
        holderCap = HolderCapCondition(
            _proxy(address(new HolderCapCondition()), abi.encodeCall(HolderCapCondition.initialize, (address(auth))))
        );
        gpApproval = GPLPApprovalCondition(
            _proxy(
                address(new GPLPApprovalCondition()), abi.encodeCall(GPLPApprovalCondition.initialize, (address(auth)))
            )
        );

        holdingPeriod = HoldingPeriodCondition(
            _proxy(
                address(new HoldingPeriodCondition()),
                abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), HOLD_PERIOD))
            )
        );
        rule144Disclosure = Rule144DisclosureCondition(
            _proxy(
                address(new Rule144DisclosureCondition()),
                abi.encodeCall(Rule144DisclosureCondition.initialize, (address(auth), DISCLOSURE_MAX_AGE))
            )
        );
        section4a7 = Section4a7DisclosureCondition(
            _proxy(
                address(new Section4a7DisclosureCondition()),
                abi.encodeCall(
                    Section4a7DisclosureCondition.initialize, (address(auth), address(registry), DISCLOSURE_MAX_AGE)
                )
            )
        );
        accredited = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(
                    LexChexBadgeKindCondition.initialize, (address(auth), address(badge), K_ACCREDITED, false)
                )
            )
        );
        legalOpinion = LegalOpinionCondition(
            _proxy(
                address(new LegalOpinionCondition()), abi.encodeCall(LegalOpinionCondition.initialize, (address(auth)))
            )
        );
        regS = RegSDistributionComplianceCondition(
            _proxy(
                address(new RegSDistributionComplianceCondition()),
                abi.encodeCall(RegSDistributionComplianceCondition.initialize, (address(auth)))
            )
        );
        nonUsPerson = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(LexChexBadgeKindCondition.initialize, (address(auth), address(badge), K_NON_US, false))
            )
        );

        settlementDelay = new TimeSettlementPeriodCondition();
        killSwitch = new KillSwitchCondition(metalexAdmin, legionAdmin);
    }

    function _wireConditionLayers() internal {
        address[] memory fundSpecific = new address[](6);
        fundSpecific[0] = address(eligibility);
        fundSpecific[1] = address(spvWhitelist);
        fundSpecific[2] = address(blueSky);
        fundSpecific[3] = address(cfius);
        fundSpecific[4] = address(holderCap);
        fundSpecific[5] = address(gpApproval);
        dm.setSpvThresholdConditions(fundSpecific);

        dm.setPathwayThresholdConditions(
            ExemptionPathway.RULE_144, _pair(address(holdingPeriod), address(rule144Disclosure)), true
        );
        dm.setPathwayThresholdConditions(
            ExemptionPathway.SECTION_4A7, _pair(address(section4a7), address(accredited)), true
        );
        dm.setPathwayThresholdConditions(
            ExemptionPathway.SECTION_4A1HALF, _pair(address(legalOpinion), address(accredited)), true
        );
        dm.setPathwayThresholdConditions(
            ExemptionPathway.REGULATION_S, _pair(address(regS), address(nonUsPerson)), true
        );

        dm.setClosingConditions(_pair(address(settlementDelay), address(killSwitch)));
    }

    function _pair(address a, address b) internal pure returns (address[] memory set) {
        set = new address[](2);
        set[0] = a;
        set[1] = b;
    }

    function _configureConditions() internal {
        eligibility.setClearance(address(corp), seller, true);
        eligibility.setClearance(address(corp), buyer, true);
        eligibility.setClearance(address(corp), offshoreBuyer, true);

        holderCap.setConfig(address(corp), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false);

        // No Martin Act registration, so New York blocks by default; the rest is the usual list for a fund
        // expecting only Section 4(a)(1/2) and Rule 144 resales.
        blueSky.setMartinActRegistered(address(corp), false);
        blueSky.setStateBlocked(address(corp), bytes2("AL"), true);
        blueSky.setStateBlocked(address(corp), bytes2("KY"), true);
        blueSky.setStateBlocked(address(corp), bytes2("VA"), true);

        cfius.setTidUsBusiness(address(corp), true);
        string[] memory blocked = new string[](2);
        blocked[0] = "CN";
        blocked[1] = "RU";
        cfius.setBlockedJurisdictions(address(corp), blocked);
        // The GP ran the review on the Cayman feeder and recorded the outcome.
        cfius.setCfiusClearance(address(corp), offshoreBuyer, true);

        gpApproval.setApprover(address(dm), gp);
        legalOpinion.setMechanism(address(corp), LegalOpinionCondition.OpinionMechanism.EITHER);
        // Category 3 U.S. equity: a one-year distribution compliance period.
        regS.setRegSConfig(address(corp), 3, uint64(HOLD_PERIOD));
    }

    function _configureFees() internal {
        dmFactory.setPlatformPayable(platformPayable);
        dmFactory.setDefaultFeeRatio(PLATFORM_FEE_BPS);
        dmFactory.setIntegrator(integrator, true, INTEGRATOR_FEE_SHARE_BPS);
    }

    /// @dev Ages the seller's position past the one-year hold, then anchors the disclosure packages so both
    /// are current as of the seasoned date.
    function _seasonPosition() internal {
        vm.warp(block.timestamp + SEASONING);
        rule144Disclosure.setDisclosurePackage(address(corp), SETTLEMENT_URI, uint64(block.timestamp));
        section4a7.setDisclosurePackage(address(corp), SETTLEMENT_URI, uint64(block.timestamp), DISCLOSURE_ACK);
    }

    function _fundBuyers() internal {
        uint256 funding = POSITION_UNITS * PRICE_PER_UNIT * 2;
        paymentToken.mint(buyer, funding);
        paymentToken.mint(offshoreBuyer, funding);
        vm.prank(offshoreBuyer);
        paymentToken.approve(address(dm), type(uint256).max);
    }

    // ── Offer / settlement builders ───────────────────────────────────────────

    function _sellParams(ExemptionPathway pathway, uint256 units, string memory saltSeed)
        internal
        view
        returns (PostOfferParams memory p)
    {
        p = PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(printer),
            tokenId: sellerTokenId,
            units: units,
            paymentToken: address(paymentToken),
            consideration: units * PRICE_PER_UNIT,
            exemptionPathway: pathway,
            validUntil: block.timestamp + 30 days,
            counterpartyRestrictions: bytes(
                "Accredited investors only. No transfer to a competitor of the issuer, or to any person the "
                "governing body has identified as a restricted party, without prior written consent."
            ),
            additionalTerms: bytes(
                "Buyer accedes to the governing documents of the issuer as a holder of record. Any market "
                "stand-off in those documents travels with the interest."
            ),
            integrator: integrator,
            templateId: _offerTemplateId(),
            salt: uint256(keccak256(bytes(saltSeed))),
            globalValues: _globalValues(),
            offerorPartyValues: _sellerPartyValues(),
            offerorAgreementSig: "",
            openEndorsementSig: bytes("sellerEndorsementInBlank"),
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
    }

    function _sellerPartyValues() internal view returns (string[] memory v) {
        v = new string[](4);
        v[0] = "teh investOOOr";
        v[1] = vm.toString(seller);
        v[2] = "Natural person";
        v[3] = ""; // the acknowledgment is the acquirer's to make
    }

    function _buyerPartyValues(address acceptor) internal view returns (string[] memory v) {
        v = new string[](4);
        v[0] = _buyerName(acceptor);
        v[1] = vm.toString(acceptor);
        v[2] = "Entity";
        v[3] = DISCLOSURE_ACK;
    }

    function _buyerName(address acceptor) internal view returns (string memory) {
        return acceptor == offshoreBuyer ? "Blue Harbour Feeder Fund (Cayman) Ltd." : "Meridian Family Office LLC";
    }

    function _acceptParams(bytes32 offerId, uint256 units, ExemptionPathway pathway, address acceptor, uint256 key)
        internal
        view
        returns (AcceptOfferParams memory)
    {
        string[] memory partyValues = _buyerPartyValues(acceptor);
        return AcceptOfferParams({
            offerId: offerId,
            units: units,
            exemptionPathway: pathway,
            buyerName: _buyerName(acceptor),
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: partyValues,
            acceptorAgreementSig: _acceptorSig(offerId, acceptor, key, partyValues),
            openEndorsementSig: ""
        });
    }

    /// @dev Records the per-deal governance artifacts the fund-specific and Section 4(a)(1/2) layers read.
    /// Both are keyed on the offerId, which pre-approves every settlement of that offer.
    function _recordGovernanceArtifacts(bytes32 offerId) internal {
        vm.prank(gp);
        gpApproval.setDealApproval(address(dm), offerId, true);
        legalOpinion.recordGPSignOff(address(dm), offerId);
    }

    // ── Measured steps ────────────────────────────────────────────────────────

    function _measurePost(PostOfferParams memory p) internal returns (bytes32 offerId, uint256 gasUsed) {
        vm.prank(seller);
        uint256 gasStart = gasleft();
        offerId = dm.postOffer(p);
        gasUsed = gasStart - gasleft();
    }

    function _measureAccept(AcceptOfferParams memory a, address acceptor)
        internal
        returns (bytes32 settlementId, uint256 gasUsed)
    {
        vm.prank(acceptor);
        uint256 gasStart = gasleft();
        settlementId = dm.acceptOffer(a);
        gasUsed = gasStart - gasleft();
    }

    function _measureFinalize(bytes32 settlementId) internal returns (uint256 gasUsed) {
        vm.prank(keeper);
        uint256 gasStart = gasleft();
        dm.finalizeSecondaryTradeAgreement(settlementId);
        gasUsed = gasStart - gasleft();
    }

    function _assertUnderLimit(string memory step, uint256 gasUsed) internal pure {
        console2.log(step, gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, string.concat(step, " exceeds 90% of EIP-7825 block gas limit"));
    }

    /// @dev Posts unpinned, elects `pathway` at acceptance, waits out the settlement delay, finalizes.
    function _lifecycle(string memory label, ExemptionPathway pathway, address acceptor, uint256 acceptorKey) internal {
        console2.log(label);

        PostOfferParams memory p = _sellParams(ExemptionPathway.NONE, POSITION_UNITS, label);
        (bytes32 offerId, uint256 postGas) = _measurePost(p);
        _assertUnderLimit("  postOffer gas:", postGas);

        _recordGovernanceArtifacts(offerId);

        AcceptOfferParams memory a = _acceptParams(offerId, POSITION_UNITS, pathway, acceptor, acceptorKey);
        (bytes32 settlementId, uint256 acceptGas) = _measureAccept(a, acceptor);
        _assertUnderLimit("  acceptOffer gas:", acceptGas);

        // The intervention window TimeSettlementPeriodCondition enforces between acceptance and settlement.
        vm.warp(block.timestamp + settlementDelay.DEFAULT_DELAY() + 1);

        uint256 finalizeGas = _measureFinalize(settlementId);
        _assertUnderLimit("  finalize gas:", finalizeGas);

        // The lot really moved: the seller's fully-sold token is voided and the buyer holds a fresh one.
        assertTrue(printer.isVoided(sellerTokenId), "fully-sold seller token is voided");
        assertTrue(printer.isLegalHolder(acceptor), "acquirer is on the register");
        // Both fee legs ran, so the finalize measurement includes them.
        assertGt(paymentToken.balanceOf(platformPayable), 0, "platform took its fee");
        assertGt(paymentToken.balanceOf(integrator), 0, "integrator took its share");
    }

    // ── Shared tests, run against whichever printer the subclass builds ───────

    /// @notice Rule 144 resale to a U.S. accredited family office. The seasoned position clears the
    ///         one-year hold and the issuer's 144(c)(2) package is current.
    function test_gasLimit_lifecycle_rule144() public {
        _lifecycle("Rule 144 resale", ExemptionPathway.RULE_144, buyer, buyerKey);
    }

    /// @notice Section 4(a)(7) resale. The acquirer's information-delivery acknowledgment rides on the
    ///         settlement agreement's party values.
    function test_gasLimit_lifecycle_section4a7() public {
        _lifecycle("Section 4(a)(7) resale", ExemptionPathway.SECTION_4A7, buyer, buyerKey);
    }

    /// @notice Section 4(a)(1/2) resale backed by the GP's recorded counsel sign-off.
    function test_gasLimit_lifecycle_section4a1half() public {
        _lifecycle("Section 4(a)(1/2) resale", ExemptionPathway.SECTION_4A1HALF, buyer, buyerKey);
    }

    /// @notice Regulation S resale to the Cayman feeder: attested non-U.S. person, past the Category 3
    ///         distribution compliance period, and CFIUS-cleared by the GP.
    function test_gasLimit_lifecycle_regulationS() public {
        _lifecycle("Regulation S resale", ExemptionPathway.REGULATION_S, offshoreBuyer, offshoreBuyerKey);
    }

    /// @notice Posting pinned to Rule 144 resolves both condition layers at postOffer instead of the
    ///         fund-specific layer alone. HoldingPeriodCondition reads the seller lot there, so this is the
    ///         posting shape that exposes payload size.
    function test_gasLimit_postOffer_pinnedToRule144() public {
        PostOfferParams memory p = _sellParams(ExemptionPathway.RULE_144, POSITION_UNITS, "pinned Rule 144 offer");
        (, uint256 gasUsed) = _measurePost(p);
        _assertUnderLimit("postOffer (pinned Rule 144) gas:", gasUsed);
    }

    /// @notice Two partial fills of one offer. Each lot mints the acquirer its own Ledger Entry Token, so
    ///         settlement cost is per lot, not per offer.
    function test_gasLimit_partialFill_twoLots() public {
        PostOfferParams memory p = _sellParams(ExemptionPathway.NONE, POSITION_UNITS, "partial fill offer");
        (bytes32 offerId, uint256 postGas) = _measurePost(p);
        _assertUnderLimit("partial fill / postOffer gas:", postGas);

        _recordGovernanceArtifacts(offerId);

        AcceptOfferParams memory first =
            _acceptParams(offerId, FIRST_LOT_UNITS, ExemptionPathway.RULE_144, buyer, buyerKey);
        (bytes32 firstSettlement, uint256 firstAcceptGas) = _measureAccept(first, buyer);
        _assertUnderLimit("partial fill / lot 1 acceptOffer gas:", firstAcceptGas);

        vm.warp(block.timestamp + settlementDelay.DEFAULT_DELAY() + 1);
        _assertUnderLimit("partial fill / lot 1 finalize gas:", _measureFinalize(firstSettlement));

        // The seller keeps the balance of the position, so the second lot settles against the same token.
        assertFalse(printer.isVoided(sellerTokenId), "seller keeps the residual position");
        assertEq(
            printer.getActiveCertificateDetails(sellerTokenId).unitsRepresented,
            POSITION_UNITS - FIRST_LOT_UNITS,
            "the residual is the unsold balance"
        );

        AcceptOfferParams memory second =
            _acceptParams(offerId, POSITION_UNITS - FIRST_LOT_UNITS, ExemptionPathway.RULE_144, buyer, buyerKey);
        (bytes32 secondSettlement, uint256 secondAcceptGas) = _measureAccept(second, buyer);
        _assertUnderLimit("partial fill / lot 2 acceptOffer gas:", secondAcceptGas);

        vm.warp(block.timestamp + settlementDelay.DEFAULT_DELAY() + 1);
        _assertUnderLimit("partial fill / lot 2 finalize gas:", _measureFinalize(secondSettlement));

        assertTrue(printer.isVoided(sellerTokenId), "the exhausted seller token is voided");
    }

    /// @notice Reports the two per-lot data sizes that separate the baselines: the certificate payload and
    ///         the printer's legend block.
    function test_report_perLotDataSize() public view {
        uint256 payload = printer.getActiveCertificateDetails(sellerTokenId).extensionData.length;
        // Every lot is minted with a copy of this block, so its size is a per-lot cost.
        string[] memory legends = LedgerEntryToken(address(printer)).defaultLegend();
        uint256 legendBytes;
        for (uint256 i = 0; i < legends.length; i++) {
            legendBytes += bytes(legends[i]).length;
        }
        console2.log("cert payload bytes:", payload);
        console2.log("legend count:", legends.length);
        console2.log("legend bytes:", legendBytes);
    }
}
