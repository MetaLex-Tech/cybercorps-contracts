# CertificateUriBuilder

Builds the fully onchain token-URI metadata (JSON + SVG) for cyberCERTs.

* **Sources:** [`src/CertificateUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateUriBuilder.sol),
  [`src/CertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilder.sol),
  [`src/CertificateImageContentBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageContentBuilder.sol)
* **Interface:** [`IUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IUriBuilder.sol)

## What it produces

`CyberCertPrinter.tokenURI(tokenId)` delegates to a URI builder, which
assembles a metadata document containing:

* the standard `name` / `description`,
* an `image` — an onchain-rendered SVG share-certificate showing the corp
  name, security class/series, officer, units, valuation, jurisdiction,
  holder name, and token id (see the `CertificateSVGParams` struct in
  [`CyberCorpConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorpConstants.sol)),
* the certificate's instrument data, drawn from the registered extension.

The metadata is built onchain at read time, so a cyberCERT renders from any
node or explorer with no external service.

> The URI builder is configured on the IssuanceManager (`uriBuilder()` /
> `setUriBuilder`). This page is a high-level description; consult the source
> for the exact `IUriBuilder` function set, which is sizeable.
