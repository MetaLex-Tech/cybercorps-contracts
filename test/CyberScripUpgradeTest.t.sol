// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";

import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Round, RoundLib} from "../src/libs/RoundLib.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {IssuerApprovalRecertificationCondition} from "../src/libs/conditions/IssuerApprovalRecertificationCondition.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";

import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";

interface IUUPS {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract SelectorCondition is ICondition {
    address public expectedContract;
    bytes4 public expectedSelector;
    bytes32 public expectedDataHash;

    constructor(
        address _contract,
        bytes4 _selector,
        bytes memory data
    ) {
        expectedContract = _contract;
        expectedSelector = _selector;
        expectedDataHash = keccak256(data);
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool) {
        return
            _contract == expectedContract &&
            _functionSignature == expectedSelector &&
            keccak256(data) == expectedDataHash;
    }
}

contract CyberScripUpgradeTest is Test {
    using ERC1967ProxyLib for address;
    using RoundLib for Round;

    string internal constant RPC_ENV_VAR = "FORK_RPC_URL";
    address internal constant METALEX_SAFE =
        0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 internal constant ESCROWEDSIGNATUREDATA_TYPEHASH =
        keccak256(
            "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
        );

    DeploymentConstants.CoreDeployment internal deployment;

    uint256 internal companyOwnerPk;
    uint256 internal investorPk;
    uint256 internal otherInvestorPk;
    address internal companyOwner;
    address internal investor;
    address internal otherInvestor;

    function setUp() public {

        deployment = DeploymentConstants.coreV2(block.chainid);

        // deterministic test users
        companyOwnerPk = uint256(keccak256("cyberscrip-upgrade-company-owner"));
        investorPk = uint256(keccak256("cyberscrip-upgrade-investor"));
        otherInvestorPk = uint256(keccak256("cyberscrip-upgrade-other-investor"));
        companyOwner = vm.addr(companyOwnerPk);
        investor = vm.addr(investorPk);
        otherInvestor = vm.addr(otherInvestorPk);
    }

    function test_UpgradeCyberScrip_And_InvestorRoundFlow() public {
        CyberCorpFactory corpFactory = CyberCorpFactory(
            deployment.cyberCorpFactory
        );
        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );
        RoundManagerFactory rmFactory = RoundManagerFactory(
            deployment.roundManagerFactory
        );
        CyberCorpSingleFactory corpSingleFactory = CyberCorpSingleFactory(
            deployment.cyberCorpSingleFactory
        );
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            deployment.issuanceManagerFactory
        );

        address stable = corpFactory.stable();
        assertTrue(stable != address(0), "stable token not configured");

        bytes32 templateId = bytes32(
            uint256(keccak256("cyberscrip-upgrade-test-template"))
        );

