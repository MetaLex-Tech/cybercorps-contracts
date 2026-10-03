---
description: "Certificate and corp extensions: per-security-type data and JSON rendering"
---

# Certificate extensions

Extensions are pluggable metadata contracts. Each LET contract (a
`LedgerEntryToken` deployment) points at **one** extension contract, set
when the LET contract is created. The extension decodes the
instrument-specific attributes that appear in the `tokenURI` of each
Ledger Entry Token (LET), from up to three opaque payloads, one per scope:

* **LET scope:** `CertificateDetails.extensionData` on each LET, decoded
  by the base `ICertificateExtension` surface (`supportsExtensionType`,
  `getExtensionURI(data)`).
* **Series scope:** the LET contract's `seriesData`, terms shared by every
  LET it issues.
* **Class scope:** the `classData` of the LET contract's security class on
  the IssuanceManager (`SecurityClassInfo`). Only `ShareExtensionV3` reads
  it.

A V1 or V2 extension renders the LET payload alone. A V3 extension
(`ICertificateExtensionV3`) renders the whole certificate: it answers
`supportsResolvedExtensionData()` with `true`, and
`getResolvedExtensionURI(printer, tokenId)` reads every scope through the
LET contract, merges them and returns one JSON section. The
[CertificateUriBuilder](contracts/CertificateUriBuilder.md) probes for
that function and falls back to the LET payload for V1 and V2 extensions.
Each V3 extension also offers typed helpers that the shared interface
cannot declare, because their return types differ per instrument:
`decodeExtensionData(bytes)`, `encodeExtensionData(<stored shape>)`, and
`resolveCert(printer, tokenId)`, which returns the resolved typed data.

{% hint style="warning" %}
A V3 extension calls `getSeriesInfo` on the LET contract, and
`ShareExtensionV3` also calls `getPrinterClassId` / `getSecurityClass` on
the IssuanceManager. LET contracts and IssuanceManagers below v5 lack some
of these, and the URI builder does not catch an extension revert, so
binding a V3 extension to a LET contract of a company that has not
upgraded to v5 makes `tokenURI` revert. Bind V3 extensions only to LET
contracts of v5 companies.
{% endhint %}

