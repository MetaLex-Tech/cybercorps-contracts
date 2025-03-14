// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import {AgreementFactory} from "../dependencies/cyberCorpTripler/src/SAFEDealManager.sol";
import {DoubleTokenLexscrowRegistry} from "../dependencies/cyberCorpTripler/src/DoubleTokenLexscrowRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {ERC721LexscrowFactory} from "../dependencies/cyberCorpTripler/src/ERC721LexscrowFactory.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/CyberCorpConstants.sol";


contract CyberCorpTest is Test {
//     Counter public counter;


     CyberCorpFactory cyberCorpFactory; 

     function setUp() public {
       
        ///deploy cyberCertPrinterImplementation
        vm.startPrank(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
        address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));
        address cyberCertPrinterImplementation = address(new CyberCertPrinter());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        cyberCertPrinter.initialize("", "", "", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());


        DoubleTokenLexscrowRegistry registry = new DoubleTokenLexscrowRegistry(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
        address lexscrowFactory = address(new ERC721LexscrowFactory());
        address cyberAgreementFactory = address(new CyberAgreementFactory(address(lexscrowFactory)));

        cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, cyberAgreementFactory);
        registry.enableFactory(cyberAgreementFactory);
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
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
          _details
        );
     }
}
