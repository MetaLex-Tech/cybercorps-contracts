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
         address stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;// 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;//0x036CbD53842c5426634e7929541eC2318f3dCF7e; //sepolia base
         address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
        //use salt to deploy BorgAuth
        BorgAuth auth = new BorgAuth{salt: salt}();
        auth.initialize();
        address issuanceManagerFactory = address(new IssuanceManagerFactory{salt: salt}());
        address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "";
        cyberCertPrinter.initialize(defaultLegend, "", "", "ipfs.io/ipfs/[cid]", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory{salt: salt}());
        address dealManagerFactory = address(new DealManagerFactory{salt: salt}());
        address registry = address(new CyberAgreementRegistry{salt: salt}());
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
        
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(1)), "SAFE", "https://ipfs.io/ipfs/bafybeidyuiymbeen46ggt6foln6yelfi5q4qu2diolhcdk324befwg2f4u", globalFieldsSafe, partyFieldsSafe);*/
        address uriBuilder = address(new CertificateUriBuilder{salt: salt}());
        CyberCorpFactory cyberCorpFactory = new CyberCorpFactory{salt: salt}(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, dealManagerFactory, uriBuilder);
        cyberCorpFactory.initialize(address(auth));
        cyberCorpFactory.setStable(stable);

        auth.updateRole(address(multisig), 200);
        auth.zeroOwner();

        console.log("auth: ", address(auth));
        console.log("issuanceManagerFactory: ", address(issuanceManagerFactory));
        console.log("cyberCorpSingleFactory: ", address(cyberCorpSingleFactory));
        console.log("dealManagerFactory: ", address(dealManagerFactory));
        console.log("uriBuilder: ", address(uriBuilder));
        console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
        console.log("CyberAgreementRegistry: ", address(registry));
        console.log("CyberCorpFactory: ", address(cyberCorpFactory));
        
     }
}