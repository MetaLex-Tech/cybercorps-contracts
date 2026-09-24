// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentScript} from "../../script/libs/DeploymentScript.sol";
import {DeploymentUtils} from "../../script/libs/DeploymentUtils.sol";
import {GnosisTransaction} from "../../script/libs/safe.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {EligibilityCondition} from "../../src/libs/conditions/secondary/EligibilityCondition.sol";
import {HolderCapCondition} from "../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {KillSwitchCondition} from "../../src/libs/conditions/secondary/KillSwitchCondition.sol";
import "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev The steps broadcast from the deployer key, so CreateX and the auths see the deployer EOA as `msg.sender`.
///      `deployCreate3` calls the library without a broadcast, so there the harness is the sender.
contract DeploymentScriptHarness is DeploymentScript {
    function init(uint256 deployerPrivateKey, address safe_) external {
        initDeployment("[test]", block.chainid, deployerPrivateKey, safe_);
    }

    function initWithChainId(uint256 chainId, uint256 deployerPrivateKey, address safe_) external {
        initDeployment("[test]", chainId, deployerPrivateKey, safe_);
    }

    function deployCreate3(address deployer_, string memory saltStr, bytes memory initCode) external returns (address) {
        return DeploymentUtils.deployCreate3(deployer_, saltStr, initCode);
    }

    function deployIfNotExistStep(string memory saltPrefix, string memory name, address existing, bytes memory initCode)
        external
        returns (address, bool)
    {
        return deployIfNotExist("[test]", saltPrefix, name, existing, initCode);
    }

    function proxyStep(
        address auth,
        string memory saltPrefix,
        string memory name,
        address existing,
        address implementation,
        bytes memory initCall
    ) external returns (address, bool) {
        return upgradeOrDeployProxyIfDiffImpl(auth, saltPrefix, name, existing, implementation, initCall);
    }

    function proxyWithCodeStep(
        address auth,
        string memory saltPrefix,
        string memory name,
        address existing,
        bytes memory creationCode,
        bytes memory initCall
    ) external returns (address, bool) {
        return upgradeOrDeployProxyIfDiffImpl(auth, saltPrefix, name, existing, creationCode, initCall);
    }

    function executeStep(address auth, address to, bytes memory data) external returns (bool) {
        return execute("[test]", auth, to, data, "test call");
    }

    function upgradeProxyStep(address auth, address proxy, address implementation) external {
        upgradeProxy("[test]", auth, proxy, "test proxy", implementation);
    }

    function upgradeProxyWithCodeStep(address auth, address proxy, bytes memory creationCode) external {
        upgradeProxy(auth, proxy, "test proxy", creationCode);
    }

    function handOffStep(address auth) external {
        handOffAuthOwner("[test]", auth, "test AUTH");
    }

    function deployIfDifferentStep(string memory name, bytes memory creationCode, address current)
        external
        returns (address, bool)
    {
        return deployIfDifferent("[test]", name, creationCode, current);
    }

    function finishStep(string memory jsonPath) external {
        finish("[test]", jsonPath);
    }

    function safeTxsOf() external view returns (GnosisTransaction[] memory) {
        return safeTxs;
    }
}

