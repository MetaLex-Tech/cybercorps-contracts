// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import {AgreementV2Factory} from "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";
import {DoubleTokenLexscrowRegistry} from "../dependencies/cyberCorpTripler/src/DoubleTokenLexscrowRegistry.sol";
// import {Counter} from "../src/Counter.sol";

contract CyberCorpTest is Test {
//     Counter public counter;


     CyberCorpFactory cyberCorpFactory; 

     function setUp() public {
       
        ///deploy cyberCertPrinterImplementation
        vm.startPrank(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
        address cyberCertPrinterImplementation = address(new CyberCertPrinter());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        cyberCertPrinter.initialize("", "", "", address(0));

        DoubleTokenLexscrowRegistry registry = new DoubleTokenLexscrowRegistry(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
        cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation);
        registry.updateAdmin(address(cyberCorpFactory));
        cyberCorpFactory.acceptRegistryAdmin();
        vm.stopPrank();
     }

     function testOffer() public {
 //create salt
        bytes32 salt = bytes32(uint256(1));

          CertificateDetails memory _details = CertificateDetails({
          investorName: "",
          signingOfficerName: "",
          signingOfficerTitle: "",
          investmentAmount: 0,
          issuerUSDValuationAtTimeofInvestment: 10000000,
          unitsRepresented: 0,
          transferable: false,
          legalDetails: "Legal Details, jusidictione etc",
          issuerSignatureURI: ""
        });


        cyberCorpFactory.deployCyberCorpAndCreateOffer(
             salt,
            "CyberCorp",
            "",
            "",
            _details
        );
     }
}
