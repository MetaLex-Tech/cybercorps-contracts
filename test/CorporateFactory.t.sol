// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuthV2} from "../src/BorgAuthV2.sol";

import {CyberCorp} from "../src/CyberCorp.sol";

import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";

import {CertificateDetails, CompanyOfficer} from "../src/interfaces/ILedgerEntryToken.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {CorporateAuth} from "../src/libs/CorporateAuth.sol";
import {BorgAuth} from "../src/libs/auth.sol";

import {GPLPApprovalCondition} from "../src/libs/conditions/secondary/GPLPApprovalCondition.sol";

import {CorporateExecutor} from "./CorporateAuth.t.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CorporateFactoryTest is Test {
    CyberCorpFactory internal factory;
    CorporateExecutor internal board;
    address internal officer = address(0xA11CE);
    CyberCorp internal corp;
    BorgAuthV2 internal auth;
    IssuanceManager internal issuance;
    DealManager internal dealManager;
    RoundManager internal round;

    function _proxy(string memory artifact, bytes memory data) internal returns (address) {
        return address(new ERC1967Proxy(deployCode(artifact), data));
    }

    function setUp() public {
        address globalAuth = address(new BorgAuth(address(this)));
        address corpImpl = deployCode("CyberCorp.sol:CyberCorp");
        address issuanceImpl = deployCode("IssuanceManager.sol:IssuanceManager");
        address certImpl = deployCode("LedgerEntryToken.sol:LedgerEntryToken");
        address scripImpl = deployCode("CyberScrip.sol:CyberScrip");
        address dealImpl = deployCode("DealManager.sol:DealManager");
        address roundImpl = deployCode("RoundManager.sol:RoundManager");
        address corpFactory = _proxy(
            "CyberCorpSingleFactory.sol:CyberCorpSingleFactory",
            abi.encodeCall(CyberCorpSingleFactory.initialize, (globalAuth, corpImpl))
        );
        address issuanceFactory = _proxy(
            "IssuanceManagerFactory.sol:IssuanceManagerFactory",
            abi.encodeCall(IssuanceManagerFactory.initialize, (globalAuth, issuanceImpl, certImpl, scripImpl))
        );
        address dealFactory = _proxy(
            "DealManagerFactory.sol:DealManagerFactory",
            abi.encodeCall(DealManagerFactory.initialize, (globalAuth, dealImpl))
        );
        address roundFactory = _proxy(
            "RoundManagerFactory.sol:RoundManagerFactory",
            abi.encodeCall(RoundManagerFactory.initialize, (globalAuth, roundImpl))
        );
        factory = CyberCorpFactory(
            _proxy(
                "CyberCorpFactory.sol:CyberCorpFactory",
                abi.encodeCall(
                    CyberCorpFactory.initialize,
                    (globalAuth, address(this), issuanceFactory, corpFactory, dealFactory, roundFactory, address(this))
                )
            )
        );
        factory.setLexchexAuth(address(0));
        factory.setBorgAuthImplementation(address(new BorgAuthV2()));
        board = new CorporateExecutor();
        (address c, address a, address i, address d, address r) = factory.deployCyberCorpWithGovernance(
            keccak256("new company"),
            "Company",
            "Corp",
            "DE",
            "contact",
            "dispute",
            officer,
            CompanyOfficer(officer, "Officer", "contact", "CEO"),
            address(this),
            address(board)
        );
        corp = CyberCorp(c);
        auth = BorgAuthV2(a);
        issuance = IssuanceManager(i);
        dealManager = DealManager(d);
        round = RoundManager(r);
    }

    function testAtomicDeploymentHasNoBootstrapAuthority() public view {
        assertTrue(auth.setupComplete());
        assertEq(auth.rootAuthority(), address(this));
        assertEq(auth.officerController(), address(corp));
        assertEq(address(corp.AUTH()), address(auth));
        assertEq(address(issuance.AUTH()), address(auth));
        assertEq(address(dealManager.AUTH()), address(auth));
        assertEq(address(round.AUTH()), address(auth));
        assertFalse(auth.hasPermission(CorporateAuth.CONFIGURE_PROTOCOL, address(factory)));
        assertFalse(auth.hasPermission(CorporateAuth.MANAGE_OFFICERS, address(factory)));
        assertFalse(auth.hasPermission(CorporateAuth.APPROVE_UPGRADE, address(dealManager)));
        assertTrue(auth.hasPermission(CorporateAuth.MANAGE_SECURITY_CLASSES, address(dealManager)));
        assertTrue(auth.hasPermission(CorporateAuth.ISSUE_SECURITIES, address(dealManager)));
        assertTrue(auth.hasPermission(CorporateAuth.MANAGE_SECURITY_CLASSES, address(round)));
    }

    function testPeripheralConfigurationRequiresRoot() public {
        vm.startPrank(officer);
        vm.expectRevert();
        issuance.setUriBuilder(officer);
        vm.expectRevert();
        dealManager.setIssuanceManager(officer);
        vm.expectRevert();
        round.setLexChex(officer);
        vm.stopPrank();
        issuance.setUriBuilder(officer);
        dealManager.setIssuanceManager(address(issuance));
        round.setLexChex(officer);
    }

    function testIssueAndTokenAdminKeepManagerBoundaries() public {
        vm.prank(officer);
        address printer = issuance.createCertPrinter(
            new string[](0), "Shares", "SH", "uri", SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0), ""
        );
        CertificateDetails memory details = CertificateDetails("Officer", "CEO", 1, 1, 100e18, "legal", "");
        vm.prank(address(dealManager));
        uint256 id = issuance.createCert(printer, officer, details);
        assertEq(LedgerEntryToken(printer).ownerOf(id), officer);
        vm.prank(address(dealManager));
        LedgerEntryToken(printer).voidCert(id);
        vm.prank(address(dealManager));
        vm.expectRevert();
        LedgerEntryToken(printer).setGlobalTransferable(true);
        vm.prank(officer);
        LedgerEntryToken(printer).setGlobalTransferable(true);
        vm.prank(officer);
        vm.expectRevert();
        LedgerEntryToken(printer).safeMint(999, officer, details);
        vm.expectRevert();
        issuance.createCert(printer, officer, details); // root has no issuance membership
        vm.prank(address(board));
        vm.expectRevert();
        issuance.createCert(printer, officer, details);
    }

    function testLegacyDeploymentPathStillWorks() public {
        (address c, address a,,,) = factory.deployCyberCorp(
            keccak256("legacy company"),
            "Legacy",
            "Corp",
            "DE",
            "contact",
            "dispute",
            officer,
            CompanyOfficer(officer, "Officer", "contact", "CEO")
        );
        assertEq(BorgAuth(a).userRoles(officer), 200);
        vm.prank(officer);
        CyberCorp(c).addOfficer(CompanyOfficer(address(0xB0B), "Second", "", "CFO"));
        assertEq(BorgAuth(a).userRoles(address(0xB0B)), 200);
    }

    function testScripExactManagerAndPolicyPermissions() public {
        CyberScrip scrip = CyberScrip(
            _proxy(
                "CyberScrip.sol:CyberScrip",
                abi.encodeCall(
                    CyberScrip.initialize,
                    (
                        address(auth),
                        address(0),
                        address(issuance),
                        "Scrip",
                        "SC",
                        new ITransferRestrictionHook[](0),
                        true,
                        true,
                        true
                    )
                )
            )
        );
        vm.prank(address(issuance));
        scrip.mint(officer, 100);
        assertEq(scrip.balanceOf(officer), 100);
        vm.prank(officer);
        vm.expectRevert();
        scrip.mint(officer, 100);
        vm.prank(address(dealManager));
        vm.expectRevert();
        scrip.setFrozen(officer, true);
        vm.expectRevert();
        scrip.setFrozen(officer, true); // root has no implicit policy permission
        vm.prank(officer);
        scrip.setFrozen(officer, true);
        vm.prank(address(issuance));
        scrip.setFrozen(officer, false);
    }

    function testSharedConditionUsesCompanyPermissions() public {
        GPLPApprovalCondition condition = GPLPApprovalCondition(
            _proxy(
                "GPLPApprovalCondition.sol:GPLPApprovalCondition",
                abi.encodeCall(GPLPApprovalCondition.initialize, (address(new BorgAuth(address(this)))))
            )
        );
        vm.prank(address(dealManager));
        vm.expectRevert();
        condition.setApprover(address(dealManager), officer);
        vm.expectRevert();
        condition.setApprover(address(dealManager), officer);
        vm.prank(officer);
        condition.setApprover(address(dealManager), officer);
        vm.prank(officer);
        condition.setDealApproval(address(dealManager), keccak256("deal"), true);
    }

    function testGovernanceConfigurationIsBoundIntoSalt() public {
        CorporateExecutor otherBoard = new CorporateExecutor();
        (address other,,,,) = factory.deployCyberCorpWithGovernance(
            keccak256("new company"),
            "Company",
            "Corp",
            "DE",
            "contact",
            "dispute",
            officer,
            CompanyOfficer(officer, "Officer", "contact", "CEO"),
            address(this),
            address(otherBoard)
        );
        assertTrue(other != address(corp));
    }
}
