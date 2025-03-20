// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";

import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";

contract BaseScript is Script {
     function run() public {

           /* address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
            vm.startBroadcast(deployerPrivateKey);

            address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));

            address cyberCertPrinterImplementation = address(new CyberCertPrinter());
            CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
            cyberCertPrinter.initialize("", "", "", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
            CyberCorpSingleFactory cyberCorpSingleFactory = new CyberCorpSingleFactory();

            CyberCorpFactory cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, address(cyberCorpSingleFactory), cyberAgreementFactory);
            registry.updateAdmin(address(cyberCorpFactory));
            cyberCorpFactory.acceptRegistryAdmin();
            vm.stopBroadcast();

            console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
            console.log("Registry: ", address(registry));
            console.log("CyberCorpFactory: ", address(cyberCorpFactory));
            console.log("lexscrowFactory: ", address(lexscrowFactory));
            console.log("cyberAgreementFactory: ", address(cyberAgreementFactory));*/
        
     }
}