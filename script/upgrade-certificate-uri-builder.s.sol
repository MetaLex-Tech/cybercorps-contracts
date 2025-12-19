// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";

/// @notice Main upgrade script - deploys image builder and upgrades CertificateUriBuilder
contract UpgradeCertificateUriBuilder is Script {
    function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.3"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        
        // Set your deployed CertificateUriBuilder proxy address here
        address deployedCertificateUriBuilderProxy = vm.envAddress("CERTIFICATE_URI_BUILDER_PROXY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy the new CertificateImageBuilderContract (standalone contract)
        address imageBuilderContract = address(new CertificateImageBuilderContract{salt: salt}());
        console.log("CertificateImageBuilderContract deployed at:", imageBuilderContract);

        // Step 2: Deploy new CertificateUriBuilder implementation
        address newImplementation = address(new CertificateUriBuilder{salt: salt}());
        console.log("New CertificateUriBuilder implementation deployed at:", newImplementation);

        // Step 3: Upgrade the proxy to the new implementation
        CertificateUriBuilder(deployedCertificateUriBuilderProxy).upgradeToAndCall(newImplementation, "");
        console.log("CertificateUriBuilder proxy upgraded successfully");

        // Step 4: Set the image builder contract address on the upgraded CertificateUriBuilder
        CertificateUriBuilder(deployedCertificateUriBuilderProxy).setImageBuilder(imageBuilderContract);
        console.log("ImageBuilder set on CertificateUriBuilder");

        vm.stopBroadcast();
    }
}

/// @notice Script to only deploy the image builder (if you need to update it separately)
contract DeployImageBuilder is Script {
    function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.3"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        
        vm.startBroadcast(deployerPrivateKey);

        address imageBuilderContract = address(new CertificateImageBuilderContract{salt: salt}());
        console.log("CertificateImageBuilderContract deployed at:", imageBuilderContract);

        vm.stopBroadcast();
    }
}

/// @notice Script to set/update the image builder address on an existing CertificateUriBuilder
contract SetImageBuilder is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployedCertificateUriBuilderProxy = vm.envAddress("CERTIFICATE_URI_BUILDER_PROXY");
        address imageBuilderContract = vm.envAddress("IMAGE_BUILDER_CONTRACT");
        
        vm.startBroadcast(deployerPrivateKey);

        CertificateUriBuilder(deployedCertificateUriBuilderProxy).setImageBuilder(imageBuilderContract);
        console.log("ImageBuilder set on CertificateUriBuilder:", imageBuilderContract);

        vm.stopBroadcast();
    }
}
