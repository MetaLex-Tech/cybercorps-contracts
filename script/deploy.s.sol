// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import {AgreementV2Factory} from "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";
import {DoubleTokenLexscrowRegistry} from "../dependencies/cyberCorpTripler/src/DoubleTokenLexscrowRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {ERC721LexscrowFactory} from "../dependencies/cyberCorpTripler/src/ERC721LexscrowFactory.sol";
import {console} from "forge-std/console.sol";

contract BaseScript is Script {
     function run() public {

            address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
            vm.startBroadcast(deployerPrivateKey);

            address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));

            address cyberCertPrinterImplementation = address(new CyberCertPrinter());
            CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
            cyberCertPrinter.initialize("", "", "", address(0));
            CyberCorpSingleFactory cyberCorpSingleFactory = new CyberCorpSingleFactory();

            DoubleTokenLexscrowRegistry registry = new DoubleTokenLexscrowRegistry(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
            address lexscrowFactory = address(new ERC721LexscrowFactory());
            address cyberAgreementFactory = address(new CyberAgreementFactory(address(lexscrowFactory)));
            CyberCorpFactory cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, address(cyberCorpSingleFactory), cyberAgreementFactory);
            registry.updateAdmin(address(cyberCorpFactory));
            cyberCorpFactory.acceptRegistryAdmin();
            vm.stopBroadcast();

            console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
            console.log("Registry: ", address(registry));
            console.log("CyberCorpFactory: ", address(cyberCorpFactory));

     }
}