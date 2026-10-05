# CertificateUriBuilder

Builds the fully onchain token-URI metadata (JSON and SVG) of every Ledger
Entry Token (LET).

* **Sources:** [`src/CertificateUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateUriBuilder.sol),
  [`src/CertificateImageBuilderContract.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilderContract.sol),
  [`src/CertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilder.sol),
  [`src/CertificateImageContentBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageContentBuilder.sol),
  [`src/libs/CertificateText.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/CertificateText.sol)
* **Interfaces:** [`IUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IUriBuilder.sol),
  [`ICertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICertificateImageBuilder.sol)
* **Pattern:** UUPS proxy (`UUPSUpgradeable`, `BorgAuthACL`) with
  `initialize(address _auth)`. SVG generation sits in a separately
  deployed image-builder contract, set with `setImageBuilder(address)`
  (`onlyOwner`, emits `ImageBuilderUpdated`), to stay under contract-size
  limits. JSON string helpers shared with other contracts live in the
  [`JsonLib`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/JsonLib.sol)
  library.

## What it produces

`LedgerEntryToken.tokenURI(tokenId)` delegates to the URI builder
configured on the IssuanceManager, which assembles a
`data:application/json;base64,…` metadata document containing:

* The standard title and type fields and `attributes` (current owner and
  name, amounts, corp identity, security type and series, certificate
  URI).
* An `image`: an onchain-rendered SVG (see
  [The certificate image](#the-certificate-image)).
* The corp identity fields and the LET's details. `investmentAmountUSD`,
  `issuerUSDValuationAtTimeOfInvestment` and `unitsRepresented` are
  18-decimal quantities that `from18DecimalsToString` renders with **two
  decimal places, truncated** (it divides by `1e16`, so `1.234e18` becomes
  `"1.23"`). The live `unitsReserved`, read from the LET contract, is
  formatted the same way and left out when the LET contract has no such
  getter. These strings are display values: read exact amounts with the
  LET contract's `getCertificateDetails(tokenId)`, not from the metadata.
* Extension-provided JSON, in order: the corp-level fragment
  (`CyberCorp.getExtensionURI`, skipped when the issuer has none), then the
  LET's own section from the LET contract's
  [extension](../extensions.md). A V3 extension that answers
  `supportsResolvedExtensionData()` with `true` renders the whole
  certificate through `getResolvedExtensionURI(printer, tokenId)`, merging
  the LET, series and (for shares) class scopes. A V1 or V2 extension
  renders the LET payload alone through `getExtensionURI(extensionData)`.
  The extension call is not caught, so a reverting extension reverts the
  whole `tokenURI` call.
* The `endorsementHistory` array (endorser, timestamp, registry, agreement
  id, investor name and address). The first entry also carries
  `purchaseAgreementDetails` read from the agreement registry: the global
  fields, `companyDetails` and `investorDetails` from the two party slots,
  and the `digitalSignature`. That read is guarded, so a registry that
  cannot answer leaves the endorsement in place without the enrichment.
* `currentOwner`.
* The `restrictiveLegends` array of structured `RestrictiveLegend`
  records. Plain-string legends are converted through
  `legacyLegendsToRestrictiveLegends`.

Every string taken from company or holder input is JSON-escaped
(`JsonLib.jsonEscape`), in the builder and in each extension's fragment.
The metadata is built onchain at read time, so a LET renders from any
node or explorer with no external service.

## The certificate image

The image builder draws a "Ledger Entry Token" certificate from a
`CertificateSVGParamsV2` (the `CertificateSVGParams` fields plus issuer
and owner addresses, consideration, transfer restrictions and void
status):

* the company name, token id and a status pill (**active** or **voided**,
  with a VOIDED stamp across a void certificate);
* **Issuer** (company name and the cyberCORP address) and **Registered
  Owner** (holder name and address);
* class and series;
* **Units** and **Consideration**: for shares and units, the units held
  and the price per share or unit; for convertibles (SAFE, SAFT, SAFTE,
  token purchase agreement, token warrant, convertible note), `1` and the
  whole amount;
* **Issue Date**, from the LET contract's `issueTimestamp` (blank when
  unknown);
* the authorizing officer's name and title;
* up to six transfer restrictions, taken from the restrictive legends
  (text, or title when the text is empty).

Names and titles are XML-escaped and truncated to fit the artwork
(`CertificateText.xml`); the full values stay in the JSON. The builder
calls `buildCertificateSVGV2`; if that returns nothing and the issue date
is known, it calls `buildCertificateSVG` instead, so the URI builder and
the image builder can be upgraded in either order. Reads of the issuer,
issue date and void status tolerate LET contracts and managers that lack
those functions. If no SVG comes back, the `image` field is left empty and
the rest of the URI still builds.

## Interface

`IUriBuilder` exposes `buildCertificateUri` and
`buildCertificateUriNotEncoded` (raw JSON, no base64 wrapper), each with
two overloads: one taking a `string[] certLegend`, one taking
`RestrictiveLegend[]`. Public helpers include `securityClassToString`,
`securityClassToUnit`, `securitySeriesToString`,
`restrictiveLegendsToJson`, `from18DecimalsToString` and
`stripIpfsPrefix`.

The URI builder is set on the IssuanceManager (`uriBuilder()` /
`setUriBuilder`). This page summarizes the builder; the source has the
full function set.
