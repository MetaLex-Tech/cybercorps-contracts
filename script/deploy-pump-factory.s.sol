// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Test.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {CompanyOfficer, SecuritySeries, SecurityClass} from "../src/CyberCorpConstants.sol";
import {RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";

contract DeployPumpCorpFactoryScript is Script {
    // EIP-712 constants for RoundManager escrow signature
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    function run() public returns (PumpCorpFactory pumpCorpFactory) {
        return
            runWithArgs(
                vm.envUint("PRIVATE_KEY_MAIN"), // deployerPrivateKey
                vm.envUint("FOUNDER_KEY_MAIN"), // founderPrivateKey
                vm.envUint("INVESTOR_KEY_MAIN"), // investorPrivateKey

                // TODO WIP: update for production
                0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf, // test corp payable
                0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf // test officer EOA
            );
    }

    function runWithArgs(
        uint256 deployerPrivateKey,
        uint256 founderPrivateKey,
        uint256 investorPrivateKey,
        address corpPayable,
        address officerAddress
    ) public returns (PumpCorpFactory pumpCorpFactory) {
        address deployerAddress = vm.addr(deployerPrivateKey);
        address investorAddress = vm.addr(investorPrivateKey);
        
        string memory saltStr = "PumpCorpFactory.deploy.v1";
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        // TODO WIP: update for production
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(DeploymentConstants.ETH_SEPOLIA);

        console2.log("==== Configs ====");
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("founder: %s", vm.addr(founderPrivateKey));
        console2.log("investor: %s", investorAddress);
        console2.log("corpPayable: %s", corpPayable);
        console2.log("officerAddress: %s", officerAddress);
        console2.log(
            "CyberAgreementRegistry:",
            deployment.cyberAgreementRegistry
        );
        console2.log("IssuanceManagerFactory:", deployment.issuanceManagerFactory);
        console2.log("CyberCorpSingleFactory:", deployment.cyberCorpSingleFactory);
        console2.log("DealManagerFactory:", deployment.dealManagerFactory);
        console2.log("RoundManagerFactory:", deployment.roundManagerFactory);
        console2.log("CertificateUriBuilder:", deployment.uriBuilder);
        console2.log("");

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        vm.startBroadcast(deployerPrivateKey);

        // (1) Deploy factory contracts

        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        pumpCorpFactory = PumpCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new PumpCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        PumpCorpFactory.initialize.selector,
                        address(auth),
                        deployment.cyberAgreementRegistry,
                        deployment.issuanceManagerFactory,
                        deployment.cyberCorpSingleFactory,
                        deployment.dealManagerFactory,
                        deployment.roundManagerFactory,
                        deployment.uriBuilder
                    )
                )
            )
        );

        // (2) Deploy test meme token
        MockERC20 memeToken = new MockERC20("Test Token", "TEST", 9);
        memeToken.mint(investorAddress, 10000e9);

        console2.log("==== Deployed ====");
        console2.log("Test MEME token:", address(memeToken));
        console2.log("Auth:", address(auth));
        console2.log("PumpCorpFactory (proxy):", address(pumpCorpFactory));
        console2.log("");

        // TODO WIP: remove before production
        // (3) Create corp and round

        uint256 corpSaltUint = block.timestamp + 1;
        bytes32 corpSalt = keccak256(abi.encodePacked(corpSaltUint));
        string memory companyName = "Test SubCo SPV 1";
        string memory companyType = "series limited liability company";
        string memory companyJurisdiction = "Delaware";
        string memory companyContact = "subco@parentco.example";
        string memory disputeResolution = "binding arbitration";

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: officerAddress,
            name: "Test Founder",
            contact: "test@company.com",
            title: "Founder"
        });

        string[] memory roundLegalDetails = new string[](1);
        roundLegalDetails[0] = "Legal Details";

        bytes[] memory roundExtensionData = new bytes[](1);
        roundExtensionData[0] = "";

        CyberCertData[] memory roundCertData = new CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        roundCertData[0] = CyberCertData({
            name: "CyberCorp",
            symbol: "CC",
            uri: "ipfs://certificate",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundFirstPartyValues = new string[](5);
        roundFirstPartyValues[0] = officer.name; // name
        roundFirstPartyValues[1] = vm.toString(officer.eoa); // evmAddress (string form)
        roundFirstPartyValues[2] = "email@founder.net"; // contactDetails
        roundFirstPartyValues[3] = "Individual"; // investorType
        roundFirstPartyValues[4] = "US"; // investorJurisdiction

        // Predict corp and round manager addresses to build a valid escrow signature
        address predictedCorp = CyberCorpSingleFactory(deployment.cyberCorpSingleFactory).computeCyberCorpSingleAddress(corpSalt);
        address predictedRM = RoundManagerFactory(deployment.roundManagerFactory).computeRoundManagerAddress(corpSalt);

        // Define shared round parameters
        SecuritySeries roundSeriesType = SecuritySeries.SeriesA;
        uint256 roundRaiseCap = 100000000000;
        uint256 roundMinTicket = 1;
        uint256 roundMaxTicket = 10000000;
        RoundType roundType = RoundType.FCFS;
        uint256 roundStartTime = block.timestamp - 1;
        uint256 roundEndTime = type(uint256).max; // no round expiry
        bytes32 roundTemplateId = bytes32(uint256(1)); // SAFE
        address roundPaymentToken = address(memeToken);
        uint256 roundPricePerUnit = 1000;
        uint256 roundValuation = 1000000000000000;

        // TODO test: print SAFE template details
//        {
//            (
//                string memory legalContractUri,
//                string memory title,
//                string[] memory globalFields,
//                string[] memory partyFields
//            ) = registry.getTemplateDetails(roundTemplateId);
//            console2.log("legalContractUri: %s", legalContractUri);
//            console2.log("title: %s", title);
//            for (uint256 i = 0; i < globalFields.length; i++) {
//                console2.log("globalFields[%d]: %s", i, globalFields[i]);
//            }
//            for (uint256 i = 0; i < partyFields.length; i++) {
//                console2.log("partyFields[%d]: %s", i, partyFields[i]);
//            }
//        }

        bytes memory escrowedSig = _computeEscrowSignature(
            predictedRM,
            roundSeriesType,
            roundRaiseCap,
            roundMinTicket,
            roundMaxTicket,
            roundType,
            roundStartTime,
            roundEndTime,
            roundTemplateId,
            roundPaymentToken,
            roundPricePerUnit,
            roundValuation,
            predictedCorp,
            founderPrivateKey
        );

        // Deploy another CyberCorp and create a public round using SAFE template id 1
        (
            address corp,
            address corpAuth,
            address issuance,
            address dealManager,
            address roundManager,
            bytes32 roundId
        ) = pumpCorpFactory.deployCyberCorpAndCreateRound(
            corpSaltUint, // salt
            roundSeriesType, // seriesType
            companyName,
            companyType,
            companyJurisdiction,
            companyContact,
            disputeResolution,
            corpPayable, // _companyPayable
            officer, // _officer
            roundLegalDetails, // legalDetails
            roundExtensionData, // extensionData
            roundCertData, // certData
            roundTemplateId, // roundTemplateId
            roundPaymentToken, // paymentToken
            roundPricePerUnit, // pricePerUnit
            roundValuation, // valuation
            roundFirstPartyValues, // roundPartyValues
            escrowedSig, // escrowedSignature
            roundType, // roundType
            new address[](0), // conditions
            roundRaiseCap, // raiseCap
            roundMinTicket, // minTicket
            roundMaxTicket, // maxTicket
            roundStartTime, // startTime
            roundEndTime, // endTime
            true, // publicRound
            true // allowTimedOffers
        );

        auth.updateRole(officerAddress, auth.OWNER_ROLE());
        auth.updateRole(corpPayable, auth.OWNER_ROLE());

        vm.stopBroadcast();

        console2.log("==== Corp & Round Created ====");
        console2.log("corp:", corp);
        console2.log("roundManager:", roundManager);
        console2.log("roundId:");
        console2.logBytes32(roundId);
        console2.log("");

        // (4) Submit EOI

        string memory investorName = "Investor 1";
        string memory investorContact = "email@investor.net";
        string memory investorType = "Individual";
        string memory investorJurisdiction = "US";
        
        string[] memory roundGlobalValues = new string[](5);
        roundGlobalValues[0] = "1.00"; // purchaseAmount
        roundGlobalValues[1] = "10000000"; // postMoneyValuationCap
        roundGlobalValues[2] = "1700000000"; // expirationTime (ts)
        roundGlobalValues[3] = "DE"; // governingJurisdiction
        roundGlobalValues[4] = "arbitration"; // disputeResolution
        
        string[] memory investorPartyValues = new string[](5);
        roundFirstPartyValues[0] = investorName; // name
        roundFirstPartyValues[1] = vm.toString(investorAddress); // evmAddress (string form)
        roundFirstPartyValues[2] = investorContact; // contactDetails
        roundFirstPartyValues[3] = investorType; // investorType
        roundFirstPartyValues[4] = investorJurisdiction; // investorJurisdiction

        vm.startBroadcast(investorPrivateKey);
        
        EOI memory eoi = EOI({
            name: investorName,
            investorType: investorType,
            jurisdiction: investorJurisdiction,
            contact: investorContact,
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

        memeToken.approve(roundManager, type(uint256).max);
        (bytes32 agreementId, uint256 tokenId) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            roundGlobalValues,
            investorPartyValues,
            _computeEOISignature(
                vm,
                CyberAgreementRegistry(registry),
                roundTemplateId,
                block.timestamp,
                roundGlobalValues,
                investorPartyValues,
                officerAddress,
                investorPrivateKey
            ),
            block.timestamp,
            new address[](0),
            bytes32(0)
        );

        vm.stopBroadcast();

        console2.log("==== EOI Submitted ====");
        console2.log("tokenId:", tokenId);
        console2.log("agreementId:");
        console2.logBytes32(agreementId);
        console2.log("");
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
        return CyberAgreementUtils.signAgreementTypedData(
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
}
