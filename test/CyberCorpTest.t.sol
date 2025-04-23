/*    .o.                                                                                         
     .888.                                                                                        
    .8"888.                                                                                       
   .8' `888.                                                                                      
  .88ooo8888.                                                                                     
 .8'     `888.                                                                                    
o88o     o8888o                                                                                   
                                                                                                  
                                                                                                  
                                                                                                  
ooo        ooooo               .             oooo                                                 
`88.       .888'             .o8             `888                                                 
 888b     d'888   .ooooo.  .o888oo  .oooo.    888   .ooooo.  oooo    ooo                          
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888  d88' `88b  `88b..8P'                           
 8  `888'   888  888ooo888   888    .oP"888   888  888ooo888    Y888'                             
 8    Y     888  888    .o   888 . d8(  888   888  888    .o  .o8"'88b                            
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888o `Y8bod8P' o88'   888o                          
                                                                                                  
                                                                                                  
                                                                                                  
  .oooooo.                .o8                            .oooooo.                                 
 d8P'  `Y8b              "888                           d8P'  `Y8b                                
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.  
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b 
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
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
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory, IssuanceManager} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
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

contract CyberCorpTest is Test {
    //     Counter public counter;

    CyberCorpFactory cyberCorpFactory;
    CyberAgreementRegistry registry;
    uint256 testPrivateKey;
    address testAddress;
    address counterPartyAddress = 0x1A762EfF397a3C519da3dF9FCDDdca7D1BD43B5e;
    address[] conditions = new address[](0);
    string[] legend;

    function setUp() public {
        testPrivateKey = 1337;
        testAddress = vm.addr(testPrivateKey);
        vm.startPrank(0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C);

        // Deploy BorgAuth with Create2
        bytes32 deploySalt = keccak256("AMetaLeXLabsCreation");
        address authAddress = Create2.computeAddress(
            deploySalt,
            keccak256(type(BorgAuth).creationCode)
        );
        BorgAuth auth = new BorgAuth{salt: deploySalt}();
        auth.initialize();

        // Deploy IssuanceManagerFactory with Create2
        address issuanceManagerFactory = Create2.deploy(
            0,
            deploySalt,
            abi.encodePacked(
                type(IssuanceManagerFactory).creationCode,
                abi.encode(address(0))
            )
        );

        // Deploy CyberCertPrinter implementation with Create2
        address cyberCertPrinterImplementation = Create2.deploy(
            0,
            deploySalt,
            type(CyberCertPrinter).creationCode
        );

        // Initialize CyberCertPrinter
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(
            cyberCertPrinterImplementation
        );

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "test-legend";
        cyberCertPrinter.initialize(
            defaultLegend,
            "",
            "",
            "ipfs.io/ipfs/[cid]",
            address(0),
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed
        );

        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());

        address dealManagerFactory = address(new DealManagerFactory());

        registry = new CyberAgreementRegistry();
        CyberAgreementRegistry(registry).initialize(address(auth));

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

        string[] memory globalFieldsSafe = new string[](7);
        globalFieldsSafe[0] = "Investment Amount";
        globalFieldsSafe[1] = "Post-Money Valuation Cap";
        globalFieldsSafe[2] = "Expiration Time";
        globalFieldsSafe[3] = "Governing Jurisdiction";
        globalFieldsSafe[4] = "Dispute Resolution";
        globalFieldsSafe[5] = "investorType";
        globalFieldsSafe[6] = "investorJurisdiction";

        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "Name";
        partyFieldsSafe[1] = "EVMAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "type";
        partyFieldsSafe[4] = "jurisdiction";


        registry.createTemplate(
            bytes32(uint256(2)),
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            globalFieldsSafe,
            partyFieldsSafe
        );

        address uriBuilder = address(new CertificateUriBuilder());

        cyberCorpFactory = new CyberCorpFactory(
            address(registry),
            cyberCertPrinterImplementation,
            issuanceManagerFactory,
            cyberCorpSingleFactory,
            dealManagerFactory,
            uriBuilder
        );

        cyberCorpFactory.initialize(address(auth));
        cyberCorpFactory.setStable(0x036CbD53842c5426634e7929541eC2318f3dCF7e);

        legend = new string[](4);
        legend[0] = "investment advisor certificate custody legend - THE SAFE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFE WITHOUT THE PRIOR CONSENT OF THE COMPANY. ";
        legend[1] = "restricted security legend - THIS SAFE, THE SAFE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE 'RESTRICTED SECURITIES' AS DEFINED IN SEC RULE 144. ";
        legend[2] = "unregistered security legend - THIS SAFE, THE SAFE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE 'SECURITIES ACT'), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM. ";
        legend[3] = "hardfork legend - IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE SAFE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A 'CONTENTIOUS HARDFORK' (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY), NO COPY OF THE SAFE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH  BLOCKCHAIN SYSTEM (AND WHICH SAFE CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE SAFE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED).  IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ITS CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH CONTENTIOUS HARFORK, MUTATIS MUTANDIS. ";

        vm.stopPrank();
    }

    function testOffer() public {
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
            legend,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();
    }

    function testCreateClosedContract() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 
        });

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


        vm.startPrank(testAddress);
         (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
             legend,
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

    function testVoidCertificate() public {
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
        (address cyberCorp, address auth, address issuanceManager, address dealManagerAddr, address cyberCertPrinterAddr, bytes32 id) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
             legend,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        //wait for 1000000 blocks
        vm.warp(block.timestamp + 1000001);
        vm.startPrank(testAddress);
        IDealManager(dealManagerAddr).voidExpiredDeal(contractId, testAddress, voidSignature);
        vm.stopPrank();
    }

    function testCreateContract() public {
        vm.startPrank(testAddress);
        BorgAuth auth = new BorgAuth();
        auth.initialize();
        CyberAgreementRegistry registry = new CyberAgreementRegistry();
        registry.initialize(address(auth));
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
        registry.createTemplate(
            bytes32(uint256(1)),
            "CyberCorp",
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields
        );
        bytes32 id = registry.createContract(
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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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

        registry.signContractFor(
            testAddress,
            id,
            partyValues[0],
            signature,
            false,
            ""
        );
        string memory contractURI = registry.getContractJson(
            bytes32(uint256(1))
        );

        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        signature = _signAgreementTypedData(
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

        vm.stopPrank();
        vm.startPrank(newPartyAddr);
        registry.signContract(id, partyValuesB, signature, true, "");
        contractURI = registry.getContractJson(id);
        console.log(contractURI);
        vm.stopPrank();
    }

    function testNet() public {
        vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
                testAddress,
                officer,
                "SAFE",
                "SAFE",
                "ipfs.io/ipfs/[cid]",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions, 
                 legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
            "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                "SAFE",
                "SAFE",
                "ipfs.io/ipfs/[cid]",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions, 
                 legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
                testAddress,
                officer,
                "SAFE",
                "SAFE",
                "ipfs.io/ipfs/[cid]",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                bytes32(uint256(1)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions, 
                 legend,
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
            abi.encode(
                _typeHash,
                contractId,
                party
            )
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
             legend,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Revoke deal before payment
        IDealManager(dealManagerAddr).revokeDeal(id, testAddress, voidSignature);
        vm.stopPrank();
    }

    function testRevokeDealAfterPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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

        IDealManager(dealManagerAddr).signDealAndPay(newPartyAddr, id, newPartySignature, partyValuesB, true, "John Doe", "passphrase");
        vm.stopPrank();

        // Try to revoke after payment - should fail
        vm.expectRevert();
        IDealManager(dealManagerAddr).revokeDeal(id, testAddress, signature);
        vm.stopPrank();
    }

    function testSignToVoidAfterPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Sign to void after payment
        IDealManager(dealManagerAddr).signToVoid(id, testAddress, voidSignature);
        vm.stopPrank();
    }

    function testVoidExpiredDeal() public {
        vm.startPrank(testAddress);
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
            bytes32(0),
            block.timestamp + 1000000
        );

        // Fast forward time to after expiry
        vm.warp(block.timestamp + 1000001);

        // Void expired deal
        IDealManager(dealManagerAddr).voidExpiredDeal(id, testAddress, voidSignature);
        vm.stopPrank();
    }

    function testFinalizeDealWithoutPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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
        IDealManager(dealManagerAddr).voidExpiredDeal(id, testAddress, voidSignature);
        vm.stopPrank();
    }

    function testSignDealWithInvalidSecret() public {
        vm.startPrank(testAddress);
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
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

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        bytes32 secretHash = keccak256(abi.encodePacked("passphrase"));

        bytes32 contractId = keccak256(
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc" 

            
        });

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
            abi.encode(bytes32(uint256(1)), block.timestamp, globalValues, parties)
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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            "Limited Liability Company",
"Juris",
"Contact Details",
"Dispute Res",
            testAddress,
            officer,
            "SAFE",
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            signature,
            _details,
            conditions, 
legend,
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

    function testUpgradeCyberCertPrinter() public {
        // Deploy and initialize IssuanceManager
        BorgAuth auth = new BorgAuth();
        auth.initialize();
        
        // Deploy initial implementation
        CyberCertPrinter implementationV1 = new CyberCertPrinter();
        
        // Deploy beacon with IssuanceManager as owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(implementationV1),
            address(this) // Set test contract as owner temporarily
        );
        
        // Deploy IssuanceManager
        IssuanceManager issuanceManager = new IssuanceManager();
        issuanceManager.initialize(
            address(auth),
            address(0), // CORP address not needed for this test
            address(implementationV1),
            address(0) // uriBuilder not needed for this test
        );

        // Transfer beacon ownership to IssuanceManager
        beacon.transferOwnership(address(issuanceManager));
        
        // Deploy proxy
        bytes memory bytecode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(beacon), "")
        );
        address proxy;
        assembly {
            proxy := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        
        // Initialize proxy
        CyberCertPrinter printer = CyberCertPrinter(proxy);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "test-legend";
        printer.initialize(
            defaultLegend,
            "Test Printer",
            "TEST",
            "ipfs://test",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA
        );
        
        // Verify initial state
        assertEq(printer.certificateUri(), "ipfs://test");
        
        // Deploy new implementation
        CyberCertPrinter implementationV2 = new CyberCertPrinter();
        
        // Grant upgrader role to test address
        //auth.updateRole(testAddress, auth.UPGRADER_ROLE());
        vm.prank(auth.UPGRADER_ADDRESS());
        
        // Upgrade implementation through IssuanceManager

        issuanceManager.upgradeImplementation(address(implementationV2));
        
        // Verify proxy still works with new implementation
        assertEq(printer.certificateUri(), "ipfs://test");
        
        // Verify upgrade was successful by checking beacon implementation
        assertEq(IssuanceManager(address(issuanceManager)).getBeaconImplementation(), address(implementationV2));
        vm.stopPrank();
    }

    //create test to print certificateuri
    function testPrintCertificateUri() public {
 vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "Gabe",
            signingOfficerTitle: "CEO",
            investmentAmount: 100000,
            issuerUSDValuationAtTimeofInvestment: 100000000,
            unitsRepresented: 100000,
            legalDetails: "Legal Details" 
        });

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        
        string[] memory globalFields = new string[](7);
        globalFields[0] = "Investment Amount";
        globalFields[1] = "Post-Money Valuation Cap";
        globalFields[2] = "Expiration Time";
        globalFields[3] = "Governing Jurisdiction";
        globalFields[4] = "Dispute Resolution";
        globalFields[5] = "investorType";
        globalFields[6] = "investorJurisdiction";


        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 100000;
        string[] memory partyFields = new string[](5);
        partyFields[0] = "Name";
        partyFields[1] = "EVMAddress";
        partyFields[2] = "contactDetails";
        partyFields[3] = "type";
        partyFields[4] = "jurisdiction";

        string[] memory globalValues = new string[](7);
        globalValues[0] =  "100000";
        globalValues[1] = "100000000";
        globalValues[2] = "12/1/2025";
        globalValues[3] = "Deleware";
        globalValues[4] = "Binding Arbitration";
        globalValues[5] = "Limited Liability Company";
        globalValues[6] = "Deleware";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabe";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@Gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Deleware";

        bytes32 contractId = keccak256(
            abi.encode(bytes32(uint256(2)), block.timestamp, globalValues, parties)
        );

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
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "CyberCorp",
            "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                "SAFE",
                "SAFE",
                "ipfs.io/ipfs/[cid]",
                SecurityClass.SAFE,
                SecuritySeries.SeriesPreSeed,
                bytes32(uint256(2)),
                globalValues,
                parties,
                _paymentAmount,
                partyValues,
                proposerSignature,
                _details,
                conditions, 
                legend,
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

        string memory certificateUri = CyberCertPrinter(cyberCertPrinterAddr).tokenURI(0);
        console.log(certificateUri);
    }
    
}

