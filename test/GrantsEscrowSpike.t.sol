// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {TestableCyberScrip} from "./mock/TestableCyberScrip.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {VestingAllocation} from "./vendor/metavest/VestingAllocation.sol";
import {BaseAllocation} from "./vendor/metavest/BaseAllocation.sol";

/// Minimal cert printer satisfying the IssuanceManager scripify path.
contract MockCertPrinterBasic {
    mapping(uint256 => address) private _owners;
    mapping(uint256 => CertificateDetails) private _details;

    function name() external pure returns (string memory) { return "Mock Cert"; }
    function symbol() external pure returns (string memory) { return "MCRT"; }

    function mockMintCert(uint256 id, address owner_, uint256 units) external {
        _owners[id] = owner_;
        _details[id].unitsRepresented = units;
    }

    function isVoided(uint256) external pure returns (bool) { return false; }
    function legalOwnerOf(uint256 id) external view returns (address) { return _owners[id]; }
    function getActiveCertificateDetails(uint256 id) external view returns (CertificateDetails memory) { return _details[id]; }
    function updateCertificateDetails(uint256 id, CertificateDetails calldata det) external { _details[id] = det; }
}

/// Stands in for a MetaVesTController: the allocation only reads controller.authority()
/// on authority-gated paths, never on fund + withdraw.
contract MockController {
    address public authority;
    constructor(address _authority) { authority = _authority; }
}