        vm.prank(METALEX_SAFE);
        registry.createTemplate(
            templateId,
            "CyberScrip upgrade test template",
            "ipfs://cyberscrip-upgrade-template",
            _strings("purchaseAmount", "valuation"),
            _strings("name", "jurisdiction")
        );

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: companyOwner,
            name: "Officer One",
            contact: "officer@test.local",
            title: "CEO"
        });

        uint256 userSalt = uint256(keccak256("cyberscrip-upgrade-corp-salt"));
        bytes32 corpSalt = keccak256(abi.encodePacked(userSalt));

        uint256 raiseCap = 100_000e6;
        uint256 minTicket = 100e6;
        uint256 maxTicket = 2_000e6;
        uint256 startTime = block.timestamp - 1;
        uint256 endTime = block.timestamp + 7 days;
        uint256 pricePerUnit = 1e18; // USD (18 decimals)
        uint256 valuation = 5_000_000e18;

        (bytes memory escrowedSignature, ) = _computeEscrowSignature(
            rmFactory.computeRoundManagerAddress(corpSalt),
            SecuritySeries.SeriesA,
            raiseCap,
            minTicket,
            maxTicket,
            RoundType.FCFS,
            startTime,
            endTime,
            templateId,
            stable,
            pricePerUnit,
            valuation,
            companyOwnerPk,
            corpSingleFactory.computeCyberCorpSingleAddress(corpSalt)
        );

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SAFE",
            symbol: "SAFE",
            uri: "ipfs://safe-cert",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: new string[](0)
        });

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "legal-details";
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";
        string[] memory roundPartyValues = _strings("Officer One", "US");

        (
            address corp,
            address auth,
            address issuanceManagerAddr,
            ,
            address roundManagerAddr,
            bytes32 roundId
        ) = _deployCorpAndRound(
                corpFactory,
                userSalt,
                officer,
                legalDetails,
                extensionData,
                certData,
                templateId,
                stable,
                pricePerUnit,
                valuation,
                roundPartyValues,
                escrowedSignature,
                raiseCap,
                minTicket,
                maxTicket,
                startTime,
                endTime
            );

        // Newly deployed corp AUTH owner is the factory by default. Grant owner to companyOwner for IM owner-gated ops.
        vm.prank(deployment.cyberCorpFactory);
        BorgAuth(auth).updateRole(companyOwner, 99);

        IssuanceManager issuanceManager = IssuanceManager(issuanceManagerAddr);
        _upgradeCoreStackForCorp(corp, issuanceManager, corpSingleFactory, imFactory);
        roundId = _recreateRoundAfterUpgrade(
            roundManagerAddr,
            SecuritySeries.SeriesA,
            RoundType.FCFS,
            templateId,
            stable,
            pricePerUnit,
            valuation,
            raiseCap,
            minTicket,
            maxTicket,
            startTime,
            endTime,
            officer,
            legalDetails,
            extensionData,
            roundPartyValues,
            escrowedSignature,
            certData
        );

        // Investor flow: submit EOI and auto-allocate (FCFS).
        deal(stable, investor, maxTicket);
        vm.prank(investor);
        IERC20(stable).approve(roundManagerAddr, maxTicket);

        EOI memory eoi = EOI({
            name: "Investor A",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.local",
            minAmount: minTicket,
            maxAmount: minTicket,
            expiry: block.timestamp + 2 days,
            naturalPerson: true,
            lexchexDetails: _emptyLex()
        });

        string[] memory globalValues = _strings("100", "5000000");
        string[] memory investorPartyValues = _strings("Investor A", "US");
        bytes memory investorSignature = _computeEOISignature(
            registry,
            templateId,
            userSalt,
            globalValues,
            investorPartyValues,
            companyOwner,
            investorPk
        );

        vm.prank(investor);
        RoundManager(roundManagerAddr).submitEOI(
            roundId,
            eoi,
            globalValues,
            investorPartyValues,
            investorSignature,
            userSalt,
            new address[](0),
            bytes32(0)
        );

        assertGt(
            RoundManager(roundManagerAddr).getRound(roundId).raised,
            0,
            "round should have raised capital"
        );

        // After allocation, issuer enables scrip for this certificate class.
        address certPrinter = RoundManager(roundManagerAddr).getRound(roundId)
            .certPrinter[0];
        assertEq(IERC721(certPrinter).ownerOf(0), investor, "investor should own cert 0");

        ITransferRestrictionHook[] memory noHooks = new ITransferRestrictionHook[](
            0
        );
        ICondition[] memory noConditions = new ICondition[](0);
        uint256[] memory noWhitelist = new uint256[](0);

        vm.prank(companyOwner);
        address scrip = issuanceManager.deployCyberScrip(
            certPrinter,
            noHooks,
            noConditions,
            noConditions,
            0, // no minimum to re-certify
            1, // ratio numerator
            1, // ratio denominator
            noWhitelist,
            false,
            false,
            false,
            false
        );

        uint256 unit = 1e18; // one cert unit in this round setup
        assertEq(IERC20(scrip).balanceOf(investor), 0, "initial scrip balance");

        // Investor scripifies a portion of the certificate.
        vm.prank(investor);
        issuanceManager.scripifyCert(certPrinter, 0, unit, address(0));
        assertEq(
            IERC20(scrip).balanceOf(investor),
            unit,
            "scrip balance after scripify"
        );

        // Investor converts scrip back to a certificate.
        vm.prank(investor);
        issuanceManager.convertScripToCert(certPrinter, unit);
        assertEq(
            IERC20(scrip).balanceOf(investor),
            0,
            "scrip balance after recertify"
        );
        assertEq(
            IERC721(certPrinter).balanceOf(investor),
            1,
            "investor should hold original cert"
        );

        assertTrue(corp != address(0), "corp should be deployed");
    }

    function test_PostUpgrade_ConversionLifecycleAndRuntimeUpdates() public {
        IssuanceManager issuanceManager = _setupUpgradedIssuanceManager();
        ICyberCertPrinter certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Lifecycle Cert",
            "LCERT"
        );
        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            75
        );

        uint256[] memory whitelistIds = new uint256[](1);
        whitelistIds[0] = certId;
        vm.prank(companyOwner);
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            50,
            3,
            2,
            whitelistIds,
            true,
            true,
            true,
            true
        );

        (uint256 initialNum, uint256 initialDen) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(initialNum, 3);
        assertEq(initialDen, 2);
        assertEq(issuanceManager.getScripToCertMinimum(address(certPrinter)), 50);
        assertTrue(issuanceManager.getScripifyWhitelistEnabled(address(certPrinter)));
        assertTrue(issuanceManager.isScripifyWhitelisted(address(certPrinter), certId));

        vm.prank(companyOwner);
        issuanceManager.setScripRatio(address(certPrinter), 4, 1);
        vm.prank(companyOwner);
        issuanceManager.setScripToCertMinimum(address(certPrinter), 40);
        vm.prank(companyOwner);
        issuanceManager.setScripifyWhitelistEnabled(address(certPrinter), false);

        uint256[] memory removeIds = new uint256[](1);
        removeIds[0] = certId;
        vm.prank(companyOwner);
        issuanceManager.removeScripifyWhitelistIds(address(certPrinter), removeIds);

        uint256[] memory addIds = new uint256[](2);
        addIds[0] = certId;
        addIds[1] = certId + 1;
        vm.prank(companyOwner);
        issuanceManager.addScripifyWhitelistIds(address(certPrinter), addIds);

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 40);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 39);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 40);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_PostUpgrade_ConversionGatesAndConditions() public {
        IssuanceManager issuanceManager = _setupUpgradedIssuanceManager();
        ICyberCertPrinter certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Guard Cert",
            "GCERT"
        );

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripifiedCertNotAllowed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 1);

        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(
            new SelectorCondition(
                address(certPrinter),
                IssuanceManager.convertScripToCert.selector,
                abi.encode(uint256(150), investor)
            )
        );

        vm.prank(companyOwner);
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            scripToCert,
            90,
            3,
            2,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(address(issuanceManager));
        ICyberScrip(scrip).mint(investor, 200);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 80);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripRatioRemainder.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 100);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 120);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 150);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 50);
    }

    function test_PostUpgrade_ReformsVoidedPath() public {
        IssuanceManager issuanceManager = _setupUpgradedIssuanceManager();
        ICyberCertPrinter certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Voided Cert",
            "VCERT"
        );
        _mintCertAfterUpgrade(issuanceManager, certPrinter, investor, 500);

        vm.prank(companyOwner);
        issuanceManager.voidCertificate(address(certPrinter), 0);
        assertTrue(certPrinter.isVoided(0));

        vm.prank(companyOwner);
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            2,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(address(issuanceManager));
        ICyberScrip(scrip).mint(investor, 20);
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 20);

        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_PostUpgrade_RequiresIssuerApprovalCondition() public {
        IssuanceManager issuanceManager = _setupUpgradedIssuanceManager();
        ICyberCertPrinter certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Approval Cert",
            "APPR"
        );
        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            10
        );

        IssuerApprovalRecertificationCondition condition = new IssuerApprovalRecertificationCondition();
        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(address(condition));

        vm.prank(companyOwner);
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            scripToCert,
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 5, address(0));

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 5);

        vm.prank(otherInvestor);
        vm.expectRevert();
        condition.setInvestorApproval(address(certPrinter), investor, true);

        // Condition approvals require AUTH.ADMIN_ROLE on the cert's issuance manager.
        BorgAuth auth = BorgAuth(issuanceManager.AUTH());
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(companyOwner);
        auth.updateRole(address(this), adminRole);

        condition.setInvestorApproval(address(scrip), investor, true);
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 5);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function _recreateRoundAfterUpgrade(
        address roundManagerAddr,
        SecuritySeries seriesType,
        RoundType roundType,
        bytes32 templateId,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 startTime,
        uint256 endTime,
        CompanyOfficer memory officer,
        string[] memory legalDetails,
        bytes[] memory extensionData,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature,
        CyberCertData[] memory certData
    ) internal returns (bytes32 roundId) {
        Round memory draft = RoundLib
            .draft()
            .setTickets(
                seriesType,
                roundType,
                true,
                true,
                raiseCap,
                minTicket,
                maxTicket,
                paymentToken,
                pricePerUnit,
                valuation,
                startTime,
                endTime
            )
            .setAgreement(
                templateId,
                officer.eoa,
                officer.name,
                officer.title,
                legalDetails,
                roundPartyValues,
                extensionData,
                new address[](0),
                escrowedSignature
            );

        vm.prank(companyOwner);
        roundId = RoundManager(roundManagerAddr).createRound(draft, certData);
    }

    function _upgradeCoreStackForCorp(
        address corp,
        IssuanceManager issuanceManager,
        CyberCorpSingleFactory corpSingleFactory,
        IssuanceManagerFactory imFactory
    ) internal {
        address newCyberCorpImpl = address(new CyberCorp());
        address newIssuanceManagerImpl = address(new IssuanceManager());
        address newCertPrinterImpl = address(new CyberCertPrinter());
        address newScripImpl = address(new CyberScrip());

        vm.startPrank(METALEX_SAFE);
        corpSingleFactory.setRefImplementation(newCyberCorpImpl);
        imFactory.setRefImplementation(newIssuanceManagerImpl);
        imFactory.setCyberCertPrinterRefImplementation(newCertPrinterImpl);
        imFactory.setCyberScripRefImplementation(newScripImpl);
        vm.stopPrank();

        assertEq(
            corpSingleFactory.getRefImplementation(),
            newCyberCorpImpl,
            "CyberCorp factory ref implementation mismatch"
        );
        assertEq(
            imFactory.getRefImplementation(),
            newIssuanceManagerImpl,
            "IssuanceManager factory ref implementation mismatch"
        );
        assertEq(
            imFactory.getCyberCertPrinterRefImplementation(),
            newCertPrinterImpl,
            "CyberCertPrinter factory ref implementation mismatch"
        );
        assertEq(
            imFactory.getCyberScripRefImplementation(),
            newScripImpl,
            "CyberScrip factory ref implementation mismatch"
        );

        address issuanceManagerAddr = address(issuanceManager);
        address oldCyberCorpImpl = corp.getErc1967Implementation();
        address oldIssuanceManagerImpl = issuanceManagerAddr
            .getErc1967Implementation();
        address oldCertPrinterImpl = issuanceManager
            .getCertPrinterBeaconImplementation();
        address oldScripImpl = issuanceManager.getScripBeaconImplementation();

        vm.prank(companyOwner);
        IUUPS(corp).upgradeToAndCall(newCyberCorpImpl, "");
        vm.prank(companyOwner);
        IUUPS(issuanceManagerAddr).upgradeToAndCall(newIssuanceManagerImpl, "");
        vm.prank(companyOwner);
        issuanceManager.upgradeCertPrinterBeaconImplementation(newCertPrinterImpl);
        vm.prank(companyOwner);
        issuanceManager.upgradeScripBeaconImplementation(newScripImpl);

        assertEq(
            corp.getErc1967Implementation(),
            newCyberCorpImpl,
            "CyberCorp implementation not upgraded"
        );
        assertEq(
            issuanceManagerAddr.getErc1967Implementation(),
            newIssuanceManagerImpl,
            "IssuanceManager implementation not upgraded"
        );
        assertEq(
            issuanceManager.getCertPrinterBeaconImplementation(),
            newCertPrinterImpl,
            "CyberCertPrinter beacon implementation not upgraded"
        );
        assertEq(
            issuanceManager.getScripBeaconImplementation(),
            newScripImpl,
            "CyberScrip beacon implementation not upgraded"
        );

        assertTrue(oldCyberCorpImpl != newCyberCorpImpl, "expected new corp impl");
        assertTrue(
            oldIssuanceManagerImpl != newIssuanceManagerImpl,
            "expected new issuance manager impl"
        );
        assertTrue(
            oldCertPrinterImpl != newCertPrinterImpl,
            "expected new cert printer impl"
        );
        assertTrue(oldScripImpl != newScripImpl, "expected new scrip impl");
    }

    function _deployCorpAndRound(
        CyberCorpFactory corpFactory,
        uint256 userSalt,
        CompanyOfficer memory officer,
        string[] memory legalDetails,
        bytes[] memory extensionData,
        CyberCertData[] memory certData,
        bytes32 templateId,
        address stable,
        uint256 pricePerUnit,
        uint256 valuation,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 startTime,
        uint256 endTime
    )
        internal
        returns (
            address corp,
            address auth,
            address issuanceManagerAddr,
            address dealManager,
            address roundManagerAddr,
            bytes32 roundId
        )
    {
        vm.prank(companyOwner);
        return
            corpFactory.deployCyberCorpAndCreateRound(
                userSalt,
                SecuritySeries.SeriesA,
                "CyberCorp Upgrade Test",
                "Limited Liability Company",
                "Delaware",
                "contact@test.local",
                "Arbitration",
                companyOwner,
                officer,
                legalDetails,
                extensionData,
                certData,
                templateId,
                stable,
                pricePerUnit,
                valuation,
                roundPartyValues,
                escrowedSignature,
                RoundType.FCFS,
                new address[](0),
                raiseCap,
                minTicket,
                maxTicket,
                startTime,
                endTime,
                true,
                true
            );
    }

    function _computeEscrowSignature(
        address roundManager,
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId_,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        uint256 signerPrivKey,
        address companyAddress
    ) internal view returns (bytes memory sig, bytes32 roundId) {
        roundId = keccak256(
            abi.encodePacked(
                seriesType,
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId_,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("RoundManager")),
                keccak256(bytes("1")),
                block.chainid,
                roundManager
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                ESCROWEDSIGNATUREDATA_TYPEHASH,
                roundId,
                uint8(seriesType),
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId_,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _computeEOISignature(
        CyberAgreementRegistry registry,
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        string[] memory partyValues,
        address authorityOfficer,
        uint256 signerPrivKey
    ) internal view returns (bytes memory) {
        (
            string memory legalUri,
            ,
            string[] memory glFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(
            abi.encode(templateId, salt, globalValues, parties)
        );
        return
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                contractId,
                legalUri,
                glFields,
                partyFields,
                globalValues,
                partyValues,
                signerPrivKey
            );
    }

    function _emptyLex() internal pure returns (LexChexDetails memory) {
        return
            LexChexDetails({
                request: MintRequest({
                    uuid: 0,
                    owner: address(0),
                    investorName: "",
                    investorType: "",
                    investorJurisdiction: "",
                    investorContact: "",
                    mintPrice: 0,
                    expiry: 0,
                    paymentToken: address(0)
                }),
                templateId: bytes32(0),
                salt: 0,
                globalValues: new string[](0),
                parties: new address[](0),
                partyValues: new string[][](0),
                agreementSignature: ""
            });
    }

    function _strings(
        string memory a,
        string memory b
    ) internal pure returns (string[] memory arr) {
        arr = new string[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _setupUpgradedIssuanceManager()
        internal
        returns (IssuanceManager issuanceManager)
    {
        CyberCorpFactory corpFactory = CyberCorpFactory(
            deployment.cyberCorpFactory
        );
        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );
        RoundManagerFactory rmFactory = RoundManagerFactory(
            deployment.roundManagerFactory
        );
        CyberCorpSingleFactory corpSingleFactory = CyberCorpSingleFactory(
            deployment.cyberCorpSingleFactory
        );
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            deployment.issuanceManagerFactory
        );

        address stable = corpFactory.stable();
        bytes32 templateId = bytes32(
            uint256(keccak256(abi.encodePacked("cyberscrip-upgrade-conversion-template", address(this), block.timestamp)))
        );

        vm.prank(METALEX_SAFE);
        registry.createTemplate(
            templateId,
            "CyberScrip conversion template",
            "ipfs://cyberscrip-conversion-template",
            _strings("purchaseAmount", "valuation"),
            _strings("name", "jurisdiction")
        );

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: companyOwner,
            name: "Officer One",
            contact: "officer@test.local",
            title: "CEO"
        });

        uint256 userSalt = uint256(
            keccak256(abi.encodePacked("cyberscrip-upgrade-conversion-salt", address(this), block.timestamp))
        );
        bytes32 corpSalt = keccak256(abi.encodePacked(userSalt));

        uint256 raiseCap = 100_000e6;
        uint256 minTicket = 100e6;
        uint256 maxTicket = 2_000e6;
        uint256 startTime = block.timestamp - 1;
        uint256 endTime = block.timestamp + 7 days;
        uint256 pricePerUnit = 1e18;
        uint256 valuation = 5_000_000e18;

        (bytes memory escrowedSignature, ) = _computeEscrowSignature(
            rmFactory.computeRoundManagerAddress(corpSalt),
            SecuritySeries.SeriesA,
            raiseCap,
            minTicket,
            maxTicket,
            RoundType.FCFS,
            startTime,
            endTime,
            templateId,
            stable,
            pricePerUnit,
            valuation,
            companyOwnerPk,
            corpSingleFactory.computeCyberCorpSingleAddress(corpSalt)
        );

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SAFE",
            symbol: "SAFE",
            uri: "ipfs://safe-cert",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: new string[](0)
        });

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "legal-details";
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";
        string[] memory roundPartyValues = _strings("Officer One", "US");

        (address corp, address auth, address issuanceManagerAddr, , , ) = _deployCorpAndRound(
            corpFactory,
            userSalt,
            officer,
            legalDetails,
            extensionData,
            certData,
            templateId,
            stable,
            pricePerUnit,
            valuation,
            roundPartyValues,
            escrowedSignature,
            raiseCap,
            minTicket,
            maxTicket,
            startTime,
            endTime
        );

        vm.prank(deployment.cyberCorpFactory);
        BorgAuth(auth).updateRole(companyOwner, 99);

        issuanceManager = IssuanceManager(issuanceManagerAddr);
        _upgradeCoreStackForCorp(
            corp,
            issuanceManager,
            corpSingleFactory,
            imFactory
        );
    }

    function _deployPrinterAfterUpgrade(
        IssuanceManager issuanceManager,
        string memory name,
        string memory symbol
    ) internal returns (ICyberCertPrinter certPrinter) {
        vm.prank(companyOwner);
        certPrinter = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                name,
                symbol,
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
    }

    function _mintCertAfterUpgrade(
        IssuanceManager issuanceManager,
        ICyberCertPrinter certPrinter,
        address to,
        uint256 units
    ) internal returns (uint256 tokenId) {
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(companyOwner);
        tokenId = issuanceManager.createCert(address(certPrinter), to, details);
    }
}
