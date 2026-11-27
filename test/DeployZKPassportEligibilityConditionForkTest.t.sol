// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    DeployZKPassportEligibilityConditionScript,
    IZKPassportRootVerifierHelpers
} from "../script/deploy-zkpassport-eligibility-condition.s.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {EligibilityRules} from "../src/interfaces/IZKPassportEligibilityCondition.sol";
import {
    IZKPassportEligibilityHelper,
    NullifierType,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";
import {ZKPassportEligibilityCondition} from "../src/libs/conditions/ZKPassportEligibilityCondition.sol";
import {ZKPassportEligibilityConditionFactory} from "../src/libs/conditions/ZKPassportEligibilityConditionFactory.sol";
import {NonUSNationalityConditionHelper} from "./NonUSNationalityConditionForkTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract ZKPassportEligibilityConditionV2ForkMock is ZKPassportEligibilityCondition {
    function forkUpgradeMarker() external pure returns (uint256) {
        return 2026;
    }
}

/// @notice Fork rehearsal tests for DeployZKPassportEligibilityConditionScript against live Base,
///         Ethereum, and Sepolia state (real core BorgAuth, MetaLeX Safe, and live ZKPassportRootVerifier).
/// @dev Skips any chain whose RPC_URL_* env var is unset. Never broadcasts live transactions.
contract DeployZKPassportEligibilityConditionForkTest is Test {
    uint256 internal constant DEPLOYER_KEY = 0xA11CE;
    address internal deployer;

    function setUp() public {
        deployer = vm.addr(DEPLOYER_KEY);
    }

    function _runDeployScript(DeployZKPassportEligibilityConditionScript script)
        internal
        returns (DeployZKPassportEligibilityConditionScript.Deployed memory)
    {
        // Fund ephemeral test deployer on fork so vm.startBroadcast() succeeds locally.
        vm.deal(deployer, 10 ether);
        // Set default sender for script broadcasts inside fork tests.
        vm.setEnv("ETH_FROM", vm.toString(deployer));
        return script.run();
    }

    function _allowGbrUsa21() internal pure returns (EligibilityRules memory) {
        string[] memory allowed = new string[](2);
        allowed[0] = "GBR";
        allowed[1] = "USA";
        return EligibilityRules({
            allowedNationalities: allowed,
            excludedNationalities: new string[](0),
            minimumAge: 21,
            enforceSanctions: false
        });
    }

    function test_Unit_RefusesChainsWithoutZKPassportVerifier() public {
        DeployZKPassportEligibilityConditionScript script = new DeployZKPassportEligibilityConditionScript();

        vm.expectRevert("No ZKPassportVerifier configured on this chain");
        script.configForChain(DeploymentConstants.ARBITRUM);

        vm.expectRevert("No ZKPassportVerifier configured on this chain");
        script.configForChain(DeploymentConstants.BASE_SEPOLIA);
    }

    function test_Fork_Base_DeployVerifyBeaconUpgradeAndLiveVerifierWiring() public {
        string memory rpc = vm.envOr("RPC_URL_BASE", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);

        DeployZKPassportEligibilityConditionScript script = new DeployZKPassportEligibilityConditionScript();
        DeployZKPassportEligibilityConditionScript.Deployed memory deployed = _runDeployScript(script);

        ZKPassportEligibilityConditionFactory factory = ZKPassportEligibilityConditionFactory(deployed.factoryProxy);
        assertFalse(factory.devModeAllowed());
        assertEq(factory.expectedDomain(), "cyberraise.metalex.tech");
        assertEq(address(factory.AUTH()), DeploymentConstants.coreV2(DeploymentConstants.BASE).auth);

        // Re-running script is idempotent and returns identical addresses.
        DeployZKPassportEligibilityConditionScript.Deployed memory second = _runDeployScript(script);
        assertEq(second.conditionImpl, deployed.conditionImpl);
        assertEq(second.factoryImpl, deployed.factoryImpl);
        assertEq(second.factoryProxy, deployed.factoryProxy);

        // Implementation initializers remain disabled.
        address authAddr = address(factory.AUTH());
        EligibilityRules memory initRules = _allowGbrUsa21();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ZKPassportEligibilityCondition(deployed.conditionImpl)
            .initialize(authAddr, "d", "s", address(0), 1 days, false, initRules);

        // Deploy a deterministic GBR/USA 21+ condition through the factory on live Base fork.
        EligibilityRules memory rules = _allowGbrUsa21();
        address predicted = factory.predictConditionAddress(rules, bytes32(0));
        address condAddr = factory.deployCondition(rules, bytes32(0));
        assertEq(condAddr, predicted);
        assertTrue(factory.isCondition(condAddr));

        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(condAddr);
        assertFalse(cond.devModeAllowed());
        assertEq(cond.minimumAge(), 21);
        assertFalse(cond.enforceSanctions());

        // MTLX1-33: caller-selected devMode reverts BEFORE verifier call.
        ProofVerificationParams memory devParams = ProofVerificationParams({
            version: script.REQUIRED_ZKPASSPORT_VERSION(),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(0), proof: hex"", publicInputs: new bytes32[](0)
            }),
            committedInputs: hex"",
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: 1 days,
                domain: cond.expectedDomain(),
                scope: cond.expectedScope(),
                devMode: true
            })
        });
        vm.expectRevert(ZKPassportEligibilityCondition.DevModeProof.selector);
        cond.submitProof(devParams);

        // Live Base v0.21.0 VerifierHelper exists and responds cleanly to getNullifierType.
        address helperAddr =
            IZKPassportRootVerifierHelpers(factory.verifier()).helpers(script.REQUIRED_ZKPASSPORT_VERSION());
        assertTrue(helperAddr != address(0) && helperAddr.code.length > 0);

        // Only MetaLeX Safe (not random caller) can upgrade the beacon implementation.
        ZKPassportEligibilityConditionV2ForkMock v2Impl = new ZKPassportEligibilityConditionV2ForkMock();
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        factory.setImplementation(address(v2Impl));

        address metalexSafe = DeploymentConstants.coreV2(DeploymentConstants.BASE).metalexSafe;
        vm.prank(metalexSafe);
        factory.setImplementation(address(v2Impl));
        assertEq(ZKPassportEligibilityConditionV2ForkMock(condAddr).forkUpgradeMarker(), 2026);
    }

    function test_Fork_Sepolia_DeployVerifyLiveHelperAndRejectPreV021Proof() public {
        string memory rpc = vm.envOr("RPC_URL_SEPOLIA", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);

        DeployZKPassportEligibilityConditionScript script = new DeployZKPassportEligibilityConditionScript();
        DeployZKPassportEligibilityConditionScript.Deployed memory deployed = _runDeployScript(script);

        ZKPassportEligibilityConditionFactory factory = ZKPassportEligibilityConditionFactory(deployed.factoryProxy);
        assertTrue(factory.devModeAllowed());
        assertEq(factory.expectedDomain(), "staging.cyberraise.metalex.tech");

        // Deploy the sample Sepolia condition (GBR/USA, 18+, sanctions=false).
        (address sampleCond, string memory sampleScope) = script.deploySepoliaSampleCondition(deployed.factoryProxy);
        assertTrue(factory.isCondition(sampleCond));
        assertEq(ZKPassportEligibilityCondition(sampleCond).expectedScope(), sampleScope);
        assertTrue(ZKPassportEligibilityCondition(sampleCond).devModeAllowed());

        // Verify live Sepolia v0.21.0 VerifierHelper accepts getNullifierType ABI directly.
        address helperAddr =
            IZKPassportRootVerifierHelpers(factory.verifier()).helpers(script.REQUIRED_ZKPASSPORT_VERSION());
        assertTrue(helperAddr != address(0) && helperAddr.code.length > 0);
        // Public inputs layout has NULLIFIER_TYPE at length - 2 (here 5-element array with 0 = NON_SALTED_NULLIFIER).
        bytes32[] memory syntheticInputs = new bytes32[](5);
        NullifierType nt = IZKPassportEligibilityHelper(helperAddr).getNullifierType(syntheticInputs);
        assertEq(uint8(nt), uint8(NullifierType.NON_SALTED_NULLIFIER));

        // Legacy v0.16.0 proof fixture (no getNullifierType on v0.16.0 helper) must revert cleanly,
        // never bypassing nullifier-type enforcement.
        (ProofVerificationParams memory legacyParams, address account) = NonUSNationalityConditionHelper.parseProofFromJson(
            "test/res/sample-non-us-sanctioned-countries-sanctioned-list-proof-call.json"
        );
        vm.prank(account);
        vm.expectRevert();
        ZKPassportEligibilityCondition(sampleCond).submitProof(legacyParams);
    }

    function test_Fork_EthereumAndBase_ShareIdenticalDeterministicFactoryAddress() public {
        string memory rpcBase = vm.envOr("RPC_URL_BASE", string(""));
        string memory rpcEth = vm.envOr("RPC_URL_ETHEREUM", string(""));
        if (bytes(rpcBase).length == 0 || bytes(rpcEth).length == 0) vm.skip(true);

        DeployZKPassportEligibilityConditionScript script = new DeployZKPassportEligibilityConditionScript();

        vm.createSelectFork(rpcBase);
        DeployZKPassportEligibilityConditionScript.Deployed memory baseDeployed = _runDeployScript(script);

        vm.createSelectFork(rpcEth);
        DeployZKPassportEligibilityConditionScript.Deployed memory ethDeployed = _runDeployScript(script);

        assertEq(ethDeployed.conditionImpl, baseDeployed.conditionImpl);
        assertEq(ethDeployed.factoryImpl, baseDeployed.factoryImpl);
        assertEq(ethDeployed.factoryProxy, baseDeployed.factoryProxy);
    }
}
