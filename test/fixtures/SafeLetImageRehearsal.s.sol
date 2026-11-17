// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {CertificateUriBuilder} from "../../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParams, SecurityClass} from "../../src/CyberCorpConstants.sol";
import {PreviousRenderingUriBuilder, PreviousImageRenderer} from "../UpgradeCertificateRenderingScript.t.sol";
import {RehearsalUpgradeAuthority} from "./BoundRegistryUpgradeRehearsal.s.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SafeLetImageReadback {
    function render(address image) external pure returns (string memory) {
        CertificateSVGParams memory p;
        p.securityType = SecurityClass.SAFE;
        p.units = 40_000e18;
        p.considerationKnown = false;
        return CertificateImageBuilderContract(image).buildCertificateSVG(p, 0);
    }
}

/// @dev Local-only contract authority stand-in. Does not test Safe thresholds or guards.
contract SafeLetImageRehearsal is Script {
    function run(string memory path, address owner) external {
        require(block.chainid == 31337, "Local rehearsal only");
        vm.startBroadcast(msg.sender);
        RehearsalUpgradeAuthority authority = new RehearsalUpgradeAuthority(owner);
        // Both deployer and authority own the proxy; the upgrade script must still export the owner call.
        BorgAuth auth = new BorgAuth(msg.sender);
        auth.updateRole(address(authority), 99);
        address implementation = address(new PreviousRenderingUriBuilder());
        CertificateUriBuilder builder = CertificateUriBuilder(address(new ERC1967Proxy(implementation,
            abi.encodeCall(CertificateUriBuilder.initialize, (address(auth))))));
        address image = address(new PreviousImageRenderer());
        builder.setImageBuilder(image);
        SafeLetImageReadback readback = new SafeLetImageReadback();
        vm.stopBroadcast();
        vm.serializeAddress("fixture", "proxy", address(builder));
        vm.serializeAddress("fixture", "auth", address(auth));
        vm.serializeAddress("fixture", "oldImage", image);
        vm.serializeAddress("fixture", "readback", address(readback));
        string memory json = vm.serializeAddress("fixture", "authority", address(authority));
        vm.writeJson(json, path);
    }
}
