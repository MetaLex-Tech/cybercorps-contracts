// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BorgAuth} from "../../src/libs/auth.sol";
import {DeploymentUtils} from "./DeploymentUtils.sol";
import {GnosisTransaction} from "./safe.sol";
import {Script, console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

/// @notice Base for deploy scripts. A script lists what to deploy, what to upgrade and what to call.
///         Each step decides how to do it, so a re-run does only the work that is still open.
/// @dev Existing contracts:
///      - DeploymentConstants holds the address of each proxy, singleton and auth that exists.
///        A step keeps an existing address and does not deploy it again.
///      - We do not record implementation addresses in DeploymentConstants as they change frequently during development.
///      New singletons, proxies and auths (`deployIfNotExist`):
///      - They use CREATE3 when their DeploymentConstants field is zero. The salt is `saltPrefix/saltName`.
///      - The address depends only on the deployer and the salt, not on the code. The same deployer key
///        gives the same address on each chain. Another deployer gets other addresses.
///      - Contracts deployed prior to this script are not necessarily all created using CREATE3.
///      - DeploymentConstants take precedence if the salt's CREATE3 disagree with it; however,
///        if the salt's address has code, the existing address must be that address. See `DeploymentUtils.verifyExisting`.
///      New implementations (`deployIfDifferent`):
///      - They use CREATE, so they need no salt.
///      - The step compares the new runtime code with the current implementation. It deploys only when
///        the code is different. The change detection is intentionally simple and strict to avoid false negatives,
///        as a result, a comment change also counts as a change.
///      Who sends a call (`execute`):
///      - The deployer sends a call now when it holds the owner role on the call's BorgAuth.
///      - Otherwise the call goes to `safeTxs`, and the MetaLeX Safe must sign it.
///        `finish` runs these calls as the Safe after all deployer calls, which is their order on chain.
///        Then it writes the batch JSON for the Safe Transaction Builder.
abstract contract DeploymentScript is Script {
    error ImplementationMismatch(address proxy, address expected);
    error ImplementationCreationFailed(string name);
    error ChainIdMismatch(uint256 chainId, uint256 connectedChainId);

    uint256 private deployerPrivateKey;
    address internal deployer;
    address internal safe;
    GnosisTransaction[] internal safeTxs;

    /// @dev Log markers. A step that does work (sends, deploys or queues) logs RUN. A step that skips logs SKIP.
    string private constant RUN = unicode"🟢 ";
    string private constant SKIP = unicode"⚫️ ";

    /// @dev `chainId` selects the DeploymentConstants that the script uses. It must be the chain that the
    ///      script runs on, otherwise the script would use the addresses of another chain.
    ///      It logs the chain id, the deployer and the Safe. The script logs its own header first.
    ///      Each step that logs takes `logLabel` first. Each of its log lines starts with that label.
    ///      A line about a step that does work or skips starts with a RUN or SKIP marker before the label.
    function initDeployment(string memory logLabel, uint256 chainId, uint256 deployerPrivateKey_, address safe_)
        internal
    {
        if (chainId != block.chainid) revert ChainIdMismatch(chainId, block.chainid);
        deployerPrivateKey = deployerPrivateKey_;
        deployer = vm.addr(deployerPrivateKey_);
        safe = safe_;
        delete safeTxs;

        console2.log(string.concat(logLabel, " chainId: ", vm.toString(chainId)));
        console2.log(string.concat(logLabel, " deployer: ", vm.toString(deployer)));
        console2.log(string.concat(logLabel, " Safe: ", vm.toString(safe)));
    }

    /// @notice Sends an owner-gated call now, or gives it to the Safe.
    /// @return direct True when the deployer sent the call.
    function execute(string memory logLabel, address auth, address to, bytes memory data, string memory description)
        internal
        returns (bool direct)
    {
        direct = DeploymentUtils.hasOwnerRole(auth, deployer);
        if (direct) {
            vm.broadcast(deployerPrivateKey);
            Address.functionCall(to, data);
            console2.log(string.concat(RUN, logLabel, " executed ", description));
        } else {
            _queueForSafe(logLabel, to, data, description);
        }
    }

    /// @notice Deploys `creationCode` with CREATE, unless `current` already has the same code.
    /// @dev The step deploys a copy only in the simulation and compares its runtime code with `current`.
    ///      The only masked difference is the contract's own address, which UUPSUpgradeable keeps as an
    ///      immutable. Any other difference, a comment change included, deploys a new contract.
    ///      A zero `current` always deploys.
    ///      `creationCode` must include the constructor arguments, if any.
    /// @return deployed The new contract, or `current` when the code is the same.
    /// @return isNew True when the step deployed a new contract.
    function deployIfDifferent(string memory logLabel, string memory name, bytes memory creationCode, address current)
        internal
        returns (address deployed, bool isNew)
    {
        if (current != address(0) && _sameCode(current, _create(creationCode, name))) {
            console2.log(string.concat(SKIP, logLabel, " ", name, " unchanged, keeping: ", vm.toString(current)));
            return (current, false);
        }
        vm.broadcast(deployerPrivateKey);
        deployed = _create(creationCode, name);
        isNew = true;
        console2.log(string.concat(RUN, logLabel, " deployed new ", name, " (CREATE): ", vm.toString(deployed)));
    }

    /// @notice Keeps an existing contract from DeploymentConstants as it is, or deploys a new one with CREATE3.
    /// @dev The CREATE3 salt is `saltPrefix/saltName`. See `DeploymentUtils.verifyExisting` for the check of
    ///      `existing`. A zero `existing` deploys `initCode`.
    /// @return deployed The new contract, or `existing`.
    /// @return isNew True when the step deployed a new contract.
    function deployIfNotExist(
        string memory logLabel,
        string memory saltPrefix,
        string memory saltName,
        address existing,
        bytes memory initCode
    ) internal returns (address deployed, bool isNew) {
        string memory saltStr = string.concat(saltPrefix, "/", saltName);
        DeploymentUtils.verifyExisting(existing, deployer, saltStr);
        if (existing != address(0)) {
            console2.log(
                string.concat(SKIP, logLabel, " ", saltName, " already exists, skipping: ", vm.toString(existing))
            );
            return (existing, false);
        }
        vm.broadcast(deployerPrivateKey);
        deployed = DeploymentUtils.deployCreate3(deployer, saltStr, initCode);
        isNew = true;
        console2.log(string.concat(RUN, logLabel, " deployed new ", saltName, " (CREATE3): ", vm.toString(deployed)));
    }

    /// @notice Deploys a new implementation when its code differs from the current one. Then it upgrades the
    ///         existing proxy to it, or deploys a new proxy with CREATE3 when `existing` is zero.
    /// @dev The proxy's CREATE3 salt is `saltPrefix/saltName`. `saltName` also names both contracts in the logs.
    /// @return proxy The new proxy, or `existing`.
    /// @return isNew True when the step deployed a new proxy.
    function upgradeOrDeployProxyIfDiffImpl(
        address auth,
        string memory saltPrefix,
        string memory saltName,
        address existing,
        bytes memory creationCode,
        bytes memory initCall
    ) internal returns (address proxy, bool isNew) {
        // Check `existing` before any implementation work, so a wrong address stops the run at once.
        DeploymentUtils.verifyExisting(existing, deployer, string.concat(saltPrefix, "/", saltName));
        (address implementation,) =
            deployIfDifferent("[deploy implementation]", saltName, creationCode, implementationOf(existing));
        return upgradeOrDeployProxyIfDiffImpl(auth, saltPrefix, saltName, existing, implementation, initCall);
    }

    /// @notice The same as the version above, for an implementation that the caller already deployed.
    ///         Use it when several proxies share one implementation.
    function upgradeOrDeployProxyIfDiffImpl(
        address auth,
        string memory saltPrefix,
        string memory saltName,
        address existing,
        address implementation,
        bytes memory initCall
    ) internal returns (address proxy, bool isNew) {
        (proxy, isNew) = deployIfNotExist(
            "[deploy proxy]", saltPrefix, saltName, existing, proxyCreationCode(implementation, initCall)
        );
        if (!isNew) upgradeProxy("[upgrade proxy]", auth, proxy, saltName, implementation);
    }

    /// @notice Points a proxy to `implementation`, unless it already uses it. See `execute` for who sends the call.
    /// @dev An upgrade call to an address with no code does not revert, so the step reads the slot.
    ///      `finish` checks a Safe upgrade.
    function upgradeProxy(
        string memory logLabel,
        address auth,
        address proxy,
        string memory name,
        address implementation
    ) internal {
        if (proxy == address(0)) revert("Missing proxy address");
        if (implementationOf(proxy) == implementation) {
            console2.log(
                string.concat(
                    SKIP, logLabel, " ", name, " already uses the implementation, skipping: ", vm.toString(proxy)
                )
            );
            return;
        }
        bool direct = execute(
            logLabel,
            auth,
            proxy,
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, "")),
            string.concat(name, " ", vm.toString(proxy), " to implementation ", vm.toString(implementation))
        );
        if (direct) _requireImplementation(proxy, implementation);
    }

    /// @notice Deploys a new implementation when its code differs from the proxy's, then points the proxy to it.
    /// @dev Same code means that the proxy already uses it, so the step does not upgrade.
    function upgradeProxy(address auth, address proxy, string memory name, bytes memory creationCode) internal {
        (address implementation, bool isNew) =
            deployIfDifferent("[deploy implementation]", name, creationCode, implementationOf(proxy));
        if (!isNew) return;
        upgradeProxy("[upgrade proxy]", auth, proxy, name, implementation);
    }

    /// @notice Deploys a new reference implementation when the code changed, then sets it on the factory.
    /// @dev A factory keeps a reference implementation for the contracts that it creates. `setter` takes the new
    ///      implementation address as its only argument. See `execute` for who sends it.
    function deployAndSetRefImplementation(
        address auth,
        address factory,
        address current,
        bytes4 setter,
        string memory name,
        bytes memory creationCode
    ) internal {
        (address implementation, bool isNew) = deployIfDifferent("[deploy implementation]", name, creationCode, current);
        if (!isNew) return;
        execute(
            "[set ref implementation]",
            auth,
            factory,
            abi.encodeWithSelector(setter, implementation),
            string.concat(name, ": ", vm.toString(implementation))
        );
    }

    /// @notice Moves the owner role of an auth from the deployer to the Safe.
    /// @dev The move takes two runs. The deployer never drops its role before the Safe holds it.
    ///      Run 1: the deployer nominates the Safe, and the Safe batch accepts the role.
    ///      Run 2, after the Safe executes the batch: the deployer drops its role.
    ///      Only the Safe can accept, so the accept always goes to the Safe.
    function handOffAuthOwner(string memory logLabel, address auth, string memory name) internal {
        if (!DeploymentUtils.hasOwnerRole(auth, deployer)) {
            console2.log(
                string.concat(SKIP, logLabel, " deployer has no owner role on ", name, ": ", vm.toString(auth))
            );
            return;
        }
        if (DeploymentUtils.hasOwnerRole(auth, safe)) {
            vm.broadcast(deployerPrivateKey);
            BorgAuth(auth).zeroOwner();
            console2.log(
                string.concat(
                    RUN,
                    logLabel,
                    " Safe holds the owner role. Deployer dropped its owner role on ",
                    name,
                    ": ",
                    vm.toString(auth)
                )
            );
            return;
        }
        if (BorgAuth(auth).pendingOwner() != safe) {
            vm.broadcast(deployerPrivateKey);
            BorgAuth(auth).initTransferOwnership(safe);
            console2.log(
                string.concat(RUN, logLabel, " deployer nominated the Safe as owner of ", name, ": ", vm.toString(auth))
            );
        }
        _queueForSafe(
            logLabel,
            auth,
            abi.encodeCall(BorgAuth.acceptOwnership, ()),
            string.concat("accepting the owner role of ", name)
        );
    }

    /// @notice Adds the Safe calls of a sub-script, in order.
    function appendSafeTxs(string memory logLabel, GnosisTransaction[] memory txs, string memory source) internal {
        for (uint256 i = 0; i < txs.length; i++) {
            safeTxs.push(txs[i]);
        }
        console2.log(string.concat(logLabel, " added Safe calls from ", source, ", count: ", vm.toString(txs.length)));
    }

    /// @notice Runs the Safe calls as the Safe, checks the upgrades among them and writes the batch to `jsonPath`.
    /// @dev A failed call stops the script before it broadcasts anything. Call it after all other steps.
    ///      The JSON block has no label, so it can be copied as it is.
    function finish(string memory logLabel, string memory jsonPath) internal {
        console2.log("");
        if (safeTxs.length == 0) {
            console2.log(string.concat(logLabel, " The deployer sent all calls. The Safe has nothing to sign."));
            return;
        }
        console2.log(string.concat(logLabel, " The Safe must sign ", vm.toString(safeTxs.length), " calls."));
        console2.log(string.concat(logLabel, " Safe: ", vm.toString(safe)));
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(safe);
            Address.functionCallWithValue(safeTxs[i].to, safeTxs[i].data, safeTxs[i].value);
        }
        for (uint256 i = 0; i < safeTxs.length; i++) {
            _requireUpgraded(safeTxs[i]);
        }

        string memory safeTxJson = DeploymentUtils.formatSafeTxJson(safeTxs, block.chainid);
        console2.log(string.concat(logLabel, " Safe tx JSON (can be imported to Safe Transaction Builder):"));
        console2.log("==== JSON data start ====");
        console2.log(safeTxJson);
        console2.log("==== JSON data end ====");
        vm.writeFile(jsonPath, safeTxJson);
        console2.log(string.concat(logLabel, " Safe tx JSON written to: ", jsonPath));
    }

    /// @notice The init code of an ERC-1967 proxy that runs `initCall` on `implementation`.
    function proxyCreationCode(address implementation, bytes memory initCall) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initCall));
    }

    /// @notice The implementation of an ERC-1967 proxy. A zero proxy gives a zero address.
    function implementationOf(address proxy) internal view returns (address) {
        if (proxy == address(0)) return address(0);
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _queueForSafe(string memory logLabel, address to, bytes memory data, string memory description) private {
        safeTxs.push(GnosisTransaction({to: to, value: 0, data: data}));
        console2.log(string.concat(RUN, logLabel, " queued for the Safe: ", description));
    }

    /// @dev `new` needs a fixed contract type, so a step that takes any creation code needs `create`.
    function _create(bytes memory creationCode, string memory name) private returns (address created) {
        assembly ("memory-safe") {
            created := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (created == address(0)) revert ImplementationCreationFailed(name);
    }

    function _sameCode(address a, address b) private view returns (bool) {
        return keccak256(_withoutOwnAddress(a)) == keccak256(_withoutOwnAddress(b));
    }

    /// @dev Replaces each copy of the contract's own address in its runtime code with zeros.
    function _withoutOwnAddress(address target) private view returns (bytes memory code) {
        code = target.code;
        bytes20 own = bytes20(target);
        for (uint256 i = 0; i + 20 <= code.length; i++) {
            if (code[i] != own[0]) continue;
            bool found = true;
            for (uint256 j = 1; j < 20; j++) {
                if (code[i + j] != own[j]) {
                    found = false;
                    break;
                }
            }
            if (!found) continue;
            for (uint256 j = 0; j < 20; j++) {
                code[i + j] = 0;
            }
        }
    }

    /// @dev The Safe calls include the ones from sub-scripts, so read the upgrades from the call data.
    function _requireUpgraded(GnosisTransaction memory safeTx) private view {
        bytes memory data = safeTx.data;
        if (data.length < 4 || bytes4(data) != UUPSUpgradeable.upgradeToAndCall.selector) return;

        bytes memory args = new bytes(data.length - 4);
        for (uint256 j = 0; j < args.length; j++) {
            args[j] = data[j + 4];
        }
        (address implementation,) = abi.decode(args, (address, bytes));
        _requireImplementation(safeTx.to, implementation);
    }

    function _requireImplementation(address proxy, address implementation) private view {
        if (implementationOf(proxy) != implementation) revert ImplementationMismatch(proxy, implementation);
    }
}
