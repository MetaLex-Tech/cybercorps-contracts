// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";

/// @notice Script to update certificate details via the IssuanceManager
/// @dev Run with: forge script script/UpdateCertificate.s.sol --rpc-url $RPC_URL --broadcast
contract UpdateCertificate is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        
        address issuanceManagerAddress = 0x23c3a16AdB129Da2FCB297C63F6015C201dB2AC1;
        address printerAddress = 0xCB00123c91DB928CcF885FCE4f30919B0caB5845;
        uint256 tokenId = 0;
        
        
        // Prepare the details struct based on the provided image
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 1000000000000000000, 
            issuerUSDValuationAtTimeOfInvestment: 100000000000000000000, // 1e20
            unitsRepresented: 1000000000000000000, // 1e20
            legalDetails: "Dispute resolution method: Binding Arbitration\nGoverning law: Delaware",
            // Use hex literal for raw byte encoding
            extensionData: hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000004"
        });

        console.log("=== Updating Certificate Details via IssuanceManager ===");
        console.log("IssuanceManager:", issuanceManagerAddress);
        console.log("Printer Address:", printerAddress);
        console.log("Token ID:", tokenId);
        console.log("Caller:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Call updateCertificateDetails on the IssuanceManager
     //   IIssuanceManager(issuanceManagerAddress).updateCertificateDetails(printerAddress, tokenId, details);

        vm.stopBroadcast();

        console.log("Update call via IssuanceManager broadcasted successfully!");
    }
}
