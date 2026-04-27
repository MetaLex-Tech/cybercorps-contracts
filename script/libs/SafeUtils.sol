// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Vm, console2} from "forge-std/Test.sol";
import {GnosisTransaction} from "./safe.sol";

// Access hidden cheatcodes
interface EnhancedVm is Vm {
    function serializeJsonType(string calldata typeDescription, bytes memory value) external pure returns (string memory json);
}

library SafeUtils {
    EnhancedVm constant vm = EnhancedVm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function formatSafeTxJson(GnosisTransaction[] memory safeTxs) internal returns (string memory) {
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
                chainId: "1",
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

    function parseSafeTxJson(string memory json) internal returns (SafeTxImport memory) {
        return abi.decode(vm.parseJson(json), (SafeTxImport));
    }
}
