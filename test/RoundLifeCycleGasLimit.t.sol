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
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {RealWorldShareCert, REAL_WORLD_IPFS_URI} from "./libs/RealWorldShareCert.sol";
import {MainnetSeed2ShareCert} from "./libs/MainnetSeed2ShareCert.sol";
import {ShareCertData} from "../src/storage/extensions/ShareExtension.sol";
import {ShareCertDataLayerLib} from "../src/storage/extensions/ShareCertDataLayerLib.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {GasBudget} from "./libs/GasBudget.sol";

/// @notice Gas regression guard for the three most gas-intensive RoundManager operations.
///         Parameters copy real mainnet transactions:
///           createRound — block 25202917 (13,003,119 gas before Glamsterdam)
///           submitEOI   — block 25203564 (1,485,634 gas before Glamsterdam)
///           allocate    — block 25215285 (13,859,243 gas before Glamsterdam)
///         Each test checks the Glamsterdam limits in GasBudget.
///         The cert payload (six legends + ~13 KB ShareCertData) lives in RealWorldShareCert, shared with
///         the secondary-trade guard so both measure the same real-world data.
/// forge-config: default.isolate = true
contract RoundLifeCycleGasLimitTest is Test {
    using RoundLib for Round;

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
            _extensionImplementation(),
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

    /// @dev The legacy shape: no series payload, the whole `ShareCertData` on every cert.
    function _extensionImplementation() internal virtual returns (address) {
        return address(new ShareExtension());
    }

    function _seriesData() internal pure virtual returns (bytes memory) {
        return bytes("");
    }

    function _certExtensionData() internal pure virtual returns (bytes memory) {
        return RealWorldShareCert.encodedShareCertData();
    }

    function _makeCertData() internal view virtual returns (CyberCertData[] memory certData) {
        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Seed Preferred Stock - MetaLeX Labs, Inc.",
            symbol: "MLI-SEED-PREFSTCK",
            uri: REAL_WORLD_IPFS_URI,
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(shareExtension),
            seriesData: _seriesData(),
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
        extData[0] = _certExtensionData();

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

    /// @notice Emulates createRound tx (block 25202917, 13,003,119 gas before Glamsterdam).
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

        GasBudget.check("createRound gas:", gasUsed);
    }

    /// @notice Emulates submitEOI tx (block 25203564, 1,485,634 gas before Glamsterdam).
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

        GasBudget.check("submitEOI gas:", gasUsed);
    }

    /// @notice Emulates allocate tx (block 25215285, 13,859,243 gas before Glamsterdam).
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

        GasBudget.check("allocate gas:", gasUsed);
    }
}

/// @notice The same round, the same real payload, stored as layers instead of one blob per cert.
///
/// The five series-wide sections of `ShareCertData` go to the printer's `seriesData` at createRound.
/// Only `certificateData` goes on each cert at allocate.
///
/// Measured under Glamsterdam, total gas (execution gas in brackets). Per-cert payload: 928 bytes
/// against 13,984 legacy, the same 6 legends.
/// | step        | legacy                   | layered                  | change |
/// |-------------|--------------------------|--------------------------|--------|
/// | createRound | 64,910,551 (7,767,095)   | 67,057,241 (7,954,818)   | +3.3%  |
/// | submitEOI   |  6,085,402   (984,763)   |  6,085,402   (984,763)   |  0     |
/// | allocate    | 65,118,611 (9,107,972)   | 21,214,866 (3,295,107)   | -67.4% |
///
/// createRound writes the series payload to the printer one time, so it costs a little more.
/// Each allocate then writes only the lean cert payload.
/// forge-config: default.isolate = true
contract RoundLifeCycleLayeredGasLimitTest is RoundLifeCycleGasLimitTest {
    function _extensionImplementation() internal override returns (address) {
        return address(new ShareExtensionV3());
    }

    function _seriesData() internal pure virtual override returns (bytes memory) {
        return RealWorldShareCert.encodedSeriesLayer();
    }

    function _certExtensionData() internal pure virtual override returns (bytes memory) {
        return RealWorldShareCert.encodedCertLayer();
    }
}

/// @notice The same round with the live Series Seed 2 data: the printer's series layer, cert #1's layer
///         and the printer's legends, copied from Ethereum. The fixture above is larger than this data.
///
/// Measured under Glamsterdam, total gas (execution gas in brackets). Series layer 9,504 bytes, cert
/// layer 896 bytes, 6 legends of 3,329 bytes.
/// | step        | live Series Seed 2       | layered fixture          |
/// |-------------|--------------------------|--------------------------|
/// | createRound | 51,337,723 (6,143,315)   | 67,057,241 (7,954,818)   |
/// | submitEOI   |  6,085,402   (984,763)   |  6,085,402   (984,763)   |
/// | allocate    | 21,318,089 (3,300,410)   | 21,214,866 (3,295,107)   |
/// forge-config: default.isolate = true
contract RoundLifeCycleMainnetSeed2GasLimitTest is RoundLifeCycleLayeredGasLimitTest {
    function _seriesData() internal pure override returns (bytes memory) {
        return MainnetSeed2ShareCert.encodedSeriesLayer();
    }

    function _certExtensionData() internal pure override returns (bytes memory) {
        return MainnetSeed2ShareCert.encodedCertLayer();
    }

    function _makeCertData() internal view override returns (CyberCertData[] memory certData) {
        certData = super._makeCertData();
        certData[0].name = "Series Seed 2 Preferred Stock - MetaLeX Labs, Inc.";
        certData[0].symbol = "MLI-SEED2-PREFSTCK";
        certData[0].defaultLegend = MainnetSeed2ShareCert.legends();
    }

    /// @notice The copied bytes still decode to the live security under the current structs.
    function test_mainnetSeed2Layers_resolveToTheLiveSecurity() public pure {
        ShareCertData memory share = ShareCertDataLayerLib.resolve(
            "", MainnetSeed2ShareCert.encodedSeriesLayer(), MainnetSeed2ShareCert.encodedCertLayer()
        );
        assertEq(share.terms.seriesName, "Series Seed 2 Preferred Stock", "series name");
        assertEq(share.mandatoryConversionTriggers.length, 2, "conversion triggers");
        assertEq(share.specialVotingRights.length, 3, "voting rights");
        assertEq(share.transferRestrictions.length, 2, "transfer restrictions");
        assertEq(share.splitHistory.length, 0, "split history");
    }
}
