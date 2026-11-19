// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {DeploymentUtils} from "../script/libs/DeploymentUtils.sol";
import {UpgradeRoundManagerV51Script} from "../script/upgrade-round-manager-5-1.s.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @dev Writes only to its own test folder and reads a test list of known companies there. Each test uses its
/// own folder, because Forge runs the tests in parallel.
contract TestUpgradeRoundManagerV51Script is UpgradeRoundManagerV51Script {
    string internal dir;

    constructor(string memory dir_) {
        dir = dir_;
    }

    function metalexBatchPath(uint256 chainId) public view override returns (string memory) {
        return string.concat(dir, "/gnosis-batch-", vm.toString(chainId), ".json");
    }

    function corpBatchDir(uint256 chainId) public view override returns (string memory) {
        return string.concat(dir, "/", vm.toString(chainId));
    }

    function knownCorpsPath() public view override returns (string memory) {
        return string.concat("/", dir, "/known-cyber-corps.json");
    }
}

/// @notice The RoundManager 5.1 release script on a Base fork. There the MetaLeX Safe owns the core AUTH and
/// the RoundManagerFactory serves the v5 RoundManager. A company created through the live CyberCorpFactory runs
/// v5; a listed legacy company runs release 3 and is skipped.
/// @dev Needs `RPC_URL_BASE`; skipped without it. The deployer is a test key with no role.
contract UpgradeRoundManagerV51ScriptForkTest is Test {
    uint256 internal constant FORK_BLOCK = 56958568;
    address internal constant BASE_V5_ROUND_MANAGER_IMPL = 0xce8bdfa4D393649dE880AEdef01BAF6a39d59d08;
    /// @dev A known Base company from `known-cyber-corps.json`; its RoundManager runs release 3.
    address internal constant LEGACY_CORP = 0x24e62F9ed2961f7bdCb9B68AF9f1A66a020413b4;
    string internal constant ROOT = "script/res/test-round-manager-5-1";

    TestUpgradeRoundManagerV51Script internal runner;
    string internal dir;
    DeploymentConstants.CoreDeployment internal core;
    RoundManagerFactory internal factory;
    uint256 internal deployerKey;
    address internal deployer;
    address internal officer;
    address internal corp;
    address internal roundManager;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_URL_BASE", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
        (deployer, deployerKey) = makeAddrAndKey("round manager 5.1 deployer");
        vm.deal(deployer, 1 ether);
        core = DeploymentConstants.coreV2(block.chainid);
        factory = RoundManagerFactory(core.roundManagerFactory);

        officer = makeAddr("company Safe");
        (corp,,,, roundManager) =
            CyberCorpHelper.deployCorp(CyberCorpFactory(core.cyberCorpFactory), "Script Test Corp", officer, officer);
    }

    /// @dev Gives the test its own output folder and known-companies list, then a runner that uses them.
    function _useDir(string memory name) internal {
        dir = string.concat(ROOT, "/", name);
        if (vm.exists(dir)) vm.removeDir(dir, true);
        vm.createDir(dir, true);
        vm.writeFile(
            string.concat(dir, "/known-cyber-corps.json"),
            string.concat(
                '{"data":[{"chainId":8453,"address":"',
                vm.toString(corp),
                '"},{"chainId":8453,"address":"',
                vm.toString(LEGACY_CORP),
                '"},{"chainId":1,"address":"',
                vm.toString(corp),
                '"}]}'
            )
        );
        runner = new TestUpgradeRoundManagerV51Script(dir);
    }

    function test_Fixture_CompanyRunsV5AndLegacyRunsV3() public view {
        assertEq(factory.getRefImplementation(), BASE_V5_ROUND_MANAGER_IMPL, "fork must serve the v5 reference");
        assertEq(RoundManager(roundManager).DEPLOY_VERSION(), "5");
        assertEq(_implementationOf(roundManager), BASE_V5_ROUND_MANAGER_IMPL);
        assertFalse(DeploymentUtils.hasOwnerRole(core.auth, deployer));
        assertTrue(DeploymentUtils.hasOwnerRole(address(RoundManager(roundManager).AUTH()), officer));
    }

    function test_Run_QueuesReferenceForSafeAndWritesCompanyBatch() public {
        _useDir("test_Run_QueuesReferenceForSafeAndWritesCompanyBatch");
        address implementation = runner.runWithArgs(block.chainid, deployerKey, type(uint256).max);

        // MetaLeX batch: exactly one setter call to the factory, for the new 5.1 implementation.
        string memory batch = vm.readFile(runner.metalexBatchPath(block.chainid));
        assertEq(vm.parseJsonString(batch, ".chainId"), "8453");
        assertEq(vm.parseJsonAddress(batch, ".transactions[0].to"), address(factory));
        assertEq(vm.parseJsonString(batch, ".transactions[0].value"), "0");
        assertEq(
            vm.parseJsonBytes(batch, ".transactions[0].data"),
            abi.encodeCall(RoundManagerFactory.setRefImplementation, (implementation))
        );
        assertFalse(vm.keyExistsJson(batch, ".transactions[1]"));
        assertEq(RoundManager(implementation).DEPLOY_VERSION(), "5.1");
        assertLe(implementation.code.length, 24_576);

        // The script leaves the company alone and skips the release-3 company.
        assertEq(_implementationOf(roundManager), BASE_V5_ROUND_MANAGER_IMPL, "the script must not upgrade a company");
        assertFalse(vm.exists(runner.corpBatchPath(block.chainid, LEGACY_CORP)));

        // Company batch: one upgrade call that the company owner executes after the MetaLeX batch.
        string memory corpJson = vm.readFile(runner.corpBatchPath(block.chainid, corp));
        assertEq(vm.parseJsonString(corpJson, ".chainId"), "8453");
        assertEq(vm.parseJsonAddress(corpJson, ".transactions[0].to"), roundManager);
        assertEq(vm.parseJsonString(corpJson, ".transactions[0].value"), "0");
        bytes memory data = vm.parseJsonBytes(corpJson, ".transactions[0].data");
        assertEq(data, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, bytes(""))));
        assertFalse(vm.keyExistsJson(corpJson, ".transactions[1]"));

        address auth = address(RoundManager(roundManager).AUTH());
        vm.prank(officer);
        (bool ok,) = roundManager.call(data);
        assertTrue(ok, "company batch must execute");
        assertEq(RoundManager(roundManager).DEPLOY_VERSION(), "5.1");
        assertEq(address(RoundManager(roundManager).AUTH()), auth);
        (uint256 minRaise,,,,) = RoundManager(roundManager).getRoundMinimum(bytes32(0));
        assertEq(minRaise, 0);
        _cleanup();
    }

    function test_Run_TestnetOwnerDeployerSendsSetterItself() public {
        _useDir("test_Run_TestnetOwnerDeployerSendsSetterItself");
        // A deployer that owns the core AUTH (as on testnets) sends the setter; the Safe gets nothing.
        vm.store(core.auth, keccak256(abi.encode(deployer, uint256(1))), bytes32(uint256(200)));
        address implementation = runner.runWithArgs(block.chainid, deployerKey, 0);
        assertEq(factory.getRefImplementation(), implementation);
        assertFalse(vm.exists(runner.metalexBatchPath(block.chainid)));
        _cleanup();
    }

    function test_Run_AfterMetalexBatch_RerunIsNoop() public {
        _useDir("test_Run_AfterMetalexBatch_RerunIsNoop");
        // The first run leaves the MetaLeX batch executed in the simulated state.
        address implementation = runner.runWithArgs(block.chainid, deployerKey, 0);
        vm.removeFile(runner.metalexBatchPath(block.chainid));
        uint64 nonce = vm.getNonce(deployer);

        address again = runner.runWithArgs(block.chainid, deployerKey, 0);

        assertEq(again, implementation, "a re-run keeps the 5.1 reference");
        assertEq(vm.getNonce(deployer), nonce, "a re-run deploys nothing");
        assertFalse(vm.exists(runner.metalexBatchPath(block.chainid)), "a re-run writes no MetaLeX batch");
        _cleanup();
    }

    function test_CompanyUpgrade_RevertsBeforeMetalexBatch() public {
        address candidate = address(new RoundManager());
        vm.prank(officer);
        vm.expectRevert(RoundManager.NotRefImplementation.selector);
        UUPSUpgradeable(roundManager).upgradeToAndCall(candidate, "");
    }

    function test_CorpBatch_RefusesUntilReferenceIs51() public {
        _useDir("test_CorpBatch_RefusesUntilReferenceIs51");
        vm.expectRevert(bytes("The factory reference is not 5.1 yet: execute the MetaLeX Safe batch first"));
        runner.corpBatch(corp, officer);
        _cleanup();
    }

    function test_CorpBatch_RefusesNonOwnerAndLegacy() public {
        _useDir("test_CorpBatch_RefusesNonOwnerAndLegacy");
        runner.runWithArgs(block.chainid, deployerKey, 0);
        address stranger = makeAddr("not an owner");
        vm.expectRevert(bytes("upgrade simulation failed (owner role, factory or state)"));
        runner.corpBatch(corp, stranger);
        vm.expectRevert(bytes("RoundManager is not v5; use the v5 company upgrade (upgrade-v5.s.sol)"));
        runner.corpBatch(LEGACY_CORP, officer);
        _cleanup();
    }

    function test_CorpBatch_WritesForOwnerAndLeavesProxy() public {
        _useDir("test_CorpBatch_WritesForOwnerAndLeavesProxy");
        address implementation = runner.runWithArgs(block.chainid, deployerKey, 0);
        assertFalse(vm.exists(runner.corpBatchPath(block.chainid, corp)), "maxCorps 0 writes no company batch");

        string memory path = runner.corpBatch(corp, officer);

        assertEq(_implementationOf(roundManager), BASE_V5_ROUND_MANAGER_IMPL, "corpBatch broadcasts nothing");
        string memory corpJson = vm.readFile(path);
        assertEq(vm.parseJsonAddress(corpJson, ".transactions[0].to"), roundManager);
        assertEq(
            vm.parseJsonBytes(corpJson, ".transactions[0].data"),
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, bytes("")))
        );
        _cleanup();
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _cleanup() internal {
        if (vm.exists(dir)) vm.removeDir(dir, true);
    }
}
