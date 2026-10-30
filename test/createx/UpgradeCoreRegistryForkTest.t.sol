// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../../script/libs/safe.sol";
import {UpgradeCoreScript} from "../../script/upgrade-core.s.sol";
import {CyberAgreementRegistry} from "../../src/CyberAgreementRegistry.sol";
import {ZKPassportConditionLib, ZKPassportConfig} from "../../src/libs/ZKPassportConditionLib.sol";
import "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @dev Runs only the CyberAgreementRegistry part of `UpgradeCoreScript`.
contract UpgradeCoreRegistryHarness is UpgradeCoreScript {
    function runRegistryWithArgs(uint256 chainId, uint256 deployerPrivateKey)
        public
        returns (GnosisTransaction[] memory)
    {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        upgradeCyberAgreementRegistry(chainId, core);
        return safeTxs;
    }
}

/// @notice `UpgradeCoreScript` upgrades CyberAgreementRegistry and sets its ZKPassport config in the Safe batch,
///         and a second run after the Safe signed the batch finds nothing to do.
/// @dev The fork is pinned, so the first run always finds the same changes.
contract UpgradeCoreRegistryForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 26_045_574;
    uint256 internal deployerKey = 0xA11CE;
    address internal deployer = vm.addr(0xA11CE);
    DeploymentConstants.CoreDeployment internal core;

    function setUp() public {
        vm.createSelectFork("ethereum", PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        core = DeploymentConstants.coreV2(block.chainid);
    }

    function test_UpgradeAndZKPassportConfigInSafeBatch_SecondRunDoesNothing() public {
        // Run 1: the deployer holds no role on mainnet, so the upgrade and the config go to the Safe, in this order.
        GnosisTransaction[] memory safeTxs =
            (new UpgradeCoreRegistryHarness()).runRegistryWithArgs(block.chainid, deployerKey);
        assertEq(safeTxs.length, 2);
        assertEq(safeTxs[0].to, core.cyberAgreementRegistry);
        assertEq(bytes4(safeTxs[0].data), UUPSUpgradeable.upgradeToAndCall.selector);
        assertEq(safeTxs[1].to, core.cyberAgreementRegistry);
        assertEq(bytes4(safeTxs[1].data), CyberAgreementRegistry.setSignerConditionConfig.selector);
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(core.metalexSafe);
            (bool success,) = safeTxs[i].to.call(safeTxs[i].data);
            assertTrue(success);
        }

        ZKPassportConfig memory config = abi.decode(
            CyberAgreementRegistry(core.cyberAgreementRegistry).getSignerConditionConfig(ZKPassportConditionLib.KIND),
            (ZKPassportConfig)
        );
        assertEq(config.verifier, core.zkpassportVerifier);
        assertEq(config.domain, "app.metalex.tech");
        assertEq(config.scope, "cyberagreement-passport");
        assertFalse(config.devMode);

        // Run 2: the implementation and the config are unchanged, so nothing is sent or queued.
        uint256 nonce = vm.getNonce(deployer);
        safeTxs = (new UpgradeCoreRegistryHarness()).runRegistryWithArgs(block.chainid, deployerKey);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(safeTxs.length, 0);
    }
}
