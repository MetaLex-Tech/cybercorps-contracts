// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CreditFacilityFactoryDeployer} from "../script/CreditFacilityFactoryDeployer.sol";
import {DeployMetaDAOCreditFacilityFactoryScript} from "../script/deploy-metadao-credit-facility-factory.s.sol";
import {CreditFacilityTemplates} from "../script/libs/CreditFacilityTemplates.sol";

/// @notice Fork acceptance for both credit-facility deployment paths on Base
///   Sepolia: the resulting proxy, wiring, officer record, roles and templates,
///   plus the refusal when a template id is already held with another schema.
contract CreditFacilityFactoryForkTest is Test {
    address internal constant STANDARD_FACTORY = 0x734aE2b36f663D0F4233Ce4a02c13b5EB8ec959D;
    address internal constant IMPLEMENTATION = 0xD7F065826ba6dd793E8aE46B4c2F9334Fa80adbb;
    address internal constant REGISTRY = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
    address internal constant TESTNET_OFFICER = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    address internal constant IMF_V5 = 0xbbD386D237f3b407E6511A52488850b1Da0cCad2;
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// `templates` mapping slot in CyberAgreementRegistry (forge inspect storage-layout).
    uint256 internal constant TEMPLATES_SLOT = 6;

    address internal wallet = makeAddr("wallet");

    function setUp() public {
        vm.createSelectFork(vm.envOr("CREDIT_FACILITY_FORK_URL", string("base_sepolia")));
        vm.deal(wallet, 1 ether);
    }

    /// Makes the fork look like the id was never registered (the real templates
    /// exist on Base Sepolia since 2026-10-19), so each path's own registration
    /// and refusal are exercised, not a reuse of the live registration.
    function _unregister(bytes32 id) internal {
        bytes32 base = keccak256(abi.encode(id, TEMPLATES_SLOT));
        vm.store(REGISTRY, base, bytes32(0)); // legalContractUri length word
        (string memory uri,) = CyberAgreementRegistry(REGISTRY).templates(id);
        assertEq(bytes(uri).length, 0, "unregistered");
    }

    function _unregisterBoth() internal {
        _unregister(CreditFacilityTemplates.segCoId());
        _unregister(CreditFacilityTemplates.boardConsentId());
    }

    function _assertDeployment(address factory, address auth, address broadcaster) internal view {
        assertEq(address(uint160(uint256(vm.load(factory, IMPLEMENTATION_SLOT)))), IMPLEMENTATION, "implementation");
        MetaDAOFactory f = MetaDAOFactory(factory);
        MetaDAOFactory standard = MetaDAOFactory(STANDARD_FACTORY);
        assertEq(address(f.AUTH()), auth, "auth");
        assertEq(f.registryAddress(), REGISTRY, "registry");
        assertEq(f.issuanceManagerFactory(), IMF_V5, "v5 issuance manager factory on Base Sepolia");
        assertEq(f.cyberCorpSingleFactory(), standard.cyberCorpSingleFactory(), "single factory");
        assertEq(f.dealManagerFactory(), standard.dealManagerFactory(), "deal manager factory");
        assertEq(f.uriBuilder(), standard.uriBuilder(), "uri builder");
        assertEq(f.stable(), standard.stable(), "stable");
        (address eoa, string memory name, string memory contact, string memory title) = f.metaDAOOfficer();
        (address sEoa, string memory sName, string memory sContact, string memory sTitle) = standard.metaDAOOfficer();
        assertEq(eoa, sEoa, "officer eoa");
        assertEq(name, sName, "officer name");
        assertEq(contact, sContact, "officer contact");
        assertEq(title, sTitle, "officer title");
        assertEq(f.metaDAOSignatureHash().length, 0, "no escrow bytes yet");
        BorgAuth a = BorgAuth(auth);
        assertEq(a.userRoles(TESTNET_OFFICER), a.OWNER_ROLE(), "officer owns");
        assertEq(a.userRoles(broadcaster), a.OWNER_ROLE(), "broadcaster owns until revoked");
        (string memory uri, string memory t, string[] memory globals, string[] memory parties) =
            CyberAgreementRegistry(REGISTRY).getTemplateDetails(CreditFacilityTemplates.segCoId());
        assertEq(uri, CreditFacilityTemplates.SEGCO_URI);
        assertEq(t, CreditFacilityTemplates.SEGCO_TITLE);
        assertEq(globals.length, 10);
        assertEq(parties.length, 2);
        (uri,,,) = CyberAgreementRegistry(REGISTRY).getTemplateDetails(CreditFacilityTemplates.boardConsentId());
        assertEq(uri, CreditFacilityTemplates.BOARD_CONSENT_URI);
    }

    function test_deployerContractDeploysTheCreditFacilityFactory() public {
        _unregisterBoth();
        vm.prank(wallet);
        CreditFacilityFactoryDeployer d = new CreditFacilityFactoryDeployer();
        _assertDeployment(d.factory(), d.auth(), wallet);
        assertEq(BorgAuth(d.auth()).userRoles(address(d)), 0, "deployer contract dropped its role");
        assertEq(d.deployedBy(), wallet);
    }

    function test_deployerContractReusesAnIdenticalRegistration() public {
        // Live registrations (or fresh ones on a chain without them).
        CreditFacilityTemplates.ensureBoth(REGISTRY);
        vm.prank(wallet);
        CreditFacilityFactoryDeployer d = new CreditFacilityFactoryDeployer();
        _assertDeployment(d.factory(), d.auth(), wallet);
    }

    function test_deployerContractRefusesASquattedTemplateId() public {
        _unregisterBoth();
        string[] memory eight = new string[](8);
        string[] memory ten = CreditFacilityTemplates.globalFields();
        for (uint256 i = 0; i < 8; i++) eight[i] = ten[i];
        CyberAgreementRegistry(REGISTRY).createTemplate(
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            CreditFacilityTemplates.SEGCO_URI,
            eight,
            CreditFacilityTemplates.partyFields()
        );
        vm.prank(wallet);
        vm.expectRevert(
            abi.encodeWithSelector(CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.segCoId())
        );
        new CreditFacilityFactoryDeployer();
    }

    function test_scriptDeploysTheCreditFacilityFactory() public {
        _unregisterBoth();
        DeployMetaDAOCreditFacilityFactoryScript script = new DeployMetaDAOCreditFacilityFactoryScript();
        vm.deal(DEFAULT_SENDER, 1 ether);
        vm.recordLogs();
        script.run();
        // The script logs the addresses; recover them from the BorgAuth creation
        // by reading the last RoleUpdated emitter.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address auth;
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == keccak256("RoleUpdated(address,uint256)")) {
                auth = logs[i - 1].emitter;
                break;
            }
        }
        assertTrue(auth != address(0), "auth found");
        address factory;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Upgraded(address)")) {
                factory = logs[i].emitter;
                break;
            }
        }
        assertTrue(factory != address(0), "factory found");
        _assertDeployment(factory, auth, DEFAULT_SENDER);
    }

    function test_scriptRefusesASquattedTemplateId() public {
        _unregisterBoth();
        string[] memory parties = new string[](2);
        parties[0] = "Name";
        parties[1] = "ContactDetails";
        CyberAgreementRegistry(REGISTRY).createTemplate(
            CreditFacilityTemplates.boardConsentId(),
            CreditFacilityTemplates.BOARD_CONSENT_TITLE,
            CreditFacilityTemplates.BOARD_CONSENT_URI,
            CreditFacilityTemplates.globalFields(),
            parties
        );
        DeployMetaDAOCreditFacilityFactoryScript script = new DeployMetaDAOCreditFacilityFactoryScript();
        vm.expectRevert(
            abi.encodeWithSelector(
                CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.boardConsentId()
            )
        );
        script.run();
    }
}
