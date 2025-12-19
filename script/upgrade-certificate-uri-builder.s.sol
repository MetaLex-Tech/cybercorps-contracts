// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";

contract UpgradeCertificateUriBuilder is Script {
    function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        
        // TODO: Set your deployed CertificateUriBuilder proxy address here
        // You can find this from your deploy logs or on-chain
        address deployedCertificateUriBuilderProxy = vm.envAddress("CERTIFICATE_URI_BUILDER_PROXY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        address newImplementation = address(new CertificateUriBuilder{salt: salt}());
        console.log("New CertificateUriBuilder implementation deployed at:", newImplementation);

        // Upgrade the proxy to the new implementation
        CertificateUriBuilder(deployedCertificateUriBuilderProxy).upgradeToAndCall(newImplementation, "");
        console.log("CertificateUriBuilder proxy upgraded successfully");

        vm.stopBroadcast();
    }
}

