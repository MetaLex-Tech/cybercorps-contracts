// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../../script/libs/safe.sol";
import {UpgradeCoreScript} from "../../script/upgrade-core.s.sol";
import "forge-std/Test.sol";

/// @notice A second run of `UpgradeCoreScript` after the Safe signed the first batch finds nothing to deploy.
/// @dev The fork is pinned, so the first run always finds the same changes.
contract UpgradeCoreScriptForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 26_045_574;
    uint256 internal deployerKey = 0xA11CE;
    address internal deployer = vm.addr(0xA11CE);
    address internal safe;

    function setUp() public {
        vm.createSelectFork("ethereum", PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        safe = DeploymentConstants.coreV2(block.chainid).metalexSafe;
    }

    function test_SecondRunAfterSafeBatchDeploysNothing() public {
        // Run 1: the deployer holds no role on mainnet, so every upgrade and setter goes to the Safe.
        GnosisTransaction[] memory safeTxs = (new UpgradeCoreScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(safeTxs.length, 16);
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(safe);
            (bool success,) = safeTxs[i].to.call(safeTxs[i].data);
            assertTrue(success);
        }

        // Run 2: every implementation and parameter is unchanged, so the deployer sends nothing
        // and the Safe has nothing to sign.
        uint256 nonce = vm.getNonce(deployer);
        safeTxs = (new UpgradeCoreScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(safeTxs.length, 0);
    }
}
