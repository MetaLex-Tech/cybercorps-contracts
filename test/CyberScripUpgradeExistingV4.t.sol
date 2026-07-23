// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {IssuerApprovalRecertificationCondition} from "../src/libs/conditions/IssuerApprovalRecertificationCondition.sol";
import {
    CertificateDetails,
    Endorsement
} from "../src/storage/LedgerEntryTokenStorage.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

interface ILegacyStackUUPS {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract LegacySelectorCondition is ICondition {
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

/// @notice Fork-based CyberScrip upgrade tests against a legacy Base Sepolia v3 deployment.
/// @dev The corp stack is deployed at a pre-upgrade block using the old live factories,
///      then upgraded locally to the latest in-repo implementations before each test runs.
contract CyberScripUpgradeExistingV4ForkTest is Test {
    using ERC1967ProxyLib for address;

    struct UpgradeImpls {
        address cyberCorp;
        address issuanceManager;
        address dealManager;
        address roundManager;
        address certPrinter;
        address scrip;
    }

    struct MultiHolderFixture {
        IssuanceManager issuanceManager;
        ILedgerEntryToken certPrinter;
        address scrip;
        uint256 certIdA;
        uint256 certIdB;
        uint256 certIdC;
        address thirdHolder;
        address newInvestor;
    }

    uint256 internal constant BASE_SEPOLIA = 84532;
    uint256 internal constant PRE_UPGRADE_BLOCK = 38956871;

    address internal constant METALEX_SAFE =
        0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    address internal constant LEXCHEX_OWNER =
        0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
    address internal constant CYBERCORP_FACTORY_PROXY =
        0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;

    CyberCorpFactory internal corpFactory;
    CyberCorpSingleFactory internal corpSingleFactory;
    IssuanceManagerFactory internal imFactory;
    DealManagerFactory internal dmFactory;
    RoundManagerFactory internal rmFactory;

    uint256 internal companyOwnerPk;
    uint256 internal investorPk;
    uint256 internal otherInvestorPk;
    address internal companyOwner;
    address internal investor;
    address internal otherInvestor;

    function setUp() public {
        vm.createSelectFork("base_sepolia", PRE_UPGRADE_BLOCK);

        corpFactory = CyberCorpFactory(CYBERCORP_FACTORY_PROXY);
        corpSingleFactory = CyberCorpSingleFactory(
            corpFactory.cyberCorpSingleFactory()
        );
        imFactory = IssuanceManagerFactory(corpFactory.issuanceManagerFactory());
        dmFactory = DealManagerFactory(corpFactory.dealManagerFactory());
        rmFactory = RoundManagerFactory(corpFactory.roundManagerFactory());

        companyOwnerPk = uint256(keccak256("cyberscrip-upgrade-company-owner"));
        investorPk = uint256(keccak256("cyberscrip-upgrade-investor"));
        otherInvestorPk = uint256(keccak256("cyberscrip-upgrade-other-investor"));
        companyOwner = vm.addr(companyOwnerPk);
        investor = vm.addr(investorPk);
        otherInvestor = vm.addr(otherInvestorPk);
    }

    function test_PostUpgrade_ConversionLifecycleAndRuntimeUpdates() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
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
        address scrip = _deployWhitelistedScrip(
            issuanceManager,
            certPrinter,
            50,
            3,
            2,
            whitelistIds
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

    function test_PostUpgrade_ScripifyUsesLegalOwner() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Legal Owner Cert",
            "LOCERT"
        );
        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            25
        );

        vm.prank(companyOwner);
        certPrinter.setGlobalTransferable(true);

        address scrip = _deployDefaultScrip(
            issuanceManager,
            certPrinter,
            0,
            1,
            1
        );

        vm.prank(investor);
        certPrinter.safeTransferFrom(investor, otherInvestor, certId);

        assertEq(certPrinter.ownerOf(certId), otherInvestor);
        assertEq(certPrinter.legalOwnerOf(certId), investor);

