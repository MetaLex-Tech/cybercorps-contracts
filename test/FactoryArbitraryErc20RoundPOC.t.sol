// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {
    CompanyOfficer,
    SecurityClass,
    SecuritySeries
} from "../src/CyberCorpConstants.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {EOI} from "../src/storage/RoundManagerStorage.sol";
import {Round} from "../src/libs/RoundLib.sol";

contract FactoryArbitraryErc20RoundPOCTest is Test {
    uint256 internal ownerPk = 0xA11CE;
    uint256 internal officerPk = 0xB0B;
    uint256 internal investorPk = 0xC0DE;

    address internal owner = vm.addr(ownerPk);
    address internal officer = vm.addr(officerPk);
    address internal investor = vm.addr(investorPk);

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    address internal cyberCorpSingleFactory;
    address internal rmFactory;
    MockERC20 internal paymentToken;

    uint8 internal constant PAYMENT_DECIMALS = 18;
    uint256 internal constant TOKEN_SCALE = 10 ** PAYMENT_DECIMALS;
    uint256 internal constant VALUATION = 20_000_000 * TOKEN_SCALE; // 20M in mock ERC-20 units

    function setUp() public {
        address uriBuilder;
        (
            registry,
            corpFactory,
            ,
            cyberCorpSingleFactory,
            ,
            rmFactory,
            uriBuilder,
        ) = CyberCorpHelper.deployRegistryAndFactories(owner);

        vm.prank(owner);
        CyberCorpHelper.createTemplate(registry);

        // FCFS allocation mints certs and resolves tokenURI, which requires a configured image builder.
        address imageBuilder = address(new CertificateImageBuilderContract());
        vm.prank(owner);
        CertificateUriBuilder(uriBuilder).setImageBuilder(imageBuilder);

        paymentToken = new MockERC20("Mock USD", "mUSD", PAYMENT_DECIMALS);
        paymentToken.mint(investor, 2_000_000 * TOKEN_SCALE);
    }

    function test_POC_ArbitraryErc20DrivesRoundDenominationAndRatio() public {
        uint256 salt = 424242;
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        address predictedCorp = CyberCorpSingleFactory(cyberCorpSingleFactory)
            .computeCyberCorpSingleAddress(corpSalt);
        address predictedRM = RoundManagerFactory(rmFactory)
            .computeRoundManagerAddress(corpSalt);

        CompanyOfficer memory companyOfficer = CompanyOfficer({
            eoa: officer,
            name: "Officer A",
            contact: "officer@corp.com",
            title: "CEO"
        });

        uint256 raiseCap = 1_000_000 * TOKEN_SCALE; // 5% of valuation
        uint256 ticket = 1_000_000 * TOKEN_SCALE;
        uint256 pricePerUnit = 1 * TOKEN_SCALE; // 1 "unit" priced in mock ERC-20
        uint256 startTime = block.timestamp - 1;
        uint256 endTime = block.timestamp + 30 days;

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "SEED SAFE legal details";
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "SEED SAFE";
        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SEED SAFE",
            symbol: "SEEDSAFE",
            uri: "ipfs://seed-safe",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = companyOfficer.name;
        roundPartyValues[1] = companyOfficer.title;

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            predictedRM,
            SecuritySeries.SeriesSeed,
            raiseCap,
            ticket,
            ticket,
            RoundType.FCFS,
            startTime,
            endTime,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            pricePerUnit,
            VALUATION,
            officerPk,
            predictedCorp
        );

        (
            address corp,
            ,
            ,
            ,
            address roundManagerAddr,
            bytes32 roundId
        ) = corpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Seed Corp",
            "C-Corp",
            "DE",
            "contact@seedcorp.com",
            "Arbitration",
            owner,
            companyOfficer,
            legalDetails,
            extensionData,
            certData,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            pricePerUnit,
            VALUATION,
            roundPartyValues,
            escrowedSig,
            RoundType.FCFS,
            new address[](0),
            raiseCap,
            ticket,
            ticket,
            startTime,
            endTime,
            true,
            true,
            false
        );

        assertEq(corp, predictedCorp, "unexpected corp address");
        assertEq(roundManagerAddr, predictedRM, "unexpected round manager address");

        Round memory createdRound = RoundManager(roundManagerAddr).getRound(roundId);
        assertEq(createdRound.paymentToken, address(paymentToken), "round payment token must be mock erc20");
        assertEq(createdRound.raiseCap, raiseCap, "raise cap should be token-denominated");
        assertEq(createdRound.minTicket, ticket, "min ticket should be token-denominated");
        assertEq(createdRound.maxTicket, ticket, "max ticket should be token-denominated");
        assertEq(createdRound.pricePerUnit, pricePerUnit, "price per unit should be token-denominated");
        assertEq(createdRound.valuation, VALUATION, "valuation should be token-denominated");
        assertEq(uint256(createdRound.seriesType), uint256(SecuritySeries.SeriesSeed), "series should be seed");
        assertEq(
            uint256(createdRound.primarySecurityClass),
            uint256(SecurityClass.SAFE),
            "primary security should be SAFE"
        );
        assertEq(
            uint256(createdRound.primarySecuritySeries),
            uint256(SecuritySeries.SeriesSeed),
            "primary security series should be seed"
        );

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Investor";
        partyValues[1] = "Individual";
        uint256 eoiSalt = 777;

        bytes memory eoiSignature = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            eoiSalt,
            globalValues,
            partyValues,
            companyOfficer.eoa,
            investorPk,
            roundManagerAddr,
            block.timestamp + 7 days,
            bytes32(0));

        EOI memory eoi = EOI({
            name: "Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@example.com",
            minAmount: ticket,
            maxAmount: ticket,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        uint256 investorBalanceBefore = paymentToken.balanceOf(investor);
        vm.startPrank(investor);
        paymentToken.approve(roundManagerAddr, ticket);
        RoundManager(roundManagerAddr).submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            eoiSignature,
            eoiSalt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Round memory roundAfterPayment = RoundManager(roundManagerAddr).getRound(roundId);
        uint256 investorSpent = investorBalanceBefore - paymentToken.balanceOf(investor);

        assertEq(roundAfterPayment.raised, ticket, "raised should track payment token amount");
        assertEq(investorSpent, ticket, "investor payment should be in mock erc20 units");

        // 1,000,000 / 20,000,000 = 5% == 0.05e18
        uint256 expectedRatio1e18 = 50_000_000_000_000_000;
        uint256 paidToValuationRatio1e18 = (roundAfterPayment.raised * 1e18) / VALUATION;
        assertEq(
            paidToValuationRatio1e18,
            expectedRatio1e18,
            "payment-to-valuation ratio should remain consistent in token units"
        );
    }
}
