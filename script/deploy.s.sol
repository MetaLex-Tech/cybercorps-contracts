// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
         address stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; //sepolia base
        //use salt to deploy BorgAuth
        BorgAuth auth = new BorgAuth{salt: salt}();
        auth.initialize();
        address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));
        address cyberCertPrinterImplementation = address(new CyberCertPrinter());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "";
        cyberCertPrinter.initialize(defaultLegend, "", "", "ipfs.io/ipfs/[cid]", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());
        address dealManagerFactory = address(new DealManagerFactory());
        address registry = address(new CyberAgreementRegistry());
        CyberAgreementRegistry(registry).initialize(address(auth));
       /* string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "Purchase Amount";
        globalFieldsSafe[1] = "Post-Money Valuation Cap";
        globalFieldsSafe[2] = "Expiration Time";
        globalFieldsSafe[3] = "Governing Jurisdiction";
        globalFieldsSafe[4] = "Dispute Resolution";

        string[] memory partyFieldsSafe = new string[](3);
        partyFieldsSafe[0] = "Name";
        partyFieldsSafe[1] = "EVM Address";
        partyFieldsSafe[2] = "Contact";
        
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(1)), "SAFE", "ipfs.io/ipfs/[cid]", globalFieldsSafe, partyFieldsSafe);*/
        address uriBuilder = address(new CertificateUriBuilder());
        CyberCorpFactory cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, dealManagerFactory, uriBuilder, stable);

        console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
        console.log("CyberAgreementRegistry: ", address(registry));
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