// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @notice Bounded-precision cumulative loss index for proportional certificate attribution.
/// @dev An index is mantissa / 2**scale, with mantissa in [2**255, 2**256).
/// Keeping the exponent separately prevents repeated withdrawals from underflowing a fixed-point index.
/// This is accounting metadata: neither the mantissa nor the exponent is a redeemable share supply.
library ProportionalVaultMath {
    uint256 internal constant ONE = 1 << 255;

    /// @dev Requires 0 < remaining <= previous and a normalized mantissa. Rounds toward the pool.
    /// The unnormalized quotient has at least 254 significant bits, even for a one-wei residual pool.
    function reduce(uint256 mantissa, uint256 scale, uint256 remaining, uint256 previous)
        internal
        pure
        returns (uint256 nextMantissa, uint256 nextScale)
    {
        uint256 shift = Math.log2(previous) - Math.log2(remaining);
        if (shift != 0) --shift;
        // remaining << shift <= previous, so neither the shift nor mulDiv's quotient can overflow.
        uint256 quotient = Math.mulDiv(mantissa, remaining << shift, previous);
        uint256 normalize = 255 - Math.log2(quotient);
        nextMantissa = quotient << normalize;
        nextScale = scale + shift + normalize;
    }

    /// @dev Exact floor(amount * current / snapshot / 2**scaleDifference), using normalized mantissas.
    /// Unlike mulDiv followed by a shift, this also handles a 257-bit intermediate quotient.
    function balance(uint256 amount, uint256 current, uint256 snapshot, uint256 scaleDifference)
        internal
        pure
        returns (uint256)
    {
        if (amount == 0 || scaleDifference > 256) return 0;
        if (scaleDifference == 0) return Math.mulDiv(amount, current, snapshot);

        // Divide the amount by two before mulDiv, then recover the exact carry from its remainder.
        // current < 2 * snapshot, so the half-product quotient and the carry always fit uint256.
        uint256 half = amount >> 1;
        uint256 quotient = Math.mulDiv(half, current, snapshot);
        if ((amount & 1) != 0 && mulmod(half, current, snapshot) >= snapshot - (current >> 1)) {
            ++quotient;
        }
        return quotient >> (scaleDifference - 1);
    }
}
