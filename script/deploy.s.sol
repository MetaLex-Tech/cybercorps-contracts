// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberDealRegistry} from "../src/CyberDealRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";

contract BaseScript is Script {
     function run() public {
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
        BorgAuth auth = new BorgAuth();
        auth.initialize();
        address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));
        address cyberCertPrinterImplementation = address(new CyberCertPrinter());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        cyberCertPrinter.initialize("", "", "", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());
        address dealManagerFactory = address(new DealManagerFactory());
        address registry = address(new CyberDealRegistry());
        CyberDealRegistry(registry).initialize(address(auth));
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        CyberDealRegistry(registry).createTemplate(bytes32(uint256(1)), "SAFE", "ipfs.io/ipfs/[cid]", globalFields, partyFields);

        CyberCorpFactory cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, dealManagerFactory);
        // Add the cybercorpfactory as a registry admin so that it can in turn add privileged dealmanagers to support signing for the parties
        CyberDealRegistry(registry).addCyberCorpFactory(address(cyberCorpFactory));

        console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
        console.log("CyberDealRegistry: ", address(registry));
        console.log("CyberCorpFactory: ", address(cyberCorpFactory));

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