// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {CertificateUriBuilder} from "../../src/CertificateUriBuilder.sol";
import {PreviousRenderingUriBuilder, PreviousImageRenderer} from "../UpgradeCertificateRenderingScript.t.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Local Anvil fixture only. These public toy keys must never hold real funds.
contract FooterUpgradeRehearsal is Script {
    function run() external {
        require(block.chainid == 31337, "Local rehearsal only");
        vm.startBroadcast(0xA11CE);
        BorgAuth auth = new BorgAuth(vm.addr(0xA11CE));
        auth.updateRole(vm.addr(0xB0B), 99);
        address implementation = address(new PreviousRenderingUriBuilder());
        CertificateUriBuilder builder = CertificateUriBuilder(address(new ERC1967Proxy(implementation,
            abi.encodeCall(CertificateUriBuilder.initialize, (address(auth))))));
        address image = address(new PreviousImageRenderer());
        builder.setImageBuilder(image);
        vm.stopBroadcast();
        string memory key = "footer-fixture";
        vm.serializeAddress(key, "proxy", address(builder));
        vm.serializeAddress(key, "implementation", implementation);
        vm.serializeAddress(key, "auth", address(auth));
        string memory json = vm.serializeAddress(key, "oldImage", image);
        vm.writeJson(json, "script/res/test-footer-rehearsal-fixture.json");
    }
}
