// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MinimumRaiseFixture} from "./RoundManagerMinimumRaiseTest.t.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {Round} from "../src/libs/RoundLib.sol";
import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";

/// @notice Upgrade from the deployed v5 RoundManager to 5.1 keeps existing state.
/// @dev Runs on a Base fork. The company's RoundManager proxy first runs the exact v5 reference
/// implementation that the Base RoundManagerFactory serves (with its deployed linked libraries).
/// The test builds real state with that code (a founder-approved round, one allocated EOI and
/// two escrowed EOIs), upgrades the proxy to the local 5.1 build, and checks that the state
/// reads the same and every existing path still works. Needs `RPC_URL_BASE`; skipped without it.
contract RoundManagerMinimumRaiseUpgradeForkTest is MinimumRaiseFixture {
    /// @dev Reference implementation of the Base RoundManagerFactory 0xc9d5…aeb9, read 2026-11-13.
    address internal constant BASE_V5_ROUND_MANAGER_IMPL = 0xce8bdfa4D393649dE880AEdef01BAF6a39d59d08;
    uint256 internal constant FORK_BLOCK = 56958568;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_URL_BASE", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
        _deployFixture(BASE_V5_ROUND_MANAGER_IMPL);
    }

    function test_UpgradeFromDeployedV5_KeepsStateAndPaths() public {
        assertEq(RoundManager(roundManager).DEPLOY_VERSION(), "5", "fixture must start on the deployed v5 build");

        // State built by the deployed v5 code.
        bytes32 roundId = _createPlainRound(VALUATION);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        bytes32 a2 = _submitEOI(roundId, 2);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(a0, MAX_TICKET);

        Round memory before = RoundManager(roundManager).getRound(roundId);
        Escrow memory e1Before = RoundManager(roundManager).getEscrowDetails(a1);

        // MetaLeX releases 5.1; the company accepts the upgrade.
        address next = address(new RoundManager());
        vm.prank(owner);
        RoundManagerFactory(rmFactory).setRefImplementation(next);
        vm.prank(corpOwner);
        RoundManager(roundManager).upgradeToAndCall(next, "");
        assertEq(RoundManager(roundManager).DEPLOY_VERSION(), "5.1");

        // Existing state reads the same.
        Round memory afterUpgrade = RoundManager(roundManager).getRound(roundId);
        assertEq(afterUpgrade.id, before.id);
        assertEq(afterUpgrade.raised, before.raised);
        assertEq(afterUpgrade.raiseCap, before.raiseCap);
        assertEq(afterUpgrade.endTime, before.endTime);
        assertEq(afterUpgrade.templateId, before.templateId);
        assertEq(afterUpgrade.paymentToken, before.paymentToken);
        assertEq(uint8(afterUpgrade.roundType), uint8(before.roundType));
        assertEq(afterUpgrade.authorityOfficer, before.authorityOfficer);

        Escrow memory e1After = RoundManager(roundManager).getEscrowDetails(a1);
        assertEq(uint256(e1After.status), uint256(e1Before.status));
        assertEq(e1After.counterParty, e1Before.counterParty);
        assertEq(e1After.buyerAssets[0].amount, e1Before.buyerAssets[0].amount);
        _assertAllocated(a0);

        (uint256 minRaise, uint256 deadline, bool met, uint256 raised, uint256 committed) =
            RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(minRaise, 0, "an existing round has no minimum");
        assertEq(deadline, 0);
        assertFalse(met);
        assertEq(raised, before.raised);
        assertEq(committed, 0);

        // Existing paths still work on the round created before the upgrade.
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(a1, MAX_TICKET);
        _assertAllocated(a1);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        uint256 balanceBefore = paymentToken.balanceOf(investors[2]);
        vm.prank(investors[2]);
        RoundManager(roundManager).recallEOI(a2);
        assertEq(paymentToken.balanceOf(investors[2]), balanceBefore + MAX_TICKET);
    }

    function test_UpgradeFromDeployedV5_MinimumRoundWorks() public {
        address next = address(new RoundManager());
        vm.prank(owner);
        RoundManagerFactory(rmFactory).setRefImplementation(next);
        vm.prank(corpOwner);
        RoundManager(roundManager).upgradeToAndCall(next, "");

        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.MinimumNotMet.selector);
        RoundManager(roundManager).allocate(a0, MAX_TICKET);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);
        _markMet(roundId, ids);
        RoundManager(roundManager).settle(ids);

        _assertAllocated(a0);
        _assertAllocated(a1);
        (, , bool met, uint256 raised, uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertTrue(met);
        assertEq(raised, MIN_RAISE);
        assertEq(committed, 0);
    }
}
