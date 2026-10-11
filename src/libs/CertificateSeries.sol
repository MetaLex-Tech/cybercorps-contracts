// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SecuritySeries} from "../CyberCorpConstants.sol";

/// @title CertificateSeries
/// @notice The series text that a certificate shows after its class. The URI renderer and the image
///         renderer use the same rule, so the JSON and the SVG always agree.
library CertificateSeries {
    /// @notice The free-text series name of the certificate, or the fixed label of its series enum
    ///         when the name is empty.
    /// @dev The name is shown as stored. It is not prefixed with "Series", because a stored name such
    ///      as "Series Seed 2" usually includes that word already.
    function text(string memory name, SecuritySeries series) internal pure returns (string memory) {
        return bytes(name).length != 0 ? name : label(series);
    }

    /// @notice The fixed display label of a series enum. NA and unknown values have no label.
    function label(SecuritySeries series) internal pure returns (string memory) {
        if (series == SecuritySeries.SeriesPreSeed) return "Pre-Seed";
        if (series == SecuritySeries.SeriesSeed) return "Series Seed";
        if (series == SecuritySeries.SeriesA) return "Series A";
        if (series == SecuritySeries.SeriesB) return "Series B";
        if (series == SecuritySeries.SeriesC) return "Series C";
        if (series == SecuritySeries.SeriesD) return "Series D";
        if (series == SecuritySeries.SeriesE) return "Series E";
        if (series == SecuritySeries.SeriesF) return "Series F";
        if (series == SecuritySeries.ACE) return "ACE";
        return "";
    }

    /// @notice Reads the leading string of the leading struct member of an ABI-encoded struct. Returns
    ///         "" when `data` does not hold one.
    /// @dev `data` is `abi.encode(outer)`, where the first member of `outer` is a struct whose first
    ///      member is a string. `ShareCertData.terms.seriesName` has this shape. The `series.seriesName`
    ///      of a V3 `resolveCert` result also has it.
    ///      The function follows the three head offsets and checks each read against `data.length`. It
    ///      does no ABI decoding and cannot revert, so malformed data gives "".
    function leadingName(bytes memory data) internal pure returns (string memory name) {
        uint256 at;
        // Offset of the outer tuple, then of its first member, then of that member's first string.
        for (uint256 hop; hop < 3; ++hop) {
            (bool ok, uint256 offset) = _word(data, at);
            if (!ok || offset > data.length) return "";
            at += offset;
        }
        (bool found, uint256 size) = _word(data, at);
        // `found` gives `at + 32 <= data.length`, so the subtraction cannot underflow.
        if (!found || size > data.length - at - 32) return "";
        name = new string(size);
        assembly ("memory-safe") {
            let from := add(add(data, 64), at)
            let to := add(name, 32)
            for { let i := 0 } lt(i, size) { i := add(i, 32) } { mstore(add(to, i), mload(add(from, i))) }
            // Clear the bytes that the last word copied past the end of the name.
            mstore(add(to, size), 0)
        }
    }

    /// @dev The 32-byte word at byte `at` of `data`, or `ok == false` when it is not all inside `data`.
    function _word(bytes memory data, uint256 at) private pure returns (bool ok, uint256 value) {
        if (data.length < 32 || at > data.length - 32) return (false, 0);
        assembly ("memory-safe") {
            value := mload(add(add(data, 32), at))
        }
        ok = true;
    }
}
