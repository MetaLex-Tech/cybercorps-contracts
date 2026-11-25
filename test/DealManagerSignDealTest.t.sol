// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {IDealManagerStorage} from "../src/interfaces/IDealManagerStorage.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {LexScrowStorage} from "../src/storage/LexScrowStorage.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Two-step primary deal: `proposeDeal` leaves the company unsigned, the investor pays, then the
/// company signs through `DealManager.signDeal` and the deal finalizes. Real registry, factories and company.
contract DealManagerSignDealTest is Test {
    CyberAgreementRegistry internal registry;

    address internal officer;
    uint256 internal officerKey;
    address internal investor;
    uint256 internal investorKey;
    address internal companyPayable;

    address internal dealManager;
    address internal certPrinter;
    MockERC20 internal paymentToken;

    bytes32 internal constant TEMPLATE_ID = keccak256("DealManagerSignDealTest.Template");
    string internal constant TEMPLATE_URI = "ipfs://deal-manager-sign-deal";
    uint256 internal constant PRICE = 25_000e9;

    string[] internal globalFields;
    string[] internal partyFields;
    string[] internal globalValues;
    address[] internal parties;
    string[][] internal partyValues;

    function setUp() public {
        address admin = makeAddr("admin");
        (officer, officerKey) = makeAddrAndKey("officer");
        (investor, investorKey) = makeAddrAndKey("investor");
        companyPayable = makeAddr("companyPayable");

        CyberCorpFactory corpFactory;
        (registry, corpFactory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(admin);

        globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";
        vm.prank(admin);
        registry.createTemplate(TEMPLATE_ID, "Primary SPA", TEMPLATE_URI, globalFields, partyFields);

        address issuance;
        (,, issuance, dealManager,) = CyberCorpHelper.deployCorp(corpFactory, "SignDeal Corp", companyPayable, officer);

        vm.prank(officer);
        certPrinter = IssuanceManager(issuance)
            .createCertPrinter(
                new string[](0),
                "Common Stock",
                "CS",
                "ipfs://class-terms",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            );

        paymentToken = new MockERC20("Mock USD", "MUSD", 9);
        paymentToken.mint(investor, PRICE);

        globalValues = new string[](1);
        globalValues[0] = "25000";
        parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "SignDeal Corp";
        partyValues[0][1] = "Issuer";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Bob Investor";
        partyValues[1][1] = "Purchaser";
    }

    function test_signDeal_FirstPartySignsAfterInvestorPays() public {
        (bytes32 agreementId, uint256 certId) = _proposeDeal();
        _investorSignsAndPays(agreementId);

        bytes memory officerSig = _sign(agreementId, partyValues[0], officerKey);

        // The registry refuses a direct signature on a finalizer agreement.
        vm.prank(officer);
        vm.expectRevert(CyberAgreementRegistry.NotFinalizer.selector);
        registry.signContract(agreementId, partyValues[0], officerSig, false, "");

        vm.prank(officer);
        DealManager(dealManager).signDeal(officer, agreementId, partyValues[0], officerSig, "");
        assertTrue(registry.hasSigned(agreementId, officer), "DealManager records the company signature");

        vm.prank(officer);
        DealManager(dealManager).finalizeDeal(agreementId);

        assertTrue(registry.isFinalized(agreementId), "agreement finalizes");
        assertEq(LedgerEntryToken(certPrinter).ownerOf(certId), investor, "investor receives the LET");
        assertGt(paymentToken.balanceOf(companyPayable), 0, "company receives the payment");
    }

    function test_signDeal_FirstPartySignsBeforeInvestorPays() public {
        (bytes32 agreementId, uint256 certId) = _proposeDeal();
        bytes memory officerSig = _sign(agreementId, partyValues[0], officerKey);

        // Anyone can relay the company signature.
        vm.prank(makeAddr("relayer"));
        DealManager(dealManager).signDeal(officer, agreementId, partyValues[0], officerSig, "");

        bytes memory investorSig = _sign(agreementId, partyValues[1], investorKey);
        vm.startPrank(investor);
        paymentToken.approve(dealManager, PRICE);
        DealManager(dealManager)
            .signAndFinalizeDeal(investor, agreementId, partyValues[1], investorSig, false, "Bob Investor", "");
        vm.stopPrank();

        assertEq(LedgerEntryToken(certPrinter).ownerOf(certId), investor, "investor receives the LET");
    }

    function test_RevertIf_signAndFinalizeDeal_FirstPartyAfterInvestorPays() public {
        (bytes32 agreementId,) = _proposeDeal();
        _investorSignsAndPays(agreementId);
        bytes memory officerSig = _sign(agreementId, partyValues[0], officerKey);

        vm.prank(officer);
        vm.expectRevert(IDealManagerStorage.DealNotPending.selector);
        DealManager(dealManager).signAndFinalizeDeal(officer, agreementId, partyValues[0], officerSig, false, "", "");
    }

    function test_RevertIf_signDeal_SignerNotFirstParty() public {
        (bytes32 agreementId,) = _proposeDeal();
        bytes memory investorSig = _sign(agreementId, partyValues[1], investorKey);

        vm.prank(investor);
        vm.expectRevert(IDealManagerStorage.SignerNotFirstParty.selector);
        DealManager(dealManager).signDeal(investor, agreementId, partyValues[1], investorSig, "");
    }

    function test_RevertIf_signDeal_SignatureFromOtherKey() public {
        (bytes32 agreementId,) = _proposeDeal();
        bytes memory wrongSig = _sign(agreementId, partyValues[0], investorKey);

        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        DealManager(dealManager).signDeal(officer, agreementId, partyValues[0], wrongSig, "");
    }

    function test_RevertIf_signDeal_NoPrimaryEscrow() public {
        bytes32 unknownId = keccak256("unknown");
        bytes memory officerSig = _sign(unknownId, partyValues[0], officerKey);

        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        DealManager(dealManager).signDeal(officer, unknownId, partyValues[0], officerSig, "");
    }

    function _proposeDeal() internal returns (bytes32 agreementId, uint256 certId) {
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

        vm.prank(officer);
        uint256[] memory certIds;
        (agreementId, certIds) = DealManager(dealManager)
            .proposeDeal(
                printers,
                address(paymentToken),
                PRICE,
                TEMPLATE_ID,
                1,
                globalValues,
                parties,
                certs,
                partyValues,
                new address[](0),
                bytes32(0),
                block.timestamp + 7 days
            );
        certId = certIds[0];
        assertFalse(registry.hasSigned(agreementId, officer), "proposeDeal leaves the company unsigned");
    }

    function _investorSignsAndPays(bytes32 agreementId) internal {
        bytes memory investorSig = _sign(agreementId, partyValues[1], investorKey);
        vm.startPrank(investor);
        paymentToken.approve(dealManager, PRICE);
        DealManager(dealManager)
            .signDealAndPay(investor, agreementId, investorSig, partyValues[1], false, "Bob Investor", "");
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(dealManager), PRICE, "payment is in escrow");
    }

    function _sign(bytes32 agreementId, string[] memory values, uint256 key) internal returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            TEMPLATE_URI,
            globalFields,
            partyFields,
            globalValues,
            values,
            key
        );
    }
}
