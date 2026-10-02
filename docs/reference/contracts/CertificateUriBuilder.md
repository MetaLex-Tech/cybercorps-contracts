# CertificateUriBuilder

Builds the fully onchain token-URI metadata (JSON + SVG) for cyberCERTs.

* **Sources:** [`src/CertificateUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateUriBuilder.sol),
  [`src/CertificateImageBuilderContract.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilderContract.sol),
  [`src/CertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilder.sol),
  [`src/CertificateImageContentBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageContentBuilder.sol),
  [`src/libs/CertificateText.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/CertificateText.sol)
* **Interfaces:** [`IUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IUriBuilder.sol),
  [`ICertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICertificateImageBuilder.sol)
* **Pattern:** UUPS proxy (`UUPSUpgradeable`, `BorgAuthACL`);
  `initialize(address _auth)`, with the SVG generation split out into a
  separately-deployed image-builder contract configured via
  `setImageBuilder(address)` (`onlyOwner`, emits `ImageBuilderUpdated`) to
  stay under contract-size limits. JSON string helpers shared with other
  contracts live in the
  [`JsonLib`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/JsonLib.sol)
  library.

## What it produces

`LedgerEntryToken.tokenURI(tokenId)` delegates to the URI builder
configured on the IssuanceManager, which assembles a
`data:application/json;base64,…` metadata document containing:

* the standard title/type fields and `attributes` (current owner and name,
  amounts, corp identity, security type/series, certificate URI),
* an `image` — an onchain-rendered SVG (see below),
* the corp identity fields and the certificate's details —
  `investmentAmountUSD`, `issuerUSDValuationAtTimeOfInvestment`, and
  `unitsRepresented` are 18-decimal quantities formatted as **exact decimal
  strings** (`from18DecimalsToString`), plus the live `unitsReserved` read
  from the printer (left out for older printers that have no such getter),
* extension-provided JSON, in order: the corp-level fragment
  (`CyberCorp.getExtensionURI`, skipped when the issuer has none) and then
  the certificate's own section from the printer's
  [extension](../extensions.md). A V3 extension that answers
  `supportsResolvedExtensionData()` with `true` renders the whole
  certificate through `getResolvedExtensionURI(printer, tokenId)`, merging
  the cert, series and (for shares) class scopes; a V1 or V2 extension
  renders the cert payload alone through `getExtensionURI(extensionData)`.
  The extension call itself is not caught, so a reverting extension reverts
  the whole `tokenURI` call,
* the `endorsementHistory` array (endorser, timestamp, registry, agreement
  id, investor name and address). The first entry also carries
  `purchaseAgreementDetails` read from the agreement registry: the global
  fields, `companyDetails` and `investorDetails` from the two party slots,
  and the `digitalSignature`. That read is guarded, so a registry that
  cannot answer leaves the endorsement in place without the enrichment,
* `currentOwner`,
* the `restrictiveLegends` array — structured `RestrictiveLegend` records;
  plain-string legacy legends are converted via
  `legacyLegendsToRestrictiveLegends`.

Every string taken from company or holder input is JSON-escaped
(`JsonLib.jsonEscape`), in the builder and in each extension's fragment.

The metadata is built onchain at read time, so a cyberCERT renders from any
node or explorer with no external service.

## The certificate image

The image builder draws a "Ledger Entry Token" certificate from a
`CertificateSVGParamsV2` (the `CertificateSVGParams` fields plus issuer and
owner addresses, consideration, transfer restrictions and void status):

* the company name, token id, and a status pill (**active** or **voided**,
  with a VOIDED stamp across a void certificate),
* **Issuer** (company name and the cyberCORP address) and **Registered
  Owner** (holder name and address),
* class and series,
* **Units** and **Consideration**: for shares and units, the units held and
  the price per share or unit; for convertibles (SAFE, SAFT, SAFTE, token
  purchase agreement, token warrant, convertible note), `1` and the whole
  amount,
* **Issue Date**, from the printer's `issueTimestamp` (blank when unknown),
* the authorizing officer's name and title,
* up to six transfer restrictions, taken from the restrictive legends
  (text, or title when the text is empty).

Names and titles are XML-escaped and truncated to fit the artwork
(`CertificateText.xml`); the full values stay in the JSON. The builder calls
`buildCertificateSVGV2` first and, when the issue date is known, falls back
to the legacy `buildCertificateSVG`, so the URI builder can be upgraded
before or after the image builder. Reads of the issuer, issue date and void status tolerate
printers and managers that lack those functions; if no SVG comes back, the
`image` field is left empty instead of failing the URI.

## Interface

`IUriBuilder` exposes `buildCertificateUri` and
`buildCertificateUriNotEncoded` (raw JSON, no base64 wrapper), each with two
overloads — one taking legacy `string[] certLegend`, one taking
`RestrictiveLegend[]`. Public helpers include `securityClassToString`,
`securityClassToUnit`, `securitySeriesToString`, `restrictiveLegendsToJson`,
`from18DecimalsToString`, and `stripIpfsPrefix`.

> The URI builder is configured on the IssuanceManager (`uriBuilder()` /
> `setUriBuilder`). This page is a high-level description; consult the
> source for the exact function set, which is sizeable.
