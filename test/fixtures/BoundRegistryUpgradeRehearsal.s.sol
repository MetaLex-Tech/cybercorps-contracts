// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../../src/CyberAgreementRegistry.sol";
import {CyberAgreementRegistryDeployment} from "../../script/libs/CyberAgreementRegistryDeployment.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Owner-gated contract stand-in, not a Safe implementation or a threshold/guard test.
contract RehearsalUpgradeAuthority {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function getThreshold() external pure returns (uint256) {
        return 1;
    }

    function execute(address target, bytes calldata data) external {
        require(msg.sender == owner, "Not rehearsal owner");
        (bool ok, bytes memory result) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }
}

contract BoundRegistryUpgradeRehearsal is Script {
    function run(string memory path, address owner) external {
        require(block.chainid == 31337, "Local rehearsal only");
        vm.startBroadcast(msg.sender);
        RehearsalUpgradeAuthority authority = new RehearsalUpgradeAuthority(owner);
        BorgAuth auth = new BorgAuth(address(authority));
        // The rehearsal runner subsequently grants the deployer owner access through the authority.
        CyberAgreementRegistry registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(CyberAgreementRegistryDeployment.deployRouter()),
                    abi.encodeCall(CyberAgreementRegistry.initialize, (address(auth)))
                )
            )
        );
        vm.stopBroadcast();
        vm.serializeAddress("fixture", "proxy", address(registry));
        vm.serializeAddress("fixture", "auth", address(auth));
        string memory json = vm.serializeAddress("fixture", "authority", address(authority));
        vm.writeJson(json, path);
    }
}
