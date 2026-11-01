// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SyncBaseTemplatesScript} from "../script/sync-base-templates.s.sol";
import {RobinhoodPostUpgradeLifecycleTest} from "./RobinhoodPostUpgradeLifecycleTest.t.sol";

/// @notice Actual Robinhood deployed-registry acceptance. Only registration
/// calls from the complete Base export are simulated; no code or roles changed.
/// Inherits the existing real-token SAFE issuance/refusal lifecycle assertions.
contract BaseTemplateSyncForkTest is RobinhoodPostUpgradeLifecycleTest {
    function _installBaseTemplateFixtureIfMissing() internal override {
        bytes32 legacyBefore = _definitionHash(bytes32(uint256(1)));
        bytes32 implementationBefore =
            vm.load(address(registry), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        SyncBaseTemplatesScript sync = new SyncBaseTemplatesScript();
        sync.run();
        // Preflight checks every imported definition against the deployed registry.
        SyncBaseTemplatesScript.TemplateRecord[] memory entries = sync.loadManifest(sync.MANIFEST());
        bool[] memory missing = sync.preflight(entries);
        for (uint256 i; i < missing.length; i++) {
            assertFalse(missing[i]);
        }
        // Repeating the production entry point must skip all exact matches.
        sync.run();
        assertEq(_definitionHash(bytes32(uint256(1))), legacyBefore);
        assertEq(
            vm.load(address(registry), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc),
            implementationBefore
        );
    }

    function test_FullBaseSnapshotRefusesImmutableLegacyCollision() public forkOnly {
        SyncBaseTemplatesScript sync = new SyncBaseTemplatesScript();
        vm.expectRevert(
            abi.encodeWithSelector(SyncBaseTemplatesScript.ConflictingTemplate.selector, bytes32(uint256(1)))
        );
        sync.runWithManifest("script/res/base-templates.json");
        // The full strict snapshot fails before registering the still-missing SAFE.
        vm.expectRevert(bytes4(keccak256("TemplateDoesNotExist()")));
        registry.getTemplateDetails(bytes32(uint256(32)));
    }

    function _definitionHash(bytes32 id) internal view returns (bytes32) {
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(id);
        return keccak256(abi.encode(uri, title, globals, parties));
    }
}
