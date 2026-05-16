# SafeCertificateConverter

Computes a conversion plan for converting a SAFE certificate into equity,
based on round data from a RoundManager.

* **Source:** [`src/converters/SafeCertificateConverter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/converters/SafeCertificateConverter.sol)
* **Implements:** `ICertificateConverter`

> **Currently a stub.** In the present source, the body of
> `computeConversion` is commented out and the function returns an empty
> `ConversionPlan`. The intended algorithm is preserved in the source as a
> comment. Do not rely on this contract for live conversions yet.

## Interface

```solidity
function computeConversion(
    address roundManager,
    bytes32 roundId,
    address certPrinter,
    uint256 tokenId
) external view returns (ConversionPlan memory plan);
```

## Intended algorithm (from the source comments)

1. Read the source SAFE cert's `investmentAmountUSD` and
   `issuerUSDValuationAtTimeOfInvestment`.
2. Read round data from the RoundManager: the cap-table snapshot's `cCapUsed`,
   the rounding policy, the round price, and the primary security
   class/series.
3. Compute the SAFE price as `PMVC / CCap`, take the lower of the SAFE price
   and the round price as the price basis.
4. Compute `shares = investmentAmount / priceBasis`, applying the round's
   rounding policy (floor / ceil / round-half-up).
5. Return a `ConversionPlan` with the share count, price basis, and target
   class/series.

When the implementation is completed, this page will be updated with the
exact `ConversionPlan` shape and behaviour.
