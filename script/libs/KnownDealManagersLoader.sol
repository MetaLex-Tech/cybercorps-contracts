// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CommonBase, Vm} from "forge-std/Base.sol";
import {console2} from "forge-std/console2.sol";

library KnownDealManagersLoader {
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct KnownDealManagers {
        KnownDealManager[] dealManagers;
    }

    struct KnownDealManager {
        address addr;
        uint256 chainId;
    }

    function load(uint256 chainId) internal returns (address[] memory) {
        KnownDealManagers memory knownDealManagers = abi.decode(
            vm.parseJson(
                vm.readFile(
                    string.concat(
                        vm.projectRoot(),
                        "/script/res/known-deal-managers.json"
                    )
                )
            ),
            (KnownDealManagers)
        );

        // First pass: count matches
        uint256 filterCount = 0;
        for (uint256 i = 0; i < knownDealManagers.dealManagers.length; i++) {
            // Filter by chain ID
            if (knownDealManagers.dealManagers[i].chainId == chainId) {
                filterCount++;
            }
        }

        // Second pass: fill the results
        address[] memory knownDealManagerAddrs = new address[](filterCount);
        uint256 filterIdx = 0;
        for (uint256 i = 0; i < knownDealManagers.dealManagers.length; i++) {
            // Filter by chain ID
            if (knownDealManagers.dealManagers[i].chainId == chainId) {
                knownDealManagerAddrs[filterIdx++] = knownDealManagers.dealManagers[i].addr;
            }
        }

        console2.log("Loaded %d known deal managers on chain ID: %d ...", filterCount, chainId);

        return knownDealManagerAddrs;
    }
}
