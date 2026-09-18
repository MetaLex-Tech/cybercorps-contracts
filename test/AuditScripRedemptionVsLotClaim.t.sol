// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/CyberScrip.sol";
import "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../src/LedgerEntryToken.sol";
import "../src/interfaces/ICondition.sol";
import "../src/interfaces/ICyberScrip.sol";
import "../src/interfaces/ILedgerEntryToken.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/libs/auth.sol";
import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import {MockCyberCorp, MockUriBuilder} from "./IssuanceManagerConversionTest.t.sol";
import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice MTLX1-5. A holder scripifies a lot and keeps the scrip. The pool holds the backing, and the
/// lot holds an attributed claim. The claim is not the redemption right. The scrip is.
/// @dev This suite shows one thing. The holder redeems every scrip after either attack. The backing
/// is never taken. The per-lot claim does not gate redemption, so the suite asserts the redemption
/// right and never asserts the claim as a correct number. The tables print the claim so a reader can
/// see how far it drifts from what the holder can actually draw.
/// The two attacks:
///   Attack 1. One address deposits and redeems.
///   Attack 2. One address deposits, a second address redeems.
/// The section below the constructor compares them.
/// Real IssuanceManager, real printer, real CyberScrip. No vault call is mocked.
contract AuditScripRedemptionVsLotClaimTest is Test {
    bytes32 constant SALT = keccak256("AuditScripRedemptionVsLotClaim");

    /// @dev The victim scripifies this much and holds the scrip.
    uint256 constant VICTIM_UNITS = 100;
    /// @dev The attacker recycles this much every cycle. A larger loop empties the victim faster.
    uint256 constant ATTACKER_UNITS = 900;
    /// @dev Cycle budget. Both attacks reach their end state well inside this.
    uint256 constant CYCLES = 30;

    address owner;
    address victim = makeAddr("victim");

    /// @dev Attack 1 deposits and redeems on one address.
    address attacker = makeAddr("attacker");
    /// @dev Attack 2 splits the two legs over two addresses.
    address depositor = makeAddr("depositor");
    address redeemer = makeAddr("redeemer");

    BorgAuth auth;
    IssuanceManager issuanceManager;
    ILedgerEntryToken printer;
    ICyberScrip scrip;

    uint256 victimCertId;
    uint256 attackerCertId;
    uint256 depositorCertId;
    uint256 redeemerCertId;

    function setUp() public {
        owner = address(this);
        auth = new BorgAuth(owner);

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new IssuanceManagerFactory{salt: SALT}()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        new IssuanceManager(),
                        new LedgerEntryToken(),
                        new CyberScrip()
                    )
                )
            )
        );

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth), address(new MockCyberCorp()), address(new MockUriBuilder()), address(imFactory)
        );

        printer = ILedgerEntryToken(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Shared Cert",
                "SHARE",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );

        victimCertId = _mintCert(victim, VICTIM_UNITS);
        attackerCertId = _mintCert(attacker, ATTACKER_UNITS);
        depositorCertId = _mintCert(depositor, ATTACKER_UNITS);
        // The redeemer needs a live lot. Without one the conversion asks for a recertification approval.
        redeemerCertId = _mintCert(redeemer, 1);

        scrip = ICyberScrip(
            issuanceManager.deployCyberScrip(
                address(printer),
                new ITransferRestrictionHook[](0),
                new ICondition[](0),
                new ICondition[](0),
                0,
                1,
                1,
                new uint256[](0),
                false,
                true,
                true,
                true
            )
        );

        // The victim scripifies everything and keeps the scrip. Their lot now holds no active units,
        // and its only reported value is the pool claim.
        vm.prank(victim);
        issuanceManager.scripifyCert(address(printer), victimCertId, VICTIM_UNITS * 1e18, address(0));
    }

    // ══ the two attacks ═══════════════════════════════════════════════════════
    //
    // Both attacks recycle the attacker's own units. Both end with the attacker lots holding the units
    // they started with. Both cost gas only. They take nothing from the pool.
    //
    // They differ in one thing: who calls convertScripToCert.
    //
    //   item                      | attack 1                 | attack 2
    //   who deposits              | the attacker             | the depositor
    //   who redeems               | the same attacker        | the redeemer, a second address
    //   redeemer's own pool claim | covers the whole draw    | zero
    //   the draw consumes         | the redeemer's own claim | every claim, by the same ratio
    //   victim claim after        | 100, unchanged           | 0
    //
    // convertScripToCert consumes the caller's own positions first. See _withdrawOwnedScripUnits in
    // IssuanceManagerStorage.sol. That guard keys on the caller. So attack 2 steps around it by
    // redeeming on an address that never deposited, and the whole draw falls on everybody else.
    //
    // Attack 2 needs one extra step per leg: an ERC20 transfer of the scrip between the two addresses.
    // Scrip is a plain transferable token, so this step is free and needs no permission.

    // ══ the holder redeems in full after either attack ════════════════════════
    //
    // The attack moves the accounting only. It never takes the backing. The scrip is the redemption
    // right, so the holder always draws their units back.
    //
    // The victim claim column shows the inconsistency. After attack 2 the victim claim reads zero, and
    // the payout is still the full 100. So the claim does not report what the holder can draw.
    //
    // Every column below is the victim, except the pool, which is global.
    //
    //   scenario       | victim claim before | victim scrip | units paid out | victim claim after | pool after
    //   no attack      |                 100 |          100 |            100 |                  0 |          0
    //   after attack 1 |                 100 |          100 |            100 |                  0 |          0
    //   after attack 2 |                   0 |          100 |            100 |                  0 |          0

    /// @notice Baseline. No attack runs. The victim redeems every scrip.
    function test_Redeem_BaselineWithNoAttack() public {
        _assertVictimRedeemsInFull(100e18);
    }

    /// @notice Attack 1 runs to its end, then the victim redeems every scrip. Attack 1 leaves the
    /// victim claim at 100, and the payout is 100.
    function test_Redeem_InFullAfterAttack1() public {
        _runAttack1Cycles(CYCLES);
        _assertVictimRedeemsInFull(100e18);
    }

    /// @notice Attack 2 runs to its end, then the victim redeems every scrip. Attack 2 drives the
    /// victim claim to zero, and the payout is still 100.
    function test_Redeem_InFullAfterAttack2() public {
        _runAttack2Cycles(CYCLES);
        _assertVictimRedeemsInFull(0);
    }

    // Four parts of 25. Here the victim claim tracks the payout, because attack 1 leaves it alone.
    //
    //   slice | victim claim before | victim active unitsRepresented | victim claim after | pool after
    //       1 |                 100 |                             25 |                 75 |         75
    //       2 |                  75 |                             50 |                 50 |         50
    //       3 |                  50 |                             75 |                 25 |         25
    //       4 |                  25 |                            100 |                  0 |          0

    /// @notice Attack 1, then four part redemptions. Each part pays out.
    function test_Redeem_InSlicesAfterAttack1() public {
        _runAttack1Cycles(CYCLES);
        _assertVictimRedeemsInSlices([uint256(100e18), 75e18, 50e18, 25e18, 0]);
    }

    // Four parts of 25. The victim claim reads zero at every step. Every part still pays, and the pool
    // draws down in step with the payout. The claim and the payout disagree on all four rows.
    //
    //   slice | victim claim before | victim active unitsRepresented | victim claim after | pool after
    //       1 |                   0 |                             25 |                  0 |         75
    //       2 |                   0 |                             50 |                  0 |         50
    //       3 |                   0 |                             75 |                  0 |         25
    //       4 |                   0 |                            100 |                  0 |          0

    /// @notice Attack 2, then four part redemptions. Each part pays out.
    function test_Redeem_InSlicesAfterAttack2() public {
        _runAttack2Cycles(CYCLES);
        _assertVictimRedeemsInSlices([uint256(0), 0, 0, 0, 0]);
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    //
    // What one cycle of each attack does to the pool claim. The claim is reported here for context
    // only. No test asserts it as a correct number.
    //
    // Attack 1, per cycle. Row "a" is after the scripify, row "b" after the convert.
    //   cycle | attacker units | attacker claim | victim claim | pool
    //   start |            900 |              0 |          100 |  100
    //      1a |              0 |            900 |          100 | 1000
    //      1b |            900 |              0 |          100 |  100
    // The redeemer's own position covers the whole draw. The victim claim holds at 100.
    //
    // Attack 2, per cycle. Leg A is the depositor deposit and the redeemer redemption. Leg B returns
    // the units the other way. One cycle is both legs.
    //   cycle | dep units | dep claim | red claim |  victim claim | pool
    //   start |       900 |         0 |         0 |    100        |  100
    //      1A |         0 |        90 |         0 |     10        |  100
    //      1B |       900 |         0 |     98.90 |      1.0989   |  100
    //       2 |       900 |         0 |     99.99 |      0.013548 |  100
    //      11 |       900 |         0 |    100.00 |      0        |  100
    // The redeemer holds no position, so the whole draw is socialized. The victim claim falls by
    // about eighty times each cycle and hits zero at cycle 11. Both attacker lots end with the units
    // they started with, so the attack costs gas only.

    /// @dev One cycle scripifies the attacker's units and converts the scrip straight back. The units
    /// return to the same lot, so the cycle costs gas only.
    function _runAttack1Cycle() internal {
        vm.prank(attacker);
        issuanceManager.scripifyCert(address(printer), attackerCertId, ATTACKER_UNITS * 1e18, address(0));
        vm.prank(attacker);
        issuanceManager.convertScripToCert(address(printer), ATTACKER_UNITS * 1e18);
    }

    function _runAttack1Cycles(uint256 cycles) internal {
        for (uint256 i = 0; i < cycles; i++) {
            _runAttack1Cycle();
        }
    }

    /// @dev Leg A: the depositor scripifies their own units and hands the scrip to the redeemer. The
    /// redeemer holds no pool position, so the whole draw is socialized. Leg B returns the units.
    function _runAttack2Cycle() internal {
        vm.prank(depositor);
        issuanceManager.scripifyCert(address(printer), depositorCertId, ATTACKER_UNITS * 1e18, address(0));
        vm.prank(depositor);
        scrip.transfer(redeemer, ATTACKER_UNITS * 1e18);
        vm.prank(redeemer);
        issuanceManager.convertScripToCert(address(printer), ATTACKER_UNITS * 1e18);

        vm.prank(redeemer);
        issuanceManager.scripifyCert(address(printer), redeemerCertId, ATTACKER_UNITS * 1e18, address(0));
        vm.prank(redeemer);
        scrip.transfer(depositor, ATTACKER_UNITS * 1e18);
        vm.prank(depositor);
        issuanceManager.convertScripToCert(address(printer), ATTACKER_UNITS * 1e18);
    }

    function _runAttack2Cycles(uint256 cycles) internal {
        for (uint256 i = 0; i < cycles; i++) {
            _runAttack2Cycle();
        }
    }

    /// @dev The victim burns every scrip and must receive every unit on their own live lot.
    /// @param expectedClaimBefore The victim claim the scenario table predicts, before the redemption.
    function _assertVictimRedeemsInFull(uint256 expectedClaimBefore) internal {
        assertFalse(printer.isVoided(victimCertId), "victim lot voided before the redemption");
        assertEq(_claim(victimCertId), expectedClaimBefore, "victim claim before does not match the table");
        assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip changed");

        vm.prank(victim);
        issuanceManager.convertScripToCert(address(printer), VICTIM_UNITS * 1e18);

        assertEq(_activeUnitsRepresented(victimCertId), VICTIM_UNITS * 1e18, "victim did not get their units back");
        assertEq(_unitsRepresented(victimCertId), VICTIM_UNITS * 1e18, "victim unitsRepresented wrong after redeeming");
        assertEq(_claim(victimCertId), 0, "victim claim after does not match the table");
        assertEq(scrip.balanceOf(victim), 0, "victim scrip not burned");
        assertEq(scrip.totalSupply(), 0, "scrip still outstanding");
        assertEq(_poolAssets(), 0, "pool not empty");
        assertFalse(printer.isVoided(victimCertId), "victim lot voided by the redemption");
    }

    /// @dev The victim redeems in four equal parts. Each part must land on their lot.
    /// @param expectedClaim The victim claim column of the slice table. Index 0 is the claim before
    /// slice 1. Index i is the claim after slice i.
    function _assertVictimRedeemsInSlices(uint256[5] memory expectedClaim) internal {
        uint256 slice = (VICTIM_UNITS * 1e18) / 4;
        assertEq(_claim(victimCertId), expectedClaim[0], "victim claim before slice 1 does not match the table");

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(victim);
            issuanceManager.convertScripToCert(address(printer), slice);

            uint256 paidOut = slice * (i + 1);
            uint256 left = VICTIM_UNITS * 1e18 - paidOut;
            string memory at = string.concat(" after slice ", vm.toString(i + 1));
            assertEq(_activeUnitsRepresented(victimCertId), paidOut, string.concat("victim units wrong", at));
            assertEq(_claim(victimCertId), expectedClaim[i + 1], string.concat("victim claim off the table", at));
            assertEq(scrip.balanceOf(victim), left, string.concat("victim scrip wrong", at));
            assertEq(_poolAssets(), left, string.concat("pool wrong", at));
        }

        assertEq(_activeUnitsRepresented(victimCertId), VICTIM_UNITS * 1e18, "victim did not get every unit back");
        assertEq(scrip.balanceOf(victim), 0, "victim scrip not burned");
        assertEq(_poolAssets(), 0, "pool not empty");
    }

    /// @dev unitsRepresented from getCertificateDetails: the active units plus the pool claim. This is
    /// the value tokenURI renders.
    function _unitsRepresented(uint256 tokenId) internal view returns (uint256) {
        return printer.getCertificateDetails(tokenId).unitsRepresented;
    }

    function _claim(uint256 tokenId) internal view returns (uint256) {
        return issuanceManager.getScripPoolAmountById(address(printer), tokenId);
    }

    /// @dev unitsRepresented from getActiveCertificateDetails: the active units alone, no pool claim.
    function _activeUnitsRepresented(uint256 tokenId) internal view returns (uint256) {
        return printer.getActiveCertificateDetails(tokenId).unitsRepresented;
    }

    function _poolAssets() internal view returns (uint256 assets) {
        (assets,) = issuanceManager.getCertScripUnitVault(address(printer));
    }

    function _mintCert(address to, uint256 units) internal returns (uint256 tokenId) {
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units * 1e18,
            legalDetails: "",
            extensionData: bytes("")
        });
        vm.prank(owner);
        tokenId = issuanceManager.createCertAndAssign(address(printer), to, details);
    }
}
