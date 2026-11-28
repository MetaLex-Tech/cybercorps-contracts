// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {DealManager} from "../src/DealManager.sol";
import {IDealManagerStorage} from "../src/interfaces/IDealManagerStorage.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";

/// @notice Behavioral regression and recovery suite for Issue #218 on `DealManager.proposeDeal` two-step escrow.
/// @dev Verifies against real protocol contracts (zero mocks for contracts under test) that:
///      1. After `DealManager.proposeDeal` and `DealManager.signDealAndPay`, direct `CyberAgreementRegistry.signContract`
///         by `parties[0]` reverts with `NotFinalizer()`, enforcing finalizer-routed signing (`DealManager.signDeal`).
///      2. `DealManager.signAndFinalizeDeal` cannot substitute once `signDealAndPay` has funded escrow (`DealNotPending`).
///      3. Investor funds locked in `DealManager` escrow remain recoverable via `DealManager.voidExpiredDeal`.
contract Issue218RegistryRegressionsTest is Test {
    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;

    address internal admin;
    address internal officer;
    uint256 internal officerKey;
    address internal investor;
    uint256 internal investorKey;
    address internal companyPayable;

    address internal issuance;
    address internal dealManager;
    address internal certPrinter;
    MockPaymentToken internal paymentToken;

    bytes32 internal constant DEAL_TEMPLATE_ID = keccak256("Issue218.PrimaryDealTemplate");
    string internal constant DEAL_URI = "ipfs://issue-218-primary-deal";

    function setUp() public {
        admin = makeAddr("issue218-admin");
        (officer, officerKey) = makeAddrAndKey("issue218-officer");
        (investor, investorKey) = makeAddrAndKey("issue218-investor");
        companyPayable = makeAddr("issue218-company-payable");

        (registry, corpFactory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(admin);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";
        vm.prank(admin);
        registry.createTemplate(DEAL_TEMPLATE_ID, "Primary SPA", DEAL_URI, globalFields, partyFields);

        (,, issuance, dealManager,) =
            CyberCorpHelper.deployCorp(corpFactory, "Issue 218 Corp", companyPayable, officer);

        vm.prank(officer);
        certPrinter = IssuanceManager(issuance).createCertPrinter(
            new string[](0),
            "Common Stock",
            "CS",
            "ipfs://class-terms",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0),
            bytes("")
        );

        paymentToken = new MockPaymentToken();
        paymentToken.transfer(investor, 100_000e6);
    }

    function test_Case3_ProposeDealTwoStepEscrow_DirectRegistrySignRevertsNotFinalizer_AndVoidRefundWorks() public {
        address[] memory printers = new address[](1);
        printers[0] = certPrinter;

        CertificateDetails[] memory certs = new CertificateDetails[](1);
        certs[0] = CertificateDetails({
            signingOfficerName: "Alice Founder",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 25_000,
            issuerUSDValuationAtTimeOfInvestment: 5_000_000,
            unitsRepresented: 25_000,
            legalDetails: "",
            extensionData: bytes("")
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "25000000000";

        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Issue 218 Corp";
        partyValues[0][1] = "Issuer";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Bob Investor";
        partyValues[1][1] = "Purchaser";

        uint256 price = 25_000e6;
        uint256 expiry = block.timestamp + 7 days;

        vm.prank(officer);
        (bytes32 agreementId,) = DealManager(dealManager).proposeDeal(
            printers,
            address(paymentToken),
            price,
            DEAL_TEMPLATE_ID,
            1,
            globalValues,
            parties,
            certs,
            partyValues,
            new address[](0),
            bytes32(0),
            expiry
        );
        assertFalse(registry.hasSigned(agreementId, officer), "proposeDeal leaves parties[0] unsigned");

        string[] memory globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";

        bytes memory investorSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            investorKey
        );

        uint256 investorBalanceBefore = paymentToken.balanceOf(investor);

        vm.startPrank(investor);
        paymentToken.approve(dealManager, price);
        DealManager(dealManager).signDealAndPay(
            investor,
            agreementId,
            investorSig,
            partyValues[1],
            false,
            "Bob Investor",
            ""
        );
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(dealManager), price, "investor payment is locked in DealManager escrow");

        bytes memory officerSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            officerKey
        );

        // Direct registry signing by `parties[0]` is refused by `NotFinalizer()`; proposer must use `DealManager.signDeal`.
        vm.prank(officer);
        vm.expectRevert(CyberAgreementRegistry.NotFinalizer.selector);
        registry.signContract(agreementId, partyValues[0], officerSig, false, "");

        // `signAndFinalizeDeal` is also rejected once `signDealAndPay` moved escrow to `PAID`.
        vm.prank(officer);
        vm.expectRevert(IDealManagerStorage.DealNotPending.selector);
        DealManager(dealManager).signAndFinalizeDeal(
            officer, agreementId, partyValues[0], officerSig, false, "Alice Founder", ""
        );

        // Escrowed buyer payment remains recoverable after expiry via `voidExpiredDeal`.
        vm.warp(expiry + 1);
        bytes memory voidSig = CyberAgreementUtils.signVoidAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            agreementId,
            investor,
            investorKey
        );
        vm.prank(investor);
        DealManager(dealManager).voidExpiredDeal(agreementId, investor, voidSig);

        assertTrue(registry.isVoided(agreementId), "expired deal is voided");
        assertEq(paymentToken.balanceOf(investor), investorBalanceBefore, "investor payment is refunded in full");
    }
}
