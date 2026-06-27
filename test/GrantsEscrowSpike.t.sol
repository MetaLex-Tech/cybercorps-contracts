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
import {VestingAllowlistHook} from "../src/hooks/transfer/VestingAllowlistHook.sol";
import {TestableCyberScrip} from "./mock/TestableCyberScrip.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {VestingAllocation} from "./vendor/metavest/VestingAllocation.sol";
import {BaseAllocation} from "./vendor/metavest/BaseAllocation.sol";

/// Minimal cert printer that satisfies the IssuanceManager scripify path
/// (legalOwnerOf / unitsRepresented), mirroring the existing compliance test.
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

/// Stands in for a MetaVesTController: the allocation only ever reads controller.authority(),
/// and only on authority-gated paths (terminate / confirmMilestone), never on fund+withdraw.
contract MockController {
    address public authority;
    constructor(address _authority) { authority = _authority; }
}

/// P0 spike: prove a CyberScrip can be escrowed in a MetaVesT VestingAllocation, vest over
/// time, and be withdrawn to the recipient through the scrip's restriction hook — and that
/// under allocation-authority mode (force-ops disabled at deploy) the issuer cannot claw it back.
contract GrantsEscrowSpike is Test {
    bytes32 private constant SALT = keccak256("GrantsEscrowSpike");
    uint256 private constant TOTAL = 1000 ether;
    uint160 private constant RATE = 1e18; // tokens/sec -> fully vests in 1000s; within [100, 1000e18]

    BorgAuth public auth;
    IssuanceManager public issuanceManager;
    IssuanceManagerFactory public imFactory;
    MockCertPrinterBasic public cert;
    CyberScrip public scrip;
    VestingAllowlistHook public hook;
    MockController public controller;
    VestingAllocation public vest;

    address public admin;     // ADMIN_ROLE: configures the hook + would call force ops
    address public authority; // grantor: owns the cert, holds + funds the scrip
    address public grantee;   // service provider receiving the vesting award

    function setUp() public {
        admin = makeAddr("admin");
        authority = makeAddr("authority");
        grantee = makeAddr("grantee");

        // Auth: this test contract is OWNER (deploys scrip); admin gets ADMIN_ROLE.
        auth = new BorgAuth(address(this));
        auth.updateRole(admin, auth.ADMIN_ROLE());

        // IssuanceManager via its factory (mirrors IssuanceManagerScripComplianceTest).
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

        // Cert held by the authority, with units to scripify.
        cert = new MockCertPrinterBasic();
        cert.mockMintCert(0, authority, TOTAL);

        // Restriction hook (enabled on init). Authority must be an escrow party so the
        // scripify mint (to = authority) and later funding leg (from = authority) pass.
        hook = new VestingAllowlistHook();
        hook.initialize(address(auth));
        vm.prank(admin);
        hook.setEscrowParty(authority, true);

        // allocation-authority mode: deploy the vesting scrip with ALL force powers OFF.
        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](1);
        hooks[0] = ITransferRestrictionHook(address(hook));
        ICondition[] memory noConds = new ICondition[](0);
        uint256[] memory noIds = new uint256[](0);
        scrip = CyberScrip(
            issuanceManager.deployCyberScrip(
                address(cert), hooks, noConds, noConds,
                0, 1, 1, noIds, false,
                false, // enableForceTransfer
                false, // enableForceBurn
                false  // enableFreeze
            )
        );

        // Mint scrip to the authority by scripifying the cert (1:1).
        vm.prank(authority);
        issuanceManager.scripifyCert(address(cert), 0, TOTAL, address(0));
        assertEq(scrip.balanceOf(authority), TOTAL, "authority should hold scrip");

        // Deploy the vesting allocation and register it as an escrow party (needed for BOTH
        // the funding leg's `to` and the withdraw leg's `from`).
        controller = new MockController(authority);
        BaseAllocation.Allocation memory alloc = BaseAllocation.Allocation({
            tokenStreamTotal: TOTAL,
            vestingCliffCredit: 0,
            unlockingCliffCredit: 0,
            vestingRate: RATE,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: RATE,
            unlockStartTime: uint48(block.timestamp),
            tokenContract: address(scrip)
        });
        BaseAllocation.Milestone[] memory ms = new BaseAllocation.Milestone[](0);
        vest = new VestingAllocation(grantee, grantee, address(controller), alloc, ms);
        vm.prank(admin);
        hook.setEscrowParty(address(vest), true);

        // Fund escrow (this is what the controller does via safeTransferFrom on signDealAndCreateMetavest).
        vm.prank(authority);
        scrip.transfer(address(vest), TOTAL);
        assertEq(scrip.balanceOf(address(vest)), TOTAL, "escrow should be funded");
    }

    /// Core proof: vested scrip can be withdrawn to the recipient through the restriction hook.
    function test_fundVestWithdraw_throughHook() public {
        assertEq(vest.getAmountWithdrawable(), 0, "nothing withdrawable at t0");

        vm.warp(block.timestamp + 500);
        uint256 w = vest.getAmountWithdrawable();
        assertEq(w, 500 ether, "half should be withdrawable at t+500s");

        vm.prank(grantee);
        vest.withdraw(w);
        assertEq(scrip.balanceOf(grantee), w, "recipient received vested scrip through the hook");
        assertEq(scrip.balanceOf(address(vest)), TOTAL - w, "remainder stays escrowed");
    }

    /// The hook blocks the recipient from re-selling still-restricted scrip to a third party.
    function test_publicResaleBlocked() public {
        vm.warp(block.timestamp + 500);
        vm.prank(grantee);
        vest.withdraw(500 ether);

        address outsider = makeAddr("outsider");
        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(CyberScrip.RestrictedTransfer.selector, "scrip locked: vesting escrow only"));
        scrip.transfer(outsider, 1);
    }

    /// allocation-authority guarantee: with force-ops disabled at deploy, the issuer cannot
    /// reclaim escrowed scrip by any admin override.
    function test_issuerCannotClawback_forceOpsDisabled() public {
        // Primary clawback vector: force-transfer escrowed scrip back to the issuer.
        vm.prank(admin);
        vm.expectRevert(CyberScrip.ComplianceFeatureDisabled.selector);
        issuanceManager.forceScripTransfer(address(cert), address(vest), authority, TOTAL);

        // Freeze the escrow account: blocked by the disabled flag.
        vm.prank(admin);
        vm.expectRevert(CyberScrip.ComplianceFeatureDisabled.selector);
        issuanceManager.setScripFrozen(address(cert), address(vest), true);

        // Burn the escrow: also impossible with force-burn disabled (the IM's vault accounting
        // reverts before the burn here, but the property — escrow cannot be destroyed — holds).
        vm.prank(admin);
        vm.expectRevert();
        issuanceManager.forceScripBurn(address(cert), address(vest), TOTAL);

        // Escrow is untouched after every clawback attempt.
        assertEq(scrip.balanceOf(address(vest)), TOTAL, "escrow intact - no clawback possible");
    }

    /// The "register the allocation as an escrow party" step is load-bearing for the WITHDRAW
    /// leg: if the allocation is not an escrow party, allocation -> grantee fails the hook
    /// (neither endpoint is allowlisted), so vested tokens cannot be released.
    function test_withdrawBlockedIfAllocationNotAllowlisted() public {
        vm.warp(block.timestamp + 500);
        assertEq(vest.getAmountWithdrawable(), 500 ether, "tokens are vested");

        // De-register the allocation, simulating a grant whose post-deploy registration was skipped.
        vm.prank(admin);
        hook.setEscrowParty(address(vest), false);

        // The hook blocks allocation -> grantee. NB: MetaVesT's withdraw routes through its inline
        // SafeTransferLib, which masks the scrip's RestrictedTransfer reason as a generic
        // TransferFailed() — a UX/diagnostics consideration for the frontend.
        vm.prank(grantee);
        vm.expectRevert();
        vest.withdraw(500 ether);

        assertEq(scrip.balanceOf(grantee), 0, "no tokens released while allocation de-allowlisted");
        assertEq(scrip.balanceOf(address(vest)), TOTAL, "escrow intact");
    }
}
