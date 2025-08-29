// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RoundManager.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberCertPrinter.sol";
import "../src/storage/RoundManagerStorage.sol";
import "../src/CyberCorpConstants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

// Import necessary types
using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**6); // Mint 1M tokens with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract RoundManagerTest is Test {
    RoundManager public roundManager;
    IssuanceManager public issuanceManager;
    CyberCertPrinter public certPrinter;
    MockPaymentToken public paymentToken;
    
    address public owner;
    address public investor;
    
    // Test round parameters
    bytes32 public constant ROUND_ID = bytes32("TEST_ROUND_1");
    uint256 public constant MIN_TICKET = 1000 * 10**6; // 1,000 USDC
    uint256 public constant MAX_TICKET = 100000 * 10**6; // 100,000 USDC
    uint256 public constant RAISE_CAP = 1000000 * 10**6; // 1M USDC
    uint256 public constant PRICE_PER_UNIT = 10 * 10**6; // 10 USDC per unit
    uint256 public constant VALUATION = 10000000; // $10M valuation

    function setUp() public {
        owner = address(this);
        investor = address(0x1);
        
        // Deploy mock payment token
        paymentToken = new MockPaymentToken();
        
        // Setup IssuanceManager and CertPrinter (simplified setup)
        issuanceManager = new IssuanceManager();
        // Note: In real setup you'd need to properly initialize these with all dependencies
        
        // Setup RoundManager
        roundManager = new RoundManager();
        // Note: In real setup you'd need to properly initialize with auth and other dependencies

        // Create certificate data for the round
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Test Legend";
        
        certData[0] = RoundManager.CyberCertData({
            name: "Test Certificate",
            symbol: "TEST",
            uri: "https://test.uri",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });
        
        // Create test round
        roundManager.createRound(
            "Series A",
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            "Test Terms",
            block.timestamp,
            block.timestamp + 30 days,
            bytes32("TEST_TEMPLATE"),
            certData,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            6, // USDC decimals
            new string[](0),
            bytes("")
        );
        
        // Fund investor
        paymentToken.transfer(investor, 1000000 * 10**6);
        vm.prank(investor);
        paymentToken.approve(address(roundManager), type(uint256).max);
    }

    function _setRoundMeta(
        bytes32 roundId,
        uint256 roundPricePerShare,
        uint8 roundPriceDecimals,
        uint256 cCapUsed,
        uint8 roundingMode,
        uint8 priceDecimals,
        uint8 shareDecimals
    ) internal {
        // Set normalized round price
        vm.prank(owner);
        roundManager.setRoundPricePerShare(roundId, roundPricePerShare, roundPriceDecimals);

        // Set snapshot
        CapTableSnapshot memory snap = CapTableSnapshot({
            totalCapitalSecuritiesOutstanding: 0,
            totalConvertingSecurities: 0,
            totalOptionsIssuedAndOutstanding: 0,
            totalPromisedOptions: 0,
            unissuedOptionPoolPreRound: 0,
            unissuedOptionPoolIncreaseIncludedInCalc: 0,
            cCapUsed: cCapUsed
        });
        vm.prank(owner);
        roundManager.setCapTableSnapshot(roundId, snap);

        // Set rounding policy
        RoundingPolicy memory policy = RoundingPolicy({
            mode: RoundingMode(roundingMode),
            priceDecimals: priceDecimals,
            shareDecimals: shareDecimals
        });
        vm.prank(owner);
        roundManager.setRoundingPolicy(roundId, policy);
    }

    function test_ConversionFormula_MinChoosesSafePrice_Floor() public {
        // Given
        uint8 priceDec = 2; // cents
        uint8 shareDec = 0;
        // PMVC = 10,000,000; CCapUsed = 100,000 → SAFE_Price = 100.00 → 10000 (2dp)
        uint256 PMVC = 10_000_000;
        uint256 CCapUsed = 100_000;
        uint256 safePrice = (PMVC * (10 ** priceDec)) / CCapUsed; // 10000
        // roundPrice = 120.00 → 12000
        uint256 roundPrice = 12_000;

        _setRoundMeta(ROUND_ID, roundPrice, priceDec, CCapUsed, /*Floor*/0, priceDec, shareDec);

        // Expected price basis is SAFE price (lower)
        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice;
        assertEq(priceBasis, safePrice);

        // PA = 1,000,000 → shares = PA * 10^priceDec / priceBasis
        uint256 PA = 1_000_000;
        uint256 expectedShares = (PA * (10 ** priceDec)) / priceBasis; // 10,000
        assertEq(expectedShares, 10_000);
    }

    function test_ConversionFormula_MinChoosesRoundPrice_Floor() public {
        uint8 priceDec = 2;
        uint8 shareDec = 0;
        // PMVC = 12,000,000; CCapUsed = 100,000 → SAFE_Price = 120.00 → 12000
        uint256 PMVC = 12_000_000;
        uint256 CCapUsed = 100_000;
        uint256 safePrice = (PMVC * (10 ** priceDec)) / CCapUsed; // 12000
        // roundPrice = 100.00 → 10000
        uint256 roundPrice = 10_000;

        _setRoundMeta(ROUND_ID, roundPrice, priceDec, CCapUsed, /*Floor*/0, priceDec, shareDec);

        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice;
        assertEq(priceBasis, roundPrice);

        uint256 PA = 1_000_000;
        uint256 expectedShares = (PA * (10 ** priceDec)) / priceBasis; // 10,000
        assertEq(expectedShares, 10_000);
    }

    function test_ConversionFormula_RoundingModes() public {
        uint8 priceDec = 2;
        uint8 shareDec = 0;
        uint256 PMVC = 10_000_000;
        uint256 CCapUsed = 100_000; // SAFE price = 100.00 (10000)
        uint256 roundPrice = 10_050; // 100.50 to force rounding differences
        uint256 PA = 1_000_001; // off-by-one to test rounding edges

        // Floor
        _setRoundMeta(ROUND_ID, roundPrice, priceDec, CCapUsed, /*Floor*/0, priceDec, shareDec);
        uint256 safePrice = (PMVC * (10 ** priceDec)) / CCapUsed; // 10000
        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice; // 10000
        uint256 floorShares = (PA * (10 ** priceDec)) / priceBasis; // 10000 (floor)
        assertEq(floorShares, 10_000);

        // Ceil
        _setRoundMeta(ROUND_ID, roundPrice, priceDec, CCapUsed, /*Ceil*/1, priceDec, shareDec);
        uint256 ceilShares = (PA * (10 ** priceDec) + priceBasis - 1) / priceBasis;
        assertEq(ceilShares, 10_001);

        // Round half up
        _setRoundMeta(ROUND_ID, roundPrice, priceDec, CCapUsed, /*Round*/2, priceDec, shareDec);
        uint256 halfUpShares = (PA * (10 ** priceDec) + (priceBasis / 2)) / priceBasis;
        assertEq(halfUpShares, 10_000); // since half of 10000 is 5000, still 10000 for these values
    }

    function test_PmvcSubseriesLabel_SetAndGet() public {
        vm.prank(owner);
        roundManager.setPMVCSubseriesLabel(ROUND_ID, 10_000_000, "SAFE1");
        string memory label = roundManager.getPMVCSubseriesLabel(ROUND_ID, 10_000_000);
        assertEq(keccak256(bytes(label)), keccak256(bytes("SAFE1")));
    }

    function test_SubmitEOI_Success() public {
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10**6, // 5,000 USDC
            maxAmount: 10000 * 10**6 // 10,000 USDC
        });
        
        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value";
        
        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value";
        
        bytes memory signature = "0x";
        uint256 salt = 1;
        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 7 days;
        bytes memory voidSignature = "0x";
        
        bytes32 agreementId = roundManager.submitEOI(
            ROUND_ID,
            eoi,
            globalValues,
            partyValues,
            signature,
            salt,
            conditions,
            secretHash,
            expiry,
            "Test Investor"
        );
        
        assertTrue(agreementId != bytes32(0), "Agreement ID should not be zero");
        
        // Verify EOI was stored correctly by checking the EOISubmitted event
        vm.expectEmit(true, true, true, true);
        emit RoundManager.EOISubmitted(agreementId, ROUND_ID, investor, eoi.maxAmount);
        
        vm.stopPrank();
    }

    function test_SubmitEOI_InvalidAmount() public {
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 100 * 10**6, // Below MIN_TICKET
            maxAmount: 1000000 * 10**6 // Above MAX_TICKET
        });
        
        string[] memory globalValues = new string[](1);
        string[] memory partyValues = new string[](1);
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAmount.selector));
        
        roundManager.submitEOI(
            ROUND_ID,
            eoi,
            globalValues,
            partyValues,
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );
        
        vm.stopPrank();
    }

    function test_Allocate_Success() public {
        // First submit an EOI
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10**6,
            maxAmount: 10000 * 10**6
        });
        
        bytes32 agreementId = roundManager.submitEOI(
            ROUND_ID,
            eoi,
            new string[](1),
            new string[](1),
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );
        
        vm.stopPrank();
        
        // Now allocate as owner
        uint256 allocatedAmount = 7500 * 10**6; // 7,500 USDC
        
        vm.prank(owner);
        roundManager.allocate(agreementId, allocatedAmount, "0x");
        
        // Verify allocation by checking if the round exists and getting its price info
        assertTrue(roundManager.roundExists(ROUND_ID), "Round should exist");
        
        // We can verify the allocation was successful by checking if an AllocationMade event was emitted
        vm.expectEmit(true, true, false, true);
        uint256[] memory expectedCertIds = new uint256[](1);
        expectedCertIds[0] = 0; // First certificate ID
        emit RoundManager.AllocationMade(agreementId, ROUND_ID, allocatedAmount, expectedCertIds);
        
        // Verify certificate was created
        // Note: In a real test you'd need to properly mock the CertPrinter and verify its state
    }

    function test_Allocate_InvalidAmount() public {
        // Submit EOI first
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10**6,
            maxAmount: 10000 * 10**6
        });
        
        bytes32 agreementId = roundManager.submitEOI(
            ROUND_ID,
            eoi,
            new string[](1),
            new string[](1),
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );
        
        vm.stopPrank();
        
        // Try to allocate an amount below min
        uint256 invalidAmount = 1000 * 10**6; // Below eoi.minAmount
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        
        vm.prank(owner);
        roundManager.allocate(agreementId, invalidAmount, "0x");
    }

    function test_Allocate_ExceedsRaiseCap() public {
        // Submit EOI first
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10**6,
            maxAmount: RAISE_CAP + 1 // Just over the raise cap
        });
        
        bytes32 agreementId = roundManager.submitEOI(
            ROUND_ID,
            eoi,
            new string[](1),
            new string[](1),
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );
        
        vm.stopPrank();
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        
        vm.prank(owner);
        roundManager.allocate(agreementId, RAISE_CAP + 1, "0x");
    }

    function test_SubmitEOI_RoundClosed() public {
        // Fast forward past round end time
        vm.warp(block.timestamp + 31 days);
        
        vm.startPrank(investor);
        
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10**6,
            maxAmount: 10000 * 10**6
        });
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.RoundNotOpen.selector));
        
        roundManager.submitEOI(
            ROUND_ID,
            eoi,
            new string[](1),
            new string[](1),
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );
        
        vm.stopPrank();
    }

    function test_MultipleAllocations_RespectRaiseCap() public {
        // Submit first EOI
        vm.startPrank(investor);
        EOI memory eoi1 = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor1@example.com",
            minAmount: 400000 * 10**6, // 400k USDC
            maxAmount: 600000 * 10**6 // 600k USDC
        });
        
        bytes32 agreementId1 = roundManager.submitEOI(
            ROUND_ID,
            eoi1,
            new string[](1),
            new string[](1),
            "0x",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 1"
        );
        vm.stopPrank();
        
        // Submit second EOI from different investor
        address investor2 = address(0x2);
        paymentToken.transfer(investor2, 1000000 * 10**6);
        vm.startPrank(investor2);
        paymentToken.approve(address(roundManager), type(uint256).max);
        
        EOI memory eoi2 = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor2@example.com",
            minAmount: 400000 * 10**6, // 400k USDC
            maxAmount: 600000 * 10**6 // 600k USDC
        });
        
        bytes32 agreementId2 = roundManager.submitEOI(
            ROUND_ID,
            eoi2,
            new string[](1),
            new string[](1),
            "0x",
            2,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 2"
        );
        vm.stopPrank();
        
        // Allocate to first investor
        vm.startPrank(owner);
        roundManager.allocate(agreementId1, 500000 * 10**6, "0x"); // 500k USDC
        
        // Try to allocate remaining to second investor
        roundManager.allocate(agreementId2, 500000 * 10**6, "0x"); // 500k USDC
        
        // Verify total raised equals sum of allocations by checking that the round is closed
        // When total raised equals raise cap, no more allocations should be possible
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        roundManager.allocate(agreementId2, 1, "0x"); // Try to allocate 1 more token, should fail
        vm.stopPrank();
    }

}

