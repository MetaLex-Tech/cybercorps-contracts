# CyberCertPrinter

The ERC-721 contract for one security class's cyberCERTs (Ledger Entry
Tokens). Mutated only by its IssuanceManager.

* **Source:** [`src/CyberCertPrinter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCertPrinter.sol)
* **Inherits:** `ERC721EnumerableUpgradeable`
* **Pattern:** beacon proxy (beacon owned by the IssuanceManager)
* **`DEPLOY_VERSION`:** `"4"`

Every state-changing function carries the `onlyIssuanceManager` modifier —
the caller must be the IssuanceManager that deployed the printer. End users
act through the IssuanceManager, not directly.

## Minting and assignment

```solidity
function safeMint(uint256 tokenId, address to, CertificateDetails details)
    external onlyIssuanceManager returns (uint256);
function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails details,
    string investorName) external onlyIssuanceManager returns (uint256);
function assignCert(address from, uint256 tokenId, address to,
    CertificateDetails details) external onlyIssuanceManager returns (uint256);
function burn(uint256 tokenId) external onlyIssuanceManager;
function updateCertificateDetails(uint256 tokenId, CertificateDetails details)
    external onlyIssuanceManager;
```

## Endorsements and signatures

```solidity
function addEndorsement(uint256 tokenId, Endorsement newEndorsement) public;
function endorseAndTransfer(uint256 tokenId, Endorsement e, address from, address to) external;
function addIssuerSignature(uint256 tokenId, bytes signature) external onlyIssuanceManager;
function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (Endorsement);
function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256);
function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes);
```

## Void / status

`voidCert`, `unvoidCert` (both `onlyIssuanceManager`), `isVoided`.

## Legends, hooks, transferability

`addDefaultLegend` / `removeDefaultLegendAt` / `getDefaultLegendAt` /
`getDefaultLegendCount`; `addCertLegend` / `removeCertLegendAt` /
`getCertLegendAt` / `getCertLegendCount`; `setRestrictionHook(id, hook)`,
`setGlobalRestrictionHook`, `setGlobalTransferable`,
`setTokenTransferable` / `isTokenTransferable`; `setExtension` /
`getExtension` / `getExtensionData`.

## Token possession vs. registered ownership

Two distinct owners are tracked:

* `ownerOf(tokenId)` — the ERC-721 token holder.
* `legalOwnerOf(tokenId)` — the **registered owner of record**, stored
  separately in the cert's `OwnerDetails`.

The `_update` override enforces this: a transfer only updates the registered
owner when a matching **endorsement** exists (or when `endorsementRequired`
is false). Moving the NFT without an endorsement does not change the
registered owner. This is the onchain mechanism behind the
[dual-token model](../../explanation/dual-token-model.md).

## Views

`tokenURI`, `getCertificateDetails`, `getActiveCertificateDetails`,
`defaultLegend`, `certificateUri`, `issuanceManager`, `securityType`
(`SecurityClass`), `securitySeries` (`SecuritySeries`), `transferable`,
`endorsementRequired`, `legalOwnerOf`.

## Events

`CyberCertPrinter_CertificateCreated`, `CertificateAssigned`,
`CertificateEndorsed`, `CertificateSigned`, `CertificateVoided`,
`CertificateUnvoided`, `CyberCertTransfer`, `RestrictionHookSet`,
`GlobalRestrictionHookSet`, `GlobalTransferableSet`, `Converted`.
