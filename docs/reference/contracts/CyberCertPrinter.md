# CyberCertPrinter

The **CyberCertPrinter** is the ERC-721 contract that mints cyberCERTs —
Ledger Entry Tokens — for a single cyberCORP. There is typically one printer
per instrument family, registered against the `IssuanceManager`.

* **Source:** [`src/CyberCertPrinter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCertPrinter.sol)
* **Proxy pattern:** beacon proxy (owned by the cyberCORP's `IssuanceManager`)

## What's encoded in each token

Each cyberCERT carries — onchain — all information required by the relevant
governing law for an entry on the holder register. For a Delaware C-corp this
maps to DGCL §§158, 202, 219 requirements. For non-US entities the same
fields satisfy the analogous statutory or contractual requirements.

* Holder name (legal name of the holder of record)
* Unit count (shares / membership-interest units / partnership-interest units
  / fund-interest units)
* Share class and series
* Restriction legend
* Endorsement history
* Authorized signatures (officer / director / manager / general partner /
  secretary)
* Acquisition price
* Governing agreement URI (`CyberAgreementRegistry` pointer + content hash)
* A fully onchain Base64 SVG visualisation produced by
  `CertificateImageBuilder`

## Extensions

Instrument-specific metadata is added via [extensions](../extensions.md)
registered on the printer:

* `ShareExtension` — Preferred / Common stock (NVCA-aligned terms)
* `SAFEExtension`, `ACESAFEExtension`
* `SAFTExtension`, `SAFTExtensionV2`
* `SAFTEExtension`, `SAFTEExtensionV2`
* `TokenWarrantExtension`, `TokenWarrantExtensionV2`

## Selected public interface

```solidity
function mint(uint256 tokenId, address to, bytes calldata metadata) external; // IssuanceManager only
function burn(uint256 tokenId) external;                                       // IssuanceManager only

function tokenURI(uint256 tokenId) external view returns (string memory);
function setExtension(bytes32 securityType, address extension) external;       // DIRECTOR_AUTHORITY
function setMaxHolders(uint256) external;                                      // DIRECTOR_AUTHORITY
function setLegend(uint256 tokenId, string calldata) external;                 // SECRETARY_AUTHORITY
```

## Behaviour: NFT transfer ≠ register transfer

NFT `transferFrom` alone does **not** change registered ownership. Cert
metadata must be explicitly mutated through the `IssuanceManager`. This
maintains the distinction between *token possession* and *registered
ownership* that corporate, LLC, partnership, and fund law require. See
[The dual-token model](../../explanation/dual-token-model.md).

## See also

* [`IssuanceManager`](IssuanceManager.md)
* [`CertificateUriBuilder`](CertificateUriBuilder.md)
* [Extensions](../extensions.md)
