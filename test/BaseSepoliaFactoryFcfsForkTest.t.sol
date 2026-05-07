// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {KnownAddressesLoaded} from "./libs/KnownAddressesLoaded.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {
    CompanyOfficer,
    SecurityClass,
    SecuritySeries
} from "../src/CyberCorpConstants.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {Round, RoundType} from "../src/libs/RoundLib.sol";
import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";

contract BaseSepoliaFactoryFcfsForkTest is Test, KnownAddressesLoaded {
    uint256 internal constant FOUNDER_PK = 0xA11CE;
    uint256 internal constant OFFICER_PK = 0xB0B;
    uint256 internal constant INVESTOR_PK = 0xC0DE;

    uint256 internal constant RAISE_CAP = 1_000_000e6;
    uint256 internal constant TICKET = 25_000e6;
    uint256 internal constant PRICE_PER_UNIT = 10e18;
    uint256 internal constant VALUATION = 20_000_000e18;

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal cyberCorpFactory;
    CyberCorpSingleFactory internal cyberCorpSingleFactory;
    RoundManagerFactory internal roundManagerFactory;
    ERC20 internal stable;

    address internal founder;
    address internal officer;
    address internal investor;

    function setUp() public {
        //assertEq(block.chainid, BASE_SEPOLIA_CHAIN_ID, "Fork test: Base Sepolia only");
        //vm.rollFork(BASE_SEPOLIA_FORK_BLOCK); // TODO: Uncomment this when the fork is ready      

        registry = CyberAgreementRegistry(CYBER_AGREEMENT_REGISTRY);
        cyberCorpFactory = CyberCorpFactory(CYBERCORP_FACTORY);
        cyberCorpSingleFactory = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory());
        roundManagerFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());
        stable = ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

        founder = vm.addr(FOUNDER_PK);
        officer = vm.addr(OFFICER_PK);
        investor = vm.addr(INVESTOR_PK);
    }

    function test_BaseSepoliaFactory_CreatesFcfsRound_AndInvestorFundsIt() public {
        bytes32 templateId = bytes32(uint256(5535));
        _createTemplate(templateId);

        uint256 salt = uint256(keccak256("BaseSepoliaFactoryFcfsForkTest.corp"));
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        address predictedCorp = cyberCorpSingleFactory.computeCyberCorpSingleAddress(corpSalt);
        address predictedRoundManager = roundManagerFactory.computeRoundManagerAddress(corpSalt);

        CompanyOfficer memory companyOfficer = CompanyOfficer({
            eoa: officer,
            name: "Fork Officer",
            contact: "officer@cybercorp.test",
            title: "CEO"
        });

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Base Sepolia FCFS SAFE";

        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SEED SAFE",
            symbol: "SEEDSAFE",
            uri: "ipfs://base-sepolia-fcfs-safe",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = companyOfficer.name;
        roundPartyValues[1] = companyOfficer.title;

        uint256 startTime = block.timestamp - 1;
        uint256 endTime = block.timestamp + 30 days;

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            predictedRoundManager,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            TICKET,
            TICKET,
            RoundType.FCFS,
            startTime,
            endTime,
            templateId,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            OFFICER_PK,
            predictedCorp
        );

        (
            address corp,
            ,
            ,
            ,
            address roundManagerAddr,
            bytes32 roundId
        ) = cyberCorpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Base Sepolia FCFS Corp",
            "Delaware C-Corp",
            "DE",
            "founder@cybercorp.test",
            "Arbitration",
            founder,
            companyOfficer,
            legalDetails,
            extensionData,
            certData,
            templateId,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            roundPartyValues,
            escrowedSig,
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            true,
            false
        );

        assertEq(corp, predictedCorp, "unexpected corp address");
        assertEq(roundManagerAddr, predictedRoundManager, "unexpected round manager address");

        RoundManager roundManager = RoundManager(roundManagerAddr);
        Round memory createdRound = roundManager.getRound(roundId);
        assertEq(createdRound.paymentToken, address(stable), "wrong payment token");
        assertEq(uint256(createdRound.roundType), uint256(RoundType.FCFS), "wrong round type");
        assertEq(createdRound.raiseCap, RAISE_CAP, "wrong raise cap");
        assertEq(createdRound.raised, 0, "new round should start empty");

        deal(address(stable), investor, TICKET * 4);

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Base Sepolia";

        string[] memory eoiPartyValues = new string[](2);
        eoiPartyValues[0] = "Fork Investor";
        eoiPartyValues[1] = "Individual";

        uint256 eoiSalt = 777;
        bytes memory eoiSignature = CyberCorpHelper.computeEOISignature(
            registry,
            templateId,
            eoiSalt,
            globalValues,
            eoiPartyValues,
            companyOfficer.eoa,
            INVESTOR_PK
        );

        EOI memory eoi = EOI({
            name: "Fork Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@cybercorp.test",
            minAmount: TICKET,
            maxAmount: TICKET,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        uint256 investorBalanceBefore = stable.balanceOf(investor);

        vm.startPrank(investor);
        stable.approve(roundManagerAddr, TICKET);
        (bytes32 agreementId, ) = roundManager.submitEOI(
            roundId,
            eoi,
            globalValues,
            eoiPartyValues,
            eoiSignature,
            eoiSalt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Round memory fundedRound = roundManager.getRound(roundId);
        Escrow memory escrow = roundManager.getEscrowDetails(agreementId);

        assertEq(fundedRound.raised, TICKET, "fcfs submission should raise funds immediately");
        assertEq(investorBalanceBefore - stable.balanceOf(investor), TICKET, "investor should spend the ticket");
        assertEq(uint256(escrow.status), uint256(EscrowStatus.FINALIZED), "escrow should finalize");
        assertGt(escrow.corpAssets.length, 0, "allocation should mint corp-side assets");
    }

    function _createTemplate(bytes32 templateId) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Jurisdiction";

        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";

        vm.prank(METALEX_SAFE);
        registry.createTemplate(
            templateId,
            "Base Sepolia FCFS Template",
            "ipfs://base-sepolia-fcfs-template",
            globalFields,
            partyFields
        );
    }
}
