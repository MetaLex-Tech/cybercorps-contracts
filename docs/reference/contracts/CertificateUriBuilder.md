# CertificateUriBuilder / CertificateImageBuilder

These contracts construct the fully onchain token URI (JSON) and certificate
image (SVG) for every cyberCERT.

* **Sources:**
  [`src/CertificateUriBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateUriBuilder.sol),
  [`src/CertificateImageBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageBuilder.sol),
  [`src/CertificateImageContentBuilder.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CertificateImageContentBuilder.sol).

## What they produce

`tokenURI(tokenId)` returns a `data:application/json;base64,...` URI whose
JSON payload includes:

* a standard `name` / `description` consumable by NFT viewers,
* a `data:image/svg+xml;base64,...` `image` rendered onchain — the
  share-certificate-style SVG with the holder name, units, class, series,
  signatures, legend, and entity branding,
* an `attributes` array with the extension-specific instrument data (SAFE
  valuation cap, SAFT vesting schedule, ShareExtension liquidation
  preference, etc.).

The entire metadata document is constructed onchain at read time. There is
no IPFS dependency for visualisation (though the *governing-agreement* URI
stored on the cert may itself be an IPFS pointer).

## Why this matters

* The register entry is self-describing forever, regardless of any external
  service.
* Anyone can render the certificate from a node, an explorer, or a wallet.
* For DGCL §158 compliance (and analogues elsewhere), the certificate fields
  required by statute are *in the asset itself*.
