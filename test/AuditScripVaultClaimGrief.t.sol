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

/// @notice MTLX1-5 regression. A certificate keeps no claim on the scrip pool, so a conversion cannot
/// reduce another holder's position. The scrip is the claim, and only its holder can spend it.
/// @dev Before this change every conversion reduced every position in proportion. One holder could drive
/// another holder's claim to zero for the cost of gas, and the emptied lot then became sweepable.
/// Real IssuanceManager, real printer, real CyberScrip. No vault call is mocked.
contract AuditScripVaultClaimGriefTest is Test {
    bytes32 constant SALT = keccak256("AuditScripVaultClaimGrief");

    uint256 constant VICTIM_UNITS = 100;
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

        // The victim scripifies everything and keeps the scrip.
        vm.prank(victim);
        issuanceManager.scripifyCert(address(printer), victimCertId, VICTIM_UNITS * 1e18, address(0));
    }

    /// @notice The attack cycle no longer touches the victim. Each cycle takes out only what it put in.
    function test_ConversionCannotReduceAnotherHoldersPosition() public {
        uint256 poolBefore = _poolAssets();

        for (uint256 i = 0; i < 30; i++) {
            _runAttackCycle();

            // The pool returns to exactly what the victim put in. Nothing of theirs was taken.
            assertEq(_poolAssets(), poolBefore, "pool moved");
            assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip moved");
        }

        // The attacker ends where they started.
        assertEq(_units(attackerCertId), ATTACKER_UNITS * 1e18, "attacker units moved");
        assertEq(scrip.balanceOf(attacker), 0, "attacker scrip moved");
        assertEq(_poolAssets(), VICTIM_UNITS * 1e18, "pool no longer backs the victim scrip");
    }

    /// @notice The victim redeems in full after the attack. The scrip is the claim, so it always works.
    function test_VictimStillRedeemsInFullAfterTheAttack() public {
        for (uint256 i = 0; i < 30; i++) {
            _runAttackCycle();
        }

        vm.prank(victim);
        issuanceManager.convertScripToCert(address(printer), VICTIM_UNITS * 1e18);

        assertEq(_units(victimCertId), VICTIM_UNITS * 1e18, "victim did not get their units back");
        assertEq(scrip.balanceOf(victim), 0, "victim scrip not burned");
        assertEq(_poolAssets(), 0, "pool not empty");
    }

    /// @notice A lot that scripified everything holds nothing, so an admin sweep retires it.
    /// The units went to the pool, and the scrip is the claim on them.
    /// @dev After the sweep the holder needs a recertification approval to convert back, because they
    /// have no live lot to convert into. That is accepted.
    function test_FullyScripifiedLotIsEmptyAndSweepable() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = victimCertId;

        assertEq(_units(victimCertId), 0, "lot still holds units");
        issuanceManager.voidEmptyCerts(address(printer), ids);
        assertTrue(printer.isVoided(victimCertId), "empty lot not swept");

        // The pool still holds the units that back the victim's scrip.
        assertEq(_poolAssets(), VICTIM_UNITS * 1e18, "pool no longer backs the victim scrip");
        assertEq(scrip.balanceOf(victim), VICTIM_UNITS * 1e18, "victim scrip changed");
    }

    /// @notice A lot that still holds units is not empty, so the sweep refuses it.
    function test_SweepRefusesALotThatStillHoldsUnits() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = attackerCertId;

        vm.expectRevert(IssuanceManagerStorage.CertNotEmpty.selector);
        issuanceManager.voidEmptyCerts(address(printer), ids);
    }

    /// @notice The sweep is admin only. A caller with no role cannot void an empty lot.
    function test_SweepRefusesACallerWithNoRole() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = victimCertId;

        address passerby = makeAddr("passerby");
        bytes memory expected =
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.ADMIN_ROLE(), passerby);

        vm.prank(passerby);
        vm.expectRevert(expected);
        issuanceManager.voidEmptyCerts(address(printer), ids);
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /// @dev Scripify the attacker's own units, then convert the same scrip straight back.
    function _runAttackCycle() internal {
        vm.prank(attacker);
        issuanceManager.scripifyCert(address(printer), attackerCertId, ATTACKER_UNITS * 1e18, address(0));
        vm.prank(attacker);
        issuanceManager.convertScripToCert(address(printer), ATTACKER_UNITS * 1e18);
    }

    function _units(uint256 tokenId) internal view returns (uint256) {
        return printer.getActiveCertificateDetails(tokenId).unitsRepresented;
    }

    function _poolAssets() internal view returns (uint256) {
        return issuanceManager.getCertScripUnitVault(address(printer));
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
