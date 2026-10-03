# SafeCertificateConverter

Computes a plan for converting a SAFE Ledger Entry Token (LET) into
equity, from a RoundManager's round data.

* **Source:** [`src/converters/SafeCertificateConverter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/converters/SafeCertificateConverter.sol)
* **Implements:** `ICertificateConverter`

> **Stub.** The body of `computeConversion` is commented out, and the
> function returns an empty `ConversionPlan`. The intended algorithm is
> kept in the source as a comment. Do not use this contract for live
> conversions.

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

1. Read the source SAFE LET's `investmentAmountUSD` and
   `issuerUSDValuationAtTimeOfInvestment`.
2. Read round data from the RoundManager: the cap table snapshot's
   `cCapUsed`, the rounding policy, the round price, and the primary
   security class and series.
3. Compute the SAFE price as `PMVC / CCap`, and take the lower of the SAFE
   price and the round price as the price basis.
4. Compute `shares = investmentAmount / priceBasis`, applying the round's
   rounding policy (floor, ceil or round-half-up).
5. Return a `ConversionPlan` with the share count, price basis, and target
   class and series.