/// @notice Checks `DeploymentScript` and the CREATE3 helpers of `DeploymentUtils` against the live CreateX.
contract DeploymentScriptForkTest is Test {
    string[4] internal chains = ["ethereum", "base", "sepolia", "base_sepolia"];
    uint256[4] internal forks;

    /// @dev The harness has the same address on each chain, so it acts as one deployer.
    DeploymentScriptHarness internal harness = DeploymentScriptHarness(makeAddr("harness"));
    address internal safe = makeAddr("safe");
    uint256 internal deployerKey = 0xA11CE;
    address internal deployer = vm.addr(0xA11CE);

    string internal constant JSON_PATH = "script/res/test-deployment-script.json";

    function setUp() public {
        // DeploymentScript uses cheatcodes: it computes addresses, broadcasts and runs the Safe calls with a prank.
        vm.allowCheatcodes(address(harness));
        for (uint256 i = 0; i < chains.length; i++) {
            forks[i] = vm.createFork(chains[i]);
            vm.selectFork(forks[i]);
            vm.etch(address(harness), type(DeploymentScriptHarness).runtimeCode);
            harness.init(deployerKey, safe);
        }
    }

    // ---- CREATE3 ----

    /// @dev Each chain gets different admin keys, so the init code differs.
    function test_KillSwitchSameAddressOnEveryChain() public {
        address first;
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address metalexAdmin = makeAddr(string.concat("metalex-", chains[i]));
            address legionAdmin = makeAddr(string.concat("legion-", chains[i]));

            KillSwitchCondition killSwitch = KillSwitchCondition(
                harness.deployCreate3(address(harness), "kill switch", _killSwitchInitCode(metalexAdmin, legionAdmin))
            );

            if (i == 0) first = address(killSwitch);
            assertEq(address(killSwitch), first, chains[i]);
            assertEq(address(killSwitch), _expectedFor(address(harness), "kill switch"), chains[i]);
            assertEq(killSwitch.metalexAdmin(), metalexAdmin, chains[i]);
            assertEq(killSwitch.legionAdmin(), legionAdmin, chains[i]);
        }
    }

    function test_DifferentSaltGivesDifferentAddress() public {
        vm.selectFork(forks[0]);
        bytes memory initCode = _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"));
        address a = harness.deployCreate3(address(harness), "salt a", initCode);
        address b = harness.deployCreate3(address(harness), "salt b", initCode);
        assertNotEq(a, b);
    }

    /// @dev This is the case of a script that calls CreateX outside the deployer's broadcast.
    function test_RevertWhen_SenderIsNotDeployer() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            bytes memory initCode = _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"));
            vm.expectPartialRevert(DeploymentUtils.Create3AddressMismatch.selector);
            harness.deployCreate3(makeAddr("deployer"), "kill switch", initCode);
        }
    }

    function test_RevertWhen_CreateXCodeDiffers() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            vm.etch(DeploymentUtils.CREATEX, hex"00");
            bytes memory initCode = _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"));
            vm.expectRevert(
                abi.encodeWithSelector(DeploymentUtils.CreateXCodeHashMismatch.selector, keccak256(hex"00"))
            );
            harness.deployCreate3(address(harness), "kill switch", initCode);
        }
    }

    /// @dev A second CREATE2 of the helper collides and uses all the gas that it gets, so the call has a gas limit.
    function test_RevertWhen_SaltIsUsedTwice() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            bytes memory initCode = _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"));
            harness.deployCreate3(address(harness), "kill switch", initCode);

            vm.expectRevert(abi.encodeWithSignature("FailedContractCreation(address)", DeploymentUtils.CREATEX));
            harness.deployCreate3{gas: 5_000_000}(address(harness), "kill switch", initCode);
        }
    }

    function test_RevertWhen_ConstructorReverts() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address admin = makeAddr("admin");
            bytes memory initCode = _killSwitchInitCode(admin, admin);
            vm.expectRevert(abi.encodeWithSignature("FailedContractCreation(address)", DeploymentUtils.CREATEX));
            harness.deployCreate3(address(harness), "kill switch", initCode);
        }
    }

    // ---- deployOrExisting / proxy steps ----

    function test_DeployIfNotExist_NewThenExisting() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            bytes memory initCode = _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"));
            address expected = _expected("prefix/KillSwitchCondition");

            (address deployed, bool isNew) =
                harness.deployIfNotExistStep("prefix", "KillSwitchCondition", address(0), initCode);
            assertEq(deployed, expected, chains[i]);
            assertTrue(isNew, chains[i]);
            assertGt(expected.code.length, 0, chains[i]);

            // A second run with the existing address keeps the contract. An empty init code shows that nothing deploys.
            (deployed, isNew) = harness.deployIfNotExistStep("prefix", "KillSwitchCondition", expected, "");
            assertEq(deployed, expected, chains[i]);
            assertFalse(isNew, chains[i]);
        }
    }

    /// @dev A CREATE2 address is not checked, so it passes through.
    function test_DeployIfNotExist_KeepsCreate2Address() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address create2Address = makeAddr("create2 address");
            (address deployed, bool isNew) =
                harness.deployIfNotExistStep("prefix", "KillSwitchCondition", create2Address, "");
            assertEq(deployed, create2Address, chains[i]);
            assertFalse(isNew, chains[i]);
        }
    }

    /// @dev After a CREATE3 deployment, an existing address that differs, or a zero one, is a wrong configuration.
    function test_RevertWhen_ExistingIsNotTheDeployedCreate3Address() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address expected = _expected("prefix/KillSwitchCondition");
            harness.deployIfNotExistStep(
                "prefix",
                "KillSwitchCondition",
                address(0),
                _killSwitchInitCode(makeAddr("metalex"), makeAddr("legion"))
            );

            address wrong = makeAddr("wrong");
            vm.expectRevert(
                abi.encodeWithSelector(DeploymentUtils.ExistingCreate3AddressMismatch.selector, wrong, expected)
            );
            harness.deployIfNotExistStep("prefix", "KillSwitchCondition", wrong, "");

            vm.expectRevert(
                abi.encodeWithSelector(DeploymentUtils.ExistingCreate3AddressMismatch.selector, address(0), expected)
            );
            harness.deployIfNotExistStep("prefix", "KillSwitchCondition", address(0), "");
        }
    }

    /// @dev The address is the same on all chains, so DeploymentConstants can list it for a chain that does not have the contract yet.
    function test_RevertWhen_ExistingCreate3AddressHasNoCode() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address expected = _expected("prefix/KillSwitchCondition");
            vm.expectRevert(abi.encodeWithSelector(DeploymentUtils.ExistingCreate3AddressHasNoCode.selector, expected));
            harness.deployIfNotExistStep("prefix", "KillSwitchCondition", expected, "");
        }
    }

    /// @dev The deployer owns the auth, so it upgrades the existing proxy itself.
    function test_UpgradeOrDeployProxy_NewThenDirectUpgrade() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address auth = address(new BorgAuth(deployer));
            address implA = address(new EligibilityCondition());
            bytes memory initCall = abi.encodeCall(EligibilityCondition.initialize, (auth));

            (address proxy, bool isNew) =
                harness.proxyStep(auth, "prefix", "EligibilityCondition", address(0), implA, initCall);
            assertEq(proxy, _expected("prefix/EligibilityCondition"), chains[i]);
            assertTrue(isNew, chains[i]);
            assertEq(_implementation(proxy), implA, chains[i]);

            address implB = address(new EligibilityCondition());
            address again;
            (again, isNew) = harness.proxyStep(auth, "prefix", "EligibilityCondition", proxy, implB, initCall);
            assertEq(again, proxy, chains[i]);
            assertFalse(isNew, chains[i]);
            assertEq(_implementation(proxy), implB, chains[i]);
            assertEq(harness.safeTxsOf().length, 0, chains[i]);
        }
    }

    /// @dev The code version deploys the implementation only when its code differs from the proxy's.
    function test_UpgradeOrDeployProxy_WithCode() public {
        vm.selectFork(forks[0]);
        address auth = address(new BorgAuth(deployer));
        bytes memory initCall = abi.encodeCall(EligibilityCondition.initialize, (auth));
        (address proxy, bool isNew) = harness.proxyWithCodeStep(
            auth, "prefix", "EligibilityCondition", address(0), type(EligibilityCondition).creationCode, initCall
        );
        assertTrue(isNew);
        address implementation = _implementation(proxy);

        uint256 nonce = vm.getNonce(deployer);
        (, isNew) = harness.proxyWithCodeStep(
            auth, "prefix", "EligibilityCondition", proxy, type(EligibilityCondition).creationCode, initCall
        );
        assertFalse(isNew);
        assertEq(_implementation(proxy), implementation);
        assertEq(vm.getNonce(deployer), nonce);

        harness.proxyWithCodeStep(
            auth, "prefix", "EligibilityCondition", proxy, type(HolderCapCondition).creationCode, initCall
        );
        assertNotEq(_implementation(proxy), implementation);
        assertEq(harness.safeTxsOf().length, 0);
    }

    /// @dev The Safe owns the auth, so the upgrade of the existing proxy goes to the Safe.
    function test_UpgradeOrDeployProxy_SafeUpgrade() public {
        vm.selectFork(forks[0]);
        (address auth, address proxy, address implementation) = _proxyOwnedBy(safe);

        (, bool isNew) = harness.proxyWithCodeStep(
            auth, "prefix", "EligibilityCondition", proxy, type(HolderCapCondition).creationCode, ""
        );
        assertFalse(isNew);
        assertEq(_implementation(proxy), implementation);
        GnosisTransaction[] memory txs = harness.safeTxsOf();
        assertEq(txs.length, 1);
        assertEq(txs[0].to, proxy);
    }

    function test_RevertWhen_ExistingProxyIsNotTheDeployedCreate3Address() public {
        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            address auth = address(new BorgAuth(deployer));
            address impl = address(new EligibilityCondition());
            bytes memory initCall = abi.encodeCall(EligibilityCondition.initialize, (auth));
            (address proxy,) = harness.proxyStep(auth, "prefix", "EligibilityCondition", address(0), impl, initCall);

            address wrong = makeAddr("wrong");
            vm.expectRevert(
                abi.encodeWithSelector(DeploymentUtils.ExistingCreate3AddressMismatch.selector, wrong, proxy)
            );
            harness.proxyStep(auth, "prefix", "EligibilityCondition", wrong, impl, initCall);
        }
    }

    // ---- execute / upgrade / finish ----
    // These steps do not use CreateX, so they run on one chain.

    function test_Execute_DeployerIsOwner_SendsNow() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(deployer);
        address user = makeAddr("user");

        assertTrue(harness.executeStep(address(auth), address(auth), abi.encodeCall(BorgAuth.updateRole, (user, 98))));
        assertEq(auth.userRoles(user), 98);
        assertEq(harness.safeTxsOf().length, 0);
    }

    function test_Execute_DeployerIsNotOwner_QueuesForSafe() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(safe);
        address user = makeAddr("user");
        bytes memory data = abi.encodeCall(BorgAuth.updateRole, (user, 98));

        assertFalse(harness.executeStep(address(auth), address(auth), data));
        assertEq(auth.userRoles(user), 0);
        GnosisTransaction[] memory txs = harness.safeTxsOf();
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(auth));
        assertEq(txs[0].data, data);
    }

    /// @dev `finish` runs the queued upgrade as the Safe, then writes the batch.
    function test_Upgrade_Queued_FinishRunsItAsSafe() public {
        vm.selectFork(forks[0]);
        (address auth, address proxy, address implA) = _proxyOwnedBy(safe);
        address implB = address(new EligibilityCondition());

        harness.upgradeProxyStep(auth, proxy, implB);
        assertEq(_implementation(proxy), implA);

        harness.finishStep(JSON_PATH);
        assertEq(_implementation(proxy), implB);

        DeploymentUtils.SafeTxImport memory batch = DeploymentUtils.parseSafeTxJson(vm.readFile(JSON_PATH));
        vm.removeFile(JSON_PATH);
        assertEq(batch.transactions.length, 1);
        assertEq(batch.transactions[0].to, proxy);
        assertEq(batch.transactions[0].data, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implB, "")));
    }

    /// @dev A Safe call that fails in the simulation stops the script before it broadcasts anything.
    function test_RevertWhen_SafeCallFails() public {
        vm.selectFork(forks[0]);
        (address auth, address proxy,) = _proxyOwnedBy(makeAddr("other owner"));
        address implB = address(new EligibilityCondition());

        harness.upgradeProxyStep(auth, proxy, implB);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, safe));
        harness.finishStep(JSON_PATH);
    }

    function test_Finish_NoSafeTxs_WritesNothing() public {
        vm.selectFork(forks[0]);
        harness.finishStep(JSON_PATH);
        assertFalse(vm.exists(JSON_PATH));
    }

    // ---- deployIfDifferent / upgradeProxy ----

    /// @dev The second call finds the same code. Only the own address in the `__self` immutable differs.
    function test_DeployIfDifferent_UnchangedCodeKeepsCurrent() public {
        vm.selectFork(forks[0]);
        bytes memory code = type(EligibilityCondition).creationCode;
        (address first, bool isNew) = harness.deployIfDifferentStep("EligibilityCondition", code, address(0));
        assertTrue(isNew);
        assertGt(first.code.length, 0);

        uint256 nonce = vm.getNonce(deployer);
        address kept;
        (kept, isNew) = harness.deployIfDifferentStep("EligibilityCondition", code, first);
        assertEq(kept, first);
        assertFalse(isNew);
        assertEq(vm.getNonce(deployer), nonce);
    }

    function test_DeployIfDifferent_ChangedCodeDeploysNew() public {
        vm.selectFork(forks[0]);
        (address current,) =
            harness.deployIfDifferentStep("HolderCapCondition", type(HolderCapCondition).creationCode, address(0));

        (address deployed, bool isNew) =
            harness.deployIfDifferentStep("EligibilityCondition", type(EligibilityCondition).creationCode, current);
        assertTrue(isNew);
        assertNotEq(deployed, current);
        assertEq(deployed, vm.computeCreateAddress(deployer, vm.getNonce(deployer) - 1));
    }

    /// @dev A proxy that already uses the implementation needs no upgrade, so nothing goes to the Safe.
    function test_Upgrade_SameImplementationSkips() public {
        vm.selectFork(forks[0]);
        (address auth, address proxy, address implementation) = _proxyOwnedBy(safe);

        harness.upgradeProxyStep(auth, proxy, implementation);
        assertEq(harness.safeTxsOf().length, 0);
    }

    /// @dev The overload that takes creation code deploys only when the code differs from the proxy's.
    function test_UpgradeProxy_WithCode() public {
        vm.selectFork(forks[0]);
        (address auth, address proxy, address implementation) = _proxyOwnedBy(deployer);

        uint256 nonce = vm.getNonce(deployer);
        harness.upgradeProxyWithCodeStep(auth, proxy, type(EligibilityCondition).creationCode);
        assertEq(_implementation(proxy), implementation);
        assertEq(vm.getNonce(deployer), nonce);

        harness.upgradeProxyWithCodeStep(auth, proxy, type(HolderCapCondition).creationCode);
        assertNotEq(_implementation(proxy), implementation);
        assertEq(harness.safeTxsOf().length, 0);
    }

    /// @dev The chain id selects the DeploymentConstants, so a different connected chain is a wrong configuration.
    function test_RevertWhen_ChainIdDiffersFromConnectedChain() public {
        vm.selectFork(forks[0]);
        vm.expectRevert(abi.encodeWithSelector(DeploymentScript.ChainIdMismatch.selector, 8453, 1));
        harness.initWithChainId(8453, deployerKey, safe);
    }

    // ---- handOffAuthOwner ----

    function test_HandOff_NominatesSafeAndQueuesAccept() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(deployer);

        harness.handOffStep(address(auth));
        assertEq(auth.pendingOwner(), safe);
        GnosisTransaction[] memory txs = harness.safeTxsOf();
        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(BorgAuth.acceptOwnership, ()));
        assertEq(auth.userRoles(deployer), 99);

        harness.finishStep(JSON_PATH);
        vm.removeFile(JSON_PATH);
        assertEq(auth.userRoles(safe), 99);
    }

    /// @dev A second run before the Safe signs does not nominate again. It only queues the accept.
    function test_HandOff_AlreadyNominated_QueuesAcceptOnly() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(deployer);
        vm.prank(deployer);
        auth.initTransferOwnership(safe);

        harness.handOffStep(address(auth));
        assertEq(harness.safeTxsOf().length, 1);
        assertEq(auth.userRoles(deployer), 99);
    }

    /// @dev The deployer drops its role only after the Safe holds the owner role.
    function test_HandOff_SafeAccepted_DeployerDropsRole() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(deployer);
        vm.prank(deployer);
        auth.initTransferOwnership(safe);
        vm.prank(safe);
        auth.acceptOwnership();

        harness.handOffStep(address(auth));
        assertEq(auth.userRoles(deployer), 0);
        assertEq(auth.userRoles(safe), 99);
        assertEq(harness.safeTxsOf().length, 0);
    }

    function test_HandOff_DeployerHasNoRole_DoesNothing() public {
        vm.selectFork(forks[0]);
        BorgAuth auth = new BorgAuth(safe);

        harness.handOffStep(address(auth));
        assertEq(auth.pendingOwner(), address(0));
        assertEq(harness.safeTxsOf().length, 0);
    }

    // ---- helpers ----

    function _proxyOwnedBy(address owner) internal returns (address auth, address proxy, address implementation) {
        auth = address(new BorgAuth(owner));
        implementation = address(new EligibilityCondition());
        proxy = address(new ERC1967Proxy(implementation, abi.encodeCall(EligibilityCondition.initialize, (auth))));
    }

    function _expected(string memory saltStr) internal view returns (address) {
        return _expectedFor(deployer, saltStr);
    }

    function _expectedFor(address sender, string memory saltStr) internal pure returns (address) {
        return DeploymentUtils.computeCreate3Address(sender, DeploymentUtils.create3Salt(sender, saltStr));
    }

    function _implementation(address proxy) internal view returns (address) {
        return
            address(
                uint160(uint256(vm.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))
            );
    }

    function _killSwitchInitCode(address metalexAdmin, address legionAdmin) internal pure returns (bytes memory) {
        return abi.encodePacked(type(KillSwitchCondition).creationCode, abi.encode(metalexAdmin, legionAdmin));
    }
}