Each extension is its own UUPS-upgradeable contract (in
[`src/storage/extensions/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/storage/extensions)).
Every version stays deployed: a LET contract's payloads are decoded by the
extension version it points at, and the V3 extensions have their own
proxies (addresses in [Deployments](deployments.md)). Every extension
JSON-escapes the strings it writes.

## ShareExtension / ShareExtensionV3

Preferred and common stock. NVCA-aligned terms, rendered to JSON with
`JsonLib`; prices and share quantities are 18-decimal fixed-point. The
`ShareCertData` a LET renders combines:

| Part | Contents |
|---|---|
| `SeriesTerms` | Series name, par value, authorized shares, original issue price, liquidation preference (multiple and type), seniority, dividends, conversion (`targetConversionSeriesId` string, conversion price, anti-dilution: broad- or narrow-based weighted average, full ratchet, none), voting (`votesPerShare`, board seats, class and series votes), redemption, pay-to-play, registration rights, pro rata rights, information rights and drag-along, each rights flag paired with a terms URI. |
| `CertificateData` | Per-LET facts, including DGCL §156 partly paid stock (`isPartlyPaid`, `amountPaid`, `totalConsideration`), representation type (certificated, uncertificated or tokenized) and holding-period tacking. |
| Lists | Mandatory-conversion triggers, special voting rights, transfer restrictions and split history. |

`ShareExtension` (V1) stores a whole `ShareCertData` on each LET.
`ShareExtensionV3` stores a `ShareCertDataLayer` at each of the three
scopes (class, series, LET) and merges them:

* `certificateData` and `terms` are single values: the most specific layer
  that sets one wins (LET, then series, then class).
* The four lists append from class to series to LET, so a LET payload
  cannot drop a class-level restriction. A layer's overwrite flag
  (`overwriteConversionTriggers`, `overwriteVotingRights`,
  `overwriteTransferRestrictions`, `overwriteSplitHistory`) makes its list
  replace the lists above it. To clear a section, set an empty list and
  its flag.
* `terms`, `conversionTriggers` and `splitHistory` must sit on the same
  layer, because a stock split rescales all three. The series is the
  recommended scope.

Payloads carry no version tag, so a LET contract's payloads and its
extension must be the same generation. Bind `ShareExtensionV3` when the
LET contract is created, and do not point a LET contract that already
holds whole `ShareCertData` payloads at it. The merge code lives in the
linked `ShareCertDataLayerLib`. The companion `ShareExtensionLogic`
contract offers validation and update helpers over a layer
(`validateShareData`, `updateSeriesTerms`, `recordStockSplit`, …) for
offchain tooling and scripts; a helper that edits an existing section
reverts when the layer does not set that section.

## SAFEExtension / SAFEExtensionV3

Simple Agreement for Future Equity. Per-LET `SAFEData` holds a
`customProvisions` string; the SAFE economics (investment amount,
valuation) live in the base `CertificateDetails`. `SAFEExtensionV3` adds
series-scope `SAFESeriesData` (series name, governing-document URIs,
custom provisions), rendered as a `SAFESeriesDetails` section next to the
LET fields.

Feeds [`SafeCertificateConverter`](contracts/SafeCertificateConverter.md).

## ACESAFEExtension / ACESAFEExtensionV3

The ACE SAFE variant for token-to-equity conversions, used by
[PumpCorpFactory](factories.md#specialised-factories). Per-LET
`ACESAFEData` holds the denomination token and custom provisions.
`ACESAFEExtensionV3` adds series-scope `ACESAFESeriesData` (series name,
denomination token, governing-document URIs, custom provisions).

## SAFTExtension / SAFTExtensionV2 / SAFTExtensionV3

Simple Agreement for Future Tokens.

* Unlock schedule (start-time type, start time, period, interval type)
* Cliff period and cliff percentage
* V2 adds a `customProvisions` string
* V3 adds series-scope `SAFTSeriesData` (series name, token generation
  event date, governing-document URIs, custom provisions)

## SAFTEExtension / SAFTEExtensionV2 / SAFTEExtensionV3

Simple Agreement for Future Tokens or Equity. SAFT-style unlock fields
plus the token-amount calculation method, minimum company reserve, token
premium multiplier, and protocol valuation at time of investment. V2 adds
`customProvisions`; V3 adds series-scope `SAFTESeriesData` (series name,
governing-document URIs, custom provisions).

## TokenWarrantExtension / TokenWarrantExtensionV2 / TokenWarrantExtensionV3

Token warrants.

* Exercise price and method (per token or per warrant)
* Token-amount calculation method (equity pro rata to company reserve or
  to token supply, dollar pro rata to protocol valuation)
* Unlock parameters (start, period, cliff, interval)
* Latest expiration time
* V2 adds `customProvisions`; V3 adds series-scope
  `TokenWarrantSeriesData` (series name, underlying-token description,
  governing-document URIs, custom provisions)

For the SAFE, ACE SAFE, SAFT, SAFTE and token-warrant V3 extensions, and
for fund interests, the LET and series scopes hold different fields, so
`resolveCert` returns the two side by side (`{series, certificate}`)
instead of merging them.

## FundInterestExtensionV3

Fund (LP) interests, with separate LET and series data:

* Per-LET `FundInterestData`: `acquisitionDate`,
  `tackedFromAcquisitionDate` (the Rule 144 tacking anchor that
  `HoldingPeriodCondition` reads), an affiliate or control-person flag,
  and custom provisions.
* Series-scope `FundInterestSeriesData`: interest class, fund entity type,
  ICA exception relied upon, management fee and carried interest (bps),
  distribution waterfall position, governing-document URIs, and security
  identification fields.

The typed `IFundInterestExtension` interface exposes `acquisitionDate`,
`tackedFromAcquisitionDate` and `withTackedFrom`, so consumers read and
rewrite the payload through the extension instead of decoding the struct.

## CyberCorp extensions

A parallel family implements `ICyberCorpExtension` and attaches to the
**corp** instead of a LET contract, through
`CyberCorp.setExtension(extension, extensionType)` /
`setExtensionData(bytes)` (both `onlyOwner`):

| Extension | Adds |
|---|---|
| `CyberCorpExtension` / `CyberCorpExtensionV2` | Corp-level profile metadata (website, business line, entity id, metadata URI; V2 adds investor-relations URI and transfer agent). |
| `CyberCorpComplianceExtension` | Compliance parameters (ERISA allowance, ownership bounds, holder count cap, CFIUS-approval flag, holder restrictions, fee details). |
| `CyberCorpFundExtension` | Per-SPV fund metadata (entity type, ICA exception relied upon, Reg S issuer category, holder cap, portfolio holdings, provenance attestation, governing-document URIs). |

## Registering an extension

The extension and its series payload are supplied when the LET contract
is created:

```solidity
issuanceManager.createCertPrinter(
    ledger, name, ticker, certificateUri,
    securityType, securitySeries,
    address(extension),   // decodes the LET, series (and class) payloads
    seriesData            // "" when the extension has no series section
);
```

Per-LET `CertificateDetails.extensionData` is then `abi.encode`d to the
extension's expected struct at issuance (for `ShareExtensionV3`, a
`ShareCertDataLayer`; an empty payload takes every section from the series
and class). The series payload can be updated later through
`LedgerEntryToken.setSeriesData` (IssuanceManager or admin), and a share
class payload through `IssuanceManager.updateSecurityClass`.
