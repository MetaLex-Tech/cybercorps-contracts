// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {LegacyCyberCertData} from "./libs/LegacyCyberCorpFactory.sol";
import {SecuritySeries, SecurityClass, CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {RoundLib, Round, RoundType} from "../src/libs/RoundLib.sol";
import {RoundLib as RoundLibV3, Round as RoundV3} from "./libs/v3/RoundLib.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";

interface IRoundManagerV3 {
    function createRound(
        RoundV3 memory roundDraft,
        LegacyCyberCertData[] memory certData
    ) external returns (bytes32);
}

/// @notice Helper for creating rounds against the pre-upgrade (v3) RoundManager ABI,
/// which lacks the `restrictEndTimeReduction` field.
library CyberCorpHelperV3 {
    using RoundLibV3 for RoundV3;

    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function createRound(
        IRoundManagerV3 rm,
        address paymentToken,
        bytes32 templateId,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 pricePerUnit,
        uint256 valuation,
        RoundType roundType,
        uint256 officerPrivKey,
        address companyAddress,
        bool publicRound
    ) internal returns (bytes32) {
        address officerEOA = vm.addr(officerPrivKey);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        LegacyCyberCertData[] memory certData = new LegacyCyberCertData[](1);
        certData[0] = LegacyCyberCertData({
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

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            address(rm),
            SecuritySeries.SeriesSeed,
            raiseCap,
            minTicket,
            maxTicket,
            roundType,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            paymentToken,
            pricePerUnit,
            valuation,
            officerPrivKey,
            companyAddress
        );

        vm.startPrank(officerEOA);
        return rm.createRound(
            RoundLibV3.draft()
                .setTickets(
                    SecuritySeries.SeriesSeed,
                    roundType,
                    publicRound,
                    true,
                    raiseCap,
                    minTicket,
                    maxTicket,
                    paymentToken,
                    pricePerUnit,
                    valuation,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    templateId,
                    officerEOA,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    roundPartyValues,
                    new bytes[](certData.length),
                    new address[](0),
                    escrowedSig
                ),
            certData
        );
        vm.stopPrank();
    }
}

/// @notice Fork-based test for the restrictEndTimeReduction flag introduced in v3.next.
/// A corp and round are created on the OLD (pre-upgrade) RoundManager implementation,
/// the upgrade is then simulated, and tests verify both backward compatibility and
/// new-feature correctness.
contract RoundManagerV3NextForkTest is Test {
    using RoundLib for Round;
    using ERC1967ProxyLib for address;

    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    ERC20 stable = ERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e); // Base Sepolia USDC

    address deployer;
    uint256 deployerPrivKey;
    address corpOwnerV3;
    uint256 corpOwnerPrivKeyV3;
    address corpOwnerV4;
    uint256 corpOwnerPrivKeyV4;
    address investor;
    uint256 investorPrivKey;

    address corpV3;
    address rmV3;
    bytes32 roundIdV3;

    address corpV4;
    address rmV4;
    
    string[] testRoundPartyValues;
    address[] knownLegacyCorps;

    RoundManagerFactory rmFactory;

    uint256 constant MIN_TICKET     = 1_000   * 1e6;
    uint256 constant MAX_TICKET     = 100_000 * 1e6;
    uint256 constant RAISE_CAP      = 1_000_000 * 1e6;
    uint256 constant PRICE_PER_UNIT = 10 * 1e18;
    uint256 constant VALUATION      = 10_000_000 * 1e18;

    function setUp() public {
        vm.createSelectFork("base_sepolia", 38956871); // pinned to an old block before upgrades

        (deployer,       deployerPrivKey)    = makeAddrAndKey("deployer");
        (corpOwnerV3,    corpOwnerPrivKeyV3) = makeAddrAndKey("corpOwnerV3");
        (corpOwnerV4,    corpOwnerPrivKeyV4) = makeAddrAndKey("corpOwnerV4");
        (investor,       investorPrivKey)    = makeAddrAndKey("investor");

        testRoundPartyValues = new string[](2);
        testRoundPartyValues[0] = "Officer";
        testRoundPartyValues[1] = "CEO";

        rmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        // Create template 777 in the live registry so EOI signatures can be verified
        {
            string[] memory globalFields = new string[](1);
            globalFields[0] = "Global Field";
            string[] memory partyFields = new string[](2);
            partyFields[0] = "Officer Name";
            partyFields[1] = "Officer Title";
            vm.prank(metalexSafe);
            registry.createTemplate(
                CyberCorpHelper.TEMPLATE_ID,
                "Test",
                "ipfs://template",
                globalFields,
                partyFields
            );
        }

        // ── Pre-upgrade: deploy v3 corp and create unrestricted round ───────────────
        // Corp and RoundManager proxy are on the OLD implementation. createRound is
        // called via the v3 ABI (no restrictEndTimeReduction field) to match the
        // deployed impl's function selector.
        (corpV3, , , , rmV3) = cyberCorpFactory.deployCyberCorp(
            keccak256("v3Corp"),
            "Test v3 Corp",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            corpOwnerV3,
            CompanyOfficer({
                eoa: corpOwnerV3,
                name: "Officer",
                contact: "officer@example.com",
                title: "CEO"
            })
        );

        roundIdV3 = CyberCorpHelperV3.createRound(
            IRoundManagerV3(rmV3),
            address(stable),
            CyberCorpHelper.TEMPLATE_ID,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            corpOwnerPrivKeyV3,
            corpV3,
            false
        );

        // ── Simulate upgrade ─────────────────────────────────────────────────────
        vm.startPrank(metalexSafe);
        rmFactory.AUTH().updateRole(deployer, rmFactory.AUTH().OWNER_ROLE());
        vm.stopPrank();

        RoundManager newRmRef = new RoundManager();
        vm.prank(deployer);
        rmFactory.setRefImplementation(address(newRmRef));

        vm.prank(corpV3);
        RoundManager(rmV3).upgradeToAndCall(address(newRmRef), "");

        IssuanceManagerFactory issuanceFactory = IssuanceManagerFactory(
            cyberCorpFactory.issuanceManagerFactory()
        );
        vm.startPrank(metalexSafe);
        issuanceFactory.AUTH().updateRole(
            deployer,
            issuanceFactory.AUTH().OWNER_ROLE()
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        IssuanceManager newIssuanceManager = new IssuanceManager();
        issuanceFactory.setRefImplementation(address(newIssuanceManager));
        issuanceFactory.setCyberCertPrinterRefImplementation(
            address(new CyberCertPrinter())
        );
        vm.stopPrank();

        address issuanceManagerV3 = CyberCorp(corpV3).issuanceManager();
        vm.prank(corpOwnerV3);
        IssuanceManager(issuanceManagerV3).upgradeToAndCall(
            address(newIssuanceManager),
            ""
        );

        // ── deploy v4 corp ───────────────

        (corpV4, , , , rmV4) = cyberCorpFactory.deployCyberCorp(
            keccak256("v4Corp"),
            "Test v4 Corp",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            corpOwnerV4,
            CompanyOfficer({
                eoa: corpOwnerV4,
                name: "Officer",
                contact: "officer@example.com",
                title: "CEO"
            })
        );
        
        // ── provision investor ─────────────────────────────────────────────────────

        deal(address(stable), investor, 1_000_000e6);
        vm.prank(investor);
        stable.approve(rmV3, type(uint256).max);
    }

    // ── Upgrade sanity ────────────────────────────────────────────────────────────

    function test_SanityCheck() public view {
        address newRef = rmFactory.getRefImplementation();
        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp c = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(c.roundManager());
            assertEq(
                address(rm).getErc1967Implementation(),
                newRef,
                string(abi.encodePacked("Legacy corp ", vm.toString(address(c)), " RoundManager not on new impl"))
            );
        }
        assertEq(
            rmV3.getErc1967Implementation(),
            newRef,
            "Test corp RoundManager not on new impl"
        );
    }

    // ── Backward compatibility (round created on old impl, restrictEndTimeReduction=0) ──

    function test_SetRoundEndTime_Reduce_NotRestricted() public {
        uint256 newEndTime = block.timestamp + 1 days;
        vm.prank(corpOwnerV3);
        RoundManager(rmV3).setRoundEndTime(roundIdV3, newEndTime);
        assertEq(RoundManager(rmV3).getRound(roundIdV3).endTime, newEndTime);
    }

    function test_CloseRoundNow_NotRestricted() public {
        vm.prank(corpOwnerV3);
        RoundManager(rmV3).closeRoundNow(roundIdV3);
        assertEq(RoundManager(rmV3).getRound(roundIdV3).endTime, block.timestamp);
    }

    // ── New flag behavior (restricted round created post-upgrade) ─────────────────

    function test_RevertIf_SetRoundEndTime_Reduce_Restricted() public {
        bytes32 restrictedRoundId = _createV4CorpRound(true);
        uint256 currentEndTime = RoundManager(rmV4).getRound(restrictedRoundId).endTime;
        vm.expectRevert(RoundManager.EndTimeReductionRestricted.selector);
        vm.prank(corpOwnerV4);
        RoundManager(rmV4).setRoundEndTime(restrictedRoundId, currentEndTime - 1 days);
    }

    function test_SetRoundEndTime_Increase_Restricted() public {
        bytes32 restrictedRoundId = _createV4CorpRound(true);
        uint256 currentEndTime = RoundManager(rmV4).getRound(restrictedRoundId).endTime;
        uint256 newEndTime = currentEndTime + 1 days;
        vm.prank(corpOwnerV4);
        RoundManager(rmV4).setRoundEndTime(restrictedRoundId, newEndTime);
        assertEq(RoundManager(rmV4).getRound(restrictedRoundId).endTime, newEndTime);
    }

    function test_RevertIf_CloseRoundNow_Restricted() public {
        bytes32 restrictedRoundId = _createV4CorpRound(true);
        vm.expectRevert(RoundManager.EndTimeReductionRestricted.selector);
        vm.prank(corpOwnerV4);
        RoundManager(rmV4).closeRoundNow(restrictedRoundId);
    }

    /// @notice When restrictEndTimeReduction == true, allowTimedOffers == false, and
    /// endTime == type(uint256).max, the founder cannot close/shorten the round and the
    /// investor cannot recall their EOI (it never expires). However, reject() can still release funds.
    function test_RejectEOI_WorksWhenRestrictedWithMaxEndTime() public {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCertData[] memory cd = new CyberCertData[](1);
        cd[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });

        uint256 maxEndTime = type(uint256).max;

        (bytes memory sig, ) = CyberCorpHelper.computeEscrowSignature(
            rmV3,
            SecuritySeries.SeriesB,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            maxEndTime,
            CyberCorpHelper.TEMPLATE_ID,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwnerPrivKeyV3,
            corpV3
        );

        vm.prank(corpOwnerV3);
        bytes32 restrictedMaxRoundId = RoundManager(rmV3).createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesB,
                    RoundType.FounderApproved,
                    false,
                    false, // allowTimedOffers = false
                    true,  // restrictEndTimeReduction = true
                    RAISE_CAP,
                    MIN_TICKET,
                    MAX_TICKET,
                    address(stable),
                    PRICE_PER_UNIT,
                    VALUATION,
                    block.timestamp,
                    maxEndTime
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    corpOwnerV3,
                    "Officer",
                    "CEO",
                    new string[](cd.length),
                    testRoundPartyValues,
                    new bytes[](cd.length),
                    new address[](0),
                    sig
                ),
            cd
        );

        // Confirm the round cannot be closed or shortened by the founder
        vm.startPrank(corpOwnerV3);
        vm.expectRevert(RoundManager.EndTimeReductionRestricted.selector);
        RoundManager(rmV3).closeRoundNow(restrictedMaxRoundId);
        vm.expectRevert(RoundManager.EndTimeReductionRestricted.selector);
        RoundManager(rmV3).setRoundEndTime(restrictedMaxRoundId, block.timestamp + 1 days);
        vm.stopPrank();

        // Investor submits EOI
        uint256 balBefore = stable.balanceOf(investor);
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(rmV3),
            registry,
            restrictedMaxRoundId,
            42,
            5_000 * 10 ** 6,
            10_000 * 10 ** 6,
            corpOwnerV3,
            investorPrivKey
        );
        vm.stopPrank();

        Escrow memory escBefore = RoundManager(rmV3).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));
        assertEq(stable.balanceOf(investor), balBefore - 10_000 * 10 ** 6);

        // Investor cannot recall — EOI never expires (allowTimedOffers=false + endTime=max)
        vm.prank(investor);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        RoundManager(rmV3).recallEOI(agreementId);

        // Founder rejects the EOI — must refund the investor
        vm.prank(corpOwnerV3);
        RoundManager(rmV3).reject(agreementId);

        Escrow memory escAfter = RoundManager(rmV3).getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(stable.balanceOf(investor), balBefore);
    }

    // ── Private helper ────────────────────────────────────────────────────────────

    function _createV4CorpRound(bool restrictEndTimeReduction) private returns (bytes32 newRoundId) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCertData[] memory cd = new CyberCertData[](1);
        cd[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });

        (bytes memory sig, ) = CyberCorpHelper.computeEscrowSignature(
            rmV4,
            SecuritySeries.SeriesA,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwnerPrivKeyV4,
            corpV4
        );

        vm.startPrank(corpOwnerV4);
        newRoundId = RoundManager(rmV4).createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesA,
                    RoundType.FounderApproved,
                    false,
                    true,
                    restrictEndTimeReduction,
                    RAISE_CAP,
                    MIN_TICKET,
                    MAX_TICKET,
                    address(stable),
                    PRICE_PER_UNIT,
                    VALUATION,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    corpOwnerV4,
                    "Officer",
                    "CEO",
                    new string[](cd.length),
                    testRoundPartyValues,
                    new bytes[](cd.length),
                    new address[](0),
                    sig
                ),
            cd
        );
        vm.stopPrank();
    }
}
