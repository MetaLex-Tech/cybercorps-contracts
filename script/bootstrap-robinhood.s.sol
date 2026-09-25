// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BorgAuth} from "../src/libs/auth.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {Script, console2} from "forge-std/Script.sol";

interface IRobinhoodFactory {
    function AUTH() external view returns (BorgAuth);
    function registryAddress() external view returns (address);
    function uriBuilder() external view returns (address);
    function issuanceManagerFactory() external view returns (address);
    function cyberCorpSingleFactory() external view returns (address);
    function dealManagerFactory() external view returns (address);
    function roundManagerFactory() external view returns (address);
    function lexchexAuth() external view returns (address);
    function stable() external view returns (address);
}

interface IRobinhoodComponent {
    function getDefaultFeeRatio() external view returns (uint256);
    function getPlatformPayable() external view returns (address);
    function isWhitelistedToken(address token) external view returns (bool);
}

/// @notice Fresh-chain bridge from feat/new-chain-deploy to upgrade-v5.s.sol.
/// @dev Deploys frozen historical CREATE2 payloads, then emits an atomic Safe configuration batch.
///      Execute that batch before v5. This is not a migration for chains with existing corps.
///      See script/res/robinhood-bootstrap.md. Never run with --skip-simulation.
contract BootstrapRobinhoodScript is Script {
    address public constant REPLAY_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address public constant HISTORICAL_OWNER = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
    address public constant ORIGINAL_FACTORY_IMPL = 0xa150525deD1aA387E160FDF4b45e975acD02E156;
    address public constant BRIDGE_FACTORY_IMPL = 0x424ab1B1DA8b7B2FE13cA0A7ABC346b22efa9191;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 public constant MANIFEST_SHA256 = 0x3fe0f9b53fdfd089154e34cd81912231cbae4fa6a7ed0b665121cde5594ccd23;
    string internal constant MANIFEST = "script/res/robinhood-bootstrap.json";

    // Canonical Arachnid deterministic deployment proxy runtime (not an interchangeable factory).
    bytes internal constant REPLAY_FACTORY_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    // vm.parseJson decodes object fields in alphabetical order.
    struct Creation {
        address addr;
        bytes data;
        address implementation;
        string name;
        bytes32 sourceTx;
    }

    struct Config {
        address stable;
        address feeRecipient;
        uint256 primaryFeeBps;
        bool freshDeployment;
    }

    error UnsupportedChain(uint256 chainId);
    error InvalidConfig();
    error MissingCode(address target);
    error WrongCode(address target);
    error WrongImplementation(address target, address actual);
    error WrongAuth(address target);
    error WrongState(address target);
    error InvalidManifest();
    error InvalidCreation(address target);
    error DeploymentFailed(address target);
    error MissingOwner(address auth, address owner);

    GnosisTransaction[] internal calls;

    function run() external {
        address sender = vm.rememberKey(vm.envUint("PRIVATE_KEY_MAIN"));
        Config memory config = Config({
            stable: vm.envAddress("ROBINHOOD_STABLE"),
            feeRecipient: vm.envAddress("ROBINHOOD_FEE_RECIPIENT"),
            primaryFeeBps: vm.envUint("ROBINHOOD_PRIMARY_FEE_BPS"),
            freshDeployment: vm.envBool("ROBINHOOD_FRESH_DEPLOYMENT")
        });
        runWithArgs(sender, config);
        // Simulation only: the deployer does not sign or send these Safe-owned calls.
        simulateSafeBatch(config);
        string memory path =
            string.concat("script/res/gnosis-batch-bootstrap-robinhood-", vm.toString(block.chainid), ".json");
        vm.writeFile(path, safeBatchJson());
        console2.log("Execute the complete Safe batch before upgrade-v5.s.sol:", path);
    }

    /// @notice Builds the bridge; broadcasts are only sent by forge script when --broadcast is supplied.
    function runWithArgs(address sender, Config memory config) public returns (GnosisTransaction[] memory) {
        _chain();
        delete calls;
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        _preflight(core, sender, config);
        Creation[] memory entries = _manifest();
        // Check every address before recording any broadcast.
        for (uint256 i; i < entries.length; ++i) {
            _checkAddress(entries[i]);
        }
        for (uint256 i; i < entries.length; ++i) {
            _replay(entries[i], sender);
        }

        // Historical AUTH constructor embeds HISTORICAL_OWNER, regardless of who relays CREATE2.
        // The original key is necessary on the first run, unless that owner has already granted the Safe.
        BorgAuth lexAuth = BorgAuth(core.lexchexAuth);
        if (!_owner(lexAuth, core.metalexSafe)) {
            if (!_owner(lexAuth, sender)) revert MissingOwner(core.lexchexAuth, sender);
            uint256 ownerRole = lexAuth.OWNER_ROLE();
            vm.broadcast(sender);
            lexAuth.updateRole(core.metalexSafe, ownerRole);
        }
        _auth(core.lexchex, core.lexchexAuth);
        _auth(core.lexchexMinter, core.lexchexAuth);
        _validateManifestProxies(entries);

        // This historical intermediate has the necessary setters, but not the v5 namespace guard.
        // Never substitute today's creation code: that would change the historical factory addresses.
        if (_implementation(core.cyberCorpFactory) == ORIGINAL_FACTORY_IMPL) {
            _queue(
                core.cyberCorpFactory,
                abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BRIDGE_FACTORY_IMPL, bytes(""))
            );
        }
        _queue(
            core.cyberCorpFactory,
            abi.encodeWithSignature("setIssuanceManagerFactory(address)", core.issuanceManagerFactory)
        );
        _queue(
            core.cyberCorpFactory,
            abi.encodeWithSignature("setCyberCorpSingleFactory(address)", core.cyberCorpSingleFactory)
        );
        _queue(
            core.cyberCorpFactory, abi.encodeWithSignature("setDealManagerFactory(address)", core.dealManagerFactory)
        );
        _queue(
            core.cyberCorpFactory, abi.encodeWithSignature("setRoundManagerFactory(address)", core.roundManagerFactory)
        );
        _queue(core.cyberCorpFactory, abi.encodeWithSignature("setLexchexAuth(address)", core.lexchexAuth));
        _queue(core.cyberCorpFactory, abi.encodeWithSignature("setStable(address)", config.stable));
        _queue(
            core.roundManagerFactory, abi.encodeWithSignature("setWhitelistedToken(address,bool)", config.stable, true)
        );
        _queue(core.roundManagerFactory, abi.encodeWithSignature("setDefaultFeeRatio(uint256)", config.primaryFeeBps));
        _queue(core.roundManagerFactory, abi.encodeWithSignature("setPlatformPayable(address)", config.feeRecipient));
        _queue(core.dealManagerFactory, abi.encodeWithSignature("setDefaultFeeRatio(uint256)", config.primaryFeeBps));
        _queue(core.dealManagerFactory, abi.encodeWithSignature("setPlatformPayable(address)", config.feeRecipient));
        _queue(core.lexchexAuth, abi.encodeCall(BorgAuth.updateRole, (core.cyberCorpFactory, lexAuth.OWNER_ROLE())));
        _queue(core.lexchexAuth, abi.encodeCall(BorgAuth.updateRole, (core.lexchexMinter, lexAuth.ADMIN_ROLE())));
        return calls;
    }

    /// @notice Executes the batch as the Safe in the local simulation and verifies the resulting wiring.
    function simulateSafeBatch(Config memory config) public {
        _chain();
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(core.metalexSafe);
            (bool ok, bytes memory reason) = calls[i].to.call(calls[i].data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        IRobinhoodFactory factory = IRobinhoodFactory(core.cyberCorpFactory);
        if (
            _implementation(core.cyberCorpFactory) != BRIDGE_FACTORY_IMPL
                || factory.issuanceManagerFactory() != core.issuanceManagerFactory
                || factory.cyberCorpSingleFactory() != core.cyberCorpSingleFactory
                || factory.dealManagerFactory() != core.dealManagerFactory
                || factory.roundManagerFactory() != core.roundManagerFactory || factory.lexchexAuth() != core.lexchexAuth
                || factory.stable() != config.stable
        ) {
            revert WrongState(core.cyberCorpFactory);
        }
        if (
            !IRobinhoodComponent(core.roundManagerFactory).isWhitelistedToken(config.stable)
                || IRobinhoodComponent(core.roundManagerFactory).getDefaultFeeRatio() != config.primaryFeeBps
                || IRobinhoodComponent(core.dealManagerFactory).getDefaultFeeRatio() != config.primaryFeeBps
                || IRobinhoodComponent(core.roundManagerFactory).getPlatformPayable() != config.feeRecipient
                || IRobinhoodComponent(core.dealManagerFactory).getPlatformPayable() != config.feeRecipient
        ) {
            revert WrongState(core.roundManagerFactory);
        }
        BorgAuth lexAuth = BorgAuth(core.lexchexAuth);
        if (!_owner(lexAuth, core.cyberCorpFactory) || lexAuth.userRoles(core.lexchexMinter) != lexAuth.ADMIN_ROLE()) {
            revert WrongState(core.lexchexAuth);
        }
    }

    /// @notice Safe Transaction Builder JSON. All interpolated values are hex or unsigned integers.
    /// @dev Uses standard cheatcodes so this bridge also works with older installed Foundry builds.
    function safeBatchJson() public view returns (string memory json) {
        _chain();
        address safe = DeploymentConstants.coreV2(block.chainid).metalexSafe;
        json = string.concat(
            '{"version":"1.0","chainId":"',
            vm.toString(block.chainid),
            '","createdAt":',
            vm.toString(block.timestamp * 1000),
            ',"meta":{"name":"Robinhood bootstrap","txBuilderVersion":"1.16.5","createdFromSafeAddress":"',
            vm.toString(safe),
            '"},"transactions":['
        );
        for (uint256 i; i < calls.length; ++i) {
            if (i != 0) json = string.concat(json, ",");
            json = string.concat(
                json, '{"to":"', vm.toString(calls[i].to), '","value":"0","data":"', vm.toString(calls[i].data), '"}'
            );
        }
        return string.concat(json, "]}");
    }

    function _preflight(DeploymentConstants.CoreDeployment memory core, address sender, Config memory config)
        internal
        view
    {
        if (
            !config.freshDeployment || sender == address(0) || config.stable.code.length == 0
                || config.feeRecipient == address(0) || config.primaryFeeBps > 10_000
        ) revert InvalidConfig();
        // Do not manufacture a Safe or replay a role handoff to an empty address.
        if (core.metalexSafe.code.length == 0) revert MissingCode(core.metalexSafe);
        if (keccak256(REPLAY_FACTORY.code) != keccak256(REPLAY_FACTORY_CODE)) revert WrongCode(REPLAY_FACTORY);
        if (core.auth.code.length == 0) revert MissingCode(core.auth);
        if (!_owner(BorgAuth(core.auth), core.metalexSafe)) revert MissingOwner(core.auth, core.metalexSafe);
        if (core.cyberCorpFactory.code.length == 0) revert MissingCode(core.cyberCorpFactory);
        address impl = _implementation(core.cyberCorpFactory);
        if (impl != ORIGINAL_FACTORY_IMPL && impl != BRIDGE_FACTORY_IMPL) {
            revert WrongImplementation(core.cyberCorpFactory, impl);
        }
        _auth(core.cyberCorpFactory, core.auth);
        _auth(core.cyberAgreementRegistry, core.auth);
        _auth(core.uriBuilder, core.auth);
        IRobinhoodFactory factory = IRobinhoodFactory(core.cyberCorpFactory);
        if (factory.registryAddress() != core.cyberAgreementRegistry || factory.uriBuilder() != core.uriBuilder) {
            revert WrongState(core.cyberCorpFactory);
        }
        if (core.lexchexAuth.code.length == 0 && sender != HISTORICAL_OWNER) {
            revert MissingOwner(core.lexchexAuth, sender);
        }
    }

    function _manifest() internal view returns (Creation[] memory) {
        string memory json = vm.readFile(MANIFEST);
        if (sha256(bytes(json)) != MANIFEST_SHA256) revert InvalidManifest();
        return abi.decode(vm.parseJson(json, ".deployments"), (Creation[]));
    }

    function _checkAddress(Creation memory entry) internal pure {
        if (entry.data.length <= 32) revert InvalidCreation(entry.addr);
        bytes memory initCode = _initCode(entry.data);
        bytes32 salt;
        bytes memory data = entry.data;
        assembly ("memory-safe") {
            salt := mload(add(data, 32))
        }
        address expected = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), REPLAY_FACTORY, salt, keccak256(initCode)))))
        );
        if (expected != entry.addr) revert InvalidCreation(entry.addr);
    }

    function _replay(Creation memory entry, address sender) internal {
        if (entry.addr.code.length == 0) {
            vm.broadcast(sender);
            (bool ok,) = REPLAY_FACTORY.call(entry.data);
            if (!ok || entry.addr.code.length == 0) revert DeploymentFailed(entry.addr);
        }
        // Compare the frozen runtime, masking only the UUPS/library self-address immutable.
        // Snapshot rollback removes the comparison contract, its initialization and nonce effects.
        uint256 snapshot = vm.snapshotState();
        bytes memory initCode = _initCode(entry.data);
        address sample;
        assembly ("memory-safe") {
            sample := create(0, add(initCode, 32), mload(initCode))
        }
        if (sample == address(0)) revert DeploymentFailed(entry.addr);
        bool matches = keccak256(_normalized(entry.addr)) == keccak256(_normalized(sample));
        require(vm.revertToState(snapshot), "snapshot rollback failed");
        if (!matches) revert WrongCode(entry.addr);
        console2.log("[historical deployment]", entry.addr);
    }

    function _validateManifestProxies(Creation[] memory entries) internal view {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].implementation == address(0)) continue;
            address impl = _implementation(entries[i].addr);
            if (impl != entries[i].implementation) revert WrongImplementation(entries[i].addr, impl);
            _auth(
                entries[i].addr,
                entries[i].addr == core.lexchex || entries[i].addr == core.lexchexMinter ? core.lexchexAuth : core.auth
            );
        }
    }

    function _normalized(address target) internal view returns (bytes memory code) {
        code = target.code;
        bytes20 own = bytes20(target);
        for (uint256 i; i + 20 <= code.length; ++i) {
            if (code[i] != own[0]) continue;
            bool found = true;
            for (uint256 j; j < 20; ++j) {
                if (code[i + j] != own[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                for (uint256 j; j < 20; ++j) {
                    code[i + j] = 0;
                }
            }
        }
    }

    function _initCode(bytes memory data) internal pure returns (bytes memory initCode) {
        initCode = new bytes(data.length - 32);
        assembly ("memory-safe") {
            for { let j := 0 } lt(j, mload(initCode)) { j := add(j, 32) } {
                mstore(add(add(initCode, 32), j), mload(add(add(data, 64), j)))
            }
        }
    }

    function _implementation(address target) internal view returns (address) {
        return address(uint160(uint256(vm.load(target, IMPLEMENTATION_SLOT))));
    }

    function _owner(BorgAuth auth, address account) internal view returns (bool) {
        return auth.userRoles(account) >= auth.OWNER_ROLE();
    }

    function _auth(address target, address expected) internal view {
        if (target.code.length == 0) revert MissingCode(target);
        if (address(IRobinhoodFactory(target).AUTH()) != expected) revert WrongAuth(target);
    }

    function _queue(address to, bytes memory data) internal {
        calls.push(GnosisTransaction({to: to, value: 0, data: data}));
    }

    function _chain() internal view {
        if (block.chainid != 4663 && block.chainid != 46630) revert UnsupportedChain(block.chainid);
    }
}
