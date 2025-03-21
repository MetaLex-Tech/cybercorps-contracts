// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateDetails, IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberDealRegistry} from "../src/CyberDealRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";



contract CyberCorpTest is Test {
//     Counter public counter;


     CyberCorpFactory cyberCorpFactory; 
     CyberDealRegistry registry;
     uint256 testPrivateKey;
     address testAddress;

     function setUp() public {
       
        ///deploy cyberCertPrinterImplementation
        testPrivateKey = 1337;
        testAddress = vm.addr(testPrivateKey);
        vm.startPrank(testAddress);
        BorgAuth auth = new BorgAuth();
        auth.initialize();
        address issuanceManagerFactory = address(new IssuanceManagerFactory(address(0)));
        address cyberCertPrinterImplementation = address(new CyberCertPrinter());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);
        cyberCertPrinter.initialize("", "", "", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());

        address dealManagerFactory = address(new DealManagerFactory());

        registry = new CyberDealRegistry();
        CyberDealRegistry(registry).initialize(address(auth));
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        registry.createTemplate(bytes32(uint256(1)), "SAFE", "ipfs.io/ipfs/[cid]", globalFields, partyFields);

        cyberCorpFactory = new CyberCorpFactory(address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, dealManagerFactory);

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


       string[] memory globalValues = new string[](1);
       globalValues[0] = "Global Value 1";
       address[] memory parties = new address[](2);
       parties[0] = address(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
       parties[1] = address(0);
       uint256 _paymentAmount = 1000000000000000000;
       string[] memory partyValues = new string[](1);
       partyValues[0] = "Party Value 1";
       
       bytes32 contractId = keccak256(abi.encode(bytes32(uint256(1)), globalValues, parties));
       
       bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            globalValues,
            partyValues,
            testPrivateKey
       );

      cyberCorpFactory.deployCyberCorpAndCreateOffer(
        bytes32(uint256(1)),
        "CyberCorp",
        0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B,
        "SAFE",
        "SAFE",
        SecurityClass.SAFE,
        SecuritySeries.SeriesPreSeed,
        bytes32(uint256(1)),
        globalValues,
        parties,
        _paymentAmount,
        partyValues,
        signature,
        _details
      );
     }

     function testCreateContract() public {
      vm.startPrank(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
      BorgAuth auth = new BorgAuth();
      auth.initialize();
      CyberDealRegistry registry = new CyberDealRegistry();
      registry.initialize(address(auth));
      string[] memory globalFields = new string[](1);
      globalFields[0] = "Global Field 1";
      string[] memory partyFields = new string[](1);
      partyFields[0] = "Party Field 1";
      string[] memory globalValues = new string[](1);
      globalValues[0] = "Global Value 1";
      string[] memory partyValues = new string[](1);
      partyValues[0] = "Party Value 1";

      string[] memory partyValuesB = new string[](1);
      partyValuesB[0] = "Party Value B";
      address[] memory parties = new address[](2);
      parties[0] = address(testAddress);
      parties[1] = address(0);
      registry.createTemplate(bytes32(uint256(1)), "CyberCorp", "ipfs.io/ipfs/[cid]", globalFields, partyFields);
      bytes32 id = registry.createContract(bytes32(uint256(1)), globalValues, parties);
      
      bytes32 contractId = keccak256(abi.encode(bytes32(uint256(1)), globalValues, parties));
      
      bytes memory signature = _signAgreementTypedData(
           registry.DOMAIN_SEPARATOR(),
           registry.SIGNATUREDATA_TYPEHASH(),
           contractId,
           globalValues,
           partyValues,
           testPrivateKey
      );      
 
      registry.signContract(id, partyValues, signature, false);
      string memory contractURI = registry.getContractJson(bytes32(uint256(1)));
      
      uint256 newPartyPk = 80085;
      address newPartyAddr = vm.addr(newPartyPk);
      
      signature = _signAgreementTypedData(
           registry.DOMAIN_SEPARATOR(),
           registry.SIGNATUREDATA_TYPEHASH(),
           contractId,
           globalValues,
           partyValuesB,
           newPartyPk
      );      
      
      vm.stopPrank();
      vm.startPrank(newPartyAddr);
      registry.signContract(id, partyValuesB, signature, true);
      contractURI = registry.getContractJson(id);
      console.log(contractURI);
      vm.stopPrank();
     }

     function testNet() public {
      vm.startPrank(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
      CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8);
      
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
      

      /*    function deployCyberCorpAndCreateOffer(
        bytes32 salt,
        string memory companyName,
        address _companyPayable,
        string memory certName,
        string memory certSymbol,
        SecurityClass securityClass,
        SecuritySeries securitySeries,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[] memory _partyValues,
        CertificateDetails memory _details
    )*/

       string[] memory globalValues = new string[](1);
       globalValues[0] = "Global Value 1";
       address[] memory parties = new address[](2);
       parties[0] = address(testAddress);
       parties[1] = address(0);
       uint256 _paymentAmount = 1000000000000000000;
       string[] memory partyValues = new string[](1);
       partyValues[0] = "Party Value 1";
       
       bytes32 contractId = keccak256(abi.encode(bytes32(uint256(1)), globalValues, parties));
       
       bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            globalValues,
            partyValues,
            testPrivateKey
       );

      (address cyberCorp, address auth, address issuanceManager, address dealManagerAddr, address cyberCertPrinterAddr, bytes32 id) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
        bytes32(uint256(1)),
        "CyberCorp",
        testAddress,
        "SAFE",
        "SAFE",
        SecurityClass.SAFE,
        SecuritySeries.SeriesPreSeed,
        bytes32(uint256(1)),
        globalValues,
        parties,
        _paymentAmount,
        partyValues,
        proposerSignature,
        _details
      );
      vm.stopPrank();

      uint256 newPartyPk = 80085;
      address newPartyAddr = vm.addr(newPartyPk);
      string[] memory partyValuesB = new string[](1);
      partyValuesB[0] = "Party Value B";
            
      vm.startPrank(newPartyAddr);
      bytes memory newPartySignature = _signAgreementTypedData(
              registry.DOMAIN_SEPARATOR(),
              registry.SIGNATUREDATA_TYPEHASH(),
              contractId,
              globalValues,
              partyValuesB,
              newPartyPk
      );           
      IDealManager dealManager = IDealManager(dealManagerAddr);
      deal(0x036CbD53842c5426634e7929541eC2318f3dCF7e, newPartyAddr,_paymentAmount);
      IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(address(dealManager), _paymentAmount);
      dealManager.finalizeDeal(newPartyAddr, id, partyValuesB, newPartySignature, true);
      vm.stopPrank();
     }


    function _signAgreementTypedData (
        bytes32 _domainSeparator,
        bytes32 _typeHash,
        bytes32 contractId,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparator, keccak256(
           abi.encode(
              _typeHash,
              contractId,
              globalValues,
              partyValues
           ) 
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);        
        return signature;
    }
}