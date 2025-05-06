/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter, Endorsement} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory, IssuanceManager} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {CompanyOfficer} from "../src/storage/CyberCertPrinterStorage.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DealManager} from "../src/DealManager.sol";
import {Escrow} from "../src/storage/LexScrowStorage.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {TokenWarrantExtension, TokenWarrantData} from "../src/storage/extensions/TokenWarrantExtension.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

contract CyberCorpTest is Test {
    using ERC1967ProxyLib for address;

    //     Counter public counter;

    CyberCorpFactory cyberCorpFactory;
    CyberAgreementRegistry registry;
    uint256 testPrivateKey;
    address testAddress;
    BorgAuth auth;
    address counterPartyAddress = 0x1A762EfF397a3C519da3dF9FCDDdca7D1BD43B5e;
    address[] conditions = new address[](0);
    string[][] legend = new string[][](0);
    address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    SecurityClass[] securityClasses;
    SecuritySeries[] securitySerieses;
    CyberCorpFactory.CyberCertData[] certData;

    string[] certNames;
    string[] certSymbols;
    string[] certificateUris;
    string[][] defaultLegends;
    address[] extensions;

    function setUp() public {
        testPrivateKey = 1337;
        testAddress = vm.addr(testPrivateKey);
        vm.startPrank(testAddress);

        /*        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        CertificateDetails _details;
        string[] defaultLegend;
        address extensions;*/

          string[] memory _dataDefaultString = new string[](1);
            _dataDefaultString[0] = "Legend 1";

        CyberCorpFactory.CyberCertData memory _certData = CyberCorpFactory.CyberCertData({
            name: "Cert Name 1",
            symbol: "Cert Symbol 1",
            uri: "ipfs.io/ipfs/[cid]",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: _dataDefaultString
        });
        certData = new CyberCorpFactory.CyberCertData[](1);
        certData[0] = _certData;

        securityClasses = new SecurityClass[](1);
        securityClasses[0] = SecurityClass.SAFE;
        securitySerieses = new SecuritySeries[](1);
        securitySerieses[0] = SecuritySeries.SeriesPreSeed;
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunch"));
        address stableMainNetEth = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address stableArbitrum = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address stableBase = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; //0x036CbD53842c5426634e7929541eC2318f3dCF7e;// 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;//0x036CbD53842c5426634e7929541eC2318f3dCF7e; //sepolia base

        extensions = new address[](1);
        extensions[0] = address(0);

        certNames = new string[](1);
        certNames[0] = "Cert Name 1";
        certSymbols = new string[](1);
        certSymbols[0] = "Cert Symbol 1";
        certificateUris = new string[](1);
        certificateUris[0] = "ipfs.io/ipfs/[cid]";

        //use salt to deploy BorgAuth
        auth = new BorgAuth{salt: salt}(testAddress);
        //auth.initialize();
        address issuanceManagerFactory = address(
            new IssuanceManagerFactory{salt: salt}(address(auth))
        );

        address cyberCertPrinterImplementation = address(
            new CyberCertPrinter{salt: salt}()
        );
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(
            cyberCertPrinterImplementation
        );

        defaultLegends = new string[][](1);
        defaultLegends[0] = new string[](1);
        defaultLegends[0][0] = "Legend 1";

        //cyberCertPrinter.initialize(defaultdefaultLegends, "", "", "ipfs.io/ipfs/[cid]", address(0), securityClasses, SecuritySeries.SeriesPreSeed);

        address cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: salt}(address(auth))
        );

        address dealManagerFactory = address(
            new DealManagerFactory{salt: salt}(address(auth))
        );

        // Deploy upgradeable singletons

        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        address uriBuilder = address(new ERC1967Proxy{salt: salt}(
            address(new CertificateUriBuilder{salt: salt}()),
            abi.encodeWithSelector(
                CertificateUriBuilder.initialize.selector,
                address(auth)
            )
        ));

        cyberCorpFactory = CyberCorpFactory(address(new ERC1967Proxy{salt: salt}(
            address(new CyberCorpFactory{salt: salt}()),
            abi.encodeWithSelector(
                CyberCorpFactory.initialize.selector,
                address(auth),
                address(registry),
                cyberCertPrinterImplementation,
                issuanceManagerFactory,
                cyberCorpSingleFactory,
                dealManagerFactory,
                uriBuilder
            )
        )));
        cyberCorpFactory.setStable(stable);

        string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";

        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "name";
        partyFieldsSafe[1] = "evmAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "investorType";
        partyFieldsSafe[4] = "investorJurisdiction";

        registry.createTemplate(
            bytes32(uint256(2)),
            "SAFE",
            "https://ipfs.io/ipfs/bafybeieee4xjqpwcq5nowm4iqw6ik4wkwpz7uqohl3yamypwz54was2h64",
            globalFieldsSafe,
            partyFieldsSafe
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        registry.createTemplate(
            bytes32(uint256(1)),
            "Test",
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields
        );

        auth.updateRole(address(multisig), 200);
        auth.zeroOwner();
        auth.userRoles(multisig);
        vm.stopPrank();
    }

    function testOffer() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        string[] memory certName = new string[](1);
        certName[0] = "Cert Name 1";
        string[] memory certSymbol = new string[](1);
        certSymbol[0] = "Cert Symbol 1";
        string[] memory certificateUri = new string[](1);
        certificateUri[0] = "ipfs.io/ipfs/[cid]";

        vm.startPrank(testAddress);
        cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();
    }

    function testCreateClosedContract() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(newPartyAddr);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) =         cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();
        IDealManager dealManager = IDealManager(dealManagerAddr);
        vm.startPrank(newPartyAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            newPartyPk
        );

        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            contractId,
            partyValues[1],
            newPartySignature,
            true,
            "Counter Party Name",
            ""
        );
        vm.stopPrank();
    }

    function testCreateClosedContractTWarrant() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        CertificateDetails[] memory _details = new CertificateDetails[](2);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        CertificateDetails memory _detailsB = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });

        _details[0] = _detailsA;
        _details[1] = _detailsB;
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        securityClasses = new SecurityClass[](2);
        securityClasses[0] = SecurityClass.SAFE;
        securityClasses[1] = SecurityClass.TokenWarrant;
        securitySerieses = new SecuritySeries[](2);
        securitySerieses[0] = SecuritySeries.SeriesPreSeed;
        securitySerieses[1] = SecuritySeries.SeriesPreSeed;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(newPartyAddr);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );
        string[] memory certNames = new string[](2);
        certNames[0] = "Safe";
        certNames[1] = "Token Warrant";
        string[] memory certSymbols = new string[](2);
        certSymbols[0] = "SAFE";
        certSymbols[1] = "TWARRENT";

        string[] memory certificateUris = new string[](2);
        certificateUris[0] = "ipfs.io/ipfs/[cid1]";
        certificateUris[1] = "ipfs.io/ipfs/[cid2]";

        string[][] memory defaultLegends = new string[][](2);
        defaultLegends[0] = new string[](1);
        defaultLegends[0][0] = "Legend 1";
        defaultLegends[1] = new string[](1);
        defaultLegends[1][0] = "Legend 2";

        extensions = new address[](2);
        extensions[0] = address(0);
        extensions[1] = address(0);
        CyberCorpFactory.CyberCertData[] memory certData = new CyberCorpFactory.CyberCertData[](2);
        certData[0] = CyberCorpFactory.CyberCertData({
            name: "SAFE",
            symbol: "SAFE",
            uri: "ipfs.io/ipfs/[cid]",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: defaultLegends[0]
        });

        certData[1] = CyberCorpFactory.CyberCertData({
            name: "Token Warrant",
            symbol: "TWARRENT",
            uri: "ipfs.io/ipfs/[cid]",
            securityClass: SecurityClass.TokenWarrant,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: defaultLegends[1]
        });

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) =         cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();
        IDealManager dealManager = IDealManager(dealManagerAddr);
        vm.startPrank(newPartyAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            newPartyPk
        );

        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            contractId,
            partyValues[1],
            newPartySignature,
            true,
            "Counter Party Name",
            ""
        );
        vm.stopPrank();
        console.log("tokens received:");
        string memory contractURI = CyberCertPrinter(cyberCertPrinterAddr[0])
            .tokenURI(certIds[0]);
        console.log(contractURI);
        string memory contractURI2 = CyberCertPrinter(cyberCertPrinterAddr[1])
            .tokenURI(certIds[1]);
        console.log(contractURI2);
    }

    function testVoidCertificate() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) =         cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        //wait for 1000000 blocks
        vm.warp(block.timestamp + 1000001);
        vm.startPrank(testAddress);
        IDealManager(dealManagerAddr).voidExpiredDeal(
            contractId,
            testAddress,
            voidSignature
        );
        vm.stopPrank();
    }

    function testCreateContract() public {
        vm.startPrank(testAddress);
        BorgAuth auth = new BorgAuth(testAddress);
        // auth.initialize();
        CyberAgreementRegistry registrya = new CyberAgreementRegistry();
        registrya.initialize(address(auth));
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        registrya.createTemplate(
            bytes32(uint256(1)),
            "CyberCorp",
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields
        );
        bytes32 id = registrya.createContract(
            bytes32(uint256(1)),
            block.timestamp,
            globalValues,
            parties,
            partyValues,
            bytes32(0),
            address(testAddress),
            block.timestamp + 1000000
        );

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registrya.DOMAIN_SEPARATOR(),
            registrya.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        registrya.signContractFor(
            testAddress,
            id,
            partyValues[0],
            signature,
            false,
            ""
        );
        string memory contractURI = registrya.getContractJson(
            bytes32(uint256(1))
        );

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        signature = _signAgreementTypedData(
            registrya.DOMAIN_SEPARATOR(),
            registrya.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        vm.stopPrank();
        vm.startPrank(newPartyAddr);
        registrya.signContract(id, partyValuesB, signature, true, "");
        contractURI = registrya.getContractJson(id);
        console.log(contractURI);
        vm.stopPrank();
    }

    function testNet() public {
        vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) =         cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            proposerSignature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
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
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        IDealManager dealManager = IDealManager(dealManagerAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            ""
        );
        vm.stopPrank();
    }

    function testSecretHashFailure() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        // Create secret hash from "passphrase"
        bytes32 secretHash = keccak256(abi.encodePacked("passphrase"));

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) =         cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            proposerSignature,
            _details,
            conditions,
            secretHash,
            block.timestamp + 1000000
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
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        IDealManager dealManager = IDealManager(dealManagerAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );

        // Try to sign and finalize with wrong passphrase
        vm.expectRevert(); // Expect revert due to invalid secret
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            "wrongpassphrase" // Using wrong passphrase
        );
        vm.stopPrank();
    }

    function testSecretHashSuccess() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        // Create secret hash from "passphrase"
        bytes32 secretHash = keccak256(abi.encode("passphrase"));

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            proposerSignature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
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
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        IDealManager dealManager = IDealManager(dealManagerAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );

        // Sign and finalize with correct passphrase
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            "passphrase" // Using correct passphrase
        );
        vm.stopPrank();
    }

    function _signAgreementTypedData(
        bytes32 _domainSeparator,
        bytes32 _typeHash,
        bytes32 contractId,
        string memory contractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        // Hash string arrays the same way as the contract
        bytes32 contractUriHash = keccak256(bytes(contractUri));
        bytes32 globalFieldsHash = _hashStringArray(globalFields);
        bytes32 partyFieldsHash = _hashStringArray(partyFields);
        bytes32 globalValuesHash = _hashStringArray(globalValues);
        bytes32 partyValuesHash = _hashStringArray(partyValues);

        // Create the message hash using the same approach as the contract
        bytes32 structHash = keccak256(
            abi.encode(
                _typeHash,
                contractId,
                contractUriHash,
                globalFieldsHash,
                partyFieldsHash,
                globalValuesHash,
                partyValuesHash
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _signVoidRequest(
        bytes32 _domainSeparator,
        bytes32 _typeHash,
        bytes32 contractId,
        address party,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        // Create the message hash using the same approach as the contract
        bytes32 structHash = keccak256(
            abi.encode(_typeHash, contractId, party)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }

    // Add this helper function to your test contract
    function _hashStringArray(
        string[] memory array
    ) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            hashes[i] = keccak256(bytes(array[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function testRevokeDealBeforePayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Revoke deal before payment
        IDealManager(dealManagerAddr).revokeDeal(
            id,
            testAddress,
            voidSignature
        );
        vm.stopPrank();
    }

    function testRevokeDealAfterPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // have a buyer sign and pay

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        IDealManager(dealManagerAddr).signDealAndPay(
            newPartyAddr,
            id,
            newPartySignature,
            partyValuesB,
            true,
            "John Doe",
            "passphrase"
        );
        vm.stopPrank();

        // Try to revoke after payment - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).revokeDeal(id, testAddress, signature);
        vm.stopPrank();
    }

    function testSignToVoidAfterPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Sign to void after payment
        IDealManager(dealManagerAddr).signToVoid(
            id,
            testAddress,
            voidSignature
        );
        vm.stopPrank();
    }

    function testVoidExpiredDeal() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Fast forward time to after expiry
        vm.warp(block.timestamp + 1000001);

        // Void expired deal
        IDealManager(dealManagerAddr).voidExpiredDeal(
            id,
            testAddress,
            voidSignature
        );
        vm.stopPrank();
    }

    function testFinalizeDealWithoutPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Try to finalize without payment - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).finalizeDeal(
            testAddress,
            id,
            partyValues[0],
            signature,
            false,
            "John Doe",
            ""
        );
        vm.stopPrank();
    }

    function testSignDealAndPay() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        IDealManager(dealManagerAddr).signDealAndPay(
            newPartyAddr,
            id,
            newPartySignature,
            partyValuesB,
            true,
            "John Doe",
            ""
        );
        vm.stopPrank();
    }

    function testFinalizeDealTwice() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        IDealManager(dealManagerAddr).signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            ""
        );

        // Try to finalize again - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).finalizeDeal(
            testAddress,
            id,
            partyValues[0],
            signature,
            false,
            "",
            ""
        );
        vm.stopPrank();
    }

    function testVoidDealAfterFinalization() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        IDealManager(dealManagerAddr).signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            ""
        );

        // Try to void after finalization - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).voidExpiredDeal(
            id,
            testAddress,
            voidSignature
        );
        vm.stopPrank();
    }

    function testSignDealWithInvalidSecret() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        bytes32 secretHash = keccak256(abi.encodePacked("passphrase"));

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                signature,
                _details,
                conditions,
                secretHash,
                block.timestamp + 1000000
            );
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        // Try to sign with invalid secret - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).signDealAndPay(
            newPartyAddr,
            id,
            newPartySignature,
            partyValuesB,
            true,
            "John Doe",
            "wrongpassphrase"
        );
        vm.stopPrank();
    }

    function testSignDealWithExpiredContract() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Fast forward time to after expiry
        vm.warp(block.timestamp + 1000001);

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](1);
        partyValuesB[0] = "Party Value B";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );

        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManagerAddr),
            _paymentAmount
        );

        // Try to sign expired contract - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).signDealAndPay(
            newPartyAddr,
            id,
            newPartySignature,
            partyValuesB,
            true,
            "John Doe",
            ""
        );
        vm.stopPrank();
    }

    //create test to print certificateuri
    function testPrintCertificateUri() public {
        vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Gabe",
            signingOfficerTitle: "CEO",
            investmentAmount: 100000,
            issuerUSDValuationAtTimeofInvestment: 100000000,
            unitsRepresented: 100000,
            legalDetails: "Legal Details",
            extensionData: ""
        });
        _details[0] = _detailsA;
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](5);
        globalFields[0] = "purchaseAmount";
        globalFields[1] = "postMoneyValuationCap";
        globalFields[2] = "expirationTime";
        globalFields[3] = "governingJurisdiction";
        globalFields[4] = "disputeResolution";

        string[] memory partyFields = new string[](5);
        partyFields[0] = "name";
        partyFields[1] = "evmAddress";
        partyFields[2] = "contactDetails";
        partyFields[3] = "investorType";
        partyFields[4] = "investorJurisdiction";

        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 100000;

        string[] memory globalValues = new string[](5);
        globalValues[0] = "100000";
        globalValues[1] = "100000000";
        globalValues[2] = "12/1/2025";
        globalValues[3] = "Deleware";
        globalValues[4] = "Binding Arbitration";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabe";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@Gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Deleware";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(2)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "https://ipfs.io/ipfs/bafybeieee4xjqpwcq5nowm4iqw6ik4wkwpz7uqohl3yamypwz54was2h64",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(2)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions,
                bytes32(0),
                block.timestamp + 1000000
            );
        vm.stopPrank();

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](5);
        partyValuesB[0] = "Mr. Prepop";
        partyValuesB[1] = "0xC0FFEEBABE12345678909876543210866666666666";
        partyValuesB[2] = "@0xPrepop";
        partyValuesB[3] = "Limited Liability Company";
        partyValuesB[4] = "Deleware";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "https://ipfs.io/ipfs/bafybeieee4xjqpwcq5nowm4iqw6ik4wkwpz7uqohl3yamypwz54was2h64",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        IDealManager dealManager = IDealManager(dealManagerAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            ""
        );
        vm.stopPrank();
        console.log("printer addr length:", cyberCertPrinterAddr.length);
        string memory certificateUri = CyberCertPrinter(cyberCertPrinterAddr[0])
            .tokenURI(0);
        console.log(certificateUri);

        // Create a new recipient address
        address newRecipient = vm.addr(12345);

        // Try to transfer without making transferable and without endorsement - should revert
        vm.startPrank(newPartyAddr);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(cyberCertPrinterAddr[0]).transferFrom(
            newPartyAddr,
            newRecipient,
            0
        );
        vm.stopPrank();

        // Make the certificate transferable
        vm.startPrank(issuanceManager);
        CyberCertPrinter(cyberCertPrinterAddr[0]).setGlobalTransferable(true);
        vm.stopPrank();

        // Create and add endorsement
        vm.startPrank(newPartyAddr);
        Endorsement memory endorsement = Endorsement({
            endorser: newPartyAddr,
            timestamp: block.timestamp,
            signatureHash: bytes("test-signature"),
            endorsee: newRecipient,
            agreementId: bytes32(0),
            registry: address(0),
            endorseeName: "New Owner"
        });
        CyberCertPrinter(cyberCertPrinterAddr[0]).addEndorsement(
            0,
            endorsement
        );

        // Now transfer should succeed
        CyberCertPrinter(cyberCertPrinterAddr[0]).transferFrom(
            newPartyAddr,
            newRecipient,
            0
        );

        // Verify the transfer was successful
        assertEq(
            CyberCertPrinter(cyberCertPrinterAddr[0]).ownerOf(0),
            newRecipient
        );
        vm.stopPrank();
    }

     function testPrintCertificateTokenWarrantUri() public {
        vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        address warrantExtension = address(new TokenWarrantExtension());

         TokenWarrantData memory tokenWarrant = TokenWarrantData({
            exercisePriceMethod: ExercisePriceMethod.perWarrant,
            exercisePrice: 100000,
            unlockStartTimeType: UnlockStartTimeType.tokenWarrentTime,
            unlockStartTime: block.timestamp,
            unlockingPeriod: 100000,
            latestExpirationTime: block.timestamp + 100000,
            unlockingCliffPeriod: 100000,
            unlockingCliffPercentage: 100000,
            unlockingIntervalType: UnlockingIntervalType.monthly,
            tokenCalculationMethod: TokenCalculationMethod.equityProRataToTokenSupply,
            minCompanyReserve: 0,
            tokenPremiumMultiplier: 0
        });

        bytes memory tokenWarrantData = abi.encode(tokenWarrant);

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Gabe",
            signingOfficerTitle: "CEO",
            investmentAmount: 100000,
            issuerUSDValuationAtTimeofInvestment: 100000000,
            unitsRepresented: 100000,
            legalDetails: "Legal Details",
            extensionData: tokenWarrantData
        });
        _details[0] = _detailsA;
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalFields = new string[](5);
        globalFields[0] = "purchaseAmount";
        globalFields[1] = "postMoneyValuationCap";
        globalFields[2] = "expirationTime";
        globalFields[3] = "governingJurisdiction";
        globalFields[4] = "disputeResolution";

        string[] memory partyFields = new string[](5);
        partyFields[0] = "name";
        partyFields[1] = "evmAddress";
        partyFields[2] = "contactDetails";
        partyFields[3] = "investorType";
        partyFields[4] = "investorJurisdiction";

        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 100000;

        string[] memory globalValues = new string[](5);
        globalValues[0] = "100000";
        globalValues[1] = "100000000";
        globalValues[2] = "12/1/2025";
        globalValues[3] = "Deleware";
        globalValues[4] = "Binding Arbitration";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabe";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@Gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Deleware";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(2)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        address[] memory extensions = new address[](1);
        extensions[0] = warrantExtension;

        bytes memory proposerSignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "https://ipfs.io/ipfs/bafybeieee4xjqpwcq5nowm4iqw6ik4wkwpz7uqohl3yamypwz54was2h64",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(2)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions,
                bytes32(0),
                block.timestamp + 1000000
            );
        vm.stopPrank();

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        string[] memory partyValuesB = new string[](5);
        partyValuesB[0] = "Mr. Prepop";
        partyValuesB[1] = "0xC0FFEEBABE12345678909876543210866666666666";
        partyValuesB[2] = "@0xPrepop";
        partyValuesB[3] = "Limited Liability Company";
        partyValuesB[4] = "Deleware";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "https://ipfs.io/ipfs/bafybeieee4xjqpwcq5nowm4iqw6ik4wkwpz7uqohl3yamypwz54was2h64",
            globalFields,
            partyFields,
            globalValues,
            partyValuesB,
            newPartyPk
        );
        IDealManager dealManager = IDealManager(dealManagerAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            newPartyAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            id,
            partyValuesB,
            newPartySignature,
            true,
            "John Doe",
            ""
        );
        vm.stopPrank();
        console.log("printer addr length:", cyberCertPrinterAddr.length);
        string memory certificateUri = CyberCertPrinter(cyberCertPrinterAddr[0])
            .tokenURI(0);
        console.log(certificateUri);

        // Create a new recipient address
        address newRecipient = vm.addr(12345);

        // Try to transfer without making transferable and without endorsement - should revert
        vm.startPrank(newPartyAddr);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(cyberCertPrinterAddr[0]).transferFrom(
            newPartyAddr,
            newRecipient,
            0
        );
        vm.stopPrank();

        // Make the certificate transferable
        vm.startPrank(issuanceManager);
        CyberCertPrinter(cyberCertPrinterAddr[0]).setGlobalTransferable(true);
        vm.stopPrank();

        // Create and add endorsement
        vm.startPrank(newPartyAddr);
        Endorsement memory endorsement = Endorsement({
            endorser: newPartyAddr,
            timestamp: block.timestamp,
            signatureHash: bytes("test-signature"),
            endorsee: newRecipient,
            agreementId: bytes32(0),
            registry: address(0),
            endorseeName: "New Owner"
        });
        CyberCertPrinter(cyberCertPrinterAddr[0]).addEndorsement(
            0,
            endorsement
        );

        // Now transfer should succeed
        CyberCertPrinter(cyberCertPrinterAddr[0]).transferFrom(
            newPartyAddr,
            newRecipient,
            0
        );

        // Verify the transfer was successful
        assertEq(
            CyberCertPrinter(cyberCertPrinterAddr[0]).ownerOf(0),
            newRecipient
        );
        vm.stopPrank();
    }

    function testUpgradeCyberAgreementRegistry() public {
        // Deploy initial implementation and proxy
        address registryImplementation = address(new CyberAgreementRegistry());
        bytes memory initData = abi.encodeWithSelector(
            CyberAgreementRegistry.initialize.selector,
            address(auth)
        );
        address registryAddr = address(
            new ERC1967Proxy(registryImplementation, initData)
        );
        CyberAgreementRegistry registry = CyberAgreementRegistry(registryAddr);

        // Create a test template to verify functionality
        string[] memory globalFields = new string[](1);
        globalFields[0] = "testField";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "testPartyField";

        vm.prank(multisig);
        registry.createTemplate(
            bytes32(uint256(1)),
            "Test Template",
            "https://test.uri",
            globalFields,
            partyFields
        );

        // Deploy new implementation
        address newImplementation = address(new CyberAgreementRegistry());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        CyberAgreementRegistry(registryAddr).upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(multisig);
        CyberAgreementRegistry(registryAddr).upgradeToAndCall(
            newImplementation,
            ""
        );
        assertEq(registryAddr.getErc1967Implementation(vm), newImplementation);

        // Verify the registry still works by checking the template
        (
            string memory legalContractUri,
            string memory title,
            string[] memory retGlobalFields,
            string[] memory retPartyFields
        ) = registry.getTemplateDetails(bytes32(uint256(1)));

        assertEq(legalContractUri, "https://test.uri");
        assertEq(retGlobalFields[0], "testField");
        assertEq(retPartyFields[0], "testPartyField");
    }

    function testUpgradeCyberCorpFactory() public {
        // Deploy new implementation
        address newImplementation = address(new CyberCorpFactory());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        cyberCorpFactory.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(multisig);
        cyberCorpFactory.upgradeToAndCall(newImplementation, "");
        assertEq(address(cyberCorpFactory).getErc1967Implementation(vm), newImplementation);

        // Verify the factory still works by checking the dependencies and creating a new corp

        assertEq(cyberCorpFactory.registryAddress(), address(registry));

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (address cyberCorp, address auth, address issuanceManager, address dealManagerAddr, address[] memory cyberCertPrinterAddr, bytes32 id, uint256[] memory certIds) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();
    }

    function testUpgradeCertificateUriBuilder() public {
        CertificateUriBuilder uriBuilder = CertificateUriBuilder(cyberCorpFactory.uriBuilder());

        // Deploy new implementation
        address newImplementation = address(new CertificateUriBuilder());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        uriBuilder.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(multisig);
        uriBuilder.upgradeToAndCall(newImplementation, "");
        assertEq(address(uriBuilder).getErc1967Implementation(vm), newImplementation);

        // Verify the URI builder still works
        assertEq(uriBuilder.securityClassToString(SecurityClass.SAFT), "SAFT");
    }

    function testUpgradeDealManagerBeacon() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                signature,
                _details,
                conditions,
                bytes32(0),
                block.timestamp + 1000000
            );
        vm.stopPrank();

        // Deploy new implementation
        address newImplementation = address(new DealManager());
        address factoryaddr = cyberCorpFactory.dealManagerFactory();
        // Upgrade beacon implementation
        console.log(DealManagerFactory(factoryaddr).AUTH().userRoles(address(multisig)));

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        DealManagerFactory(factoryaddr).upgradeImplementation(newImplementation);

        // Owner should be able to upgrade it
        console.log(
            DealManagerFactory(factoryaddr).AUTH().userRoles(address(multisig))
        );
        vm.prank(multisig);
        DealManagerFactory(factoryaddr).upgradeImplementation(newImplementation);
        assertEq(DealManagerFactory(factoryaddr).getBeaconImplementation(), newImplementation);

        // Verify the deal manager still works by checking the deal
        Escrow memory escrow = DealManager(dealManagerAddr).getEscrowDetails(
            id
        );

        console.log(escrow.counterParty);
        assertEq(
            DealManagerFactory(factoryaddr).getBeaconImplementation(),
            newImplementation
        );
    }

    function testUpgradeIssuanceManager() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        // Create a certificate to verify functionality
        string[] memory ledger = new string[](1);
        ledger[0] = "Test Ledger";

        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager)
            .createCertPrinter(
                ledger,
                "Test Certificate",
                "TEST",
                "ipfs://test",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                address(0)
            );

        // Deploy new implementation
        address newImplementation = address(new IssuanceManager());
        address factoryAddr = cyberCorpFactory.issuanceManagerFactory();

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        IssuanceManagerFactory(factoryAddr).upgradeImplementation(newImplementation);

        // Owner should be able to upgrade it
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).upgradeImplementation(newImplementation);
        assertEq(IssuanceManagerFactory(factoryAddr).getBeaconImplementation(), newImplementation);

        address newImplementation2 = address(new CyberCertPrinter());

        //get the factory address
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).upgradePrinterBeaconAt(
            issuanceManager,
            newImplementation2
        );

        // Verify the IssuanceManager still works by checking the certificate printer
        address printerAddr = IssuanceManager(issuanceManager).printers(0);
        //assertEq(printerAddr, certPrinter);
        // assertEq(IssuanceManagerFactory(factoryAddr).getBeaconImplementation(), newImplementation);
    }

    function testUpgradeCyberCorpSingle() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                signature,
                _details,
                conditions,
                bytes32(0),
                block.timestamp + 1000000
            );
        vm.stopPrank();

        // Create a certificate to verify functionality
        string[] memory ledger = new string[](1);
        ledger[0] = "Test Ledger";

        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager)
            .createCertPrinter(
                ledger,
                "Test Certificate",
                "TEST",
                "ipfs://test",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                address(0)
            );

        // Deploy new implementation
        address newImplementation = address(new CyberCorp());
        address factoryAddr = cyberCorpFactory.cyberCorpSingleFactory();

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        CyberCorpSingleFactory(factoryAddr).upgradeImplementation(newImplementation);

        // Owner should be able to upgrade it
        vm.prank(multisig);
        CyberCorpSingleFactory(factoryAddr).upgradeImplementation(newImplementation);
        assertEq(CyberCorpSingleFactory(factoryAddr).getBeaconImplementation(), newImplementation);

        //check the company name
        assertEq(CyberCorp(cyberCorp).cyberCORPName(), "CyberCorp");
    }

    function testUpgradeCyberCertPrinter() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                bytes32(uint256(1)),
                block.timestamp,
                globalValues,
                parties
            )
        );

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = _signAgreementTypedData(
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            testPrivateKey
        );

        bytes memory voidSignature = _signVoidRequest(
            registry.DOMAIN_SEPARATOR(),
            registry.VOIDSIGNATUREDATA_TYPEHASH(),
            contractId,
            testAddress,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                certData,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                signature,
                _details,
                conditions,
                bytes32(0),
                block.timestamp + 1000000
            );
        vm.stopPrank();

        // Create a certificate to verify functionality
        string[] memory ledger = new string[](1);
        ledger[0] = "Test Ledger";

        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager)
            .createCertPrinter(
                ledger,
                "Test Certificate",
                "TEST",
                "ipfs://test",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                address(0)
            );

        // Deploy new implementation
        address newImplementation = address(new CyberCertPrinter());

        address factoryAddr = cyberCorpFactory.issuanceManagerFactory();

        // Only factory can call the Issuance Manager to upgrade its CyberCert Printer
        vm.expectRevert(abi.encodeWithSelector(IssuanceManager.NotUpgradeFactory.selector));
        IssuanceManager(issuanceManager).upgradeBeaconImplementation(newImplementation);

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        IssuanceManagerFactory(factoryAddr).upgradePrinterBeaconAt(issuanceManager, newImplementation);

        // Owner should be able to upgrade it
        console.log(IssuanceManager(issuanceManager).getUpgradeFactory());
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).upgradePrinterBeaconAt(issuanceManager, newImplementation);
        assertEq(IssuanceManager(issuanceManager).getBeaconImplementation(), newImplementation);

        //check the security type
        assertEq(CyberCertPrinter(certPrinter).certificateUri(), "ipfs://test");
    }

    function testUpdateCyberAgreementRegistry() public {
        // First give the test contract the OWNER_ROLE (99)
        address registry = 0x9d4EFe86964eb038848D7aD4d208AAdEA7282516;
        // Deploy new implementation
        address newImplementation = address(new CyberAgreementRegistry());

        // Get the current registry address from the factory
        //address registryAddr = cyberCorpFactory.registryAddress();
        console.log("regaddr: ", address(registry));
        // Upgrade the existing registry


        vm.startPrank(multisig);
        CyberAgreementRegistry(registry).upgradeToAndCall(
            newImplementation,
            ""
        );
        //get the template
        (string memory template, string memory title) = CyberAgreementRegistry(registry).templates(bytes32(uint256(1)));
        console.log("template: ", template);
        console.log("title: ", title);

        (string memory legalContractUri, string memory titleA, string[] memory globalFields, string[] memory signerFields) = CyberAgreementRegistry(registry).getTemplateDetails(bytes32(uint256(1)));
        console.log("legalContractUri: ", legalContractUri);
        console.log("title: ", titleA);
    }
}
