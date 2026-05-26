# Certificate extensions

Extensions are pluggable metadata contracts registered on a `CyberCertPrinter`
for a given security type. They produce the instrument-specific attributes
built into the cyberCERT's `tokenURI` and enforce any instrument-specific
rules at issuance time.

Each extension is its own UUPS-upgradeable contract.

## ShareExtension

Preferred and Common stock. NVCA-aligned series terms.

* Liquidation preference
* Conversion ratio (preferred ↔ common)
* Anti-dilution (broad-based weighted average, full ratchet, none)
* Voting power
* Series identifier ("Series Seed", "Series A", "Series Pre-A", etc.)

## SAFEExtension

Simple Agreement for Future Equity.

* Custom provisions field
* Valuation cap
* Discount
* MFN flag
* Conversion trigger event

Feeds [`SafeCertificateConverter`](contracts/SafeCertificateConverter.md).

## ACESAFEExtension

ACE-specific SAFE variant for token-to-equity conversions, used by
[PumpCorpFactory](factories.md#pumpcorpfactory).

## SAFTExtension / SAFTExtensionV2

Simple Agreement for Future Tokens.

* Unlock schedule
* Cliff period
* Vesting interval
* Token (or token-yet-to-be-deployed) reference

## SAFTEExtension / SAFTEExtensionV2

Simple Agreement for Future Tokens or Equity. Combines SAFT and SAFE
attributes; the conversion path is determined by which trigger event fires
first.

## TokenWarrantExtension / TokenWarrantExtensionV2

Token warrants.

* Exercise price
* Token-amount calculation method (fixed, pro rata, formula)
* Unlock parameters
* Expiration

## Registering an extension

```solidity
certPrinter.setExtension(SECURITY_TYPE_SAFE, address(safeExtension));
```

A `CertIssuance.extensionData` is then `abi.encode`d to the extension's
expected struct.
