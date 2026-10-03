---
description: The intended SafeCertificateConverter flow for converting SAFE LETs into equity in a priced round; the converter is a stub
---

# Convert SAFEs to equity

When a cyberCORP runs a priced round, its outstanding SAFEs convert to
equity. Each SAFE is recorded as a Ledger Entry Token (LET) on the
company's SAFE LET contract, and `SafeCertificateConverter` is meant to
compute each one's conversion plan from the round's data.

{% hint style="warning" %}
`SafeCertificateConverter` is a stub. The body of `computeConversion` is
commented out in the source, and the function returns an empty plan. Do
not rely on it for live conversions. This guide describes the intended use;
see [SafeCertificateConverter](../reference/contracts/SafeCertificateConverter.md).
{% endhint %}

## Compute the conversion plan

```solidity
import {ICertificateConverter} from "src/interfaces/ICertificateConverter.sol";

ConversionPlan memory plan = ICertificateConverter(CONVERTER).computeConversion(
    roundManager,   // the RoundManager running the priced round
    roundId,        // bytes32, the priced round
    certPrinter,    // the SAFE LET contract
    tokenId         // the SAFE LET to convert
);
```

The converter is designed to read the SAFE LET's `investmentAmountUSD` and `issuerUSDValuationAtTimeOfInvestment`, the
round's price and cap table snapshot, and apply the round's rounding policy
to produce a share count and a target class and series.

## Execute the plan

Issue the new equity LETs through the IssuanceManager (see [Issue a
LET](issue-a-let.md)) and void the SAFE LETs with `voidCert` on the SAFE LET
contract.

Function-level detail is in
[SafeCertificateConverter](../reference/contracts/SafeCertificateConverter.md)
and [RoundManager](../reference/contracts/RoundManager.md).
