// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Vm, console2} from "forge-std/Test.sol";
import {GnosisTransaction} from "./safe.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Access hidden cheatcodes
interface EnhancedVm is Vm {
    function serializeJsonType(string calldata typeDescription, bytes memory value) external pure returns (string memory json);
}

library SafeUtils {
    EnhancedVm constant vm = EnhancedVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ImplementationMismatch(address proxy, address expected);

    struct SafeTxImport {
        string version;
        string chainId;
        uint256 createdAt;
        SafeTxMeta meta;
        SafeTx[] transactions;
    }

    struct SafeTxMeta {
        string name;
        string description;
        string txBuilderVersion;
        string createdFromSafeAddress;
        string createdFromOwnerAddress;
        string checksum;
    }

    struct SafeTx {
        address to;
        string value;
        bytes data;
    }

    function formatSafeTxJson(GnosisTransaction[] memory safeTxs, uint256 chainId) internal returns (string memory) {
        SafeTx[] memory convertedSafeTxs = new SafeTx[](safeTxs.length);
        for (uint256 i = 0; i < safeTxs.length; i++) {
            convertedSafeTxs[i] = SafeTx({
                to: safeTxs[i].to,
                value: vm.toString(safeTxs[i].value),
                data: safeTxs[i].data
            });
        }

        return vm.serializeJsonType(
            // it is important to include the input argument names as the utility will use them
            "SafeTxImport(string version,string chainId,uint256 createdAt,SafeTxMeta meta,SafeTx[] transactions)SafeTxMeta(string name,string description,string txBuilderVersion,string createdFromSafeAddress,string createdFromOwnerAddress,string checksum)SafeTx(address to,string value,bytes data)",
            abi.encode(SafeTxImport({
                version: "1.0",
                chainId: vm.toString(chainId),
                createdAt: block.timestamp * 1000,
                meta: SafeTxMeta({
                    name: "Transactions Batch",
                    description: "",
                    txBuilderVersion: "",
                    createdFromSafeAddress: "",
                    createdFromOwnerAddress: "",
                    checksum: ""
                }),
                transactions: convertedSafeTxs
            }))
        );
    }

    /// @notice Adds one owner-gated call to the list.
    /// @dev The deployer deploys new contracts. A script collects each call that needs the owner
    ///      role in a list. `executeOrHandOff` then sends the list or hands it to the Safe.
    function queue(GnosisTransaction[] storage gatedCalls, address to, bytes memory data) internal {
        gatedCalls.push(GnosisTransaction({to: to, value: 0, data: data}));
    }

    function queueAll(GnosisTransaction[] storage gatedCalls, GnosisTransaction[] memory calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            gatedCalls.push(calls[i]);
        }
    }

    function queueUpgrade(
        GnosisTransaction[] storage gatedCalls,
        address proxy,
        address implementation,
        string memory name
    ) internal {
        if (proxy == address(0)) revert("Missing proxy address");
        queue(gatedCalls, proxy, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, "")));
        console2.log(string.concat("queued upgrading proxy ", name, ":"), proxy);
    }

    /// @dev A recorded proxy keeps its address and takes the new code. A zero one gets a new proxy.
    ///      The upgrade needs the owner role, so it goes to the gated calls.
    function deployOrUpgrade(
        GnosisTransaction[] storage gatedCalls,
        string memory name,
        address recorded,
        address implementation,
        bytes memory initCall,
        bytes32 proxySalt
    ) internal returns (address) {
        console2.log(string.concat("deployed new implementation ", name, ":"), implementation);
        return upgradeOrNewProxy(gatedCalls, name, recorded, implementation, initCall, proxySalt);
    }

    /// @dev The same as `deployOrUpgrade`, for an implementation that the caller already logged.
    function upgradeOrNewProxy(
        GnosisTransaction[] storage gatedCalls,
        string memory name,
        address recorded,
        address implementation,
        bytes memory initCall,
        bytes32 proxySalt
    ) internal returns (address) {
        if (recorded != address(0)) {
            queueUpgrade(gatedCalls, recorded, implementation, name);
            return recorded;
        }
        address proxy = address(new ERC1967Proxy{salt: proxySalt}(implementation, initCall));
        console2.log(string.concat("queued deploying new proxy ", name, ":"), proxy);
        return proxy;
    }

    /// @notice Tells if the account holds the owner role on the auth.
    function hasOwnerRole(address auth, address account) internal view returns (bool) {
        return BorgAuth(auth).userRoles(account) >= BorgAuth(auth).OWNER_ROLE();
    }

    /// @notice Runs the owner-gated calls of a deployment.
    /// @dev When `direct` is true, the deployer sends the calls itself.
    ///      When `direct` is false, the Safe must sign the calls as one batch. The script runs the calls
    ///      as the Safe in the simulation, then prints the batch and writes it to `jsonPath`.
    ///      A failed call stops the script before it broadcasts anything.
    ///      Both paths check that each upgraded proxy holds its new implementation.
    function executeOrHandOff(
        GnosisTransaction[] memory safeTxs,
        uint256 chainId,
        uint256 deployerPrivateKey,
        address safe,
        bool direct,
        string memory jsonPath
    ) internal {
        if (direct) {
            console2.log("Deployer has authority. It sends %d gated calls itself.", safeTxs.length);
            vm.startBroadcast(deployerPrivateKey);
            _callAll(safeTxs);
            vm.stopBroadcast();
        } else {
            console2.log("Deployer has no authority. The Safe must sign %d gated calls.", safeTxs.length);
            console2.log("Safe:", safe);
            for (uint256 i = 0; i < safeTxs.length; i++) {
                vm.prank(safe);
                Address.functionCallWithValue(safeTxs[i].to, safeTxs[i].data, safeTxs[i].value);
            }
            if (safeTxs.length > 0) _printAndWrite(safeTxs, chainId, jsonPath);
        }
        _verifyUpgrades(safeTxs);
    }

    function _callAll(GnosisTransaction[] memory safeTxs) private {
        for (uint256 i = 0; i < safeTxs.length; i++) {
            Address.functionCallWithValue(safeTxs[i].to, safeTxs[i].data, safeTxs[i].value);
        }
    }

    function _printAndWrite(GnosisTransaction[] memory safeTxs, uint256 chainId, string memory jsonPath) private {
        string memory safeTxJson = formatSafeTxJson(safeTxs, chainId);
        console2.log("Safe tx JSON (can be imported to Safe Transaction Builder):");
        console2.log("==== JSON data start ====");
        console2.log(safeTxJson);
        console2.log("==== JSON data end ====");
        vm.writeFile(jsonPath, safeTxJson);
        console2.log("Safe tx JSON written to:", jsonPath);
    }

    /// @dev An upgrade call to an address with no code does not revert, so read the slot to be sure.
    function _verifyUpgrades(GnosisTransaction[] memory safeTxs) private view {
        for (uint256 i = 0; i < safeTxs.length; i++) {
            bytes memory data = safeTxs[i].data;
            if (data.length < 4 || bytes4(data) != UUPSUpgradeable.upgradeToAndCall.selector) continue;

            bytes memory args = new bytes(data.length - 4);
            for (uint256 j = 0; j < args.length; j++) {
                args[j] = data[j + 4];
            }
            (address implementation,) = abi.decode(args, (address, bytes));
            if (address(uint160(uint256(vm.load(safeTxs[i].to, IMPLEMENTATION_SLOT)))) != implementation) {
                revert ImplementationMismatch(safeTxs[i].to, implementation);
            }
        }
    }

    function parseSafeTxJson(string memory json) internal returns (SafeTxImport memory) {
        return abi.decode(vm.parseJson(json), (SafeTxImport));
    }
}
