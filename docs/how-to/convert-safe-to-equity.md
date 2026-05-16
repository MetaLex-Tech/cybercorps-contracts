# Convert SAFEs to equity

When a cyberCORP runs its first priced round, outstanding SAFEs must convert
into the new preferred series. The `SafeCertificateConverter` computes the
conversion plan from a round-pricing snapshot and a cap-table snapshot, and
the `IssuanceManager` executes it.

## Prerequisites

* You have one or more SAFE cyberCERTs outstanding (issued via the
  [`SAFEExtension`](../reference/extensions.md)).
* You have configured the priced round in the `RoundManager` and know its
  `pricePerShare` and `preMoneyValuation`.
* The Series A `ShareExtension` parameters (liquidation preference, etc.) are
  set.

## Steps

### 1. Snapshot the cap table

```solidity
bytes32 capTableSnapshot = cyberShares.snapshot();
```

### 2. Compute the plan

```solidity
ISafeCertificateConverter converter = ISafeCertificateConverter(CONVERTER);

ConversionPlan memory plan = converter.computePlan(
    safeCertIds,        // uint256[] of SAFE certs to convert
    capTableSnapshot,
    RoundPricing({
        pricePerShare: 2.50e6,        // $2.50 / share in USDC
        preMoneyValuation: 20_000_000e6
    })
);
```

The plan applies each SAFE's valuation cap, discount and MFN provisions
(per its `SAFEExtension` metadata) to produce a per-SAFE share count and
residual cash refund (if any).

### 3. Review and execute

Inspect `plan.entries[i]` for each SAFE. When satisfied:

```solidity
issuanceManager.executeSafeConversion(plan);
```

The call will:

* burn each input SAFE cyberCERT,
* mint a Series A `ShareExtension`-typed cyberCERT to each former SAFE holder,
* endorse each new cert with a reference to the conversion event,
* refund any residual to the holder (rare; depends on rounding policy).

## Related

* Reference:
  [`SafeCertificateConverter`](../reference/contracts/SafeCertificateConverter.md),
  [Extensions](../reference/extensions.md).
* Tutorial: [Run a cyberRAISE round](../tutorials/run-a-cyberraise-round.md).
