// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Test.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {IRoundManager} from "../src/interfaces/IRoundManager.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {RoundType} from "../src/libs/RoundLib.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PublicRoundTestDeploy is Script {
    // EIP-712 constants for RoundManager escrow signature
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Fresh salt per request
        bytes32 salt = keccak256(
            abi.encodePacked("PublicRound.Test.v4")
        );

        // Resolve stable (USDC) per chain
        address stable;
        uint256 currentChainId = block.chainid;
        if (currentChainId == 1) {
            stable = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet
        } else if (currentChainId == 42161) {
            stable = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum
        } else if (currentChainId == 8453) {
            stable = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base
        } else if (currentChainId == 84532) {
            stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia
        } else if (currentChainId == 11155111) {
            stable = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia
        } else {
            revert("Unsupported chain ID");
        }

        // Core AUTH
        BorgAuth auth = new BorgAuth{salt: salt}(deployer);

        // Factories + Implementations
        address issuanceManagerImpl = address(new IssuanceManager{salt: salt}());
        address cyberCertPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImpl = address(new CyberScrip{salt: salt}());
        address issuanceManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new IssuanceManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    issuanceManagerImpl,
                    cyberCertPrinterImpl,
                    cyberScripImpl
                )
            )
        );

        address cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: salt}(address(auth))
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
        address roundManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        );

        // Upgradeable singletons
        address registry = address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        );

        address uriBuilder = address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(auth)
                )
            )
        );

        // CyberCorpFactory (UUPS proxy)
        CyberCorpFactory corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(auth),
                        address(registry),
                        address(cyberCertPrinterImpl),
                        address(cyberScripImpl),
                        address(issuanceManagerFactory),
                        address(cyberCorpSingleFactory),
                        address(dealManagerFactory),
                        address(roundManagerFactory),
                        address(uriBuilder)
                    )
                )
            )
        );

        // Configure factory
        corpFactory.setStable(stable);
       BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2).updateRole(address(corpFactory), 99);
        // Create templates: (a) test template 777 (b) SAFE template id 1
        bytes32 templateId = bytes32(uint256(777));
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        CyberAgreementRegistry(registry).createTemplate(
            templateId,
            "FCFS-Test",
            "ipfs://template",
            globalFields,
            partyFields
        );

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

        CyberAgreementRegistry(registry).createTemplate(
            bytes32(uint256(1)),
            "SAFE",
            "https://ipfs.io/ipfs/bafybeih5wvr7zfw76plnb66teaa66rtgoikhhcqh55oecuoxtuw5c3dooi",
            globalFieldsSafe,
            partyFieldsSafe
        );

        // Prepare public round params
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: deployer,
            name: "CEO",
            contact: "ceo@example.com",
            title: "Chief Executive Officer"
        });

        CyberCertData[] memory certData = new CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = CyberCertData({
            name: "CyberCorp",
            symbol: "CC",
            uri: "ipfs://certificate",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        // SAFE template id 1 requires 5 global fields and 5 party fields
        string[] memory safeGlobalValues = new string[](5);
        safeGlobalValues[0] = "1000.00"; // purchaseAmount
        safeGlobalValues[1] = "10000000"; // postMoneyValuationCap
        safeGlobalValues[2] = "1700000000"; // expirationTime (ts)
        safeGlobalValues[3] = "DE"; // governingJurisdiction
        safeGlobalValues[4] = "arbitration"; // disputeResolution

        string[] memory safePartyValues = new string[](5);
        safePartyValues[0] = "Investor 1"; // name
        safePartyValues[1] = "0xINVESTOR"; // evmAddress (string form)
        safePartyValues[2] = "email"; // contactDetails
        safePartyValues[3] = "Individual"; // investorType
        safePartyValues[4] = "US"; // investorJurisdiction

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        // Predict corp and round manager addresses to build a valid escrow signature
        bytes32 corpSalt = keccak256(abi.encodePacked(block.timestamp + 1));
        address predictedCorp = CyberCorpSingleFactory(cyberCorpSingleFactory).computeCyberCorpSingleAddress(corpSalt);
        address predictedRM = RoundManagerFactory(roundManagerFactory).computeRoundManagerAddress(corpSalt);

        bytes memory escrowedSig = _computeEscrowSignature(
            predictedRM,
            SecuritySeries.SeriesA,
            100000000000,
            1,
            10000000,
            RoundType.FCFS,
            block.timestamp - 1,
            block.timestamp + 21 days,
            bytes32(uint256(1)),
            stable,
            1000,
            1000000000000000,
            predictedCorp,
            deployerPrivateKey
        );

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Legal Details";
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";

        // Deploy another CyberCorp and create a public round using SAFE template id 1
        (
            address corp2,
            address corpAuth2,
            address issuance2,
            address dealManager2,
            address roundManager2,
            bytes32 roundId2
        ) = corpFactory.deployCyberCorpAndCreateRound(
                block.timestamp + 1,
                SecuritySeries.SeriesA,
                "SafeCorp",
                "Limited Liability Company",
                "DE",
                "contact@corp.example",
                "arbitration",
                deployer,
                officer,
                legalDetails,
                extensionData,
                certData,
                bytes32(uint256(1)),
                stable,
                1000,
                1000000000000000,
                safePartyValues,
                escrowedSig,
                RoundType.FCFS,
                new address[](0),
                100000000000,
                1,
                10000000,
                block.timestamp - 1,
                block.timestamp + 21 days,
                true
            );

 

        // Lock down AUTH if desired (mirror deploy.s.sol behavior lightly)
        // auth.updateRole(address(multisig), 200);
        // auth.zeroOwner();

        // Logs
        console.log("AUTH:", address(auth));
        console.log("Registry:", address(registry));
        console.log("URI Builder:", address(uriBuilder));
        console.log("IssuanceManagerFactory:", address(issuanceManagerFactory));
        console.log("CyberCorpSingleFactory:", address(cyberCorpSingleFactory));
        console.log("DealManagerFactory:", address(dealManagerFactory));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
        console.log("CyberCertPrinterImpl:", address(cyberCertPrinterImpl));
        console.log("CyberScripImpl:", address(cyberScripImpl));
        console.log("CyberCorpFactory:", address(corpFactory));
        console.log("Stable:", stable);

        console.log("CyberCorp2:", corp2);
        console.log("Corp2 AUTH:", corpAuth2);
        console.log("IssuanceManager2:", issuance2);
        console.log("DealManager2:", dealManager2);
        console.log("RoundManager2:", roundManager2);
        console.logBytes32(roundId2);

        // End deployer broadcast and submit an EOI with a different key to SAFE round
        vm.stopBroadcast();

        uint256 testPrivateKey = vm.envUint("TEST_KEY");
        vm.startBroadcast(testPrivateKey);
        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 1,
            maxAmount: 1,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: LexChexDetails({
                request: MintRequest({
                    uuid: 0,
                    owner: address(0),
                    investorName: "",
                    investorType: "",
                    investorJurisdiction: "",
                    investorContact: "",
                    mintPrice: 0,
                    expiry: 0,
                    paymentToken: address(0)
                }),
                templateId: bytes32(0),
                salt: 0,
                globalValues: new string[](0),
                parties: new address[](0),
                partyValues: new string[][](0),
                agreementSignature: ""
            })
        });

        bytes memory signature = _computeEOISignature(
            vm,
            CyberAgreementRegistry(registry),
            bytes32(uint256(1)),
            block.timestamp,
            safeGlobalValues,
            safePartyValues,
            deployer,
            testPrivateKey
        );

        ERC20(payable(stable)).approve(address(roundManager2), type(uint256).max);
        RoundManager(roundManager2).submitEOI(
            roundId2,
            eoi,
            safeGlobalValues,
            safePartyValues,
            signature,
            block.timestamp,
            new address[](0),
            bytes32(0)
        );

        vm.stopBroadcast();
    }

    function _computeEOISignature(
        Vm vm,
        CyberAgreementRegistry registry,
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        string[] memory partyValues,
        address authorityOfficer,
        uint256 signerPrivKey
    ) internal view returns (bytes memory) {
        (
            string memory legalUri,
            ,
            string[] memory glFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(
            abi.encode(templateId, salt, globalValues, parties)
        );
        return
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                contractId,
                legalUri,
                glFields,
                partyFields,
                globalValues,
                partyValues,
                signerPrivKey
            );
    }

    function _computeEscrowSignature(
        address roundManager,
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        address companyAddress,
        uint256 signerPrivKey
    ) internal view returns (bytes memory sig) {
        bytes32 roundId = keccak256(
            abi.encodePacked(
                seriesType,
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("RoundManager")),
                keccak256(bytes("1")),
                block.chainid,
                roundManager
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                ESCROWEDSIGNATUREDATA_TYPEHASH,
                roundId,
                uint8(seriesType),
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
    }
}

