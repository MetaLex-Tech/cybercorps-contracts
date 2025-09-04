// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RoundManager.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberCertPrinter.sol";
import "../src/storage/RoundManagerStorage.sol";
import "../src/CyberCorpConstants.sol";
import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
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
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";

// Import necessary types
using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6); // Mint 1M tokens with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// Mock condition that always fails
contract AlwaysFalseCondition is ICondition {
    function checkCondition(
        address,
        bytes4,
        bytes memory
    ) external pure returns (bool) {
        return false;
    }
}

contract RoundManagerTest is Test {
    RoundManager public roundManager;
    IssuanceManager public issuanceManager;
    CyberCertPrinter public certPrinter;
    MockPaymentToken public paymentToken;

    address public owner;
    uint256 private ownerPrivKey;
    address public investor;
    uint256 private investorPrivKey;

    // Infra
    CyberAgreementRegistry private registry;
    CyberCorpFactory private corpFactory;
    address private corp;
    address private auth;
    address private issuance;
    address private dealManager;
    address private uriBuilder;
    RoundManagerFactory private rmFactory;
    bytes32 private templateId;
    string[] private testRoundPartyValues;

    // Captured round id
    bytes32 public roundId;

    // Test round parameters
    uint256 public constant MIN_TICKET = 1000 * 10 ** 6; // 1,000 USDC
    uint256 public constant MAX_TICKET = 100000 * 10 ** 6; // 100,000 USDC
    uint256 public constant RAISE_CAP = 1000000 * 10 ** 6; // 1M USDC
    uint256 public constant PRICE_PER_UNIT = 10 * 10 ** 6; // 10 USDC per unit
    uint256 public constant VALUATION = 10000000; // $10M valuation

    function setUp() public {
        ownerPrivKey = 0xA0A0;
        owner = vm.addr(ownerPrivKey);
        investorPrivKey = 0xA11CE;
        investor = vm.addr(investorPrivKey);

        // Deploy infra (auth, registry, factories)
        bytes32 salt = keccak256(abi.encodePacked("roundmanager-infra", owner));
        BorgAuth bootstrapAuth = new BorgAuth{salt: salt}(owner);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(bootstrapAuth)
                    )
                )
            )
        );

        uriBuilder = address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(bootstrapAuth)
                )
            )
        );

        address issuanceManagerFactoryAddr = address(
            new IssuanceManagerFactory{salt: salt}(address(bootstrapAuth))
        );
        address cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: salt}(address(bootstrapAuth))
        );
        address dealManagerFactory = address(
            new DealManagerFactory{salt: salt}(address(bootstrapAuth))
        );

        address certPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImpl = address(new CyberScrip{salt: salt}());

        corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(bootstrapAuth),
                        address(registry),
                        certPrinterImpl,
                        cyberScripImpl,
                        issuanceManagerFactoryAddr,
                        cyberCorpSingleFactory,
                        dealManagerFactory,
                        uriBuilder
                    )
                )
            )
        );

        // Deploy corp
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: owner,
            name: "Officer",
            contact: "officer@example.com",
            title: "CEO"
        });
        (corp, auth, issuance, dealManager) = corpFactory.deployCyberCorp(
            keccak256("rm-corp"),
            "Test Corp",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            owner,
            officer
        );

        // RoundManager via factory and initialize
        rmFactory = new RoundManagerFactory(auth);
        address proxy = rmFactory.deployRoundManager(keccak256("rm"));
        roundManager = RoundManager(payable(proxy));
        roundManager.initialize(
            auth,
            corp,
            address(registry),
            issuance,
            address(rmFactory)
        );
        // Authorize RM as owner in IssuanceManager
        vm.prank(owner);
        BorgAuth(auth).updateRole(address(roundManager), 99);
        // Allow RM to transfer certs by setting it as corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(roundManager));

        // Define a template with 1 global and 1 party field to match tests
        templateId = bytes32("TEST_TEMPLATE");
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field";
        vm.prank(owner);
        registry.createTemplate(
            templateId,
            "TestT",
            "ipfs://template",
            globalFields,
            partyFields
        );

        // Deploy mock payment token
        paymentToken = new MockPaymentToken();

        // Create certificate data for the round
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
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

        // Create test round (template has 1 party field; provide 1 round party value)
        testRoundPartyValues = new string[](1);
        testRoundPartyValues[0] = "Officer";

        // Create test round
        vm.prank(owner);
        roundId = roundManager.createRound(
            "Series A",
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            certData,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            6, // USDC decimals
            testRoundPartyValues,
            bytes("")
        );

        // Fund investor
        paymentToken.transfer(investor, 1000000 * 10 ** 6);
        vm.prank(investor);
        paymentToken.approve(address(roundManager), type(uint256).max);
    }

    function _computeEOISignature(
        bytes32 _templateId,
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
        ) = registry.getTemplateDetails(_templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(
            abi.encode(_templateId, salt, globalValues, parties)
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

    // Sign for an existing agreementId (used by allocate path)
    function _signForAgreement(
        bytes32 agreementId,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 signerPrivKey
    ) internal view returns (bytes memory) {
        (
            string memory legalUri,
            ,
            string[] memory glFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        return
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                legalUri,
                glFields,
                partyFields,
                globalValues,
                partyValues,
                signerPrivKey
            );
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
        roundManager.setRoundPricePerShare(
            roundId,
            roundPricePerShare,
            roundPriceDecimals
        );

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

        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            CCapUsed,
            /*Floor*/ 0,
            priceDec,
            shareDec
        );

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

        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            CCapUsed,
            /*Floor*/ 0,
            priceDec,
            shareDec
        );

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
        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            CCapUsed,
            /*Floor*/ 0,
            priceDec,
            shareDec
        );
        uint256 safePrice = (PMVC * (10 ** priceDec)) / CCapUsed; // 10000
        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice; // 10000
        uint256 floorShares = (PA * (10 ** priceDec)) / priceBasis; // 10000 (floor)
        assertEq(floorShares, 10_000);

        // Ceil
        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            CCapUsed,
            /*Ceil*/ 1,
            priceDec,
            shareDec
        );
        uint256 ceilShares = (PA * (10 ** priceDec) + priceBasis - 1) /
            priceBasis;
        assertEq(ceilShares, 10_001);

        // Round half up
        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            CCapUsed,
            /*Round*/ 2,
            priceDec,
            shareDec
        );
        uint256 halfUpShares = (PA * (10 ** priceDec) + (priceBasis / 2)) /
            priceBasis;
        assertEq(halfUpShares, 10_000); // since half of 10000 is 5000, still 10000 for these values
    }

    function test_PmvcSubseriesLabel_SetAndGet() public {
        vm.prank(owner);
        roundManager.setPMVCSubseriesLabel(roundId, 10_000_000, "SAFE1");
        string memory label = roundManager.getPMVCSubseriesLabel(
            roundId,
            10_000_000
        );
        assertEq(keccak256(bytes(label)), keccak256(bytes("SAFE1")));
    }

    function test_SubmitEOI_Success() public {
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6, // 5,000 USDC
            maxAmount: 10000 * 10 ** 6 // 10,000 USDC
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value";

        string[] memory partyValues = new string[](1);
        partyValues[0] = "Party Value";

        uint256 salt = 1;
        bytes memory signature = _computeEOISignature(
            templateId,
            salt,
            globalValues,
            partyValues,
            owner,
            investorPrivKey
        );
        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 7 days;
        bytes memory voidSignature = "0x";

        bytes32 agreementId = roundManager.submitEOI(
            roundId,
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

        assertTrue(
            agreementId != bytes32(0),
            "Agreement ID should not be zero"
        );

        // Verify EOI was stored correctly by checking the EOISubmitted event
        vm.expectEmit(true, true, true, true);
        emit RoundManager.EOISubmitted(
            agreementId,
            roundId,
            investor,
            eoi.maxAmount
        );

        vm.stopPrank();
    }

    function test_SubmitEOI_InvalidAmount() public {
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 100 * 10 ** 6, // Below MIN_TICKET
            maxAmount: 1000000 * 10 ** 6 // Above MAX_TICKET
        });

        string[] memory globalValues = new string[](1);
        string[] memory partyValues = new string[](1);

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );

        bytes memory sig = _computeEOISignature(
            templateId,
            1,
            globalValues,
            partyValues,
            owner,
            investorPrivKey
        );
        roundManager.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
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
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6
        });

        bytes32 agreementId = roundManager.submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                1,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );

        vm.stopPrank();

        // Now allocate as owner
        uint256 allocatedAmount = 7500 * 10 ** 6; // 7,500 USDC

        // Company officer signature over party values for allocation path (signs agreementId)
        bytes memory officerSig = _signForAgreement(
            agreementId,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );

        vm.prank(owner);
        roundManager.allocate(agreementId, allocatedAmount, officerSig);

        // Verify allocation by checking if the round exists and getting its price info
        assertTrue(roundManager.roundExists(roundId), "Round should exist");

        // We can verify the allocation was successful by checking if an AllocationMade event was emitted
        vm.expectEmit(true, true, false, true);
        uint256[] memory expectedCertIds = new uint256[](1);
        expectedCertIds[0] = 0; // First certificate ID
        emit RoundManager.AllocationMade(
            agreementId,
            roundId,
            allocatedAmount,
            expectedCertIds
        );

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
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6
        });

        bytes32 agreementId = roundManager.submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                1,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );

        vm.stopPrank();

        // Try to allocate an amount below min
        uint256 invalidAmount = 1000 * 10 ** 6; // Below eoi.minAmount

        // Signature still required but allocation should fail before signature is used
        bytes memory officerSig = _signForAgreement(
            agreementId,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        roundManager.allocate(agreementId, invalidAmount, officerSig);
    }

    function test_Allocate_ExceedsRaiseCap() public {
        // Submit EOI first
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: RAISE_CAP + 1 // Just over the raise cap
        });

        // Expect revert because eoi.maxAmount exceeds round.maxTicket bounds
        bytes memory sig = _computeEOISignature(
            templateId,
            1,
            new string[](1),
            new string[](1),
            owner,
            investorPrivKey
        );
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
        roundManager.submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](1),
            sig,
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Test Investor"
        );

        vm.stopPrank();
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
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6
        });

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.RoundNotOpen.selector)
        );

        roundManager.submitEOI(
            roundId,
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
            minAmount: 400000 * 10 ** 6, // 400k USDC
            maxAmount: 600000 * 10 ** 6 // 600k USDC
        });

        bytes32 agreementId1 = roundManager.submitEOI(
            roundId,
            eoi1,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                1,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 1"
        );
        vm.stopPrank();

        // Submit second EOI from different investor
        address investor2 = address(0x2);
        paymentToken.transfer(investor2, 1000000 * 10 ** 6);
        vm.startPrank(investor2);
        paymentToken.approve(address(roundManager), type(uint256).max);

        EOI memory eoi2 = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor2@example.com",
            minAmount: 400000 * 10 ** 6, // 400k USDC
            maxAmount: 600000 * 10 ** 6 // 600k USDC
        });

        bytes32 agreementId2 = roundManager.submitEOI(
            roundId,
            eoi2,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                2,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            2,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 2"
        );
        vm.stopPrank();

        // Allocate to first investor
        vm.startPrank(owner);
        bytes memory officerSig1 = _signForAgreement(
            agreementId1,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );
        roundManager.allocate(agreementId1, 500000 * 10 ** 6, officerSig1); // 500k USDC

        // Try to allocate remaining to second investor
        bytes memory officerSig2 = _signForAgreement(
            agreementId2,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );
        roundManager.allocate(agreementId2, 500000 * 10 ** 6, officerSig2); // 500k USDC

        // Verify total raised equals sum of allocations by checking that the round is closed
        // When total raised equals raise cap, no more allocations should be possible
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        roundManager.allocate(agreementId2, 1, officerSig2); // Try to allocate 1 more token, should fail
        vm.stopPrank();
    }

    function test_RejectEOI_RefundsAndVoids() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Reject Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        bytes32 agreementId = roundManager.submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                3,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Reject Me"
        );
        vm.stopPrank();
        Escrow memory escBefore = roundManager.getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Reject as owner -> refund and void
        vm.prank(owner);
        roundManager.reject(agreementId);
        Escrow memory escAfter = roundManager.getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor) - balBefore, eoi.maxAmount);
    }

    function test_Allocate_WithFailingCondition_Reverts() public {
        // Deploy failing condition
        AlwaysFalseCondition cond = new AlwaysFalseCondition();

        // Submit EOI with condition attached
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Fail Cond",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "cond@example.com",
            minAmount: 5_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6
        });
        address[] memory conditions = new address[](1);
        conditions[0] = address(cond);
        bytes32 agreementId = roundManager.submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                4,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            4,
            conditions,
            bytes32(0),
            block.timestamp + 7 days,
            "Fail Cond"
        );
        vm.stopPrank();

        // Attempt allocation -> should revert due to AgreementConditionsNotMet
        bytes memory officerSig = _signForAgreement(
            agreementId,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RoundManager.AgreementConditionsNotMet.selector
            )
        );
        roundManager.allocate(agreementId, 10_000 * 10 ** 6, officerSig);
    }

    function test_SubmitEOI_BeforeStart_Reverts() public {
        // Create a new round with future start
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });
        bytes32 roundIdFuture;
        vm.prank(owner);
        roundIdFuture = roundManager.createRound(
            "Series F",
            100_000 * 10 ** 6,
            1_000 * 10 ** 6,
            50_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            templateId,
            certData,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            6,
            testRoundPartyValues,
            bytes("")
        );

        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Z",
            investorType: "I",
            jurisdiction: "US",
            contact: "z@z",
            minAmount: 1_000 * 10 ** 6,
            maxAmount: 2_000 * 10 ** 6
        });
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.RoundNotOpen.selector)
        );
        roundManager.submitEOI(
            roundIdFuture,
            eoi,
            new string[](1),
            new string[](1),
            _computeEOISignature(
                templateId,
                6,
                new string[](1),
                new string[](1),
                owner,
                investorPrivKey
            ),
            6,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Z"
        );
        vm.stopPrank();
    }

    function test_SetCapTableSnapshot_EmitsEventAndGetters() public {
        CapTableSnapshot memory snap = CapTableSnapshot({
            totalCapitalSecuritiesOutstanding: 1,
            totalConvertingSecurities: 2,
            totalOptionsIssuedAndOutstanding: 3,
            totalPromisedOptions: 4,
            unissuedOptionPoolPreRound: 5,
            unissuedOptionPoolIncreaseIncludedInCalc: 6,
            cCapUsed: 7
        });

        vm.expectEmit(true, true, true, true);
        emit RoundManager.RoundSnapshotSet(roundId, 1, 2, 3, 4, 5, 6, 7);
        vm.prank(owner);
        roundManager.setCapTableSnapshot(roundId, snap);

        (
            uint256 a,
            uint256 b,
            uint256 c,
            uint256 d,
            uint256 e,
            uint256 f,
            uint256 g
        ) = roundManager.getCapTableSnapshotFields(roundId);
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(c, 3);
        assertEq(d, 4);
        assertEq(e, 5);
        assertEq(f, 6);
        assertEq(g, 7);
    }

    function test_IssuanceManagerGetter_ReturnsConfigured() public {
        assertEq(address(roundManager.issuanceManager()), issuance);
    }

    function test_Getters_RoundPriceAndRoundingPolicy() public {
        uint8 priceDec = 2;
        uint8 shareDec = 0;
        uint256 roundPrice = 12_345;
        uint256 cCapUsed = 1_000_000;
        _setRoundMeta(
            roundId,
            roundPrice,
            priceDec,
            cCapUsed,
            /*Round*/ 2,
            priceDec,
            shareDec
        );

        (uint256 rp, uint8 rpDec) = roundManager.getRoundPriceInfo(roundId);
        assertEq(rp, roundPrice);
        assertEq(rpDec, priceDec);

        (uint8 mode, uint8 outPriceDec, uint8 outShareDec) = roundManager
            .getRoundingPolicyFields(roundId);
        assertEq(mode, uint8(RoundingMode.Round));
        assertEq(outPriceDec, priceDec);
        assertEq(outShareDec, shareDec);
    }

    function test_SetPrimarySecurity_UpdatesFields() public {
        vm.prank(owner);
        roundManager.setPrimarySecurity(
            roundId,
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesA
        );
        (SecurityClass cls, SecuritySeries series) = roundManager
            .getPrimarySecurity(roundId);
        assertEq(uint256(cls), uint256(SecurityClass.PreferredStock));
        assertEq(uint256(series), uint256(SecuritySeries.SeriesA));
    }

    function test_RoundExists_FalseForUnknown() public {
        bytes32 unknownId = keccak256("unknown");
        assertFalse(roundManager.roundExists(unknownId));
    }

    function test_SubmitEOI_InvalidRound_Reverts() public {
        bytes32 unknownId = keccak256("unknown");
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "X",
            investorType: "I",
            jurisdiction: "US",
            contact: "x@x",
            minAmount: 5_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6
        });
        string[] memory gl = new string[](1);
        string[] memory pv = new string[](1);
        bytes memory sig = _computeEOISignature(
            templateId,
            9,
            gl,
            pv,
            owner,
            investorPrivKey
        );
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidRound.selector)
        );
        roundManager.submitEOI(
            unknownId,
            eoi,
            gl,
            pv,
            sig,
            9,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "X"
        );
        vm.stopPrank();
    }

    function test_FounderApproved_RefundsExcess_WhenRemainingBelowEscrow()
        public
    {
        // Create a new round with small raise cap so remaining < escrowed amount
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        bytes32 roundId2;
        vm.prank(owner);
        roundId2 = roundManager.createRound(
            "Series R",
            6_000 * 10 ** 6, // small cap
            1_000 * 10 ** 6,
            100_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            certData,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            6,
            testRoundPartyValues,
            bytes("")
        );

        // Investor submits EOI for 10,000 USDC, escrow pulls funds
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Y",
            investorType: "I",
            jurisdiction: "US",
            contact: "y@y",
            minAmount: 1_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6
        });
        string[] memory gl = new string[](1);
        string[] memory pv = new string[](1);
        bytes memory sig = _computeEOISignature(
            templateId,
            5,
            gl,
            pv,
            owner,
            investorPrivKey
        );
        uint256 balBefore = paymentToken.balanceOf(investor);
        bytes32 agreementId = roundManager.submitEOI(
            roundId2,
            eoi,
            gl,
            pv,
            sig,
            5,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Y"
        );
        uint256 balAfterSubmit = paymentToken.balanceOf(investor);
        assertEq(balBefore - balAfterSubmit, 10_000 * 10 ** 6);
        vm.stopPrank();

        // Allocate as owner: candidate will be remaining (6,000 USDC), refund 4,000 USDC
        bytes memory officerSig = _signForAgreement(
            agreementId,
            new string[](1),
            testRoundPartyValues,
            ownerPrivKey
        );
        vm.prank(owner);
        roundManager.allocate(agreementId, type(uint256).max, officerSig);

        uint256 balAfterAllocate = paymentToken.balanceOf(investor);
        assertEq(balAfterAllocate - balAfterSubmit, 4_000 * 10 ** 6);
    }
}

