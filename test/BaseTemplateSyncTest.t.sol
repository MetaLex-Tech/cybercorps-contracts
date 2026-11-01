// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SyncBaseTemplatesScript} from "../script/sync-base-templates.s.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import "forge-std/Test.sol";

/// @dev Local unit fixture only; actual deployed-registry acceptance is separate.
contract TemplateRegistryFixture {
    struct Entry {
        string uri;
        string title;
        string[] globals;
        string[] parties;
    }

    mapping(bytes32 => Entry) internal definitions;
    uint256 public registrations;
    bool public readFailure;

    function failReads() external {
        readFailure = true;
    }

    function getTemplateDetails(bytes32 id)
        external
        view
        returns (string memory, string memory, string[] memory, string[] memory)
    {
        if (readFailure) revert("unexpected registry failure");
        Entry storage e = definitions[id];
        if (bytes(e.uri).length == 0) revert CyberAgreementRegistry.TemplateDoesNotExist();
        return (e.uri, e.title, e.globals, e.parties);
    }

    function createTemplate(
        bytes32 id,
        string memory title,
        string memory uri,
        string[] memory globals,
        string[] memory parties
    ) external {
        require(bytes(definitions[id].uri).length == 0, "already registered");
        definitions[id] = Entry(uri, title, globals, parties);
        registrations++;
    }
}

contract TemplateSyncHarness is SyncBaseTemplatesScript {
    function sync(TemplateRecord[] memory entries) external {
        _sync(entries);
    }
}

contract BaseTemplateSyncTest is Test {
    TemplateSyncHarness script;
    TemplateRegistryFixture registry;

    function setUp() public {
        vm.chainId(4663);
        script = new TemplateSyncHarness();
        TemplateRegistryFixture fixture = new TemplateRegistryFixture();
        vm.etch(script.REGISTRY(), address(fixture).code);
        registry = TemplateRegistryFixture(script.REGISTRY());
    }

    function _entries() internal view returns (SyncBaseTemplatesScript.TemplateRecord[] memory) {
        return script.loadManifest("test/res/base-template-sync.json");
    }

    function _seed(SyncBaseTemplatesScript.TemplateRecord memory e) internal {
        registry.createTemplate(e.id, e.title, e.legalContractUri, e.globalFields, e.partyFields);
    }

    function _assertMatches(SyncBaseTemplatesScript.TemplateRecord memory e) internal view {
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(e.id);
        assertEq(keccak256(abi.encode(uri, title, globals, parties)), script.definitionHash(e));
    }

    function test_ManifestPreservesNumericAndStringIdsAndFieldOrder() public view {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        assertEq(e.length, 2);
        assertEq(e[0].id, bytes32(uint256(32)));
        assertEq(e[1].id, bytes32("ace_safev1"));
        assertEq(e[0].legalContractUri, "IPFS://CaseSensitive-CID");
        assertEq(e[0].globalFields[0], "purchaseAmount");
        assertEq(e[0].globalFields[1], "valuationCap");
        assertEq(e[1].globalFields.length, 0);
    }

    function test_FirstRegistrationAndIdempotentRerun() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        script.runWithManifest("test/res/base-template-sync.json");
        assertEq(registry.registrations(), 2);
        for (uint256 i; i < e.length; i++) {
            _assertMatches(e[i]);
        }
        script.runWithManifest("test/res/base-template-sync.json");
        assertEq(registry.registrations(), 2);
    }

    function test_PartialDeploymentSkipsExistingExactDefinition() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        _seed(e[0]);
        bool[] memory missing = script.preflight(e);
        assertFalse(missing[0]);
        assertTrue(missing[1]);
        script.sync(e);
        assertEq(registry.registrations(), 2);
        _assertMatches(e[0]);
        _assertMatches(e[1]);
    }

    function test_LateConflictRefusesBeforeAnyEarlierWrite() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        SyncBaseTemplatesScript.TemplateRecord memory conflict = e[1];
        conflict.title = "other template";
        _seed(conflict);
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.ConflictingTemplate.selector, e[1].id));
        script.runWithManifest("test/res/base-template-sync.json");
        assertEq(registry.registrations(), 1);
        vm.expectRevert(CyberAgreementRegistry.TemplateDoesNotExist.selector);
        registry.getTemplateDetails(e[0].id);
    }

    function test_FieldOrderIsAConflict() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        _seed(e[0]);
        (e[0].globalFields[0], e[0].globalFields[1]) = (e[0].globalFields[1], e[0].globalFields[0]);
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.ConflictingTemplate.selector, e[0].id));
        script.sync(e);
        assertEq(registry.registrations(), 1);
    }

    function test_UriCaseIsAConflict() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        _seed(e[0]);
        e[0].legalContractUri = "ipfs://CaseSensitive-CID";
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.ConflictingTemplate.selector, e[0].id));
        script.sync(e);
    }

    function test_DuplicateIdsRefuseBeforeWrites() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        e[1].id = e[0].id;
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.DuplicateTemplate.selector, e[0].id));
        script.sync(e);
        assertEq(registry.registrations(), 0);
    }

    function test_EmptyUriRefusesBeforeWrites() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        e[1].legalContractUri = "";
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.InvalidTemplate.selector, e[1].id));
        script.sync(e);
        assertEq(registry.registrations(), 0);
    }

    function test_WrongChainRefuses() public {
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(SyncBaseTemplatesScript.WrongChain.selector, 8453));
        script.runWithManifest("test/res/base-template-sync.json");
        assertEq(registry.registrations(), 0);
    }

    function test_WrongManifestSourceRefusesBeforeWrites() public {
        vm.expectRevert(SyncBaseTemplatesScript.InvalidManifest.selector);
        script.runWithManifest("test/res/base-template-sync-wrong-source.json");
        assertEq(registry.registrations(), 0);
    }

    function test_EmptyInventoryRefuses() public {
        SyncBaseTemplatesScript.TemplateRecord[] memory entries = new SyncBaseTemplatesScript.TemplateRecord[](0);
        vm.expectRevert(SyncBaseTemplatesScript.InvalidManifest.selector);
        script.sync(entries);
        assertEq(registry.registrations(), 0);
    }

    function test_UnexpectedRegistryRevertIsNotTreatedAsMissing() public {
        registry.failReads();
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        vm.expectRevert(
            abi.encodeWithSelector(
                SyncBaseTemplatesScript.RegistryReadFailed.selector,
                e[0].id,
                abi.encodeWithSignature("Error(string)", "unexpected registry failure")
            )
        );
        script.sync(e);
        assertEq(registry.registrations(), 0);
    }

    function test_MissingRegistryCodeRefuses() public {
        vm.etch(address(registry), "");
        SyncBaseTemplatesScript.TemplateRecord[] memory e = _entries();
        vm.expectRevert(SyncBaseTemplatesScript.InvalidManifest.selector);
        script.sync(e);
    }
}