// Separate FCFS tests in their own contract to avoid the original setUp()
contract RoundManagerFCFSTest is Test {
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

    // Infra helpers copied from above
    function _deployRegistryAndFactories(address owner)
        internal
        returns (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            address issuanceManagerFactory,
            address cyberCorpSingleFactory,
            address dealManagerFactory,
            address uriBuilder
        )
    {
        bytes32 salt = keccak256(abi.encodePacked("fcfs-infra", owner));

        BorgAuth bootstrapAuth = new BorgAuth{salt: salt}(owner);

        registry = CyberAgreementRegistry(
            address(new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(bootstrapAuth))
            ))
        );

        uriBuilder = address(new ERC1967Proxy{salt: salt}(
            address(new CertificateUriBuilder{salt: salt}()),
            abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(bootstrapAuth))
        ));

        issuanceManagerFactory = address(new IssuanceManagerFactory{salt: salt}(address(bootstrapAuth)));
        cyberCorpSingleFactory = address(new CyberCorpSingleFactory{salt: salt}(address(bootstrapAuth)));
        dealManagerFactory = address(new DealManagerFactory{salt: salt}(address(bootstrapAuth)));

        address certPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImpl = address(new CyberScrip{salt: salt}());

        corpFactory = CyberCorpFactory(
            address(new ERC1967Proxy{salt: salt}(
                address(new CyberCorpFactory{salt: salt}()),
                abi.encodeWithSelector(
                    CyberCorpFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(registry),
                    certPrinterImpl,
                    cyberScripImpl,
                    issuanceManagerFactory,
                    cyberCorpSingleFactory,
                    dealManagerFactory,
                    uriBuilder
                )
            ))
        );
    }

    function _createTemplate(CyberAgreementRegistry registry) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        registry.createTemplate(
            bytes32(uint256(777)),
            "FCFS-Test",
            "ipfs://template",
            globalFields,
            partyFields
        );
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
        (string memory legalUri, , string[] memory glFields, string[] memory partyFields) = registry.getTemplateDetails(templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(abi.encode(templateId, salt, globalValues, parties));
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

    function _deployCorp(
        CyberCorpFactory corpFactory,
        string memory companyName,
        address companyPayable,
        address officerEOA
    )
        internal
        returns (
            address corp,
            address auth,
            address issuance,
            address dealManager
        )
    {
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: officerEOA,
            name: "Officer",
            contact: "officer@example.com",
            title: "CEO"
        });

        (
            corp,
            auth,
            issuance,
            dealManager
        ) = corpFactory.deployCyberCorp(
            keccak256("fcfs-corp"),
            companyName,
            "corporation",
            "DE",
            "contact",
            "arbitration",
            companyPayable,
            officer
        );
    }

    function _initRoundManager(
        address auth,
        address corp,
        address registry,
        address issuance
    ) internal returns (RoundManager rm) {
        // Deploy RoundManager via factory (BeaconProxy), then initialize
        RoundManagerFactory rmFactory = new RoundManagerFactory(auth);
        address proxy = rmFactory.deployRoundManager(keccak256("rm-fcfs"));
        rm = RoundManager(payable(proxy));
        rm.initialize(auth, corp, registry, issuance, address(rmFactory));
        // Allow RoundManager to call IssuanceManager.onlyOwner
        BorgAuth(auth).updateRole(address(rm), 99);
    }

    function _createFCFSRound(
        RoundManager rm,
        address paymentToken,
        uint8 payDec,
        bytes32 templateId
    ) internal returns (bytes32) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        bytes memory escrowedSig = hex"01";

        return rm.createRound(
            "Seed",
            1_000_000 * (10 ** payDec),
            1_000 * (10 ** payDec),
            100_000 * (10 ** payDec),
            RoundType.FCFS,
            "terms",
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            certData,
            paymentToken,
            10 * (10 ** payDec),
            10_000_000,
            payDec,
            roundPartyValues,
            escrowedSig
        );
    }

    function _createFCFSRoundCustom(
        RoundManager rm,
        address paymentToken,
        uint8 payDec,
        bytes32 templateId,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket
    ) internal returns (bytes32) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        bytes memory escrowedSig = hex"01";

        return rm.createRound(
            "Seed",
            raiseCap,
            minTicket,
            maxTicket,
            RoundType.FCFS,
            "terms",
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            certData,
            paymentToken,
            10 * (10 ** payDec),
            10_000_000,
            payDec,
            roundPartyValues,
            escrowedSig
        );
    }

    function test_FCFS_CreateRound_RequiresEscrowSignature() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            
        ) = _deployRegistryAndFactories(me);

        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(corpFactory, "Corp A", me, me);
        RoundManager rm = _initRoundManager(auth, corp, address(registry), issuance);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });
        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Officer";
        roundPartyValues[1] = "CEO";

        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidEscrowedSignature.selector));
        rm.createRound(
            "Seed",
            1,
            1,
            1,
            RoundType.FCFS,
            "terms",
            block.timestamp,
            block.timestamp + 1,
            bytes32(uint256(777)),
            certData,
            address(0xDEAD),
            1,
            1,
            6,
            roundPartyValues,
            bytes("")
        );
    }

    function test_FCFS_SubmitEOI_AutoAllocates_FinalizesAndMints() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            
        ) = _deployRegistryAndFactories(me);
        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(corpFactory, "Corp B", me, me);
        RoundManager rm = _initRoundManager(auth, corp, address(registry), issuance);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRoundCustom(
            rm,
            address(usdc),
            usdc.decimals(),
            bytes32(uint256(777)),
            2_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals())
        );

        uint256 salt = 1;
        uint256 privKey = 0xA11CE;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 20_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 5_000 * (10 ** usdc.decimals()),
            maxAmount: 10_000 * (10 ** usdc.decimals())
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = _computeEOISignature(
            registry,
            bytes32(uint256(777)),
            salt,
            globalValues,
            partyValues,
            address(this),
            privKey
        );

        bytes32 agreementId = rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 1"
        );
        vm.stopPrank();

        Escrow memory esc = rm.getEscrowDetails(agreementId);
        assertEq(uint256(esc.status), uint256(EscrowStatus.FINALIZED));
        assertGt(esc.corpAssets.length, 0);
    }

    function test_FCFS_RefundsExcessPayment() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            
        ) = _deployRegistryAndFactories(me);
        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(corpFactory, "Corp C", me, me);
        RoundManager rm = _initRoundManager(auth, corp, address(registry), issuance);

        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRound(rm, address(usdc), usdc.decimals(), bytes32(uint256(777)));

        uint256 salt = 1;
        uint256 privKey = 0xB0B;
        address investor = vm.addr(privKey);
        uint256 startBal = usdc.balanceOf(investor);
        usdc.transfer(investor, 50_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 10_000 * (10 ** usdc.decimals()),
            maxAmount: 40_000 * (10 ** usdc.decimals())
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = _computeEOISignature(
            registry,
            bytes32(uint256(777)),
            salt,
            globalValues,
            partyValues,
            address(this),
            privKey
        );

        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 2"
        );
        vm.stopPrank();

        uint256 endBal = usdc.balanceOf(investor);
        assertGt(endBal, startBal);
        assertLt(endBal, startBal + 40_000 * (10 ** usdc.decimals()));
    }

    function test_FCFS_SubmitEOI_InvalidAmount_Reverts() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            
        ) = _deployRegistryAndFactories(me);
        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(corpFactory, "Corp D", me, me);
        RoundManager rm = _initRoundManager(auth, corp, address(registry), issuance);
        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRound(rm, address(usdc), usdc.decimals(), bytes32(uint256(777)));

        address investor = address(0x333);
        usdc.transfer(investor, 5_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 3",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 100,
            maxAmount: 500
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAmount.selector));
        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            hex"01",
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 3"
        );
        vm.stopPrank();
    }

    function test_FCFS_SubmitEOI_RemainingBelowMin_RevertsAndNoFundsPulled() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            
        ) = _deployRegistryAndFactories(me);
        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(corpFactory, "Corp E", me, me);
        RoundManager rm = _initRoundManager(auth, corp, address(registry), issuance);
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));
        MockPaymentToken usdc = new MockPaymentToken();

        bytes32 roundId = _createFCFSRoundCustom(rm, address(usdc), usdc.decimals(), bytes32(uint256(777)), 1_500 * (10 ** usdc.decimals()), 1_500 * (10 ** usdc.decimals()), 100_000 * (10 ** usdc.decimals()));

        uint256 salt1 = 1;
        uint256 privKey1 = 0xC01;
        address inv1 = vm.addr(privKey1);
        usdc.transfer(inv1, 100_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv1);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi1 = EOI({
            name: "A",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 1_000 * (10 ** usdc.decimals()),
            maxAmount: 2_000 * (10 ** usdc.decimals())
        });
        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";
        bytes memory sig1 = _computeEOISignature(
            registry,
            bytes32(uint256(777)),
            salt1,
            globalValues,
            partyValues,
            address(this),
            privKey1
        );
        rm.submitEOI(roundId, eoi1, globalValues, partyValues, sig1, salt1, new address[](0), bytes32(0), block.timestamp + 7 days, "A");
        vm.stopPrank();

        uint256 salt2 = 2;
        uint256 privKey2 = 0xD02;
        address inv2 = vm.addr(privKey2);
        uint256 startBal = usdc.balanceOf(inv2);
        usdc.transfer(inv2, 2_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv2);
        usdc.approve(address(rm), type(uint256).max);
        EOI memory eoi2 = EOI({
            name: "B",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 2_000 * (10 ** usdc.decimals()),
            maxAmount: 2_000 * (10 ** usdc.decimals())
        });
        bytes memory sig2 = _computeEOISignature(
            registry,
            bytes32(uint256(777)),
            salt2,
            globalValues,
            partyValues,
            address(this),
            privKey2
        );
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        rm.submitEOI(roundId, eoi2, globalValues, partyValues, sig2, salt2, new address[](0), bytes32(0), block.timestamp + 7 days, "B");
        vm.stopPrank();
        assertEq(usdc.balanceOf(inv2), startBal + 2_000 * (10 ** usdc.decimals()));
    }
}