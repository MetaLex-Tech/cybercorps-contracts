// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManager} from "../src/DealManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2.Upgrade"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));
        address deployedFactoryAddr = 0x493f41876E4b681B6e0913Fa92C527183D5E1233;
        DealManagerFactory deployedFactory = DealManagerFactory(deployedFactoryAddr);
        address newImplementation = address(new DealManager{salt: salt}());
        console.log("New DealManager implementation deployed at:", newImplementation);
        //deployedFactory.upgradeImplementation(newImplementation);
        
        address newRegistryImplementation = address(new CyberAgreementRegistry{salt: salt}());
        console.log("New CyberAgreementRegistry implementation deployed at:", newRegistryImplementation);
        // Upgrade the CyberAgreementRegistry
       // CyberAgreementRegistry(registry).upgradeToAndCall(newRegistryImplementation, "");

        // Verify the upgrade was successful
        address updatedImplementation = deployedFactory.getBeaconImplementation();
        console.log("Updated DealManager beacon implementation:", updatedImplementation);

        address newDealManagerImplementation = address(new DealManager{salt: salt}());

        
     }
}