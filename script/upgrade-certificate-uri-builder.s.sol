// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";

/// @title UpgradeCertificateUriBuilder
/// @notice Main upgrade script - deploys image builder and upgrades CertificateUriBuilder
/// @dev Run with: forge script script/upgrade-certificate-uri-builder.s.sol:UpgradeCertificateUriBuilder --rpc-url $RPC_URL --broadcast --verify
contract UpgradeCertificateUriBuilder is Script {
    function run() public {
        // Use different salts for different contracts to avoid CREATE2 collision
        bytes32 imageBuilderSalt = bytes32(keccak256("MetaLexCyberCorpImageBuilderV1.2"));
        bytes32 implementationSalt = bytes32(keccak256("MetaLexCyberCorpUriBuilderV2.5"));
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get the deployed CertificateUriBuilder proxy address from env
        address deployedCertificateUriBuilderProxy = 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3;
        
        console.log("=== CertificateUriBuilder Upgrade Script ===");
        console.log("Deployer address:", deployer);
        console.log("Target proxy:", deployedCertificateUriBuilderProxy);
    
        
        console.log("");
        console.log("=== Starting Deployment ===");
        
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy the new CertificateImageBuilderContract (standalone contract)
        CertificateImageBuilderContract imageBuilderContract = new CertificateImageBuilderContract{salt: imageBuilderSalt}();
        address imageBuilderAddr = address(imageBuilderContract);
        console.log("Step 1: CertificateImageBuilderContract deployed at:", imageBuilderAddr);

        // Step 2: Deploy new CertificateUriBuilder implementation
        CertificateUriBuilder newImplementation = new CertificateUriBuilder{salt: implementationSalt}();
        address newImplAddr = address(newImplementation);
        console.log("Step 2: New CertificateUriBuilder implementation deployed at:", newImplAddr);

        // Step 3: Upgrade the proxy to the new implementation
        CertificateUriBuilder(deployedCertificateUriBuilderProxy).upgradeToAndCall(newImplAddr, "");
        console.log("Step 3: CertificateUriBuilder proxy upgraded successfully");

        // Step 4: Set the image builder contract address on the upgraded CertificateUriBuilder
        CertificateUriBuilder(deployedCertificateUriBuilderProxy).setImageBuilder(imageBuilderAddr);
        console.log("Step 4: ImageBuilder set on CertificateUriBuilder");

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("");
        console.log("=== Post-Deployment Verification ===");
        address verifyImageBuilder = CertificateUriBuilder(deployedCertificateUriBuilderProxy).imageBuilder();
        console.log("Verified imageBuilder:", verifyImageBuilder);
        require(verifyImageBuilder == imageBuilderAddr, "ImageBuilder not set correctly!");
        console.log("Upgrade completed successfully!");
        
        console.log("");
        console.log("=== Summary ===");
        console.log("Proxy address:", deployedCertificateUriBuilderProxy);
        console.log("New implementation:", newImplAddr);
        console.log("Image builder:", imageBuilderAddr);
    }
}
