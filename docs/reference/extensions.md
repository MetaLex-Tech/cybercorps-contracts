---
description: "Certificate and corp extensions: per-security-type data and JSON rendering"
---

# Certificate extensions

Extensions are pluggable metadata contracts. Each `LedgerEntryToken` cert
printer (formerly `CyberCertPrinter`) points at **one** extension contract,
set when the printer is created. The extension decodes the instrument-specific
attributes built into the cyberCERT's `tokenURI` from two opaque payloads:

* **Per-cert data** — `CertificateDetails.extensionData`, decoded by the
  base `ICertificateExtension` surface (`supportsExtensionType`,
  `getExtensionURI`).
* **Series data** (V3 extensions) — the printer's `seriesData`, terms shared
  by every cert the printer issues. `ICertificateExtensionV3` adds
  `supportsSeriesExtensionData()` and `getSeriesExtensionURI(seriesData)`;
  callers feature-detect V3 so V1/V2 extensions keep working untouched.

Each extension is its own UUPS-upgradeable contract (in
[`src/storage/extensions/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/storage/extensions)).
Older versions remain deployed: a printer's payload is always decoded by the
extension version that printer points at.

## ShareExtension / ShareExtensionV3

Preferred and Common stock. NVCA-aligned terms, rendered to JSON via
`JsonLib`; prices and share quantities are 18-decimal fixed-point. The
per-cert `ShareCertData` combines:

* `SeriesTerms` — series name, par value, authorized shares, original issue
  price, liquidation preference (multiple + type), seniority, dividends,
  conversion (`targetConversionSeriesId` string, conversion price,
  anti-dilution: broad-/narrow-based weighted average, full ratchet, none),
  voting (`votesPerShare`, board seats, class/series votes), redemption,
  pay-to-play, registration rights, pro rata rights, information rights, and
  drag-along (each rights flag paired with a terms URI).
* `CertificateData` — per-cert facts, including DGCL §156 partly-paid stock
  (`isPartlyPaid`, `amountPaid`, `totalConsideration`), representation type
  (certificated / uncertificated / tokenized), and holding-period tacking.
* Arrays of mandatory-conversion triggers, special voting rights, transfer
  restrictions, and split history.

`ShareExtensionV3` additionally encodes `SeriesTerms` as the printer's
`seriesData`. The companion `ShareExtensionLogic` contract offers
validation and encode/decode/update helpers (`validateShareData`,
`updateSeriesTerms`, …) for offchain tooling and scripts.

## SAFEExtension / SAFEExtensionV3

Simple Agreement for Future Equity. Per-cert `SAFEData` holds a
`customProvisions` string; the SAFE economics (investment amount, valuation)
live in the base `CertificateDetails`. `SAFEExtensionV3` adds series-scope
`SAFESeriesData` (series name, governing-document URIs, custom provisions).

Feeds [`SafeCertificateConverter`](contracts/SafeCertificateConverter.md).

## ACESAFEExtension / ACESAFEExtensionV3

ACE-specific SAFE variant for token-to-equity conversions, used by
[PumpCorpFactory](factories.md#specialised-factories). Per-cert
`ACESAFEData`: denomination token plus custom provisions;
`ACESAFEExtensionV3` adds the series-scope payload.

## SAFTExtension / SAFTExtensionV2 / SAFTExtensionV3

Simple Agreement for Future Tokens.

* Unlock schedule (start-time type, start time, period, interval type)
* Cliff period and cliff percentage
* V2 adds a `customProvisions` string
* V3 adds the series-scope payload

## SAFTEExtension / SAFTEExtensionV2 / SAFTEExtensionV3

Simple Agreement for Future Tokens or Equity. SAFT-style unlock fields plus
the token-amount calculation method, minimum company reserve, token premium
multiplier, and protocol valuation at time of investment. V2 adds
`customProvisions`; V3 adds the series-scope payload.

## TokenWarrantExtension / TokenWarrantExtensionV2 / TokenWarrantExtensionV3

Token warrants.

* Exercise price and method (per token / per warrant)
* Token-amount calculation method (equity pro rata to company reserve or to
  token supply, dollar pro rata to protocol valuation)
* Unlock parameters (start, period, cliff, interval)
* Latest expiration time
* V2 adds `customProvisions`; V3 adds the series-scope payload

## FundInterestExtension

Fund (LP) interests, with a split LET/series model:

* Per-cert `FundInterestData` — `acquisitionDate`,
  `tackedFromAcquisitionDate` (the Rule 144 tacking anchor read by
  `HoldingPeriodCondition`), affiliate/control-person flag, custom
  provisions.
* Series-scope `FundInterestSeriesData` — interest class, fund entity type,
  ICA exception relied upon, management fee and carried interest (bps),
  distribution waterfall position, governing-document URIs, and security
  identification fields.

The typed `IFundInterestExtension` interface exposes `acquisitionDate`,
`tackedFromAcquisitionDate`, and `withTackedFrom` so consumers read/rewrite
the payload through the extension instead of decoding the struct directly.

## CyberCorp extensions

A parallel family implements `ICyberCorpExtension` and attaches to the
**corp** rather than a cert printer, via
`CyberCorp.setExtension(extension, extensionType)` /
`setExtensionData(bytes)` (both `onlyOwner`):

| Extension | Adds |
|---|---|
| `CyberCorpExtension` / `CyberCorpExtensionV2` | Corp-level profile metadata (website, business line, entity id, metadata URI; V2 adds investor-relations URI and transfer agent). |
| `CyberCorpComplianceExtension` | Compliance parameters (ERISA allowance, ownership bounds, holder count cap, CFIUS-approval flag, holder restrictions, fee details). |
| `CyberCorpFundExtension` | Per-SPV fund metadata (entity type, ICA exception relied upon, Reg S issuer category, holder cap, portfolio holdings, provenance attestation, governing-document URIs). |

## Registering an extension

The extension and its series payload are supplied when the printer is
created:

```solidity
issuanceManager.createCertPrinter(
    ledger, name, ticker, certificateUri,
    securityType, securitySeries,
    address(extension),   // decodes both per-cert extensionData and seriesData
    seriesData            // "" when the extension has no series section
);
```

Per-cert `CertificateDetails.extensionData` is then `abi.encode`d to the
extension's expected struct at issuance. The printer's series payload can be
updated later through `LedgerEntryToken.setSeriesData`
(IssuanceManager/admin-gated).
