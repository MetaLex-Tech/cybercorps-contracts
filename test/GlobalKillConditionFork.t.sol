// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {GlobalKillCondition} from "../src/libs/conditions/GlobalKillCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {CertificateDetails, Endorsement} from "../src/storage/CyberCertPrinterStorage.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";


/// @notice Integration test: GlobalKillCondition wired into DealManager (ICondition),
///         CyberScrip (transfer hook), and CyberCertPrinter (transfer hook).
///         One combined test raises and lowers the kill switch and verifies all three
///         systems block then resume.
///
///         Run with:
///   forge test --via-ir --optimize --optimizer-runs 15 --use solc:0.8.28 \
///     --fork-url <rpc-url> --mc GlobalKillConditionForkTest
contract GlobalKillConditionForkTest is Test {
    uint256 internal constant PAYMENT = 1_000_000e6;
    uint256 internal constant SCRIP_AMOUNT = 1000 ether;

    bytes32 internal constant TEMPLATE_ID = bytes32(uint256(88_888_888));
    uint256 internal constant AGREEMENT_SALT = 77_777_777;
    string internal constant LEGAL_URI = "ipfs://kill-condition-integration-test";

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal factory;
    BorgAuth internal killAuth;
    GlobalKillCondition internal kill;

    address internal founder;
    uint256 internal founderPk;
    address internal investor;
    uint256 internal investorPk;
    address internal recipient;

    address internal issuanceManagerAddr;
    address internal dealManagerAddr;
    address internal certPrinterAddr;
    bytes32 internal agreementId;
    uint256 internal dealCertId;
    uint256 internal transferCertId;
    CyberScrip internal scrip;

    function setUp() public {
        DeploymentConstants.CoreDeployment memory dep = DeploymentConstants.coreV2(block.chainid);
        registry = CyberAgreementRegistry(dep.cyberAgreementRegistry);
        factory = CyberCorpFactory(dep.cyberCorpFactory);

        (founder, founderPk) = makeAddrAndKey("founder");
        (investor, investorPk) = makeAddrAndKey("investor");
        recipient = makeAddr("recipient");

        // investor address may have code on the forked chain; clear it so safe ERC721 mints succeed
        vm.etch(investor, "");

        killAuth = new BorgAuth(founder);
        kill = new GlobalKillCondition(address(killAuth));

        _createTemplate(dep.metalexSafe);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        string[] memory founderValues = new string[](1);
        founderValues[0] = "Founder Party Value";
        string[] memory investorValues = new string[](1);
        investorValues[0] = "Investor Party Value";

        address[] memory parties = new address[](2);
        parties[0] = founder;
        parties[1] = investor;

        bytes32 contractId = keccak256(abi.encode(TEMPLATE_ID, AGREEMENT_SALT, globalValues, parties));

        bytes memory founderSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            contractId, LEGAL_URI, globalFields, partyFields, globalValues, founderValues, founderPk
        );

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCorpFactory.CyberCertData[] memory certData = new CyberCorpFactory.CyberCertData[](1);
        certData[0] = CyberCorpFactory.CyberCertData({
            name: "SAFE",
            symbol: "SAFE",
            uri: LEGAL_URI,
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        CertificateDetails[] memory details = new CertificateDetails[](1);
        details[0] = CertificateDetails({
            signingOfficerName: "Founder",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: PAYMENT / 1e6,
            issuerUSDValuationAtTimeOfInvestment: 10_000_000,
            unitsRepresented: 0,
            legalDetails: "SAFE Agreement",
            extensionData: ""
        });

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = founderValues;
        partyValues[1] = investorValues;

        address[] memory conditions = new address[](1);
        conditions[0] = address(kill);

        address[] memory certPrinters;
        bytes32 id;
        uint256[] memory certIds;

        vm.prank(founder);
        (
            ,
            ,
            issuanceManagerAddr,
            dealManagerAddr,
            ,
            certPrinters,
            id,
            certIds
        ) = factory.deployCyberCorpAndCreateOffer(
            AGREEMENT_SALT,
            "Kill Test Corp",
            "Delaware C-Corp",
            "DE",
            "kill@test.example",
            "Arbitration",
            founder,
            CompanyOfficer({eoa: founder, name: "Founder", contact: "f@test.example", title: "CEO"}),
            certData,
            TEMPLATE_ID,
            globalValues,
            parties,
            PAYMENT,
            partyValues,
            founderSig,
            details,
            conditions,
            bytes32(0),
            block.timestamp + 7 days
        );

        certPrinterAddr = certPrinters[0];
        agreementId = id;
        dealCertId = certIds[0];

        bytes memory investorSig = CyberAgreementUtils.signAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.SIGNATUREDATA_TYPEHASH(),
            contractId, LEGAL_URI, globalFields, partyFields, globalValues, investorValues, investorPk
        );

        address stable = factory.stable();
        deal(stable, investor, PAYMENT);

        vm.startPrank(investor);
        IERC20(stable).approve(dealManagerAddr, PAYMENT);
        IDealManager(dealManagerAddr).signDealAndPay(investor, agreementId, investorSig, investorValues, false, "Investor", "");
        vm.stopPrank();

        IIssuanceManager im = IIssuanceManager(issuanceManagerAddr);

        // Deploy scrip with kill as transfer hook
        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](1);
        hooks[0] = ITransferRestrictionHook(address(kill));
        ICondition[] memory emptyConditions = new ICondition[](0);
        uint256[] memory emptyIds = new uint256[](0);

        vm.prank(founder);
        scrip = CyberScrip(im.deployCyberScrip(
            certPrinterAddr, hooks, emptyConditions, emptyConditions,
            0, 1, 1, emptyIds, false, true, true, true
        ));

        CertificateDetails memory certDetail = CertificateDetails({
            signingOfficerName: "Founder",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10_000_000,
            unitsRepresented: SCRIP_AMOUNT,
            legalDetails: "Cert",
            extensionData: ""
        });

        // Seed investor's scrip balance directly (older deployed scrip has different mint access)
        deal(address(scrip), investor, SCRIP_AMOUNT);

        // Mint cert for the cert-transfer test
        vm.prank(founder);
        transferCertId = im.createCertAndAssign(certPrinterAddr, investor, certDetail);

        // Endorsement for the transfer cert → recipient (checked after kill is lowered)
        vm.prank(investor);
        CyberCertPrinter(certPrinterAddr).addEndorsement(
            transferCertId,
            Endorsement({
                endorser: investor,
                timestamp: block.timestamp,
                signatureHash: "",
                registry: address(0),
                agreementId: bytes32(0),
                endorsee: recipient,
                endorseeName: "Recipient"
            })
        );

        // Enable cert transfers (otherwise TokenNotTransferable fires before the kill hook)
        vm.prank(founder);
        im.setGlobalTransferable(certPrinterAddr, true);

        // Wire kill as the global restriction hook
        vm.prank(founder);
        im.setGlobalRestrictionHook(certPrinterAddr, address(kill));
    }

    function test_kill_blocksAllThreeSystems() public {
        vm.prank(founder);
        kill.raiseKill();

        // Deal finalization blocked by kill condition
        vm.expectRevert(DealManager.AgreementConditionsNotMet.selector);
        vm.prank(investor);
        IDealManager(dealManagerAddr).finalizeDeal(agreementId);

        // Scrip transfer blocked by kill hook
        vm.expectRevert(abi.encodeWithSignature("RestrictedTransfer(string)", "Global kill switch active"));
        vm.prank(investor);
        scrip.transfer(recipient, 1e6);

        // Cert transfer blocked by kill hook
        vm.expectRevert(abi.encodeWithSignature("TransferRestricted(string)", "Global kill switch active"));
        vm.prank(investor);
        CyberCertPrinter(certPrinterAddr).transferFrom(investor, recipient, transferCertId);

        vm.prank(founder);
        kill.lowerKill();

        // Deal finalization succeeds after kill lowered
        vm.prank(investor);
        IDealManager(dealManagerAddr).finalizeDeal(agreementId);
        assertEq(CyberCertPrinter(certPrinterAddr).ownerOf(dealCertId), investor);

        // Scrip transfer succeeds after kill lowered
        vm.prank(investor);
        scrip.transfer(recipient, 1e6);
        assertGt(scrip.balanceOf(recipient), 0);

        // Cert transfer succeeds after kill lowered
        vm.prank(investor);
        CyberCertPrinter(certPrinterAddr).transferFrom(investor, recipient, transferCertId);
        assertEq(CyberCertPrinter(certPrinterAddr).ownerOf(transferCertId), recipient);
    }

    function _createTemplate(address metalexSafe) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        vm.prank(metalexSafe);
        registry.createTemplate(TEMPLATE_ID, "Kill Condition Test", LEGAL_URI, globalFields, partyFields);
    }
}
