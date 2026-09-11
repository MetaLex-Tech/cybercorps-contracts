// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @dev Bounds optional calls before copying returndata. Dynamic ABI decoding must occur in an
/// external frame caught by the renderer: Solidity try/catch does not catch caller-side decoding.
library MetadataCall {
    error UnavailableMetadata();

    function read(address target, bytes memory input) internal view returns (bytes memory output) {
        bool ok;
        (ok, output) = probe(target, input);
        if (!ok) revert UnavailableMetadata();
    }

    function word(address target, bytes memory input) internal view returns (bool ok, uint256 value) {
        bytes memory output;
        (ok, output) = probe(target, input);
        if (!ok || output.length != 32) return (false, 0);
        value = abi.decode(output, (uint256));
    }

    function probe(address target, bytes memory input) private view returns (bool ok, bytes memory output) {
        if (target.code.length == 0) return (false, new bytes(0));
        // Enough for the SVG path and typical extensions, without allowing an optional dependency
        // to consume an unlimited call budget or force an unbounded returndata allocation.
        assembly ("memory-safe") {
            ok := staticcall(2000000, target, add(input, 32), mload(input), 0, 0)
            let size := returndatasize()
            if gt(size, 131072) { ok := 0 }
            output := mload(0x40)
            mstore(output, 0)
            if ok {
                mstore(output, size)
                returndatacopy(add(output, 32), 0, size)
            }
            mstore(0x40, and(add(add(output, mload(output)), 63), not(31)))
        }
    }
}
