// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeployBoundAgreementRegistryScript} from "../script/deploy-bound-agreement-registry.s.sol";

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementRegistryDeployment} from "../script/libs/CyberAgreementRegistryDeployment.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test} from "forge-std/Test.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

// Never overwrite an operator's actual chain release files during a test.
contract TestBoundRegistryScript is DeployBoundAgreementRegistryScript {
    function outputPrefix(uint256 chainId) public pure override returns (string memory) {
        return string.concat("script/res/test-bound-registry-chain-", vm.toString(chainId));
    }
}

contract DeployBoundAgreementRegistryScriptTest is Test {
    DeployBoundAgreementRegistryScript runner;
    CyberAgreementRegistry registry;
    BorgAuth auth;
    address owner;
    address previous;
    address deployer;
    string PREFIX = "script/res/test-bound-registry-export";

    function setUp() public {
        // The script reads the deployer key from the environment. Use a test key, never a real one.
        uint256 deployerKey;
        (deployer, deployerKey) = makeAddrAndKey("deployer");
        vm.setEnv("PRIVATE_KEY_MAIN", vm.toString(deployerKey));
        vm.warp(1_700_000_000);
        vm.deal(address(this), 100 ether);
        owner = makeAddr("upgrade Safe");
        auth = new BorgAuth(owner);
        previous = address(CyberAgreementRegistryDeployment.deployRouter());
        registry = CyberAgreementRegistry(
            address(new ERC1967Proxy(previous, abi.encodeCall(CyberAgreementRegistry.initialize, (address(auth)))))
        );
        runner = new TestBoundRegistryScript();
    }

    function testExportLeavesProxyUntouchedEvenWhenDeployerIsOwner() public {
        vm.prank(owner);
        auth.updateRole(deployer, 99);
        address candidate = runner.runWithArgs(block.chainid, address(registry), owner, PREFIX);
        assertEq(runner.implementationOf(address(registry)), previous);
        assertNotEq(candidate, previous);
        assertLe(candidate.code.length, 24_576);
        string memory batch = vm.readFile(string.concat(PREFIX, ".json"));
        assertEq(vm.parseJsonString(batch, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonString(batch, ".meta.name"), "Transactions Batch");
        assertEq(vm.parseJsonAddress(batch, ".transactions[0].to"), address(registry));
        assertEq(vm.parseJsonString(batch, ".transactions[0].value"), "0");
        assertFalse(vm.keyExistsJson(batch, ".transactions[1]"));
        bytes memory data = vm.parseJsonBytes(batch, ".transactions[0].data");
        assertEq(data, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (candidate, bytes(""))));
        vm.prank(owner);
        (bool ok,) = address(registry).call(data);
        assertTrue(ok);
        assertEq(runner.implementationOf(address(registry)), candidate);
        assertEq(address(registry.AUTH()), address(auth));
        cleanup();
    }

    function testExistingAgreementAndPendingSignatureSurviveUpgrade() public {
        PREFIX = "script/res/test-bound-registry-existing";
        address alice = vm.addr(0xA11CE);
        address bob = vm.addr(0xB0B);
        string[] memory fields = new string[](0);
        string[] memory values = new string[](0);
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = values;
        partyValues[1] = values;
        registry.createTemplate(bytes32(uint256(1)), "Existing", "ipfs://existing", fields, fields);
        bytes32 id =
            registry.createContract(bytes32(uint256(1)), 1, values, parties, partyValues, bytes32(0), address(0), 0);
        bytes memory aliceSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            id,
            "ipfs://existing",
            fields,
            fields,
            values,
            values,
            0xA11CE
        );
        bytes memory bobSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            id,
            "ipfs://existing",
            fields,
            fields,
            values,
            values,
            0xB0B
        );
        registry.signContractFor(alice, id, values, aliceSig, false, "");
        string memory json = registry.getContractJson(id);
        bytes32 domain = registry.DOMAIN_SEPARATOR();
        address candidate = runner.runWithArgs(block.chainid, address(registry), owner, PREFIX);
        assertEq(registry.getContractJson(id), json, "simulation restored existing state");
        vm.prank(owner);
        registry.upgradeToAndCall(candidate, "");
        assertEq(registry.getContractJson(id), json);
        assertEq(registry.DOMAIN_SEPARATOR(), domain);
        assertTrue(registry.hasSigned(id, alice));
        registry.signContractFor(bob, id, values, bobSig, false, "");
        assertTrue(registry.isFinalized(id));
        cleanup();
    }

    function testWrongChainRefusesBeforeDeployment() public {
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(DeployBoundAgreementRegistryScript.WrongChain.selector, 1, block.chainid)
        );
        runner.runWithArgs(1, address(registry), owner, PREFIX);
        assertEq(vm.getNonce(deployer), nonce);
    }

    function testUnauthorizedAuthorityRefusesBeforeDeployment() public {
        address stranger = makeAddr("stranger");
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert();
        runner.runWithArgs(block.chainid, address(registry), stranger, PREFIX);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(runner.implementationOf(address(registry)), previous);
    }

    function testMissingProxyAndImplementationRefused() public {
        vm.expectRevert("Registry proxy has no code");
        runner.runWithArgs(block.chainid, address(1), owner, PREFIX);
        vm.expectRevert("Registry is not an implementation proxy");
        runner.runWithArgs(block.chainid, previous, owner, PREFIX);
    }

    function testProductionDefaultsRequireDeployedSafeAndExplicitChain() public {
        uint256[3] memory chains = [uint256(1), 8453, 42161];
        for (uint256 i; i < chains.length; i++) {
            vm.chainId(chains[i]);
            assertEq(
                runner.outputPrefix(chains[i]),
                string.concat("script/res/test-bound-registry-chain-", vm.toString(chains[i]))
            );
            vm.expectRevert("Configured Safe has no code; use explicit testnet authority");
            runner.runForChain(chains[i]);
            vm.expectRevert(
                abi.encodeWithSelector(DeployBoundAgreementRegistryScript.WrongChain.selector, chains[i] + 1, chains[i])
            );
            runner.runForChain(chains[i] + 1);
        }
    }

    function testDefaultBatchTargetsOnAllSupportedChains() public {
        uint256[5] memory chains = [uint256(1), 8453, 42161, 11155111, 84532];
        for (uint256 i; i < chains.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(chains[i]);
            DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chains[i]);
            vm.etch(core.metalexSafe, hex"00"); // Contract-code fixture; this does not model a real Safe.
            vm.etch(core.cyberAgreementRegistry, address(registry).code);
            vm.store(core.cyberAgreementRegistry, ERC1967Utils.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(previous))));
            BorgAuth chainAuth = new BorgAuth(core.metalexSafe);
            CyberAgreementRegistry(core.cyberAgreementRegistry).initialize(address(chainAuth));
            address candidate = runner.runForChain(chains[i]);
            string memory prefix = runner.outputPrefix(chains[i]);
            string memory batch = vm.readFile(string.concat(prefix, ".json"));
            assertEq(vm.parseJsonString(batch, ".chainId"), vm.toString(chains[i]));
            assertEq(vm.parseJsonAddress(batch, ".transactions[0].to"), core.cyberAgreementRegistry);
            assertEq(vm.parseJsonString(batch, ".meta.name"), "Transactions Batch");
            assertEq(
                vm.parseJsonBytes(batch, ".transactions[0].data"),
                abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (candidate, bytes("")))
            );
            assertEq(runner.implementationOf(core.cyberAgreementRegistry), previous);
            vm.removeFile(string.concat(prefix, ".json"));
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function cleanup() internal {
        vm.removeFile(string.concat(PREFIX, ".json"));
    }
}