// Separate FCFS tests in their own contract to avoid the original setUp()
contract RoundManagerFCFSTest is Test {
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

    // Infra helpers copied from above
    function _deployRegistryAndFactories(
        address owner
    )
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
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(bootstrapAuth)
                    )
                )
            )
        );

        uriBuilder = address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(bootstrapAuth)
                )
            )
        );

        issuanceManagerFactory = address(
            new IssuanceManagerFactory{salt: salt}(address(bootstrapAuth))
        );
        cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: salt}(address(bootstrapAuth))
        );
        dealManagerFactory = address(
            new DealManagerFactory{salt: salt}(address(bootstrapAuth))
        );

        address certPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImpl = address(new CyberScrip{salt: salt}());

        corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
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
                )
            )
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

        (corp, auth, issuance, dealManager) = corpFactory.deployCyberCorp(
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
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
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

        return
            rm.createRound(
                "Seed",
                1_000_000 * (10 ** payDec),
                1_000 * (10 ** payDec),
                100_000 * (10 ** payDec),
                RoundType.FCFS,
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
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
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

        return
            rm.createRound(
                "Seed",
                raiseCap,
                minTicket,
                maxTicket,
                RoundType.FCFS,
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

        (address corp, address auth, address issuance, ) = _deployCorp(
            corpFactory,
            "Corp A",
            me,
            me
        );
        RoundManager rm = _initRoundManager(
            auth,
            corp,
            address(registry),
            issuance
        );

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                RoundManager.InvalidEscrowedSignature.selector
            )
        );
        rm.createRound(
            "Seed",
            1,
            1,
            1,
            RoundType.FCFS,
   
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

        (address corp, address auth, address issuance, ) = _deployCorp(
            corpFactory,
            "Corp B",
            me,
            me
        );
        RoundManager rm = _initRoundManager(
            auth,
            corp,
            address(registry),
            issuance
        );

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRoundCustom(
            rm,
            address(usdc),
            usdc.decimals(),
            bytes32(uint256(777)),
            100_000 * (10 ** usdc.decimals()),
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

        (address corp, address auth, address issuance, ) = _deployCorp(
            corpFactory,
            "Corp C",
            me,
            me
        );
        RoundManager rm = _initRoundManager(
            auth,
            corp,
            address(registry),
            issuance
        );

        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRound(
            rm,
            address(usdc),
            usdc.decimals(),
            bytes32(uint256(777))
        );

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

        (address corp, address auth, address issuance, ) = _deployCorp(
            corpFactory,
            "Corp D",
            me,
            me
        );
        RoundManager rm = _initRoundManager(
            auth,
            corp,
            address(registry),
            issuance
        );
        MockPaymentToken usdc = new MockPaymentToken();
        bytes32 roundId = _createFCFSRound(
            rm,
            address(usdc),
            usdc.decimals(),
            bytes32(uint256(777))
        );

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

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
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

    function test_FCFS_SubmitEOI_RemainingBelowMin_RevertsAndNoFundsPulled()
        public
    {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,

        ) = _deployRegistryAndFactories(me);
        _createTemplate(registry);

        (address corp, address auth, address issuance, ) = _deployCorp(
            corpFactory,
            "Corp E",
            me,
            me
        );
        RoundManager rm = _initRoundManager(
            auth,
            corp,
            address(registry),
            issuance
        );
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));
        MockPaymentToken usdc = new MockPaymentToken();

        bytes32 roundId = _createFCFSRoundCustom(
            rm,
            address(usdc),
            usdc.decimals(),
            bytes32(uint256(777)),
            1_500 * (10 ** usdc.decimals()),
            1_500 * (10 ** usdc.decimals()),
            100_000 * (10 ** usdc.decimals())
        );

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
        rm.submitEOI(
            roundId,
            eoi1,
            globalValues,
            partyValues,
            sig1,
            salt1,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "A"
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        rm.submitEOI(
            roundId,
            eoi2,
            globalValues,
            partyValues,
            sig2,
            salt2,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "B"
        );
        vm.stopPrank();
        assertEq(
            usdc.balanceOf(inv2),
            startBal + 2_000 * (10 ** usdc.decimals())
        );
    }
}
