// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../../script/libs/safe.sol";
import {DeployBuildersScript} from "../../script/deploy-builders.s.sol";
import {CertificateUriBuilder} from "../../src/CertificateUriBuilder.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/Test.sol";

/// @notice `DeployBuildersScript` switches the URI implementation and the image builder in one Safe call, and a
///         second run after the Safe signed the batch finds nothing to deploy.
/// @dev The fork is pinned, so the first run always finds the same changes.
contract DeployBuildersScriptForkTest is Test {
    uint256 internal constant PINNED_BLOCK = 26_045_574;
    uint256 internal deployerKey = 0xA11CE;
    address internal deployer = vm.addr(0xA11CE);
    address internal safe;
    CertificateUriBuilder internal uriBuilder;

    function setUp() public {
        vm.createSelectFork("ethereum", PINNED_BLOCK);
        vm.deal(deployer, 100 ether);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        safe = core.metalexSafe;
        uriBuilder = CertificateUriBuilder(core.uriBuilder);
    }

    /// @notice Case 4, then case 1 on the rerun.
    function test_OneSafeCallSwitchesBothBuildersAndSecondRunDeploysNothing() public {
        address oldUriImplementation = _uriImplementation();
        address oldImageBuilder = uriBuilder.imageBuilder();

        // Run 1: the deployer holds no role on mainnet, so the switch goes to the Safe as one call.
        GnosisTransaction[] memory safeTxs = (new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(safeTxs.length, 1);
        assertEq(safeTxs[0].to, address(uriBuilder));
        assertEq(bytes4(safeTxs[0].data), UUPSUpgradeable.upgradeToAndCall.selector);
        _executeAsSafe(safeTxs);
        assertNotEq(_uriImplementation(), oldUriImplementation);
        assertNotEq(uriBuilder.imageBuilder(), oldImageBuilder);

        // Run 2: both parts already have the current code.
        uint256 nonce = vm.getNonce(deployer);
        safeTxs = (new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(safeTxs.length, 0);
    }

    /// @notice Case 2: when the URI implementation already has the current code, the Safe sets the image builder only.
    function test_CurrentUriImplementationOnlySetsTheImageBuilder() public {
        address oldImageBuilder = uriBuilder.imageBuilder();
        _executeAsSafe((new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey));
        address uriImplementation = _uriImplementation();
        vm.prank(safe);
        uriBuilder.setImageBuilder(oldImageBuilder);

        GnosisTransaction[] memory safeTxs = (new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(safeTxs.length, 1);
        assertEq(bytes4(safeTxs[0].data), CertificateUriBuilder.setImageBuilder.selector);
        _executeAsSafe(safeTxs);
        assertEq(_uriImplementation(), uriImplementation);
        assertNotEq(uriBuilder.imageBuilder(), oldImageBuilder);
    }

    /// @notice Case 3: when the image builder already has the current code, the upgrade does not set it again.
    function test_CurrentImageBuilderOnlyUpgradesTheUriImplementation() public {
        address oldUriImplementation = _uriImplementation();
        _executeAsSafe((new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey));
        address image = uriBuilder.imageBuilder();
        vm.prank(safe);
        UUPSUpgradeable(address(uriBuilder)).upgradeToAndCall(oldUriImplementation, "");

        GnosisTransaction[] memory safeTxs = (new DeployBuildersScript()).runWithArgs(block.chainid, deployerKey);
        assertEq(safeTxs.length, 1);
        _executeAsSafe(safeTxs);
        assertNotEq(_uriImplementation(), oldUriImplementation);
        assertEq(safeTxs[0].data, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (_uriImplementation(), "")));
        assertEq(uriBuilder.imageBuilder(), image);
    }

    function _executeAsSafe(GnosisTransaction[] memory safeTxs) internal {
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(safe);
            (bool success,) = safeTxs[i].to.call(safeTxs[i].data);
            assertTrue(success);
        }
    }

    function _uriImplementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(uriBuilder), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }
}
