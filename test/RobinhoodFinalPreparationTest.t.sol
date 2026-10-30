// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {DeploymentUtils} from "../script/libs/DeploymentUtils.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {UpgradeV5Script} from "../script/upgrade-v5.s.sol";

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";

import {ZKPassportConditionLib, ZKPassportConfig} from "../src/libs/ZKPassportConditionLib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {KillSwitchCondition} from "../src/libs/conditions/secondary/KillSwitchCondition.sol";
import "forge-std/Test.sol";

interface IFinalRobinhoodFactory {
    function AUTH() external view returns (BorgAuth);
    function registryAddress() external view returns (address);
    function uriBuilder() external view returns (address);
    function issuanceManagerFactory() external view returns (address);
    function cyberCorpSingleFactory() external view returns (address);
    function dealManagerFactory() external view returns (address);
    function roundManagerFactory() external view returns (address);
    function stable() external view returns (address);
}

contract RobinhoodFinalPreparationTest is Test {
    function test_MainnetUsesSharedBadgeAndExistingKillSwitch() public pure {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(4663);
        assertEq(core.lexchexBadgeAuth, 0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d);
        assertEq(core.lexchexBadge, 0x114664773Ba721a6AA43890d5FDE7939aF37618F);
        assertEq(DeploymentConstants.secondaryConditions(4663).killSwitch, 0x456EDAfB7283dB8FDa2A5b3ecE576d9292512435);
    }

    function test_SafeJsonWorksWithInstalledFoundry() public {
        GnosisTransaction[] memory calls = new GnosisTransaction[](2);
        calls[0] = GnosisTransaction(address(0x1234), 7, hex"12345678");
        calls[1] = GnosisTransaction(address(0x5678), 0, bytes(""));
        string memory json = DeploymentUtils.formatSafeTxJson(calls, 4663);
        assertEq(vm.parseJsonString(json, ".chainId"), "4663");
        assertEq(vm.parseJsonUint(json, ".createdAt"), block.timestamp * 1000);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), calls[0].to);
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "7");
        assertEq(vm.parseJsonBytes(json, ".transactions[0].data"), calls[0].data);
        assertEq(vm.parseJsonString(json, ".transactions[1].value"), "0");
        assertEq(vm.parseJsonBytes(json, ".transactions[1].data"), bytes(""));
    }

    function test_ForkFinalUpgradeFromObservedRobinhoodState() public {
        string memory rpc = vm.envOr("ROBINHOOD_FINAL_FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, 101730171);
        assertEq(block.chainid, 4663);
        uint256 toyKey = 0xA11CE;
        vm.setEnv("PRIVATE_KEY_MAIN", vm.toString(toyKey));
        vm.deal(vm.addr(toyKey), 100 ether);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        address killAddress = DeploymentConstants.secondaryConditions(block.chainid).killSwitch;
        address metalexAdmin = KillSwitchCondition(killAddress).metalexAdmin();
        address legionAdmin = KillSwitchCondition(killAddress).legionAdmin();
        bytes32 killCodeHash = killAddress.codehash;
        (new UpgradeV5Script()).run();
        IFinalRobinhoodFactory factory = IFinalRobinhoodFactory(core.cyberCorpFactory);
        assertEq(address(factory.AUTH()), core.auth);
        assertEq(factory.registryAddress(), core.cyberAgreementRegistry);
        assertEq(factory.uriBuilder(), core.uriBuilder);
        assertEq(factory.issuanceManagerFactory(), core.issuanceManagerFactory);
        assertEq(factory.cyberCorpSingleFactory(), core.cyberCorpSingleFactory);
        assertEq(factory.dealManagerFactory(), core.dealManagerFactory);
        assertEq(factory.roundManagerFactory(), core.roundManagerFactory);
        assertEq(factory.stable(), 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168);
        assertEq(DealManagerFactory(core.dealManagerFactory).getUnderlyingDefaultFeeRatio(), 50);
        assertEq(DealManagerFactory(core.dealManagerFactory).getUnderlyingDefaultSecondaryFeeRatio(), 500);
        assertTrue(CertificateUriBuilder(core.uriBuilder).imageBuilder() != address(0));
        assertEq(killAddress.codehash, killCodeHash);
        assertEq(KillSwitchCondition(killAddress).metalexAdmin(), metalexAdmin);
        assertEq(KillSwitchCondition(killAddress).legionAdmin(), legionAdmin);
        assertFalse(KillSwitchCondition(killAddress).killed());
        assertGe(BorgAuth(core.auth).userRoles(core.metalexSafe), 99);
        assertGe(BorgAuth(core.lexchexAuth).userRoles(core.metalexSafe), 99);
        assertGe(BorgAuth(core.lexchexBadgeAuth).userRoles(core.metalexSafe), 99);
        ZKPassportConfig memory config = abi.decode(
            CyberAgreementRegistry(core.cyberAgreementRegistry).getSignerConditionConfig(ZKPassportConditionLib.KIND),
            (ZKPassportConfig)
        );
        assertEq(config.verifier, core.zkpassportVerifier);
        assertEq(config.domain, "app.metalex.tech");
        assertEq(config.scope, "cyberagreement-passport");
        assertFalse(config.devMode);
    }
}
