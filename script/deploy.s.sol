// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import {AgreementV2Factory} from "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";
import {DoubleTokenLexscrowRegistry} from "../dependencies/cyberCorpTripler/src/DoubleTokenLexscrowRegistry.sol";
import {console} from "forge-std/console.sol";

contract BaseScript is Script {
     function run() public {

            address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
            vm.startBroadcast(deployerPrivateKey);

            address cyberCertPrinterImplementation = address(new CyberCertPrinter());
            CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
            cyberCertPrinter.initialize("", "", "", address(0));

            DoubleTokenLexscrowRegistry registry = new DoubleTokenLexscrowRegistry(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
            CyberCorpFactory cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation);
            registry.updateAdmin(address(cyberCorpFactory));
            cyberCorpFactory.acceptRegistryAdmin();
            vm.stopBroadcast();

            console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
            console.log("Registry: ", address(registry));
            console.log("CyberCorpFactory: ", address(cyberCorpFactory));

     }
}