/// P0 spike: prove a CyberScrip vests through a MetaVesT VestingAllocation with NO custom
/// transfer hook. The escrow itself plus MetaVesT's two curves are the lockup —
///   withdrawable = min(vested, unlocked) - withdrawn
/// so anything not both vested AND unlocked stays in the allocation, untouchable. A slower
/// unlock curve than the vesting curve keeps earned-but-locked scrip locked. Issuer clawback
/// is barred by deploying the scrip with force-ops disabled (allocation-authority mode).
contract GrantsEscrowSpike is Test {
    bytes32 private constant SALT = keccak256("GrantsEscrowSpike");
    uint256 private constant TOTAL = 1000 ether;
    uint160 private constant VEST_RATE = 2e18; // tokens/sec earned — fast
    uint160 private constant UNLOCK_RATE = 1e18; // tokens/sec released — slower lockup

    BorgAuth public auth;
    IssuanceManager public issuanceManager;
    IssuanceManagerFactory public imFactory;
    MockCertPrinterBasic public cert;
    CyberScrip public scrip;
    MockController public controller;
    VestingAllocation public vest;

    address public admin;     // ADMIN_ROLE: would call force ops
    address public authority; // grantor: owns the cert, holds + funds the scrip
    address public grantee;   // service provider receiving the vesting award

    function setUp() public {
        admin = makeAddr("admin");
        authority = makeAddr("authority");
        grantee = makeAddr("grantee");

        auth = new BorgAuth(address(this));
        auth.updateRole(admin, auth.ADMIN_ROLE());

        imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        address(new IssuanceManager()),
                        address(new CyberCertPrinter()),
                        address(new TestableCyberScrip())
                    )
                )
            )
        );
        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(address(auth), address(0xC0DE), address(0xBEEF), address(imFactory));

        cert = new MockCertPrinterBasic();
        cert.mockMintCert(0, authority, TOTAL);

        // allocation-authority mode: deploy the vesting scrip with force-ops OFF, and with NO
        // transfer-restriction hooks — the escrow + unlock curve are the lockup.
        ITransferRestrictionHook[] memory noHooks = new ITransferRestrictionHook[](0);
        ICondition[] memory noConds = new ICondition[](0);
        uint256[] memory noIds = new uint256[](0);
        scrip = CyberScrip(
            issuanceManager.deployCyberScrip(
                address(cert), noHooks, noConds, noConds,
                0, 1, 1, noIds, false,
                false, // enableForceTransfer
                false, // enableForceBurn
                false  // enableFreeze
            )
        );

        vm.prank(authority);
        issuanceManager.scripifyCert(address(cert), 0, TOTAL, address(0));
        assertEq(scrip.balanceOf(authority), TOTAL, "authority should hold scrip");

        controller = new MockController(authority);
        BaseAllocation.Allocation memory alloc = BaseAllocation.Allocation({
            tokenStreamTotal: TOTAL,
            vestingCliffCredit: 0,
            unlockingCliffCredit: 0,
            vestingRate: VEST_RATE,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: UNLOCK_RATE,
            unlockStartTime: uint48(block.timestamp),
            tokenContract: address(scrip)
        });
        BaseAllocation.Milestone[] memory ms = new BaseAllocation.Milestone[](0);
        vest = new VestingAllocation(grantee, grantee, address(controller), alloc, ms);

        // Fund escrow (this is what the controller does via safeTransferFrom on signDealAndCreateMetavest).
        vm.prank(authority);
        scrip.transfer(address(vest), TOTAL);
        assertEq(scrip.balanceOf(address(vest)), TOTAL, "escrow funded");
    }

    /// The lockup IS the unlock curve: with vesting faster than unlock, some scrip is earned
    /// (vested) but still locked, and stays in escrow — withdrawable tracks the slower curve.
    function test_lockupViaSlowerUnlockCurve() public {
        vm.warp(block.timestamp + 250);

        // 250s in: 500 earned, only 250 released.
        assertEq(vest.getVestedTokenAmount(), 500 ether, "500 vested (earned)");
        assertEq(vest.getUnlockedTokenAmount(), 250 ether, "250 unlocked (released)");
        assertEq(vest.getAmountWithdrawable(), 250 ether, "withdrawable = min(vested, unlocked)");

        // Grantee can take the unlocked portion...
        vm.prank(grantee);
        vest.withdraw(250 ether);
        assertEq(scrip.balanceOf(grantee), 250 ether, "recipient got unlocked scrip");

        // ...but the 250 that is vested-yet-locked cannot be pulled: it stays in escrow.
        assertEq(vest.getAmountWithdrawable(), 0, "nothing more withdrawable while locked");
        vm.prank(grantee);
        vm.expectRevert(); // MetaVesT_MoreThanAvailable
        vest.withdraw(1);
        assertEq(scrip.balanceOf(address(vest)), TOTAL - 250 ether, "earned-but-locked scrip remains escrowed");
    }

    /// Once both curves complete, the whole grant is withdrawable.
    function test_fullyVestedUnlocked_allWithdrawable() public {
        vm.warp(block.timestamp + 1001); // unlock (slower) finishes at 1000s
        assertEq(vest.getAmountWithdrawable(), TOTAL, "all vested + unlocked");
        vm.prank(grantee);
        vest.withdraw(TOTAL);
        assertEq(scrip.balanceOf(grantee), TOTAL, "recipient holds the full grant");
        assertEq(scrip.balanceOf(address(vest)), 0, "escrow drained");
    }

    /// allocation-authority guarantee: with force-ops disabled at deploy, the issuer cannot
    /// reclaim escrowed scrip by any admin override.
    function test_issuerCannotClawback_forceOpsDisabled() public {
        vm.prank(admin);
        vm.expectRevert(CyberScrip.ComplianceFeatureDisabled.selector);
        issuanceManager.forceScripTransfer(address(cert), address(vest), authority, TOTAL);

        vm.prank(admin);
        vm.expectRevert(CyberScrip.ComplianceFeatureDisabled.selector);
        issuanceManager.setScripFrozen(address(cert), address(vest), true);

        // Force-burn is likewise impossible (the IM's vault accounting reverts before the burn
        // here, but the property — escrow cannot be destroyed — holds).
        vm.prank(admin);
        vm.expectRevert();
        issuanceManager.forceScripBurn(address(cert), address(vest), TOTAL);

        assertEq(scrip.balanceOf(address(vest)), TOTAL, "escrow intact - no clawback possible");
    }
}
