// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RobinhoodPostUpgradeLifecycleTest} from "./RobinhoodPostUpgradeLifecycleTest.t.sol";

/// @notice Strict post-registration acceptance of actually deployed contracts.
/// The runner excludes the inherited historical missing-template scenario.
/// No template registration, upgrade, role change or deployment script is called.
contract RobinhoodLiveTemplateLifecycleTest is RobinhoodPostUpgradeLifecycleTest {
    function _installBaseTemplateFixtureIfMissing() internal override {
        // Deliberately read only: missing or invalid live configuration must fail.
        _requireLiveSafeTemplate();
    }

    function test_LiveSafeTemplateIsConfigured() public forkOnly {
        assertEq(block.chainid, 4663);
        _requireLiveSafeTemplate();
    }

    function _requireLiveSafeTemplate() internal view {
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(TEMPLATE);
        assertEq(uri, "IPFS://bafybeib5pqnqwbfdsnv4lqdkdglz2e4xqz2qklwdzzpbftydopzuqnri2a");
        assertEq(title, "MetaLeX cyberSAFE jx-neutral-style Reg S raise");
        assertEq(globals.length, 5);
        assertEq(globals[0], "purchaseAmount");
        assertEq(globals[1], "postMoneyValuationCap");
        assertEq(globals[2], "expirationTime");
        assertEq(globals[3], "governingJurisdiction");
        assertEq(globals[4], "disputeResolution");
        assertEq(parties.length, 5);
        assertEq(parties[0], "name");
        assertEq(parties[1], "evmAddress");
        assertEq(parties[2], "contactDetails");
        assertEq(parties[3], "investorType");
        assertEq(parties[4], "investorJurisdiction");
    }
}
