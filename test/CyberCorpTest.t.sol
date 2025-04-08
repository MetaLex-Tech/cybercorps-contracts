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
    address counterPartyAddress = 0x1A762EfF397a3C519da3dF9FCDDdca7D1BD43B5e;

    function setUp() public {
        ///deploy cyberCertPrinterImplementation
        testPrivateKey = 1337;
        testAddress = vm.addr(testPrivateKey);
        vm.startPrank(testAddress);
        BorgAuth auth = new BorgAuth();
        auth.initialize();
        address issuanceManagerFactory = address(
            new IssuanceManagerFactory(address(0))
        );
        address cyberCertPrinterImplementation = address(
            new CyberCertPrinter()
        );
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(
            cyberCertPrinterImplementation
        );
        cyberCertPrinter.initialize(
            "",
            "",
            "",
            "ipfs.io/ipfs/[cid]",
            address(0),
            SecurityClass.SAFE,
            SecuritySeries.SeriesPreSeed
        );
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory());

        address dealManagerFactory = address(new DealManagerFactory());

        registry = new CyberDealRegistry();
        CyberDealRegistry(registry).initialize(address(auth));
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        registry.createTemplate(
            bytes32(uint256(1)),
            "SAFE",
            "ipfs.io/ipfs/[cid]",
            globalFields,
            partyFields
        );

        cyberCorpFactory = new CyberCorpFactory(
            address(registry),
            cyberCertPrinterImplementation,
            issuanceManagerFactory,
            cyberCorpSingleFactory,
            dealManagerFactory
        );

        vm.stopPrank();
    }

    function testOffer() public {
        CertificateDetails memory _details = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmount: 0,
            issuerUSDValuationAtTimeofInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            issuerSignatureURI: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value 1";

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
            partyValues,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            testAddress,
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
            legalDetails: "Legal Details, jusidictione etc",
            issuerSignatureURI: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(newPartyAddr);
        uint256 _paymentAmount = 1000000000000000000;
        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value 1";

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
            partyValues,
            testPrivateKey
        );

        string[] memory counterPartyValues = new string[](1);
        counterPartyValues[0] = "Counter Party Value 1";

        vm.startPrank(testAddress);
         (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dealManagerAddr,
            address cyberCertPrinterAddr,
            bytes32 id
        ) = cyberCorpFactory.deployCyberCorpAndCreateClosedOffer(
            block.timestamp,
            "CyberCorp",
            testAddress,
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
            counterPartyValues,
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
            counterPartyValues,
            newPartyPk
        );
        
        dealManager.signAndFinalizeDeal(
            newPartyAddr,
            contractId,
            counterPartyValues,
            newPartySignature,
            true,
            "Counter Party Name"
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
            legalDetails: "Legal Details, jusidictione etc",
            issuerSignatureURI: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = address(testAddress);
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value 1";

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
            partyValues,
            testPrivateKey
        );

        vm.startPrank(testAddress);
        (address cyberCorp, address auth, address issuanceManager, address dealManagerAddr, address cyberCertPrinterAddr, bytes32 id) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "CyberCorp",
            testAddress,
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
            block.timestamp + 1000000
        );
        vm.stopPrank();

        //wait for 1000000 blocks
        vm.warp(block.timestamp + 1000001);
        vm.startPrank(testAddress);
        IDealManager(dealManagerAddr).voidExpiredDeal(contractId, testAddress, signature);
        vm.stopPrank();
    }

    function testCreateContract() public {
        vm.startPrank(testAddress);
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
            parties
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
            partyValues,
            testPrivateKey
        );

        registry.signContractFor(
            testAddress,
            id,
            partyValues,
            signature,
            false
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
        registry.signContract(id, partyValuesB, signature, true);
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
            legalDetails: "Legal Details, jusidictione etc",
            issuerSignatureURI: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = testAddress;
        parties[1] = address(0);
        uint256 _paymentAmount = 1000000000000000000;
        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value 1";

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
            partyValues,
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
                testAddress,
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
            "John Doe"
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
}
