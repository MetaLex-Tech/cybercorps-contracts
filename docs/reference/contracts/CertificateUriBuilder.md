# CertificateUriBuilder

Builds the fully onchain token-URI metadata (JSON + SVG) for cyberCERTs.

* **Sources:** [`src/CertificateUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateUriBuilder.sol),
  [`src/CertificateImageBuilderContract.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilderContract.sol),
  [`src/CertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilder.sol),
  [`src/CertificateImageContentBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageContentBuilder.sol)
* **Interface:** [`IUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IUriBuilder.sol)
* **Pattern:** UUPS proxy (`UUPSUpgradeable`, `BorgAuthACL`);
  `initialize(address _auth)`, with the SVG generation split out into a
  separately-deployed image-builder contract configured via
  `setImageBuilder(address)` (`onlyOwner`) to stay under contract-size
  limits. JSON string helpers shared with other contracts live in the
  [`JsonLib`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/JsonLib.sol)
  library.

## What it produces

`LedgerEntryToken.tokenURI(tokenId)` delegates to the URI builder
configured on the IssuanceManager, which assembles a
`data:application/json;base64,…` metadata document containing:

* the standard title/type fields and `attributes`,
* an `image` — an onchain-rendered SVG share-certificate showing the corp
  name, security class/series, officer, units, valuation, jurisdiction,
  holder name, and token id (see the `CertificateSVGParams` struct in
  [`CyberCorpConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorpConstants.sol)),
  rendered by the image-builder contract,
* the corp identity fields and the certificate's details —
  `investmentAmountUSD`, `issuerUSDValuationAtTimeOfInvestment`, and
  `unitsRepresented` are 18-decimal quantities formatted as **exact decimal
  strings** (`from18DecimalsToString`), plus the live `unitsReserved` read
  from the printer,
* extension-provided JSON sections, in order: the corp-level extension
  fragment (`CyberCorp.getExtensionURI`), the cert-level fragment
  (`ICertificateExtension.getExtensionURI(details.extensionData)`), and the
  series-level fragment (`ICertificateExtensionV3.getSeriesExtensionURI`
  over the printer's `seriesData`, when the extension supports it) — each
  guarded with `try/catch` so legacy printers and V1/V2 extensions keep
  rendering,
* the `endorsementHistory` array and `currentOwner`,
* the `restrictiveLegends` array — structured `RestrictiveLegend` records;
  plain-string legacy legends are converted via
  `legacyLegendsToRestrictiveLegends`.

The metadata is built onchain at read time, so a cyberCERT renders from any
node or explorer with no external service.

## Interface

`IUriBuilder` exposes `buildCertificateUri` and
`buildCertificateUriNotEncoded` (raw JSON, no base64 wrapper), each with two
overloads — one taking legacy `string[] certLegend`, one taking
`RestrictiveLegend[]`. Public helpers include `securityClassToString`,
`securitySeriesToString`, `restrictiveLegendsToJson`,
`from18DecimalsToString`, and `stripIpfsPrefix`.

> The URI builder is configured on the IssuanceManager (`uriBuilder()` /
> `setUriBuilder`). This page is a high-level description; consult the
> source for the exact function set, which is sizeable.
