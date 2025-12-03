// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {CyberCorpHelper} from "../test/RoundManagerTest.t.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {UpgradePublicRoundsScript} from "../script/upgrade-public-rounds.s.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";

contract UpgradePublicRoundsTest is Test {
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Assume Base-sepolia
    address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
    address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
    address cyberCorpSingleFactory;
    address rmFactory;
    address lexchex = 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
    address deployer = vm.addr(deployerPrivateKey);

    // Randomly generated to avoid contaminated common test addresses
    uint256 privateKeySalt = 0xe6fc9058b04996425a6f0e6479e6e06f7177a6c61043b10857eb0a72339853e0;

    uint256 companyOwnerPrivateKey = 0xc00 + privateKeySalt;
    address companyOwner = vm.addr(companyOwnerPrivateKey);
    uint256 alicePrivateKey = 0xa11ce + privateKeySalt;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b + privateKeySalt;
    address bob = vm.addr(bobPrivateKey);

    bytes32 templateId = bytes32(uint256(20000));
    
    function setUp() public {
        // For future-proof: some networks may have upgraded already. In such case we will roll back to a known block before the upgrades
        if (block.chainid == 84532) {
            console2.log("Existing deployment has been upgraded, rolling back to a known block before it...");
            vm.rollFork(33920951);
        }

        vm.label(deployer, "deployer");
        vm.label(companyOwner, "companyOwner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        CyberAgreementRegistry(registry).AUTH().updateRole(
            deployer,
            CyberAgreementRegistry(registry).AUTH().OWNER_ROLE()
        );
        vm.stopPrank();

        (new UpgradePublicRoundsScript()).run();

        cyberCorpSingleFactory = CyberCorpFactory(cyberCorpFactoryProxyAddr).cyberCorpSingleFactory();
        rmFactory = CyberCorpFactory(cyberCorpFactoryProxyAddr).roundManagerFactory();
    }

    function test_SanityCheck() public {
        // entire ecosystem (except the legacy deal managers and CyberCertPrinters, which we will upgrade them separately) should be in v3 by now

        assertNotEq(CyberCorpFactory(cyberCorpFactoryProxyAddr).__cyberCertPrinterImplementation(), address(0), "the field cyberCertPrinterImplementation should have been deprecated");
        assertNotEq(CyberCorpSingleFactory(cyberCorpSingleFactory).getRefImplementation(), address(0), "CyberCorpSingleFactory should have reference implementation");
        assertNotEq(DealManagerFactory(CyberCorpFactory(cyberCorpFactoryProxyAddr).dealManagerFactory()).getRefImplementation(), address(0), "DealManagerFactory should have reference implementation");
        assertNotEq(RoundManagerFactory(CyberCorpFactory(cyberCorpFactoryProxyAddr).roundManagerFactory()).getRefImplementation(), address(0), "RoundManagerFactory should have reference implementation");

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(CyberCorpFactory(cyberCorpFactoryProxyAddr).issuanceManagerFactory());
        assertNotEq(imFactory.getRefImplementation(), address(0), "IssuanceManagerFactory should have reference implementation");
        assertNotEq(imFactory.getCyberCertPrinterRefImplementation(), address(0), "IssuanceManagerFactory should have reference implementation for CyberCertPrinter");
        assertNotEq(imFactory.getCyberScripRefImplementation(), address(0), "IssuanceManagerFactory should have reference implementation for CyberScrip");

        // Legacy ecosystem should be partially upgraded

        address legacyCyberCorpSingleFactoryAddr = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        address legacyIssuanceManagerFactoryAddr = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;

        assertEq(ILegacyFactory(legacyCyberCorpSingleFactoryAddr).getBeaconImplementation(), CyberCorpSingleFactory(cyberCorpSingleFactory).getRefImplementation(), "Legacy CyberCorpSingleFactory beacon should upgrade to the same implementation");
        assertEq(ILegacyFactory(legacyIssuanceManagerFactoryAddr).getBeaconImplementation(), imFactory.getRefImplementation(), "Legacy IssuanceManagerFactory beacon should upgrade to the same implementation");
    }
    
    function test_CreateCyberCorpAndRounds() public {
        vm.startPrank(metalexSafe);
        
        // Add SAFE template (id 1) using SAFE fields from template.s.sol
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
            templateId,
            "SAFE",
            "https://ipfs.io/ipfs/bafybeih5wvr7zfw76plnb66teaa66rtgoikhhcqh55oecuoxtuw5c3dooi",
            globalFieldsSafe,
            partyFieldsSafe
        );
        
        vm.stopPrank();

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: companyOwner,
            name: "CEO",
            contact: "ceo@cybercorp.com",
            title: "1234567890"
        });

        CyberCertData[] memory certData = new CyberCertData[](1);

        certData[0] = CyberCertData({
            name: "CyberCorp",
            symbol: "CC",
            uri: "ipfs://bafkreigz4o4kqxmkcln2742v47hms7eacd7v3c43lvr7k7i5h6e7nfl77i",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: new string[](0)
        });

        string[] memory roundPartyValues = new string[](5);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";
        roundPartyValues[2] = "Alice Officer";
        roundPartyValues[3] = "CEO";
        roundPartyValues[4] = "Alice Officer";

        uint256 raiseCap = 100000000000;
        uint256 minTicket = 1;
        uint256 maxTicket = 10000000;
        uint256 pricePerUnit = 1000;
        uint256 valuation = 1000000000000000;

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Legal Details";
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";

        address rm;
        address rm2;
        bytes32 roundId;
        bytes32 roundId2;
        
        vm.startPrank(companyOwner);

        {
            uint256 salt = block.timestamp;
            bytes32 corpSalt = keccak256(abi.encodePacked(salt));

            (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
                RoundManagerFactory(rmFactory).computeRoundManagerAddress(corpSalt),
                SecuritySeries.SeriesA,
                raiseCap,
                minTicket,
                maxTicket,
                RoundType.FCFS,
                block.timestamp - 1,
                block.timestamp + 14 days,
                templateId,
                address(usdc),
                pricePerUnit,
                valuation,
                companyOwnerPrivateKey,
                CyberCorpSingleFactory(cyberCorpSingleFactory).computeCyberCorpSingleAddress(corpSalt)
            );

            //test deploy a new CyberCorp and start a public round using the factory
            (
                ,
                ,
                ,
                ,
                rm,
                roundId
            ) = CyberCorpFactory(cyberCorpFactoryProxyAddr)
                .deployCyberCorpAndCreateRound(
                salt,
                SecuritySeries.SeriesA,
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                address(companyOwner),
                officer,
                legalDetails,
                extensionData,
                certData,
                templateId,
                address(usdc),
                pricePerUnit,
                valuation,
                roundPartyValues,
                escrowedSig,
                RoundType.FCFS,
                new address[](0),
                raiseCap,
                minTicket,
                maxTicket,
                block.timestamp - 1,
                block.timestamp + 14 days,
                true,
                true
            );
        }

        {
            uint256 salt = block.timestamp + 1;
            bytes32 corpSalt = keccak256(abi.encodePacked(salt));

            (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
                RoundManagerFactory(rmFactory).computeRoundManagerAddress(corpSalt),
                SecuritySeries.SeriesA,
                raiseCap,
                minTicket,
                maxTicket,
                RoundType.FCFS,
                block.timestamp - 1,
                block.timestamp + 21 days,
                templateId,
                address(usdc),
                pricePerUnit,
                valuation,
                companyOwnerPrivateKey,
                CyberCorpSingleFactory(cyberCorpSingleFactory).computeCyberCorpSingleAddress(corpSalt)
            );

            // Example public round using SAFE template id 1
            (
                ,
                ,
                ,
                ,
                rm2,
                roundId2
            ) = CyberCorpFactory(cyberCorpFactoryProxyAddr)
                .deployCyberCorpAndCreateRound(
                salt,
                SecuritySeries.SeriesA,
                "SafeCorp",
                "Limited Liability Company",
                "Juris",
                "Contact",
                "Dispute",
                address(companyOwner),
                officer,
                legalDetails,
                extensionData,
                certData,
                templateId,
                address(usdc),
                pricePerUnit,
                valuation,
                roundPartyValues,
                escrowedSig,
                RoundType.FCFS,
                new address[](0),
                raiseCap,
                minTicket,
                maxTicket,
                block.timestamp - 1,
                block.timestamp + 21 days,
                true,
                true
            );
        }
        
        vm.stopPrank();

        // Prepare bob for submission
        deal(usdc, alice, 1);
        vm.prank(0x9182083D63F18CE4c2daA16E33c837C74f9a0Fe2);
        LeXcheX(lexchex).mint(alice, Accreditation({
            agreementId: bytes32(uint256(1)),
            registryAddress: address(0x5),
            investorName: "Test Entity",
            investorType: "LLC",
            investorJurisdiction: "Delaware",
            investorContact: "test@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: bytes("0x123..."),
            uuid: 1
        }));

        vm.startPrank(alice);
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

        address[] memory parties = new address[](2);
        parties[0] = companyOwner;
        parties[1] = alice;

        (
            string memory legalUri,
            ,
            string[] memory globalFields,
            string[] memory partyFields
        ) = CyberAgreementRegistry(registry).getTemplateDetails(
            templateId
        );

        bytes32 contractId = keccak256(
            abi.encode(
                templateId,
                block.timestamp,
                roundPartyValues,
                parties
            )
        );

        bytes memory signature = _computeEOISignature(
            CyberAgreementRegistry(registry),
            templateId,
            block.timestamp,
            roundPartyValues,
            roundPartyValues,
            companyOwner,
            alicePrivateKey
        );

        /*        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry,
        string memory name*/
        ERC20(payable(usdc)).approve(address(rm), type(uint256).max);
        RoundManager(rm).submitEOI(
            roundId,
            eoi,
            roundPartyValues,
            roundPartyValues,
            signature,
            block.timestamp,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Prepare bob for submission
        deal(usdc, bob, 1);
        vm.prank(0x9182083D63F18CE4c2daA16E33c837C74f9a0Fe2);
        LeXcheX(lexchex).mint(bob, Accreditation({
            agreementId: bytes32(uint256(1)),
            registryAddress: address(0x5),
            investorName: "Test Entity",
            investorType: "LLC",
            investorJurisdiction: "Delaware",
            investorContact: "test@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: bytes("0x123..."),
            uuid: 1
        }));

        // Submit EOI from another address for SAFE template round (roundId2)
        vm.startPrank(bob);
        EOI memory eoi2 = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email2",
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

        // Build signature for template id 1
        bytes memory signature2 = _computeEOISignature(
            CyberAgreementRegistry(registry),
            templateId,
            block.timestamp,
            roundPartyValues,
            roundPartyValues,
            companyOwner,
            bobPrivateKey
        );

        ERC20(payable(usdc)).approve(address(rm2), type(uint256).max);
        RoundManager(rm2).submitEOI(
            roundId2,
            eoi2,
            roundPartyValues,
            roundPartyValues,
            signature2,
            block.timestamp,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function _computeEOISignature(
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
}