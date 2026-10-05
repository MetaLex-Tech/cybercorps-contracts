# Security types

The `SecurityClass` enum in
[`src/CyberCorpConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorpConstants.sol)
lists the instrument types the protocol can issue. Each LET contract (a
`LedgerEntryToken` deployment) is created for one `SecurityClass` and one
`SecuritySeries`.

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

`NA` marks a security with no series; `ACE` marks securities issued
through an ACE offering.

## `SecurityStatus`

```solidity
enum SecurityStatus { Unassigned, Assigned, Void }
```

The status of a Ledger Entry Token (LET). `LedgerEntryToken.voidCert` sets
`Void`, and the IssuanceManager calls it when it voids an emptied LET
(`voidEmptyCerts`, or a seller's LET fully sold in a secondary trade). A
void LET keeps its holder and units but cannot be registered to a new
holder.

## Security classes (`SecurityClassInfo`)

Class-level designations for LETs are registered on the
`IssuanceManager`:

```solidity
struct SecurityClassInfo {
    SecurityClass classType;
    string documentURI;    // class-level governing document
    address dataExtension; // optional ICertificateExtension-style decoder/renderer
    bytes classData;       // extensionData-style opaque payload
}
```

`IssuanceManager.defineSecurityClass` (`onlyOwner`) registers a class.
Each `SecurityClass` value has at most one class, and several LET
contracts can share it. The
[IssuanceManager](contracts/IssuanceManager.md#security-class-registry)
page covers class ids, assignment and updates. `ShareExtensionV3` reads
`classData` as the class-wide layer of every LET in a share class; see
[Certificate extensions](extensions.md).

## Instrument-specific metadata

Each security class is paired with a [certificate extension](extensions.md)
that encodes its instrument-specific terms. `CyberCorpConstants.sol` also
defines supporting enums for token-warrant and vesting instruments:
`ExercisePriceMethod`, `TokenCalculationMethod`, `UnlockStartTimeType`,
`UnlockingIntervalType`.