        vm.prank(otherInvestor);
        vm.expectRevert(bytes4(keccak256("NotLegalOwner()")));
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));

        assertEq(ICyberScrip(scrip).balanceOf(investor), 10);
        assertEq(certPrinter.getActiveCertificateDetails(certId).unitsRepresented, 15);
        assertEq(certPrinter.getCertificateDetails(certId).unitsRepresented, 25);
    }

    function test_PostUpgrade_ConversionGatesAndConditions() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Guard Cert",
            "GCERT"
        );

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripifiedCertNotAllowed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 1);

        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(
            new LegacySelectorCondition(
                address(certPrinter),
                IssuanceManager.convertScripToCert.selector,
                abi.encode(uint256(150), investor)
            )
        );

        address scrip = _deployScripWithScripToCertConditions(
            issuanceManager,
            certPrinter,
            scripToCert,
            90,
            3,
            2
        );

        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            100
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 100, address(0));

        assertEq(ICyberScrip(scrip).balanceOf(investor), 150);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 80);


        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 120);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 150);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_PostUpgrade_ReformsVoidedPath() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Voided Cert",
            "VCERT"
        );
        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            500
        );

        address scrip = _deployDefaultScrip(
            issuanceManager,
            certPrinter,
            0,
            2,
            1
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 20);

        vm.prank(companyOwner);
        certPrinter.voidCert(certId);
        assertTrue(certPrinter.isVoided(certId));

        _approveRecertification(
            issuanceManager,
            address(certPrinter),
            investor,
            "Investor"
        );
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 20);

        uint256 newCertId = 1;
        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(certId), investor);
        assertTrue(certPrinter.isVoided(certId));
        assertEq(certPrinter.ownerOf(newCertId), investor);
        assertFalse(certPrinter.isVoided(newCertId));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_PostUpgrade_ForceBurnReducesPoolTotals() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
            issuanceManager,
            "Force Burn Cert",
            "FBCERT"
        );
        uint256 certId = _mintCertAfterUpgrade(
            issuanceManager,
            certPrinter,
            investor,
            100
        );

        address scrip = _deployDefaultScrip(
            issuanceManager,
            certPrinter,
            0,
            2,
            1
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));

        (uint256 totalTrackedBefore,) = issuanceManager.getScripPoolTotals(
            address(certPrinter)
        );
        (bool isScripifiedBefore, uint256 scripifiedUnitsBefore,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certId);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 20);
        assertEq(totalTrackedBefore, 20);
        assertTrue(isScripifiedBefore);
        assertEq(scripifiedUnitsBefore, 10);

        vm.prank(companyOwner);
        issuanceManager.forceScripBurn(address(certPrinter), investor, 8);

        (uint256 totalTrackedAfter,) = issuanceManager.getScripPoolTotals(
            address(certPrinter)
        );
        (bool isScripifiedAfter, uint256 scripifiedUnitsAfter,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certId);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 12);
        assertEq(totalTrackedAfter, 12);
        assertTrue(isScripifiedAfter);
        assertEq(scripifiedUnitsAfter, 6);
    }

    function test_PostUpgrade_MultiHolderTransferAndRecertificationPoolAccounting()
        public
    {
        MultiHolderFixture memory fixture = _setupMultiHolderFixture();

        _assertActiveUnitsZero(fixture);
        _assertStoredUnits(fixture, 10, 20, 50);
        _assertBalances(fixture, 10, 20, 50, 0);
        _assertPoolAmountsById(fixture, 10, 20, 50);

        _transferToNewInvestor(fixture);

        _assertBalances(fixture, 8, 16, 40, 16);
        _assertPoolAmountsById(fixture, 10, 20, 50);

        (uint256 totalTrackedBefore,) = fixture.issuanceManager.getScripPoolTotals(
            address(fixture.certPrinter)
        );
        assertEq(totalTrackedBefore, 80);

        _approveRecertification(
            fixture.issuanceManager,
            address(fixture.certPrinter),
            fixture.newInvestor,
            "New Investor"
        );
        vm.prank(fixture.newInvestor);
        fixture.issuanceManager.convertScripToCert(address(fixture.certPrinter), 16);

        _assertBalances(fixture, 8, 16, 40, 0);

        (uint256 totalTrackedAfter,) = fixture.issuanceManager.getScripPoolTotals(
            address(fixture.certPrinter)
        );
        assertEq(totalTrackedAfter, 64);
        _assertPoolAmountsById(fixture, 8, 16, 40);
        _assertStoredUnits(fixture, 8, 16, 40);

        uint256 newCertId = 3;
        assertEq(fixture.certPrinter.totalSupply(), 4);
        assertEq(fixture.certPrinter.ownerOf(newCertId), fixture.newInvestor);
        assertEq(
            fixture.issuanceManager.getScripPoolAmountById(
                address(fixture.certPrinter),
                newCertId
            ),
            0
        );
        assertEq(
            fixture.certPrinter.getCertificateDetails(newCertId).unitsRepresented,
            16
        );
        assertEq(
            fixture.certPrinter.getActiveCertificateDetails(newCertId).unitsRepresented,
            16
        );
    }

    function test_PostUpgrade_RequiresIssuerApprovalCondition() public {
        IssuanceManager issuanceManager = _setupLegacyUpgradedIssuanceManager();
        ILedgerEntryToken certPrinter = _deployPrinterAfterUpgrade(
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

        address scrip = _deployScripWithScripToCertConditions(
            issuanceManager,
            certPrinter,
            scripToCert,
            0,
            1,
            1
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 5, address(0));

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 5);

        vm.prank(otherInvestor);
        vm.expectRevert();
        condition.setInvestorApproval(address(certPrinter), investor, true);

        BorgAuth auth = BorgAuth(issuanceManager.AUTH());
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(companyOwner);
        auth.updateRole(address(this), adminRole);

        condition.setInvestorApproval(address(scrip), investor, true);
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 5);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function _setupLegacyUpgradedIssuanceManager()
        internal
        returns (IssuanceManager issuanceManager)
    {
        bytes32 corpSalt = keccak256("cyberscrip-upgrade-existing-v3-corp");
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: companyOwner,
            name: "Officer One",
            contact: "officer@test.local",
            title: "CEO"
        });

        vm.prank(LEXCHEX_OWNER);
        (address corp, address auth, address issuanceManagerAddr, , ) = corpFactory
            .deployCyberCorp(
            corpSalt,
            "CyberCorp Upgrade Test",
            "Limited Liability Company",
            "Delaware",
            "contact@test.local",
            "Arbitration",
            companyOwner,
            officer
        );


        uint256 ownerRole = BorgAuth(auth).OWNER_ROLE();
        vm.prank(address(corpFactory));
        BorgAuth(auth).updateRole(companyOwner, ownerRole);

        issuanceManager = IssuanceManager(issuanceManagerAddr);
        _upgradeCoreStackForCorp(corp, issuanceManager);
    }

    function _upgradeCoreStackForCorp(
        address corp,
        IssuanceManager issuanceManager
    ) internal {
        UpgradeImpls memory impls = _deployUpgradeImplementations();
        _setFactoryUpgradeReferences(impls);
        _upgradeExistingCorpStack(corp, issuanceManager, impls);
        _assertUpgradedImplementations(corp, issuanceManager, impls);
    }

    function _deployUpgradeImplementations()
        internal
        returns (UpgradeImpls memory impls)
    {
        impls.cyberCorp = address(new CyberCorp());
        impls.issuanceManager = address(new IssuanceManager());
        impls.dealManager = address(new DealManager());
        impls.roundManager = address(new RoundManager());
        impls.certPrinter = address(new LedgerEntryToken());
        impls.scrip = address(new CyberScrip());
    }

    function _setFactoryUpgradeReferences(UpgradeImpls memory impls) internal {
        vm.startPrank(LEXCHEX_OWNER);
        corpSingleFactory.setRefImplementation(impls.cyberCorp);
        imFactory.setRefImplementation(impls.issuanceManager);
        dmFactory.setRefImplementation(impls.dealManager);
        rmFactory.setRefImplementation(impls.roundManager);
        imFactory.setCyberCertPrinterRefImplementation(impls.certPrinter);
        imFactory.setCyberScripRefImplementation(impls.scrip);
        vm.stopPrank();
    }

    function _upgradeExistingCorpStack(
        address corp,
        IssuanceManager issuanceManager,
        UpgradeImpls memory impls
    ) internal {
        address issuanceManagerAddr = address(issuanceManager);
        address dealManagerAddr = CyberCorp(corp).dealManager();
        address roundManagerAddr = CyberCorp(corp).roundManager();

        vm.prank(companyOwner);
        ILegacyStackUUPS(corp).upgradeToAndCall(impls.cyberCorp, "");
        vm.prank(companyOwner);
        ILegacyStackUUPS(issuanceManagerAddr).upgradeToAndCall(
            impls.issuanceManager,
            ""
        );
        vm.prank(companyOwner);
        ILegacyStackUUPS(dealManagerAddr).upgradeToAndCall(
            impls.dealManager,
            ""
        );
        vm.prank(companyOwner);
        ILegacyStackUUPS(roundManagerAddr).upgradeToAndCall(
            impls.roundManager,
            ""
        );
        vm.prank(companyOwner);
        issuanceManager.upgradeCertPrinterBeaconImplementation(impls.certPrinter);
        vm.prank(companyOwner);
        issuanceManager.upgradeScripBeaconImplementation(impls.scrip);
    }

    function _assertUpgradedImplementations(
        address corp,
        IssuanceManager issuanceManager,
        UpgradeImpls memory impls
    ) internal view {
        address issuanceManagerAddr = address(issuanceManager);
        address dealManagerAddr = CyberCorp(corp).dealManager();
        address roundManagerAddr = CyberCorp(corp).roundManager();

        assertEq(corp.getErc1967Implementation(), impls.cyberCorp);
        assertEq(
            issuanceManagerAddr.getErc1967Implementation(),
            impls.issuanceManager
        );
        assertEq(dealManagerAddr.getErc1967Implementation(), impls.dealManager);
        assertEq(roundManagerAddr.getErc1967Implementation(), impls.roundManager);
        assertEq(
            issuanceManager.getCertPrinterBeaconImplementation(),
            impls.certPrinter
        );
        assertEq(issuanceManager.getScripBeaconImplementation(), impls.scrip);
    }

    function _deployPrinterAfterUpgrade(
        IssuanceManager issuanceManager,
        string memory name,
        string memory symbol
    ) internal returns (ILedgerEntryToken certPrinter) {
        vm.prank(companyOwner);
        certPrinter = ILedgerEntryToken(
            issuanceManager.createCertPrinter(
                new string[](0),
                name,
                symbol,
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );
    }

    function _deployDefaultScrip(
        IssuanceManager issuanceManager,
        ILedgerEntryToken certPrinter,
        uint256 minimum,
        uint256 numerator,
        uint256 denominator
    ) internal returns (address scrip) {
        vm.prank(companyOwner);
        scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            minimum,
            numerator,
            denominator,
            new uint256[](0),
            false,
            true,
            true,
            true
        );
    }

    function _deployWhitelistedScrip(
        IssuanceManager issuanceManager,
        ILedgerEntryToken certPrinter,
        uint256 minimum,
        uint256 numerator,
        uint256 denominator,
        uint256[] memory whitelistIds
    ) internal returns (address scrip) {
        vm.prank(companyOwner);
        scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            minimum,
            numerator,
            denominator,
            whitelistIds,
            true,
            true,
            true,
            true
        );
    }

    function _deployScripWithScripToCertConditions(
        IssuanceManager issuanceManager,
        ILedgerEntryToken certPrinter,
        ICondition[] memory scripToCertConditions,
        uint256 minimum,
        uint256 numerator,
        uint256 denominator
    ) internal returns (address scrip) {
        vm.prank(companyOwner);
        scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            scripToCertConditions,
            minimum,
            numerator,
            denominator,
            new uint256[](0),
            false,
            true,
            true,
            true
        );
    }

    function _mintCertAfterUpgrade(
        IssuanceManager issuanceManager,
        ILedgerEntryToken certPrinter,
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

        Endorsement memory selfEndorsement = Endorsement({
            endorser: to,
            timestamp: block.timestamp,
            signatureHash: "",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: to,
            endorseeName: ""
        });
        vm.prank(to);
        certPrinter.addEndorsement(tokenId, selfEndorsement);
        vm.prank(companyOwner);
        certPrinter.setTokenTransferable(tokenId, true);
        vm.prank(to);
        certPrinter.safeTransferFrom(to, to, tokenId);
        vm.prank(companyOwner);
        certPrinter.setTokenTransferable(tokenId, false);
    }

    function _approveRecertification(
        IssuanceManager issuanceManager,
        address certAddress,
        address investorAddr,
        string memory investorName
    ) internal {
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 0,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(companyOwner);
        issuanceManager.setRecertificationApproval(
            certAddress,
            investorAddr,
            investorName,
            details,
            hex"01"
        );
    }

    function _setupMultiHolderFixture()
        internal
        returns (MultiHolderFixture memory fixture)
    {
        fixture.issuanceManager = _setupLegacyUpgradedIssuanceManager();
        fixture.certPrinter = _deployPrinterAfterUpgrade(
            fixture.issuanceManager,
            "Pool Cert",
            "PCERT"
        );
        fixture.thirdHolder = vm.addr(
            uint256(keccak256("cyberscrip-upgrade-third-holder"))
        );
        fixture.newInvestor = vm.addr(
            uint256(keccak256("cyberscrip-upgrade-new-investor"))
        );

        fixture.certIdA = _mintCertAfterUpgrade(
            fixture.issuanceManager,
            fixture.certPrinter,
            investor,
            10
        );
        fixture.certIdB = _mintCertAfterUpgrade(
            fixture.issuanceManager,
            fixture.certPrinter,
            otherInvestor,
            20
        );
        fixture.certIdC = _mintCertAfterUpgrade(
            fixture.issuanceManager,
            fixture.certPrinter,
            fixture.thirdHolder,
            50
        );

        fixture.scrip = _deployDefaultScrip(
            fixture.issuanceManager,
            fixture.certPrinter,
            0,
            1,
            1
        );

        vm.prank(investor);
        fixture.issuanceManager.scripifyCert(
            address(fixture.certPrinter),
            fixture.certIdA,
            10,
            address(0)
        );
        vm.prank(otherInvestor);
        fixture.issuanceManager.scripifyCert(
            address(fixture.certPrinter),
            fixture.certIdB,
            20,
            address(0)
        );
        vm.prank(fixture.thirdHolder);
        fixture.issuanceManager.scripifyCert(
            address(fixture.certPrinter),
            fixture.certIdC,
            50,
            address(0)
        );
    }

    function _transferToNewInvestor(MultiHolderFixture memory fixture) internal {
        vm.prank(investor);
        ICyberScrip(fixture.scrip).transfer(fixture.newInvestor, 2);
        vm.prank(otherInvestor);
        ICyberScrip(fixture.scrip).transfer(fixture.newInvestor, 4);
        vm.prank(fixture.thirdHolder);
        ICyberScrip(fixture.scrip).transfer(fixture.newInvestor, 10);
    }

    function _assertActiveUnitsZero(MultiHolderFixture memory fixture) internal view {
        assertEq(
            fixture.certPrinter.getActiveCertificateDetails(fixture.certIdA)
                .unitsRepresented,
            0
        );
        assertEq(
            fixture.certPrinter.getActiveCertificateDetails(fixture.certIdB)
                .unitsRepresented,
            0
        );
        assertEq(
            fixture.certPrinter.getActiveCertificateDetails(fixture.certIdC)
                .unitsRepresented,
            0
        );
    }

    function _assertStoredUnits(
        MultiHolderFixture memory fixture,
        uint256 unitsA,
        uint256 unitsB,
        uint256 unitsC
    ) internal view {
        assertEq(
            fixture.certPrinter.getCertificateDetails(fixture.certIdA).unitsRepresented,
            unitsA
        );
        assertEq(
            fixture.certPrinter.getCertificateDetails(fixture.certIdB).unitsRepresented,
            unitsB
        );
        assertEq(
            fixture.certPrinter.getCertificateDetails(fixture.certIdC).unitsRepresented,
            unitsC
        );
    }

    function _assertBalances(
        MultiHolderFixture memory fixture,
        uint256 investorBal,
        uint256 otherInvestorBal,
        uint256 thirdHolderBal,
        uint256 newInvestorBal
    ) internal view {
        assertEq(ICyberScrip(fixture.scrip).balanceOf(investor), investorBal);
        assertEq(
            ICyberScrip(fixture.scrip).balanceOf(otherInvestor),
            otherInvestorBal
        );
        assertEq(
            ICyberScrip(fixture.scrip).balanceOf(fixture.thirdHolder),
            thirdHolderBal
        );
        assertEq(
            ICyberScrip(fixture.scrip).balanceOf(fixture.newInvestor),
            newInvestorBal
        );
    }

    function _assertPoolAmountsById(
        MultiHolderFixture memory fixture,
        uint256 certAmtA,
        uint256 certAmtB,
        uint256 certAmtC
    ) internal view {
        assertEq(
            fixture.issuanceManager.getScripPoolAmountById(
                address(fixture.certPrinter),
                fixture.certIdA
            ),
            certAmtA
        );
        assertEq(
            fixture.issuanceManager.getScripPoolAmountById(
                address(fixture.certPrinter),
                fixture.certIdB
            ),
            certAmtB
        );
        assertEq(
            fixture.issuanceManager.getScripPoolAmountById(
                address(fixture.certPrinter),
                fixture.certIdC
            ),
            certAmtC
        );
    }
}
