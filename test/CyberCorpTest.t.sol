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
import {ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory, IssuanceManager} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IDealManagerStorage} from "../src/interfaces/IDealManagerStorage.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {CompanyOfficer} from "../src/storage/CyberCertPrinterStorage.sol";
import {ToggleTransferHook} from "../src/hooks/transfer/ToggleTransferHook.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerStorage} from "../src/storage/DealManagerStorage.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {Escrow} from "../src/storage/LexScrowStorage.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {TokenWarrantExtension, TokenWarrantData} from "../src/storage/extensions/TokenWarrantExtension.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {SAFTEExtension, SAFTEData} from "../src/storage/extensions/SAFTEExtension.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LexScrowStorage} from "../src/storage/LexScrowStorage.sol";
import {LexChexCondition} from "../src/libs/conditions/lexchexCondition.sol";
import {LeXcheXUtils} from "./libs/LeXcheXUtils.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";

contract CyberCorpForkTest is Test {
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
    TokenWarrantExtension warrantExtension;
    string[] certNames;
    string[] certSymbols;
    string[] certificateUris;
    string[][] defaultLegends;
    address[] extensions;
    LeXcheX lexchex;
    LeXcheXMinter lexchexMinter;
    LexChexCondition lexchexCondition;

    function setUp() public {
        vm.createSelectFork("base_sepolia");
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

        address issuanceManagerImplementation = address(new IssuanceManager{salt: salt}());
        address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImplementation = address(new CyberScrip{salt: salt}());
        address issuanceManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new IssuanceManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    issuanceManagerImplementation,
                    cyberCertPrinterImplementation,
                    cyberScripImplementation
                )
            )
        );

        defaultLegends = new string[][](1);
        defaultLegends[0] = new string[](1);
        defaultLegends[0][0] = "Legend 1";

        address cyberCorpSingleFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberCorpSingleFactory{salt: salt}()),
                abi.encodeWithSelector(
                    CyberCorpSingleFactory.initialize.selector,
                    address(auth),
                    address(new CyberCorp())
                )
            )
        );

        address dealManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new DealManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            )
        );

        // Deploy upgradeable singletons

        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        // Deploy the CertificateImageBuilderContract (standalone contract for SVG generation)
        address imageBuilder = address(new CertificateImageBuilderContract{salt: salt}());

        // Deploy CertificateUriBuilder proxy
        address uriBuilder = address(new ERC1967Proxy{salt: salt}(
            address(new CertificateUriBuilder{salt: salt}()),
            abi.encodeWithSelector(
                CertificateUriBuilder.initialize.selector,
                address(auth))
        ));

        // Set the image builder on the CertificateUriBuilder
        CertificateUriBuilder(uriBuilder).setImageBuilder(imageBuilder);

        // RoundManager via factory and initialize
        address rmFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        );

        cyberCorpFactory = CyberCorpFactory(address(new ERC1967Proxy{salt: salt}(
            address(new CyberCorpFactory{salt: salt}()),
            abi.encodeWithSelector(
                CyberCorpFactory.initialize.selector,
                address(auth),
                address(registry),
                issuanceManagerFactory,
                cyberCorpSingleFactory,
                dealManagerFactory,
                rmFactory,
                uriBuilder
            )
        )));
        cyberCorpFactory.setStable(stable);
        address upgradeOwner = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
        address lxAuth = cyberCorpFactory.lexchexAuth();
        vm.stopPrank();
        vm.startPrank(upgradeOwner);
        BorgAuth(lxAuth).updateRole(address(cyberCorpFactory), BorgAuth(lxAuth).OWNER_ROLE());
        vm.stopPrank();
        vm.startPrank(testAddress);
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

        // Deploy LexChex contracts
        lexchex = LeXcheX(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheX{salt: salt}()),
            abi.encodeWithSelector(
                LeXcheX.initialize.selector,
                address(auth)
            )
        )));

        lexchexMinter = LeXcheXMinter(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheXMinter{salt: salt}()),
            abi.encodeWithSelector(
                LeXcheXMinter.initialize.selector,
                address(auth),
                address(lexchex),
                address(registry),
                multisig // treasury
            )
        )));

        lexchexCondition = new LexChexCondition{salt: salt}();
        lexchexCondition.initialize(address(lexchex), address(auth));

        auth.updateRole(address(multisig), 200);
        auth.updateRole(address(lexchexMinter), 98);
        auth.zeroOwner();
        auth.userRoles(multisig);
        vm.stopPrank();
    }

    /// @dev Mirrors createContract's contractId preimage for agreements created through
    /// deployCyberCorpAndCreateOffer. The finalizer is the DealManager the factory is about to
    /// deploy, so predict its CREATE2 address from the corp salt. `expiry` is not part of the id.
    function _expectedAgreementId(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        bytes32 secretHash
    ) internal view returns (bytes32) {
        address dealManager = DealManagerFactory(cyberCorpFactory.dealManagerFactory())
            .computeDealManagerAddress(keccak256(abi.encodePacked(salt)));
        return _expectedAgreementId(templateId, salt, globalValues, parties, secretHash, dealManager);
    }

    /// @dev Same preimage, for flows where the finalizing DealManager already exists.
    function _expectedAgreementId(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        bytes32 secretHash,
        address finalizer
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(templateId, salt, globalValues, parties, secretHash, finalizer)
        );
    }

    function testOffer() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });
        CertificateDetails memory _detailsB = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0), address(testAddress));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        //print cyberagreementcontract details
        string memory contractDetails = registrya.getContractJson(id);
        console.log(contractDetails);
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, secretHash);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        vm.expectRevert(CyberAgreementRegistry.InvalidSecret.selector); // Expect revert due to invalid secret
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

    function testRevokeDealBeforePayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        vm.expectRevert(IDealManagerStorage.CounterPartyValueMismatch.selector);
        IDealManager(dealManagerAddr).revokeDeal(id, testAddress, signature);
        vm.stopPrank();
    }

    function testSignToVoidAfterPayment() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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

        // Try to finalize without payment - should fail. parties[1] is address(0) and never signs,
        // so the all-parties-signed check fires before the unpaid-escrow check.
        vm.expectRevert(LexScrowStorage.DealNotFullySigned.selector);
        IDealManager(dealManagerAddr).finalizeDeal(id);
        vm.stopPrank();
    }

    function testSignDealAndPay() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // Try to finalize again - should fail. The deal is already finalized in the registry,
        // so the already-finalized check fires before the unpaid-escrow check.
        vm.expectRevert(LexScrowStorage.DealAlreadyFinalized.selector);
        IDealManager(dealManagerAddr).finalizeDeal(id);
        vm.stopPrank();
    }

    function testVoidDealAfterFinalization() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        vm.expectRevert(IDealManagerStorage.DealNotExpired.selector);
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, secretHash);

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        vm.expectRevert(CyberAgreementRegistry.InvalidSecret.selector);
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
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        vm.expectRevert(LexScrowStorage.DealExpired.selector);
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
      //  vm.warp(block.timestamp - 3000000);
        vm.startPrank(testAddress);
        CyberCorpFactory cyberCorpFactoryLive = CyberCorpFactory(
            0x2aDA6E66a92CbF283B9F2f4f095Fe705faD357B8
        );

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Gabriel Shapiro",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 10000000000000000,
            issuerUSDValuationAtTimeOfInvestment: 10000000000000000000,
            unitsRepresented: 10000000000000000,
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
        globalValues[3] = "Delaware";
        globalValues[4] = "Binding Arbitration";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabriel Shapiro";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Delaware";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(2)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        CyberCorpFactory.CyberCertData[] memory _certData = new CyberCorpFactory.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend 1";
        _certData[0] = CyberCorpFactory.CyberCertData({
            name: "Cert Name 1",
            symbol: "Cert Symbol 1",
            uri: "https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiafzkynirjta4pd3g365qv6ttlz3pkeqcquhbald7nqqfmm5vpfua",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
                block.timestamp,
                "Test CyberCorp, LLC",
                "Limited Liability Company",
                "Delaware",
                "Contact Details",
                "Dispute Res",
                testAddress,
                officer,
                _certData,
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
        partyValuesB[4] = "Delaware";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            "Mr. Prepop",
            ""
        );
        vm.stopPrank();
        vm.warp(block.timestamp + 3000000);
                string memory endorseeName = CyberCertPrinter(cyberCertPrinterAddr[0]).getEndorsementHistory(0, 0).endorseeName;
        console.log("endorsee name:", endorseeName);
       // console.log("printer addr length:", cyberCertPrinterAddr.length);

        //print endorsee name


        string memory certificateUri = CyberCertPrinter(cyberCertPrinterAddr[0])
            .tokenURI(0);
        console.log(certificateUri);

        /*string memory certificateUriJson = CyberCertPrinter(cyberCertPrinterAddr[0])
            .tokenURIJson(0);
        console.log(certificateUriJson);*/

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
        bytes32 salt = bytes32(keccak256("TestWarrant"));
        address warrantExtension = address(new ERC1967Proxy{salt: salt}(
           address(new TokenWarrantExtension{salt: salt}()),
           abi.encodeWithSelector(TokenWarrantExtension.initialize.selector, address(auth))
        ));

         TokenWarrantData memory tokenWarrant = TokenWarrantData({
            exercisePriceMethod: ExercisePriceMethod.perWarrant,
            exercisePrice: 100000,
            unlockStartTimeType: UnlockStartTimeType.tokenWarrantTime,
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
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 100000000,
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
        globalValues[3] = "Delaware";
        globalValues[4] = "Binding Arbitration";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabe";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@Gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Delaware";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(2)), block.timestamp, globalValues, parties, bytes32(0));

        address[] memory extensions = new address[](1);
        extensions[0] = warrantExtension;

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        certData[0].extension = warrantExtension;
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
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
        partyValuesB[4] = "Delaware";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        assertEq(registryAddr.getErc1967Implementation(), newImplementation);

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
        assertEq(address(cyberCorpFactory).getErc1967Implementation(), newImplementation);

        // Verify the factory still works by checking the dependencies and creating a new corp

        assertEq(cyberCorpFactory.registryAddress(), address(registry));

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
        (address cyberCorp, address auth, address issuanceManager, address dealManagerAddr, address roundManagerAddr, address[] memory cyberCertPrinterAddr, bytes32 id, uint256[] memory certIds) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
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

        // Deploy new image builder contract
        address newImageBuilder = address(new CertificateImageBuilderContract());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        uriBuilder.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(multisig);
        uriBuilder.upgradeToAndCall(newImplementation, "");
        assertEq(address(uriBuilder).getErc1967Implementation(), newImplementation);

        // Set the new image builder (required for the new architecture)
        vm.prank(multisig);
        uriBuilder.setImageBuilder(newImageBuilder);
        assertEq(uriBuilder.imageBuilder(), newImageBuilder);

        // Verify the URI builder still works
        assertEq(uriBuilder.securityClassToString(SecurityClass.SAFT), "SAFT");
    }

    function testUpgradeDealManagerViaRefImplementation() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        DealManagerFactory(factoryaddr).setRefImplementation(newImplementation);

        // Owner should be able to upgrade it
        console.log(
            DealManagerFactory(factoryaddr).AUTH().userRoles(address(multisig))
        );
        vm.prank(multisig);
        DealManagerFactory(factoryaddr).setRefImplementation(newImplementation);
        assertEq(DealManagerFactory(factoryaddr).getRefImplementation(), newImplementation);

        // Verify the deal manager still works by checking the deal
        Escrow memory escrow = DealManager(dealManagerAddr).getEscrowDetails(
            id
        );

        console.log(escrow.counterParty);
    }

    function testUpgradeIssuanceManager() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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

        // Deploy new implementation
        address newIssuanceManagerImpl = address(new IssuanceManager());
        address factoryAddr = cyberCorpFactory.issuanceManagerFactory();

        // Non-owner should not be able to set IssuanceManager reference implementation
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        IssuanceManagerFactory(factoryAddr).setRefImplementation(newIssuanceManagerImpl);

        // Owner should be able to set IssuanceManager reference implementation
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).setRefImplementation(newIssuanceManagerImpl);
        assertEq(IssuanceManagerFactory(factoryAddr).getRefImplementation(), newIssuanceManagerImpl);

        // Simulate company owner accept the upgrade
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).upgradeToAndCall(newIssuanceManagerImpl, "");

        address newCyberCertPrinterImpl = address(new CyberCertPrinter());

        // Owner should be able to set CyberCertPrinter reference implementation
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).setCyberCertPrinterRefImplementation(newCyberCertPrinterImpl);
        assertEq(IssuanceManagerFactory(factoryAddr).getCyberCertPrinterRefImplementation(), newCyberCertPrinterImpl);

        // Simulate company owner accept the upgrade
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).upgradeCertPrinterBeaconImplementation(newCyberCertPrinterImpl);

        // Verify the IssuanceManager still works by checking the certificate printer
        assertEq(IssuanceManager(issuanceManager).printers(0), cyberCertPrinterAddr[0]);
        assertEq(IssuanceManager(issuanceManager).getCertPrinterBeaconImplementation(), newCyberCertPrinterImpl);
    }

    function testUpgradeCyberCorpSingle() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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

        // Non-owner should not be able to set reference implementation
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        CyberCorpSingleFactory(factoryAddr).setRefImplementation(newImplementation);

        // Owner should be able to set reference implementation
        vm.prank(multisig);
        CyberCorpSingleFactory(factoryAddr).setRefImplementation(newImplementation);
        assertEq(CyberCorpSingleFactory(factoryAddr).getRefImplementation(), newImplementation);

        //check the company name
        assertEq(CyberCorp(cyberCorp).cyberCORPName(), "CyberCorp");
    }

    function testUpgradeCyberCertPrinter() public {
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
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

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
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
        address newCyberCertPrinterImpl = address(new CyberCertPrinter());

        address factoryAddr = cyberCorpFactory.issuanceManagerFactory();

        // Only MetaLeX can release new reference implementation
        vm.prank(multisig);
        IssuanceManagerFactory(factoryAddr).setCyberCertPrinterRefImplementation(newCyberCertPrinterImpl);
        assertEq(IssuanceManagerFactory(factoryAddr).getCyberCertPrinterRefImplementation(), newCyberCertPrinterImpl);

        // Only company owner can call the Issuance Manager to upgrade its CyberCert Printer beacon
        vm.prank(testAddress);
        vm.expectEmit(true, true, true, true);
        emit IssuanceManager.CertPrinterBeaconImplementationUpgraded(newCyberCertPrinterImpl);
        IssuanceManager(issuanceManager).upgradeCertPrinterBeaconImplementation(newCyberCertPrinterImpl);

        assertEq(IssuanceManager(issuanceManager).getCertPrinterBeaconImplementation(), newCyberCertPrinterImpl);

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

    function testCyberCorpFactoryModuleSetters() public {
        // Non-owner should be prohibited from using setter

        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        cyberCorpFactory.setCyberCorpSingleFactory(address(1));

        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        cyberCorpFactory.setDealManagerFactory(address(2));

        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        cyberCorpFactory.setIssuanceManagerFactory(address(3));

        // Owner should be able to use setter
        vm.startPrank(multisig);

        cyberCorpFactory.setCyberCorpSingleFactory(address(1));
        assertEq(cyberCorpFactory.cyberCorpSingleFactory(), address(1), "Unexpected new cyberCorpSingleFactory");

        cyberCorpFactory.setDealManagerFactory(address(2));
        assertEq(cyberCorpFactory.dealManagerFactory(), address(2), "Unexpected new dealManagerFactory");

        cyberCorpFactory.setIssuanceManagerFactory(address(3));
        assertEq(cyberCorpFactory.issuanceManagerFactory(), address(3), "Unexpected new issuanceManagerFactory");

        vm.stopPrank();
    }

    function testUpgradeWarrantExtension() public {

        bytes32 salt = bytes32(keccak256("WarrantTest"));
        address warrantExtension = address(new ERC1967Proxy{salt: salt}(
           address(new TokenWarrantExtension{salt: salt}()),
           abi.encodeWithSelector(TokenWarrantExtension.initialize.selector, address(auth))
        ));
        //deploy new implementation
        address newImplementation = address(new TokenWarrantExtension());

        //should fail for non-admin
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        TokenWarrantExtension(warrantExtension).upgradeToAndCall(newImplementation, "");

        //upgrade the extension
        vm.startPrank(multisig);
        TokenWarrantExtension(warrantExtension).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

    }

    function testRemoveOfficerAt() public {
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        vm.startPrank(testAddress);
        (
            address cyberCorpAddr,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("OfficerRemoval"),
            "CyberCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            testAddress,
            officer
        );
        CyberCorp cyberCorp = CyberCorp(cyberCorpAddr);

        CompanyOfficer memory officer2 = CompanyOfficer({
            eoa: address(0xBEEF),
            name: "Second Officer",
            contact: "second@example.com",
            title: "CTO"
        });
        cyberCorp.addOfficer(officer2);

        vm.expectEmit(true, true, true, true);
        emit CyberCorp.OfficerRemoved(officer2.eoa, 1);
        cyberCorp.removeOfficerAt(1);

        BorgAuth corpAuth = BorgAuth(cyberCorp.AUTH());
        assertEq(corpAuth.userRoles(officer2.eoa), 0);
        vm.expectRevert(); // Really, that's the error message: empty
        cyberCorp.companyOfficers(1);
        vm.stopPrank();
    }

    function precisionTest() public {

    }

    function testPrintCertificateSAFTEUri() public {
        vm.startPrank(testAddress);
        bytes32 check = bytes32(bytes("ABV_safe_t"));
        console.logBytes32(check);
     console.log("metalex_cyberstock_reg_d_v1_0");
        check = bytes32(bytes("metalex_cyberstock_reg_d_v1_0"));
        console.logBytes32(check);
     
        bytes32 salt = bytes32(keccak256("TestSAFTE"));

        address safteExtension = address(new ERC1967Proxy{salt: salt}(
           address(new SAFTEExtension{salt: salt}()),
           abi.encodeWithSelector(SAFTEExtension.initialize.selector, address(auth))
        ));

        SAFTEData memory safteData = SAFTEData({
            protocolUSDValuationAtTimeofInvestment: 100000000,
            unlockStartTimeType: UnlockStartTimeType.tokenWarrantTime,
            unlockStartTime: block.timestamp,
            unlockingPeriod: 100000,
            unlockingCliffPeriod: 100000,
            unlockingCliffPercentage: 100000,
            unlockingIntervalType: UnlockingIntervalType.monthly,
            tokenCalculationMethod: TokenCalculationMethod.equityProRataToTokenSupply,
            minCompanyReserve: 0,
            tokenPremiumMultiplier: 0
        });

        bytes memory safteDataEncoded = abi.encode(safteData);

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Gabe",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 100000000,
            unitsRepresented: 100000,
            legalDetails: "Legal Details",
            extensionData: safteDataEncoded
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
        globalValues[3] = "Delaware";
        globalValues[4] = "Binding Arbitration";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](5);
        partyValues[0][0] = "Gabe";
        partyValues[0][1] = "0xDEADBABE12345678909876543210866666666666";
        partyValues[0][2] = "@Gabe";
        partyValues[0][3] = "Limited Liability Company";
        partyValues[0][4] = "Delaware";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(2)), block.timestamp, globalValues, parties, bytes32(0));

        bytes memory proposerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        certData[0].extension = safteExtension;
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
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
        partyValuesB[4] = "Delaware";

        vm.startPrank(newPartyAddr);
        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            "passphrase"
        );

        // Get the token URI and verify it contains the SAFTE details
        string memory tokenUri = CyberCertPrinter(cyberCertPrinterAddr[0]).tokenURI(0);
        assertTrue(bytes(tokenUri).length > 0, "Token URI should not be empty");
        console.log("tokenUri: ", tokenUri);
        vm.stopPrank();
    }

    function testCreateOfferBasic() public {
        // First deploy a CyberCorp without creating an offer
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 1000,
            legalDetails: "Legal Details for test",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("CreateOfferTest"),
            "TestCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute Resolution",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Now create an offer using the new createOffer function
        DealManager dealManager = DealManager(dealManagerAddr);

        // Prepare certificate data
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Test Legend";

        DealManagerStorage.CyberCertData[] memory certData = new DealManagerStorage.CyberCertData[](1);
        certData[0] = DealManagerStorage.CyberCertData({
            name: "Test Certificate",
            symbol: "TEST",
            uri: "ipfs://test-uri",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        // Prepare deal parameters
        bytes32 templateId = bytes32(uint256(1));
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 paymentAmount = 1000000000000000000; // 1 ETH
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        // Create signature
        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0), dealManagerAddr);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 1000000;
        address stableAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        vm.startPrank(testAddress);
        (
            address[] memory certPrinterAddress,
            bytes32 id,
            uint256[] memory certIds
        ) = dealManager.proposeAndSignNewCertsDeal(
            block.timestamp,
            certData,
            templateId,
            globalValues,
            parties,
            paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            secretHash,
            expiry,
            stableAddress
        );
        vm.stopPrank();

        // Verify the results
        assertEq(certPrinterAddress.length, 1, "Should have created 1 certificate printer");
        assertEq(certIds.length, 1, "Should have created 1 certificate");
        assertTrue(id != bytes32(0), "Should have created a valid agreement ID");

        // Verify the certificate printer was created correctly
        CyberCertPrinter certPrinter = CyberCertPrinter(certPrinterAddress[0]);


        // Verify the certificate name includes the company name
        string memory expectedName = "TestCorp Test Certificate";
        // Note: We can't directly check the name as it's not exposed in the interface
        // but we can verify the certificate was created successfully

        // Verify the deal was created in the registry
        assertTrue(
            CyberAgreementRegistry(registry).hasSigned(id, testAddress),
            "Deal should be signed by the proposer"
        );

        console.log("Created certificate printer:", certPrinterAddress[0]);
        console.log("Created certificate ID:", certIds[0]);
        console.log("Created agreement ID:", vm.toString(id));
    }

    function testCreateOfferMultipleCertificates() public {
        // First deploy a CyberCorp without creating an offer
        CertificateDetails[] memory _details = new CertificateDetails[](2);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 1000,
            legalDetails: "Legal Details for SAFE",
            extensionData: ""
        });
        CertificateDetails memory _detailsB = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 50000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 500,
            legalDetails: "Legal Details for Token Warrant",
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

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("CreateOfferMultipleTest"),
            "MultiCertCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute Resolution",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Now create an offer with multiple certificates
        DealManager dealManager = DealManager(dealManagerAddr);

        // Prepare certificate data for multiple certificates
        string[] memory safeLegend = new string[](1);
        safeLegend[0] = "SAFE Legend";
        string[] memory warrantLegend = new string[](1);
        warrantLegend[0] = "Token Warrant Legend";

        DealManagerStorage.CyberCertData[] memory certData = new DealManagerStorage.CyberCertData[](2);
        certData[0] = DealManagerStorage.CyberCertData({
            name: "SAFE Certificate",
            symbol: "SAFE",
            uri: "ipfs://safe-uri",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: safeLegend
        });
        certData[1] = DealManagerStorage.CyberCertData({
            name: "Token Warrant",
            symbol: "TWARRANT",
            uri: "ipfs://warrant-uri",
            securityClass: SecurityClass.TokenWarrant,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: warrantLegend
        });

        // Prepare deal parameters
        bytes32 templateId = bytes32(uint256(1));
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 paymentAmount = 1500000000000000000; // 1.5 ETH
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        // Create signature
        bytes32 contractId = _expectedAgreementId(templateId, block.timestamp, globalValues, parties, bytes32(0), dealManagerAddr);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 1000000;
        address stableAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        vm.startPrank(testAddress);
        (
            address[] memory certPrinterAddress,
            bytes32 id,
            uint256[] memory certIds
        ) = dealManager.proposeAndSignNewCertsDeal(
             block.timestamp,
            certData,
            templateId,
            globalValues,
            parties,
            paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            secretHash,
            expiry,
            stableAddress
        );
        vm.stopPrank();

        // Verify the results
        assertEq(certPrinterAddress.length, 2, "Should have created 2 certificate printers");
        assertEq(certIds.length, 2, "Should have created 2 certificates");
        assertTrue(id != bytes32(0), "Should have created a valid agreement ID");

        // Verify the first certificate printer (SAFE)
        CyberCertPrinter safePrinter = CyberCertPrinter(certPrinterAddress[0]);

        // Verify the second certificate printer (Token Warrant)
        CyberCertPrinter warrantPrinter = CyberCertPrinter(certPrinterAddress[1]);


        // Verify the deal was created in the registry
        assertTrue(
            CyberAgreementRegistry(registry).hasSigned(id, testAddress),
            "Deal should be signed by the proposer"
        );

        // Test that we can retrieve the escrow details
        Escrow memory escrow = dealManager.getEscrowDetails(id);
        assertEq(escrow.corpAssets.length, 2, "Escrow should have 2 corporate assets");
        assertEq(escrow.buyerAssets.length, 1, "Escrow should have 1 buyer asset");
        assertEq(escrow.buyerAssets[0].amount, paymentAmount, "Payment amount should match");

        console.log("Created SAFE certificate printer:", certPrinterAddress[0]);
        console.log("Created Token Warrant certificate printer:", certPrinterAddress[1]);
        console.log("Created SAFE certificate ID:", certIds[0]);
        console.log("Created Token Warrant certificate ID:", certIds[1]);
        console.log("Created agreement ID:", vm.toString(id));
    }

    function testUpgradeLegacyDealManagersViaBeacon() public {
        // First deploy a CyberCorp which will create a DealManager
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 1000,
            legalDetails: "Legal Details for test",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("DealManagerUpgradeTest"),
            "TestCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute Resolution",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Verify the DealManager was deployed
        assertTrue(dealManagerAddr != address(0), "DealManager should be deployed");
        console.log("Deployed DealManager at:", dealManagerAddr);

        // Get the deployed DealManagerFactory address (legacy Beacon-based)
        address deployedFactoryAddr = 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3;
        ILegacyFactory deployedFactory = ILegacyFactory(deployedFactoryAddr);

        // Get the current beacon implementation
        address currentImplementation = deployedFactory.getBeaconImplementation();
        console.log("Current beacon implementation:", currentImplementation);

        // Deploy a new DealManager implementation using CREATE2
        bytes32 implementationSalt = bytes32(keccak256("NewDealManagerImplementation"));
        address newImplementation = address(new DealManager{salt: implementationSalt}());
        console.log("New implementation deployed at:", address(newImplementation));

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, address(this)));
        deployedFactory.upgradeImplementation(newImplementation);

        // Owner should be able to upgrade it
        vm.prank(multisig);
        deployedFactory.upgradeImplementation(newImplementation);

        // Verify the upgrade was successful
        address updatedImplementation = deployedFactory.getBeaconImplementation();
        assertEq(updatedImplementation, address(newImplementation), "Beacon implementation should be updated");
        console.log("Updated beacon implementation:", updatedImplementation);

        // Verify the existing DealManager still works by checking its state
        DealManager dealManager = DealManager(dealManagerAddr);


        // Create a simple deal to verify functionality still works
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Test Legend";

        DealManagerStorage.CyberCertData[] memory certData = new DealManagerStorage.CyberCertData[](1);
        certData[0] = DealManagerStorage.CyberCertData({
            name: "Test Certificate",
            symbol: "TEST",
            uri: "ipfs://test-uri",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        bytes32 templateId = bytes32(uint256(1));
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 paymentAmount = 1000000000000000000; // 1 ETH
        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = _expectedAgreementId(templateId, block.timestamp, globalValues, parties, bytes32(0), dealManagerAddr);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 1000000;
        address stableAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        vm.startPrank(testAddress);
        (
            address[] memory certPrinterAddress,
            bytes32 id,
            uint256[] memory certIds
        ) = dealManager.proposeAndSignNewCertsDeal(
            block.timestamp,
            certData,
            templateId,
            globalValues,
            parties,
            paymentAmount,
            partyValues,
            signature,
            _details,
            conditions,
            secretHash,
            expiry,
            stableAddress
        );
        vm.stopPrank();

        // Verify the deal was created successfully after the upgrade
        assertEq(certPrinterAddress.length, 1, "Should have created 1 certificate printer");
        assertEq(certIds.length, 1, "Should have created 1 certificate");
        assertTrue(id != bytes32(0), "Should have created a valid agreement ID");

        console.log("Successfully created deal after upgrade with ID:", vm.toString(id));
        console.log("Certificate printer created at:", certPrinterAddress[0]);
        console.log("Certificate ID:", certIds[0]);
    }

    // Helper function to mint a LexChex token for testing
    function _mintLexChexToken(address owner, uint256 uuid) internal returns (uint256 tokenId) {
        Accreditation memory acc = Accreditation({
            uuid: uuid,
            agreementId: bytes32(uint256(123)),
            registryAddress: address(registry),
            investorName: "Test Investor",
            investorType: "Individual",
            investorJurisdiction: "Delaware",
            investorContact: "test@investor.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: bytes("test-signature")
        });

        vm.prank(multisig); // Admin can mint
        tokenId = lexchex.mint(owner, acc);
    }

    function testLexChexConditionWithValidToken() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);
        vm.prank(multisig);
        auth.updateRole(address(testAddress), 98); // Give testAddress ADMIN_ROLE for testing
        // First mint a LexChex token for the counterparty
        uint256 tokenId = _mintLexChexToken(newPartyAddr, 1);

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jurisdiction etc",
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
        parties[1] = address(newPartyAddr); // Set counterparty to the LexChex token holder
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // Add LexChex condition to the deal
        address[] memory conditions = new address[](1);
        conditions[0] = address(lexchexCondition);

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
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
            conditions, // Include LexChex condition
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

        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // This should succeed because the counterparty has a valid LexChex token
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

        console.log("Deal finalized successfully with LexChex condition");
        console.log("LexChex token ID:", tokenId);
        console.log("Token owner:", lexchex.ownerOf(tokenId));
    }

    function testLexChexConditionWithInvalidToken() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        // Mint a LexChex token but void it
        uint256 tokenId = _mintLexChexToken(newPartyAddr, 2);
        
        // Void the token
        vm.prank(multisig);
        lexchex.void(tokenId, "Token voided for testing");

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jurisdiction etc",
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
        parties[1] = address(newPartyAddr); // Set counterparty to the LexChex token holder
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // Add LexChex condition to the deal
        address[] memory conditions = new address[](1);
        conditions[0] = address(lexchexCondition);

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
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
            conditions, // Include LexChex condition
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

        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // This should fail because the counterparty has an invalid (voided) LexChex token
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector); // Expect revert due to condition not being met
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

        console.log("Deal correctly failed with invalid LexChex token");
        console.log("LexChex token ID:", tokenId);
        console.log("Token is voided:", bytes(lexchex.accreditations(tokenId).voided).length > 0);
    }

    function testLexChexConditionWithNoToken() public {
        uint256 newPartyPk = 80085;
        address newPartyAddr = vm.addr(newPartyPk);

        // Don't mint any LexChex token for the counterparty

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jurisdiction etc",
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
        parties[1] = address(newPartyAddr); // Set counterparty without LexChex token
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // Add LexChex condition to the deal
        address[] memory conditions = new address[](1);
        conditions[0] = address(lexchexCondition);

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
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
            conditions, // Include LexChex condition
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

        bytes memory newPartySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // This should fail because the counterparty has no LexChex token
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector); // Expect revert due to condition not being met
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

        console.log("Deal correctly failed with no LexChex token");
        console.log("Counterparty token balance:", lexchex.balanceOf(newPartyAddr));
    }

    function testLexChexMinterIntegration() public {
        uint256 investorPk = 12345;
        address investorAddr = vm.addr(investorPk);
        vm.etch(investorAddr, hex"");

        vm.startPrank(multisig);
        auth.updateRole(address(testAddress), 98); // Give testAddress ADMIN_ROLE for testing
        vm.stopPrank();

        // Prepare mint request
        LeXcheXMinter.MintRequest memory request = LeXcheXMinter.MintRequest({
            uuid: 1,
            owner: investorAddr,
            investorName: "John Investor",
            investorType: "Individual",
            investorJurisdiction: "Delaware",
            investorContact: "john@investor.com",
            mintPrice: 1000000, // 1 USDC (6 decimals)
            expiry: block.timestamp + 365 days,
            paymentToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e // USDC
        });

        // Create authority signature
        LeXcheXMinter.AuthorityData memory authData = LeXcheXMinter.AuthorityData({
            uuid: request.uuid,
            owner: request.owner,
            investorName: request.investorName,
            investorType: request.investorType,
            investorJurisdiction: request.investorJurisdiction,
            investorContact: request.investorContact,
            mintPrice: request.mintPrice,
            expiry: request.expiry,
            paymentToken: request.paymentToken
        });

        bytes memory authoritySignature = LeXcheXUtils.signAuthorizationTypedData(
            vm,
            lexchexMinter.DOMAIN_SEPARATOR(),
            lexchexMinter.AUTHORITY_TYPEHASH(),
            authData,
            testPrivateKey // Admin signs the authority data
        );

        // Prepare agreement data
        bytes32 templateId = bytes32(uint256(1));
        string[] memory globalValues = new string[](1);
        globalValues[0] = "LexChex Agreement";
        address[] memory parties = new address[](1);
        parties[0] = investorAddr;

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Investor Party Value";


        bytes32 contractId = _expectedAgreementId(templateId, 1337, globalValues, parties, bytes32(0), address(lexchexMinter));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory agreementSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            investorPk
        );

        // Give the investor some USDC for payment
        vm.startPrank(investorAddr);
        deal(request.paymentToken, investorAddr, request.mintPrice);
        IERC20(request.paymentToken).approve(address(lexchexMinter), request.mintPrice);

        // Request mint
        (bytes32 agreementId, uint256 tokenId) = lexchexMinter.requestMint(
            request,
            templateId,
            1337, // salt
            globalValues,
            parties,
            partyValues,
            agreementSignature,
            authoritySignature
        );
        vm.stopPrank();

        // Verify the LexChex token was minted
        assertEq(lexchex.ownerOf(tokenId), investorAddr, "Token should be owned by investor");
        assertTrue(lexchex.isValid(tokenId), "Token should be valid");

        Accreditation memory acc = lexchex.accreditations(tokenId);
        assertEq(acc.investorName, "John Investor", "Investor name should match");
        assertEq(acc.agreementId, agreementId, "Agreement ID should match");

        console.log("LexChex minted successfully:");
        console.log("Token ID:", tokenId);
        console.log("Agreement ID:", vm.toString(agreementId));
        console.log("Token owner:", lexchex.ownerOf(tokenId));
        console.log("Token is valid:", lexchex.isValid(tokenId));

        // Now test that this LexChex token can be used for a deal with conditions
        uint256 dealPartyPk = 54321;
        address dealPartyAddr = vm.addr(dealPartyPk);

        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jurisdiction etc",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        string[] memory dealGlobalValues = new string[](1);
        dealGlobalValues[0] = "Deal Global Value 1";
        address[] memory dealParties = new address[](2);
        dealParties[0] = address(testAddress);
        dealParties[1] = address(investorAddr); // Use the LexChex token holder
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory dealPartyValues = new string[][](2);
        dealPartyValues[0] = new string[](1);
        dealPartyValues[0][0] = "Deal Party Value 1";
        dealPartyValues[1] = new string[](1);
        dealPartyValues[1][0] = "Deal Counter Party Value 1";

        bytes32 dealContractId = _expectedAgreementId(
            bytes32(uint256(1)), block.timestamp, dealGlobalValues, dealParties, bytes32(0)
        );

        bytes memory dealSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            dealContractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            dealGlobalValues,
            dealPartyValues[0],
            testPrivateKey
        );

        // Add LexChex condition to the deal
        address[] memory conditions = new address[](1);
        conditions[0] = address(lexchexCondition);

        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 dealId,
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
            dealGlobalValues,
            dealParties,
            _paymentAmount,
            dealPartyValues,
            dealSignature,
            _details,
            conditions, // Include LexChex condition
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        IDealManager dealManager = IDealManager(dealManagerAddr);
        vm.startPrank(investorAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            investorAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );
        vm.stopPrank();

        bytes memory investorDealSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            dealContractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            dealGlobalValues,
            dealPartyValues[1],
            investorPk
        );

        // This should succeed because the investor has a valid LexChex token
        vm.startPrank(testAddress);
        dealManager.signAndFinalizeDeal(
            investorAddr,
            dealContractId,
            dealPartyValues[1],
            investorDealSignature,
            true,
            "LexChex Verified Investor",
            ""
        );
        vm.stopPrank();

        console.log("Deal with LexChex condition completed successfully!");
        console.log("Deal ID:", vm.toString(dealId));
        console.log("Investor LexChex token:", tokenId);
    }

    function testDelegateSigningDeal() public {
        // Create three parties:
        // 1. testAddress - the company/proposer
        // 2. principalAddr - the investor who will delegate
        // 3. delegateAddr - the delegate who will sign and pay on behalf of principal

        uint256 principalPk = 11111;
        address principalAddr = vm.addr(principalPk);
        
        uint256 delegatePk = 22222;
        address delegateAddr = vm.addr(delegatePk);

        // Setup: Principal sets delegate
        vm.startPrank(principalAddr);
        registry.setDelegation(delegateAddr, 0); // No expiry (0 means permanent)
        vm.stopPrank();

        // Verify delegation is set
        (address retrievedDelegate, uint256 expiry) = registry.getDelegation(principalAddr);
        assertEq(retrievedDelegate, delegateAddr, "Delegate should be set correctly");
        assertEq(expiry, 0, "Expiry should be 0 (no expiry)");
        assertTrue(registry.isValidDelegate(principalAddr, delegateAddr), "Delegate should be valid");

        // Create a deal with the principal as a party
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 1000,
            legalDetails: "Legal Details for delegation test",
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
        globalValues[0] = "Delegation Test Deal";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress); // Company
        parties[1] = address(principalAddr); // Principal (who has delegated)
        uint256 _paymentAmount = 1000000000000000000; // 1 ETH
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Company Party Value";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Principal Party Value";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        // Company signs the deal first
        bytes memory companySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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

        // Create the deal
        vm.startPrank(testAddress);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "DelegationTestCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute Resolution",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            companySignature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        // Verify the deal was created but not yet complete
        assertFalse(registry.hasSigned(id, principalAddr), "Principal should not have signed yet");
        assertTrue(registry.hasSigned(id, testAddress), "Company should have signed");

        // Now the delegate signs and pays on behalf of the principal
        // Create signature - delegate signs with their private key but for the principal
        vm.startPrank(delegateAddr);
        bytes memory delegateSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1], // Principal's party values
            delegatePk // Delegate's private key
        );
        vm.stopPrank();
        IDealManager dealManager = IDealManager(dealManagerAddr);
        
        // Give the delegate funds to pay on behalf of the principal
        vm.startPrank(principalAddr);
        deal(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            principalAddr,
            _paymentAmount
        );
        IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e).approve(
            address(dealManager),
            _paymentAmount
        );

        // The delegate signs the deal FOR the principal using signContractFor
        // This is different from signAndFinalizeDeal - it's signing on behalf of another party
        registry.signContractFor(
            principalAddr, // The principal (signer)
            contractId, // The contract ID (same as the deal ID)
            partyValues[1], // The principal's party values
            delegateSignature, // Delegate's signature
            false, // Not filling unallocated
            "" // No secret
        );

        // Now finalize the deal by making the payment
        dealManager.signAndFinalizeDeal(
            principalAddr, // Principal address (who the deal is for)
            contractId,
            partyValues[1],
            delegateSignature,
            true, // Finalize payment
            "Principal via Delegate",
            ""
        );
        vm.stopPrank();

        // Verify the deal is now complete
        assertTrue(registry.hasSigned(id, principalAddr), "Principal should now have signed (via delegate)");
        assertTrue(registry.hasSigned(id, testAddress), "Company should have signed");

        // Verify the certificate was issued to the principal (not the delegate)
        CyberCertPrinter certPrinter = CyberCertPrinter(cyberCertPrinterAddr[0]);
        assertEq(certPrinter.ownerOf(certIds[0]), principalAddr, "Certificate should be owned by principal");

        console.log("Delegation test completed successfully!");
        console.log("Principal:", principalAddr);
        console.log("Delegate:", delegateAddr);
        console.log("Certificate owner:", certPrinter.ownerOf(certIds[0]));
        console.log("Deal ID:", vm.toString(id));
        console.log("Contract ID:", vm.toString(contractId));
    }

    function testDelegateSigningWithExpiry() public {
        uint256 principalPk = 33333;
        address principalAddr = vm.addr(principalPk);
        
        uint256 delegatePk = 44444;
        address delegateAddr = vm.addr(delegatePk);

        // Setup: Principal sets delegate with expiry
        uint256 delegationExpiry = block.timestamp + 1000; // Expires in 1000 seconds
        vm.startPrank(principalAddr);
        registry.setDelegation(delegateAddr, delegationExpiry);
        vm.stopPrank();

        // Verify delegation is set and valid
        assertTrue(registry.isValidDelegate(principalAddr, delegateAddr), "Delegate should be valid");
        (address retrievedDelegate, uint256 expiry) = registry.getDelegation(principalAddr);
        assertEq(retrievedDelegate, delegateAddr, "Delegate should be set correctly");
        assertEq(expiry, delegationExpiry, "Expiry should match");

        // Create a simple deal
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "Test Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100000,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 1000,
            legalDetails: "Legal Details for expiry test",
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
        globalValues[0] = "Delegation Expiry Test Deal";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(principalAddr);
        uint256 _paymentAmount = 1000000000000000000;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Company Party Value";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Principal Party Value";

        bytes32 contractId = _expectedAgreementId(bytes32(uint256(1)), block.timestamp, globalValues, parties, bytes32(0));

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        bytes memory companySignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
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
            address roundManagerAddr,
            address[] memory cyberCertPrinterAddr,
            bytes32 id,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "DelegationExpiryCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute Resolution",
            testAddress,
            officer,
            certData,
            bytes32(uint256(1)),
            globalValues,
            parties,
            _paymentAmount,
            partyValues,
            companySignature,
            _details,
            conditions,
            bytes32(0),
            block.timestamp + 2000000 // Long expiry for the deal
        );
        vm.stopPrank();

        // Fast forward past the delegation expiry
        vm.warp(block.timestamp + 1001);

        // Verify delegation is now expired
        assertFalse(registry.isValidDelegate(principalAddr, delegateAddr), "Delegate should be expired");

        // Create delegate signature
        bytes memory delegateSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            delegatePk
        );

        // Try to sign with expired delegation - should fail
        vm.startPrank(delegateAddr);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector); // Should revert due to expired delegation
        registry.signContractFor(
            principalAddr,
            contractId,
            partyValues[1],
            delegateSignature,
            false,
            ""
        );
        vm.stopPrank();

        console.log("Delegation expiry test completed successfully!");
        console.log("Delegation expired after:", delegationExpiry);
        console.log("Current time:", block.timestamp);
    }

    function testToggleTransferHookPerToken() public {
        vm.startPrank(testAddress);
        // Deploy a CyberCorp to obtain an issuance manager and printer
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 0,
            legalDetails: "",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        (
            address cyberCorp,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("ToggleHookTest"),
            "ToggleHookCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Create a certificate printer
        string[] memory ledger = new string[](1);
        ledger[0] = "Legend";
        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager).createCertPrinter(
            ledger,
            "Test Certificate",
            "TEST",
            "ipfs://test",
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed,
            address(0)
        );

        // Deploy and initialize the toggle hook with the corp's AUTH used by issuanceManager
        ToggleTransferHook hook = new ToggleTransferHook();
        BorgAuth corpAuthForIssuance = IssuanceManager(issuanceManager).AUTH();
        hook.initialize(address(corpAuthForIssuance));

        // Attach the global hook via IssuanceManager (admin)
        vm.prank(testAddress);
        CyberCertPrinter(certPrinter).setGlobalRestrictionHook(address(hook));

        // Enable global transferable on the printer (so hook decides allow/deny)
        vm.prank(issuanceManager);
        CyberCertPrinter(certPrinter).setGlobalTransferable(true);

        // Configure hook: default off, tokenId 1 on
        vm.startPrank(testAddress);
        hook.setDefaultTransferable(false);
        hook.setTokenTransferable(1, true);
        vm.stopPrank();

        // Mint 3 certificates to an EOA owner (avoid receiver-hook issues if testAddress has code)
        address certOwner = vm.addr(0xA11CE);
        assertEq(certOwner.code.length, 0, "certOwner must be EOA");

        // Mint 3 certificates to the owner
        CertificateDetails memory cd = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // tokenId 0
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // tokenId 1
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // tokenId 2

        // Prepare recipient
        address recipient = vm.addr(0xBEEF);

        // Token 0 should be blocked by hook
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSelector(ICyberCertPrinter.TransferRestricted.selector, "Transfer disabled by global hook"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient, 0);
        vm.stopPrank();

        // Token 1 should be allowed by hook, but endorsement is required by printer
        vm.startPrank(certOwner);
        Endorsement memory e = Endorsement({
            endorser: certOwner,
            timestamp: block.timestamp,
            signatureHash: bytes("hook-test"),
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient,
            endorseeName: "Recipient"
        });
        CyberCertPrinter(certPrinter).addEndorsement(1, e);
        vm.stopPrank();
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient, 1);
        assertEq(CyberCertPrinter(certPrinter).ownerOf(1), recipient);

        // Token 2 should be blocked
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSelector(ICyberCertPrinter.TransferRestricted.selector, "Transfer disabled by global hook"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient, 2);
        vm.stopPrank();
    }

    function testPerTokenTransferabilityFlag() public {
        vm.startPrank(testAddress);
        // Deploy a CyberCorp to obtain an issuance manager and printer
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        CertificateDetails memory _detailsA = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        _details[0] = _detailsA;

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });

        (
            address cyberCorp,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("PerTokenFlag"),
            "PerTokenCorp",
            "Limited Liability Company",
            "Delaware",
            "Contact Details",
            "Dispute",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Create a certificate printer and mint two certs to a code-less EOA recipient
        string[] memory ledger = new string[](0);
        address certOwner = vm.addr(0xA11CE);
        vm.etch(certOwner, hex"");
        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager).createCertPrinter(
            ledger,
            "Test",
            "TEST",
            "ipfs://test",
            SecurityClass.SAFE,
            SecuritySeries.SeriesSeed,
            address(0)
        );

        CertificateDetails memory cd = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // tokenId 0
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // tokenId 1

        address recipient = vm.addr(0xCAFE);

        // Global off; token 0 off => revert
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient, 0);
        vm.stopPrank();

        // Enable token 0 only
        vm.prank(issuanceManager);
        CyberCertPrinter(certPrinter).setTokenTransferable(0, true);

        // Transfer without endorsement: ERC721 owner changes but legal owner record does not
        address midAddr = vm.addr(0xD0);
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).transferFrom(certOwner, midAddr, 0);
        assertEq(CyberCertPrinter(certPrinter).ownerOf(0), midAddr);
        assertEq(CyberCertPrinter(certPrinter).legalOwnerOf(0), certOwner);

        // Add endorsement and endorsed transfer updates legal owner record
        Endorsement memory e = Endorsement({
            endorser: midAddr,
            timestamp: block.timestamp,
            signatureHash: hex"01",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient,
            endorseeName: "Recipient"
        });
        vm.prank(midAddr);
        CyberCertPrinter(certPrinter).addEndorsement(0, e);
        vm.prank(midAddr);
        CyberCertPrinter(certPrinter).transferFrom(midAddr, recipient, 0);
        assertEq(CyberCertPrinter(certPrinter).ownerOf(0), recipient);
        assertEq(CyberCertPrinter(certPrinter).legalOwnerOf(0), recipient);

        // Token 1 should remain blocked
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, vm.addr(0xBEEF), 1);
        vm.stopPrank();
    }

    function testRevokeDelegation() public {
        uint256 principalPk = 55555;
        address principalAddr = vm.addr(principalPk);
        
        uint256 delegatePk = 66666;
        address delegateAddr = vm.addr(delegatePk);

        // Setup: Principal sets delegate
        vm.startPrank(principalAddr);
        registry.setDelegation(delegateAddr, 0); // No expiry
        vm.stopPrank();

        // Verify delegation is set
        assertTrue(registry.isValidDelegate(principalAddr, delegateAddr), "Delegate should be valid");

        // Principal revokes delegation
        vm.startPrank(principalAddr);
        registry.revokeDelegation();
        vm.stopPrank();

        // Verify delegation is revoked
        assertFalse(registry.isValidDelegate(principalAddr, delegateAddr), "Delegate should be revoked");
        (address retrievedDelegate, uint256 expiry) = registry.getDelegation(principalAddr);
        assertEq(retrievedDelegate, address(0), "Delegate should be cleared");
        assertEq(expiry, 0, "Expiry should be cleared");

        console.log("Delegation revocation test completed successfully!");
        console.log("Principal:", principalAddr);
        console.log("Delegate:", delegateAddr);
    }

    function testGlobalTransferabilityEphemeral() public {
        vm.startPrank(testAddress);
        CertificateDetails[] memory _details = new CertificateDetails[](1);
        _details[0] = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });
        (
            address cyberCorp,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("GlobalEphemeral"),
            "Corp",
            "LLC",
            "DE",
            "Contact",
            "Dispute",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Create printer and mint two certs to a code-less EOA recipient
        string[] memory ledger = new string[](0);
        address certOwner = vm.addr(0xA11CE);
        vm.etch(certOwner, hex"");
        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager).createCertPrinter(
            ledger,
            "Cert",
            "CRT",
            "ipfs://uri",
            SecurityClass.SAFE,
            SecuritySeries.SeriesSeed,
            address(0)
        );
        CertificateDetails memory cd = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // token 0
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // token 1

        address recipient1 = vm.addr(0x1001);
        address recipient2 = vm.addr(0x1002);

        // Add endorsement for token 0 -> recipient1
        Endorsement memory e0 = Endorsement({
            endorser: certOwner,
            timestamp: block.timestamp,
            signatureHash: hex"01",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient1,
            endorseeName: "R1"
        });
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).addEndorsement(0, e0);

        // Before enabling global: expect TokenNotTransferable
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient1, 0);
        vm.stopPrank();

        // Turn global on, transfer succeeds
        vm.prank(issuanceManager);
        CyberCertPrinter(certPrinter).setGlobalTransferable(true);
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient1, 0);
        assertEq(CyberCertPrinter(certPrinter).ownerOf(0), recipient1);

        // Global off again
        vm.prank(issuanceManager);
        CyberCertPrinter(certPrinter).setGlobalTransferable(false);

        // Verify token flag not persisted
        bool persisted = CyberCertPrinter(certPrinter).isTokenTransferable(0);
        assertEq(persisted, false);

        // Add endorsement for token 1 -> recipient2 and ensure it still reverts due to global off and no per-token flag
        Endorsement memory e1 = Endorsement({
            endorser: certOwner,
            timestamp: block.timestamp,
            signatureHash: hex"02",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient2,
            endorseeName: "R2"
        });
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).addEndorsement(1, e1);
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSignature("TokenNotTransferable()"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient2, 1);
        vm.stopPrank();
    }

    function testPerTokenTransferabilityWithHookDenial() public {
        vm.startPrank(testAddress);
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });
        (
            address cyberCorp,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("PerTokenHookDeny"),
            "Corp",
            "LLC",
            "DE",
            "Contact",
            "Dispute",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Create printer and mint token 0 to a code-less EOA recipient
        string[] memory ledger = new string[](0);
        address certOwner = vm.addr(0xA11CE);
        vm.etch(certOwner, hex"");
        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager).createCertPrinter(
            ledger,
            "Cert",
            "CRT",
            "ipfs://uri",
            SecurityClass.SAFE,
            SecuritySeries.SeriesSeed,
            address(0)
        );
        CertificateDetails memory cd = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, certOwner, cd); // token 0

        // Enable per-token transferability for token 0
        vm.prank(issuanceManager);
        CyberCertPrinter(certPrinter).setTokenTransferable(0, true);

        // Install a denying global hook
        ToggleTransferHook hook = new ToggleTransferHook();
        BorgAuth corpAuth = IssuanceManager(issuanceManager).AUTH();
        hook.initialize(address(corpAuth));
        vm.prank(testAddress);
        CyberCertPrinter(certPrinter).setGlobalRestrictionHook(address(hook));
        vm.prank(testAddress);
        hook.setDefaultTransferable(false);

        // With endorsement, transfer should still be blocked by hook
        address recipient = vm.addr(0x2222);
        Endorsement memory e = Endorsement({
            endorser: certOwner,
            timestamp: block.timestamp,
            signatureHash: hex"01",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient,
            endorseeName: "R"
        });
        vm.prank(certOwner);
        CyberCertPrinter(certPrinter).addEndorsement(0, e);
        vm.startPrank(certOwner);
        vm.expectRevert(abi.encodeWithSelector(ICyberCertPrinter.TransferRestricted.selector, "Transfer disabled by global hook"));
        CyberCertPrinter(certPrinter).transferFrom(certOwner, recipient, 0);
        vm.stopPrank();
    }

    function testDealManagerExemptionWithEndorsement() public {
        vm.startPrank(testAddress);
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: testAddress,
            name: "Test Officer",
            contact: "test@example.com",
            title: "CEO"
        });
        (
            address cyberCorp,
            address authAddr,
            address issuanceManager,
            address dealManagerAddr,
            address roundManagerAddr
        ) = cyberCorpFactory.deployCyberCorp(
            keccak256("DealMgrExempt"),
            "Corp",
            "LLC",
            "DE",
            "Contact",
            "Dispute",
            testAddress,
            officer
        );
        vm.stopPrank();

        // Create printer and mint token to dealManager
        string[] memory ledger = new string[](0);
        vm.prank(testAddress);
        address certPrinter = IssuanceManager(issuanceManager).createCertPrinter(
            ledger,
            "Cert",
            "CRT",
            "ipfs://uri",
            SecurityClass.SAFE,
            SecuritySeries.SeriesSeed,
            address(0)
        );
        CertificateDetails memory cd = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 0,
            unitsRepresented: 1,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(testAddress);
        IssuanceManager(issuanceManager).createCert(certPrinter, dealManagerAddr, cd); // token 0 owned by dealManager

        // Add endorsement to recipient
        address recipient = vm.addr(0x3333);
        Endorsement memory e = Endorsement({
            endorser: dealManagerAddr,
            timestamp: block.timestamp,
            signatureHash: hex"01",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: recipient,
            endorseeName: "R"
        });
        vm.prank(dealManagerAddr);
        CyberCertPrinter(certPrinter).addEndorsement(0, e);

        // With both global and token flags off, transfer from dealManager should succeed (exemption), subject to hooks/endorsement
        vm.prank(dealManagerAddr);
        CyberCertPrinter(certPrinter).transferFrom(dealManagerAddr, recipient, 0);
        assertEq(CyberCertPrinter(certPrinter).ownerOf(0), recipient);
    }
}
