// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {SAFOData, SAFOExtension} from "../src/storage/extensions/SAFOExtension.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {SAFOIntegrationTest} from "./SAFOIntegrationTest.t.sol";

/// @notice Executes the existing signed Reg D/S ticket and round acceptance cases against
/// the actual forked factories, registry, reused libraries and proposed rollout bytecode.
/// The operator harness deploys/upgrades/registers on loopback Anvil before this suite.
/// No source-deployed manager, extension, payment token or registry replaces the targets.
contract SAFORolloutForkTest is SAFOIntegrationTest {
    string internal plan;

    function setUp() public override {
        string memory path = vm.envOr("SAFO_PLAN", string(""));
        if (bytes(path).length == 0) {
            vm.skip(true);
            return;
        }
        plan = vm.readFile(path);
        assertEq(block.chainid, vm.parseJsonUint(plan, ".chainId"));
        registry = CyberAgreementRegistry(vm.parseJsonAddress(plan, ".targets.registry"));
        companyFactory = CyberCorpFactory(vm.parseJsonAddress(plan, ".targets.factory"));
        extension = SAFOExtension(vm.parseJsonAddress(plan, ".addresses.SAFOExtensionProxy"));
        assertEq(address(extension.AUTH()), vm.parseJsonAddress(plan, ".before.auth"));
        usdc = MockPaymentToken(companyFactory.stable());
        assertEq(address(usdc), vm.parseJsonAddress(plan, ".before.paymentToken"));
        assertEq(usdc.decimals(), 6);
        officer = vm.addr(OFFICER_KEY);
        investor = vm.addr(INVESTOR_KEY);
        // These published fixture keys can carry live EIP-7702 delegations. Clear
        // only the two synthetic accounts inside this disposable fork.
        vm.etch(officer, hex"");
        vm.etch(investor, hex"");
        // Test fixture funding changes token storage only inside the disposable fork.
        deal(address(usdc), investor, 20_000e6);
        address rm;
        address dm;
        (corp,,, dm, rm) =
            CyberCorpHelper.deployCorp(companyFactory, "TEST ONLY SAFO rollout acceptance", officer, officer);
        dealManager = DealManager(dm);
        manager = RoundManager(rm);
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(address(uint160(uint256(vm.load(dm, slot)))), vm.parseJsonAddress(plan, ".addresses.DealManager"));
        assertEq(address(uint160(uint256(vm.load(rm, slot)))), vm.parseJsonAddress(plan, ".addresses.RoundManager"));
        vm.prank(investor);
        usdc.approve(rm, type(uint256).max);
        vm.prank(investor);
        usdc.approve(dm, type(uint256).max);
        SAFOData memory terms;
        terms.schemaVersion = 1;
        terms.minProjectReserve = 200_000;
        terms.maxUnlockingCliffPeriod = 365 days;
        terms.maxUnlockingPeriod = 4 * 365 days;
        terms.outsideDateEnabled = true;
        terms.outsideDate = 0;
        payload = extension.encodeExtensionData(terms);
    }

    function test_RejectsInvestorWithNonReceiverCode() public {
        vm.etch(investor, hex"60006000fd");
        (bool success, bytes memory result) =
            address(this).call(abi.encodeCall(this.test_RegD_TicketSignPayFinalizePreservesOriginalIssueDate, ()));
        assertFalse(success);
        assertEq(bytes4(result), bytes4(keccak256("ERC721InvalidReceiver(address)")));
    }

    function _template(bool regS) internal view override returns (bytes32 id) {
        id = regS ? bytes32("mlx_safo_reg_s_v1_1") : bytes32("mlx_safo_reg_d_v1_1");
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(id);
        assertEq(uri, vm.parseJsonString(plan, regS ? ".templates[1].agreementUri" : ".templates[0].agreementUri"));
        assertEq(title, regS ? "mlx_safo_reg_s_v1_1" : "mlx_safo_reg_d_v1_1");
        assertEq(globals.length, 19);
        assertEq(parties.length, 5);
    }

    function _configureFactoryStable() internal view override {
        assertEq(companyFactory.stable(), address(usdc));
    }
}
