// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ILexChexBadge} from "../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

/// @notice Keeper run that evicts expired LeXcheXBadge credentials so compliance read scans stay bounded.
/// Expiry eviction cannot happen on read (the getters are view, since conditions staticcall them), so it has to
/// be driven from outside. Permissionless — no admin key is needed, only gas.
///
/// Discovery happens here in the simulation, where reads are free: for each holder it walks the active set,
/// keeps the ids whose expiryDate has passed, and broadcasts sweepTokens in fixed-size batches. Batching by
/// calldata rather than calling sweep(holder) is what makes an oversized set drainable — a full-set sweep that
/// does not fit in a block reverts and evicts nothing, while every batch here stands on its own.
///
/// HOLDERS is a comma-separated address list, e.g.
///   HOLDERS=0xabc...,0xdef... forge script script/sweep-lexchex-badge.s.sol --rpc-url $RPC --broadcast
/// BADGE overrides the deployment default; BATCH_SIZE overrides the ids per transaction. The badge is not
/// deployed on any chain yet, so BADGE is required until DeploymentConstants carries a real lexchexBadge.
contract SweepLexchexBadgeScript is Script {
    uint256 constant DEFAULT_BATCH_SIZE = 50;

    function run() public {
        address badgeAddr = vm.envOr("BADGE", DeploymentConstants.coreV2(block.chainid).lexchexBadge);
        uint256 batchSize = vm.envOr("BATCH_SIZE", DEFAULT_BATCH_SIZE);
        address[] memory holders = vm.envAddress("HOLDERS", ",");
        require(badgeAddr != address(0), "no LeXcheXBadge for this chain: set BADGE");
        require(batchSize > 0, "BATCH_SIZE must be positive");

        ILexChexBadge badge = ILexChexBadge(badgeAddr);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        console.log("badge", badgeAddr);

        for (uint256 h = 0; h < holders.length; h++) {
            address holder = holders[h];
            uint256[] memory expired = _expiredOf(badge, holder);
            console.log("holder", holder);
            console.log("  expired credentials", expired.length);
            if (expired.length == 0) continue;

            for (uint256 start = 0; start < expired.length; start += batchSize) {
                uint256 size = expired.length - start;
                if (size > batchSize) size = batchSize;
                uint256[] memory batch = new uint256[](size);
                for (uint256 i = 0; i < size; i++) batch[i] = expired[start + i];

                vm.startBroadcast(deployerPrivateKey);
                uint256 evicted = badge.sweepTokens(batch);
                vm.stopBroadcast();
                console.log("  evicted in batch", evicted);
            }
        }
    }

    /// @dev The holder's active ids whose expiry has passed. Read-only, so it runs in the simulation for free
    /// even for a set far too large to scan inside a transaction.
    function _expiredOf(ILexChexBadge badge, address holder) internal view returns (uint256[] memory) {
        uint256[] memory active = badge.getActiveTokenIds(holder);
        uint256[] memory found = new uint256[](active.length);
        uint256 n;
        for (uint256 i = 0; i < active.length; i++) {
            Credential memory cred = badge.getCredential(active[i]);
            if (block.timestamp > cred.expiryDate) found[n++] = active[i];
        }
        uint256[] memory expired = new uint256[](n);
        for (uint256 i = 0; i < n; i++) expired[i] = found[i];
        return expired;
    }
}
