# Security types

The instrument types the protocol can issue are the `SecurityClass` enum in
[`src/CyberCorpConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorpConstants.sol).
A CyberCertPrinter is created for a specific `SecurityClass` (and
`SecuritySeries`).

## `SecurityClass`

```solidity
enum SecurityClass {
    SAFE,
    SAFT,
    SAFTE,
    TokenPurchaseAgreement,
    TokenWarrant,
    ConvertibleNote,
    CommonStock,
    StockOption,
    PreferredStock,
    RestrictedStockPurchaseAgreement,
    RestrictedStockUnit,
    RestrictedTokenPurchaseAgreement,
    RestrictedTokenUnit
}
```

## `SecuritySeries`

```solidity
enum SecuritySeries {
    SeriesPreSeed,
    SeriesSeed,
    SeriesA,
    SeriesB,
    SeriesC,
    SeriesD,
    SeriesE,
    SeriesF,
    NA,
    ACE
}
```

`NA` is used where a series is not applicable; `ACE` marks securities issued
through an ACE offering.

## `SecurityStatus`

```solidity
enum SecurityStatus { Unassigned, Assigned, Void }
```

A cyberCERT's status; `Void` is set by `CyberCertPrinter.voidCert`.

## Instrument-specific metadata

Each security class is paired with a [certificate extension](extensions.md)
that encodes its instrument-specific terms. `CyberCorpConstants.sol` also
defines supporting enums used by those extensions — `ExercisePriceMethod`,
`TokenCalculationMethod`, `UnlockStartTimeType`, `UnlockingIntervalType` —
for token-warrant and vesting instruments.
