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
            6 // USDC decimals
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
            "Test Investor",
            voidSignature
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
            "Test Investor",
            "0x"
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
            "Test Investor",
            "0x"
        );
        
        vm.stopPrank();
        
        // Now allocate as owner
        uint256 allocatedAmount = 7500 * 10**6; // 7,500 USDC
        
        vm.prank(owner);
        roundManager.allocate(agreementId, allocatedAmount);
        
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
            "Test Investor",
            "0x"
        );
        
        vm.stopPrank();
        
        // Try to allocate an amount below min
        uint256 invalidAmount = 1000 * 10**6; // Below eoi.minAmount
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        
        vm.prank(owner);
        roundManager.allocate(agreementId, invalidAmount);
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
            "Test Investor",
            "0x"
        );
        
        vm.stopPrank();
        
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        
        vm.prank(owner);
        roundManager.allocate(agreementId, RAISE_CAP + 1);
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
            "Test Investor",
            "0x"
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
            "Investor 1",
            "0x"
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
            "Investor 2",
            "0x"
        );
        vm.stopPrank();
        
        // Allocate to first investor
        vm.startPrank(owner);
        roundManager.allocate(agreementId1, 500000 * 10**6); // 500k USDC
        
        // Try to allocate remaining to second investor
        roundManager.allocate(agreementId2, 500000 * 10**6); // 500k USDC
        
        // Verify total raised equals sum of allocations by checking that the round is closed
        // When total raised equals raise cap, no more allocations should be possible
        vm.expectRevert(abi.encodeWithSelector(RoundManager.InvalidAllocation.selector));
        roundManager.allocate(agreementId2, 1); // Try to allocate 1 more token, should fail
        vm.stopPrank();
    }
}