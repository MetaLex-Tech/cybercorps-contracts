// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CommonBase, Vm} from "forge-std/Base.sol";
import {console2} from "forge-std/console2.sol";

library KnownAddressesLoader {
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct KnownAddresses {
        KnownAddress[] addresses;
    }

    struct KnownAddress {
        address addr;
        uint256 chainId;
    }

    function load(uint256 chainId, string memory path, uint256 maxCount) internal returns (address[] memory) {
        KnownAddresses memory knownAddresses = abi.decode(
            vm.parseJson(
                vm.readFile(
                    string.concat(
                        vm.projectRoot(),
                        path
                    )
                )
            ),
            (KnownAddresses)
        );

        // First pass: count matches
        uint256 filterCount = 0;
        for (uint256 i = 0; i < knownAddresses.addresses.length; i++) {
            // Filter by chain ID
            if (knownAddresses.addresses[i].chainId == chainId) {
                filterCount++;
                if (filterCount >= maxCount) {
                    break;
                }
            }
        }

        // Second pass: fill the results
        address[] memory knownAddrs = new address[](filterCount);
        uint256 filterIdx = 0;
        for (uint256 i = 0; i < knownAddresses.addresses.length; i++) {
            // Filter by chain ID
            if (knownAddresses.addresses[i].chainId == chainId) {
                knownAddrs[filterIdx++] = knownAddresses.addresses[i].addr;
                if (filterIdx >= filterCount) {
                    break;
                }
            }
        }

        console2.log("Loaded %s: %d known managers on chain ID: %d ...", path, filterCount, chainId);

        return knownAddrs;
    }
}
