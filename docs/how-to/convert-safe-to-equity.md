# Convert SAFEs to equity

When a cyberCORP runs a priced round, outstanding SAFEs convert to equity.
The `SafeCertificateConverter` computes the conversion plan from round data.

> **The `SafeCertificateConverter` is currently a stub** — the body of
> `computeConversion` is commented out in the source and the function
> returns an empty plan. This guide describes the intended use; do not rely
> on it for live conversions until the implementation lands. See
> [SafeCertificateConverter](../reference/contracts/SafeCertificateConverter.md).

## Intended usage

```solidity
import {ICertificateConverter} from "src/interfaces/ICertificateConverter.sol";

ConversionPlan memory plan = ICertificateConverter(CONVERTER).computeConversion(
    roundManager,   // the RoundManager running the priced round
    roundId,        // bytes32 — the priced round
    certPrinter,    // the SAFE cert printer
    tokenId         // the SAFE cyberCERT to convert
);
```

The converter reads the SAFE cert's `investmentAmountUSD` and
`issuerUSDValuationAtTimeOfInvestment`, the round's price and cap-table
snapshot, and applies the round's rounding policy to produce a share count
and target class/series.

The resulting plan is then executed by issuing the new equity cyberCERTs
through the IssuanceManager (see [Issue a cyberCERT](issue-a-cybercert.md))
and voiding the SAFE certs.

## Related

* [SafeCertificateConverter](../reference/contracts/SafeCertificateConverter.md),
  [RoundManager](../reference/contracts/RoundManager.md).
