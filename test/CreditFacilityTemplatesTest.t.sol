// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ICyberAgreementRegistry} from "../src/interfaces/ICyberAgreementRegistry.sol";
import {CyberAgreementRegistryDeployment} from "../script/libs/CyberAgreementRegistryDeployment.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CreditFacilityTemplates} from "../script/libs/CreditFacilityTemplates.sol";

/// @dev External wrapper so `vm.expectRevert` targets the library call itself.
contract TemplateEnsurer {
    function ensureSegCo(address registry) external returns (bool) {
        return CreditFacilityTemplates.ensure(
            registry,
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            CreditFacilityTemplates.SEGCO_URI
        );
    }
}

/// @notice Behavioral regression for the schema-reuse rule both credit-facility
///   deployment paths apply (script and one-transaction deployer): an identical
///   registration is reused, anything else at the same id is refused.
contract CreditFacilityTemplatesTest is Test {
    ICyberAgreementRegistry internal registry;
    TemplateEnsurer internal ensurer;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.startPrank(deployer);
        BorgAuth auth = new BorgAuth(deployer);
        registry = ICyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(CyberAgreementRegistryDeployment.deployRouter()),
                    abi.encodeWithSelector(ICyberAgreementRegistry.initialize.selector, address(auth))
                )
            )
        );
        vm.stopPrank();
        ensurer = new TemplateEnsurer();
    }

    function _ensureSegCo() internal returns (bool) {
        return ensurer.ensureSegCo(address(registry));
    }

    function test_registersBothTemplatesWithTheTenFieldSchema() public {
        CreditFacilityTemplates.ensureBoth(address(registry));
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(CreditFacilityTemplates.segCoId());
        assertEq(uri, CreditFacilityTemplates.SEGCO_URI);
        assertEq(title, CreditFacilityTemplates.SEGCO_TITLE);
        assertEq(globals.length, 10);
        assertEq(globals[8], "opcoName");
        assertEq(globals[9], "opcoJurisdiction");
        assertEq(parties.length, 2);
        (uri, title, globals, parties) = registry.getTemplateDetails(CreditFacilityTemplates.boardConsentId());
        assertEq(uri, CreditFacilityTemplates.BOARD_CONSENT_URI);
        assertEq(title, CreditFacilityTemplates.BOARD_CONSENT_TITLE);
        assertEq(globals.length, 10);
    }

    function test_reusesAnIdenticalRegistration() public {
        assertTrue(_ensureSegCo(), "first call registers");
        assertFalse(_ensureSegCo(), "second call reuses");
    }

    function test_refusesSameTitleAndUriWithReorderedGlobalFields() public {
        string[] memory globals = CreditFacilityTemplates.globalFields();
        (globals[8], globals[9]) = (globals[9], globals[8]);
        registry.createTemplate(
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            CreditFacilityTemplates.SEGCO_URI,
            globals,
            CreditFacilityTemplates.partyFields()
        );
        vm.expectRevert(
            abi.encodeWithSelector(CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.segCoId())
        );
        _ensureSegCo();
    }

    function test_refusesSameTitleAndUriWithFewerGlobalFields() public {
        string[] memory eight = new string[](8);
        string[] memory ten = CreditFacilityTemplates.globalFields();
        for (uint256 i = 0; i < 8; i++) eight[i] = ten[i];
        registry.createTemplate(
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            CreditFacilityTemplates.SEGCO_URI,
            eight,
            CreditFacilityTemplates.partyFields()
        );
        vm.expectRevert(
            abi.encodeWithSelector(CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.segCoId())
        );
        _ensureSegCo();
    }

    function test_refusesDifferentPartyFields() public {
        string[] memory parties = new string[](2);
        parties[0] = "Name";
        parties[1] = "ContactDetails";
        registry.createTemplate(
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            CreditFacilityTemplates.SEGCO_URI,
            CreditFacilityTemplates.globalFields(),
            parties
        );
        vm.expectRevert(
            abi.encodeWithSelector(CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.segCoId())
        );
        _ensureSegCo();
    }

    function test_refusesDifferentUri() public {
        registry.createTemplate(
            CreditFacilityTemplates.segCoId(),
            CreditFacilityTemplates.SEGCO_TITLE,
            "ipfs://bafybeisomeoneelsesdocument",
            CreditFacilityTemplates.globalFields(),
            CreditFacilityTemplates.partyFields()
        );
        vm.expectRevert(
            abi.encodeWithSelector(CreditFacilityTemplates.TemplateSchemaMismatch.selector, CreditFacilityTemplates.segCoId())
        );
        _ensureSegCo();
    }
}
