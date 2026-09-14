// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {RoundLib, Round, RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {RealWorldShareCert, REAL_WORLD_IPFS_URI} from "./libs/RealWorldShareCert.sol";
import {MockERC20} from "./mock/MockERC20.sol";

/// @notice Gas regression guard for the three most gas-intensive RoundManager operations.
///         Parameters emulate real mainnet transactions:
///           createRound — block 25202917 (13,003,119 gas, 77.5% of block limit)
///           submitEOI   — block 25203564 (1,485,634 gas)
///           allocate    — block 25215285 (13,859,243 gas, 82.6% of block limit)
///         Each test asserts gas ≤ EIP-7825 block gas limit (16,777,216).
///         The cert payload (six legends + ~13 KB ShareCertData) lives in RealWorldShareCert, shared with
///         the secondary-trade guard so both measure the same real-world data.
contract RoundLifeCycleGasLimitTest is Test {
    using RoundLib for Round;

    uint256 constant EIP7825_GAS_LIMIT     = 16_777_216;
    uint256 constant GAS_LIMIT_90_PCT      = 15_099_494; // 90% of EIP-7825 block gas limit

    // ── Template ─────────────────────────────────────────────────────────────
    bytes32 constant TEMPLATE_ID = bytes32("metalex_cyberstock_reg_d_v1_0");

    // ── Round numeric params (real tx, USDC 6 decimals) ──────────────────────
    uint256 constant RAISE_CAP      = 1_772_019_147_600;
    uint256 constant MIN_TICKET     =     2_000_000_000;
    uint256 constant MAX_TICKET     =   500_000_000_000;
    uint256 constant PRICE_PER_UNIT = 26_213_301_000_000_000_000;
    uint256 constant VALUATION      = 35_000_000_000_000_000_000_000_000;
    uint256 constant EOI_AMOUNT     =     2_000_000_000;

    // ── State ─────────────────────────────────────────────────────────────────
    CyberAgreementRegistry registry;
    CyberCorpFactory corpFactory;
    MockERC20 usdc;
    ShareExtension shareExtension;

    address officer;
    uint256 officerKey;
    address investor;
    uint256 investorKey;

    function setUp() public {
        (registry, corpFactory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(address(this));
        _createTemplate();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        (officer, officerKey) = makeAddrAndKey("officer");
        (investor, investorKey) = makeAddrAndKey("investor");

        BorgAuth shareAuth = new BorgAuth(address(this));
        shareExtension = ShareExtension(address(new ERC1967Proxy(
            address(new ShareExtension()),
            abi.encodeWithSelector(ShareExtension.initialize.selector, address(shareAuth))
        )));
    }

    // ── template / helpers ────────────────────────────────────────────────────

    function _createTemplate() internal {
        string[] memory globalFields = new string[](5);
        globalFields[0] = "Price per share";
        globalFields[1] = "Number of shares";
        globalFields[2] = "Governing law";
        globalFields[3] = "";
        globalFields[4] = "";
        string[] memory partyFields = new string[](5);
        partyFields[0] = "Investor name";
        partyFields[1] = "Investor address";
        partyFields[2] = "Investor contact";
        partyFields[3] = "Investor type";
        partyFields[4] = "";
        registry.createTemplate(
            TEMPLATE_ID,
            "MetaLeX CyberStock Reg D v1.0",
            REAL_WORLD_IPFS_URI,
            globalFields,
            partyFields
        );
    }

    function _makeCertData() internal view returns (CyberCertData[] memory certData) {
        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Seed Preferred Stock - MetaLeX Labs, Inc.",
            symbol: "MLI-SEED-PREFSTCK",
            uri: REAL_WORLD_IPFS_URI,
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(shareExtension),
            seriesData: bytes(""),
            defaultLegend: RealWorldShareCert.legends()
        });
    }

    function _buildRound(address corp, address rmAddr)
        internal returns (Round memory round, CyberCertData[] memory certData)
    {
        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Dispute resolution method: Binding Arbitration|Governing law: Delaware";

        string[] memory roundPartyValues = new string[](5);
        roundPartyValues[0] = "Test Officer Name";
        roundPartyValues[1] = vm.toString(officer);
        roundPartyValues[2] = "contact@example.com (email), @handle_tg (Telegram)";
        roundPartyValues[3] = "";
        roundPartyValues[4] = "";

        bytes[] memory extData = new bytes[](1);
        extData[0] = RealWorldShareCert.encodedShareCertData();

        (bytes memory escrowedSig,) = CyberCorpHelper.computeEscrowSignature(
            rmAddr,
            SecuritySeries.SeriesSeed,
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            TEMPLATE_ID,
            address(usdc),
            PRICE_PER_UNIT,
            VALUATION,
            officerKey,
            corp
        );

        round = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                RoundType.FounderApproved,
                false, true, false,
                RAISE_CAP, MIN_TICKET, MAX_TICKET,
                address(usdc),
                PRICE_PER_UNIT,
                VALUATION,
                block.timestamp,
                block.timestamp + 30 days
            )
            .setAgreement(
                TEMPLATE_ID,
                officer,
                "Test Officer Name",
                "CEO",
                legalDetails,
                roundPartyValues,
                extData,
                new address[](0),
                escrowedSig
            );

        certData = _makeCertData();
    }

    function _buildEOICall(address rmAddr)
        internal
        returns (EOI memory eoi, string[] memory globalValues, string[] memory partyValues, bytes memory sig, uint256 salt)
    {
        eoi = EOI({
            name: "teh investOOOr",
            investorType: "Natural person",
            jurisdiction: "",
            contact: "@investOOOr (TG)",
            minAmount: EOI_AMOUNT,
            maxAmount: EOI_AMOUNT,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        globalValues = new string[](5);
        globalValues[0] = "26.213301";
        globalValues[1] = "76.29714395756566485";
        globalValues[2] = "Delaware";
        globalValues[3] = "";
        globalValues[4] = "";

        partyValues = new string[](5);
        partyValues[0] = "teh investOOOr";
        partyValues[1] = vm.toString(investor);
        partyValues[2] = "@investOOOr (TG)";
        partyValues[3] = "Natural person";
        partyValues[4] = "";

        salt = 0x19e75873baf;
        sig = CyberCorpHelper.computeEOISignature(
            registry,
            TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officer,
            investorKey,
            rmAddr,
            block.timestamp + 7 days,
            bytes32(0));

        usdc.mint(investor, EOI_AMOUNT * 2);
        vm.prank(investor);
        usdc.approve(rmAddr, type(uint256).max);
    }

    // ── tests ─────────────────────────────────────────────────────────────────

    /// @notice Emulates createRound tx (block 25202917, 13,003,119 gas).
    ///         1 cert printer with 6 full legends + ShareCertData extension (13 KB).
    function test_gasLimit_createRound() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).createRound(round, certData);
        uint256 gasUsed = gasStart - gasleft();

        console2.log("createRound gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "createRound exceeds 90% of EIP-7825 block gas limit");
    }

    /// @notice Emulates submitEOI tx (block 25203564, 1,485,634 gas).
    ///         Investor submits on a FounderApproved round with real-world field values.
    function test_gasLimit_submitEOI() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        bytes32 roundId = RoundManager(rmAddr).createRound(round, certData);

        (
            EOI memory eoi,
            string[] memory globalValues,
            string[] memory partyValues,
            bytes memory sig,
            uint256 salt
        ) = _buildEOICall(rmAddr);

        vm.prank(investor);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).submitEOI(
            roundId, eoi, globalValues, partyValues, sig, salt, new address[](0), bytes32(0)
        );
        uint256 gasUsed = gasStart - gasleft();

        console2.log("submitEOI gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "submitEOI exceeds 90% of EIP-7825 block gas limit");
    }

    /// @notice Emulates allocate tx (block 25215285, 13,859,243 gas).
    ///         Officer allocates full EOI amount; cert stores the 13 KB ShareCertData.
    function test_gasLimit_allocate() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        bytes32 roundId = RoundManager(rmAddr).createRound(round, certData);

        (
            EOI memory eoi,
            string[] memory globalValues,
            string[] memory partyValues,
            bytes memory sig,
            uint256 salt
        ) = _buildEOICall(rmAddr);

        vm.prank(investor);
        (bytes32 agreementId,) = RoundManager(rmAddr).submitEOI(
            roundId, eoi, globalValues, partyValues, sig, salt, new address[](0), bytes32(0)
        );

        vm.prank(officer);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).allocate(agreementId, EOI_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();

        console2.log("allocate gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "allocate exceeds 90% of EIP-7825 block gas limit");
    }
}
