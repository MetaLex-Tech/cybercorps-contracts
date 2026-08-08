# LedgerEntryToken (formerly CyberCertPrinter)

The ERC-721 contract for one security series' cyberCERTs (Ledger Entry
Tokens, "LETs"). The contract was renamed from `CyberCertPrinter` to
`LedgerEntryToken`; the rename is source-level only — the ABI, storage
layout (`"cybercorp.cert.printer.storage.v1"` slot), and event names
(including `CyberCertPrinter_CertificateCreated`) are intentionally
unchanged so already-deployed beacon proxies stay compatible. Docs and code
still refer to a deployment as a "printer".

* **Source:** [`src/LedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/LedgerEntryToken.sol)
  / interface [`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol)
  / storage library [`LedgerEntryTokenStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/LedgerEntryTokenStorage.sol)
* **Inherits:** `ERC721EnumerableUpgradeable`
* **Pattern:** beacon proxy (beacon owned by the IssuanceManager)
* **`DEPLOY_VERSION`:** `"4"`

Two auth modifiers gate state changes:

* `onlyIssuanceManager` — minting, assignment, and details updates may only
  come from the IssuanceManager that deployed the printer.
* `onlyIssuanceManagerOrAdmin` — administrative functions (legends, hooks,
  transferability, voiding, signatures, endorsements, timestamps, reserved
  units) also accept BorgAuth `ADMIN_ROLE`+ callers directly, so admins no
  longer have to route these through the IssuanceManager.

## Minting and assignment

```solidity
function safeMint(uint256 tokenId, address to, CertificateDetails details)
    external onlyIssuanceManager returns (uint256);
function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails details,
    string investorName) external onlyIssuanceManager returns (uint256);
function safeMintAndAssign(address to, address owner, uint256 tokenId,
    CertificateDetails details, string ownerName)
    external onlyIssuanceManager returns (uint256); // custodian ≠ legal owner
function assignCert(address from, uint256 tokenId, address to,
    CertificateDetails details) external onlyIssuanceManager returns (uint256);
function updateCertificateDetails(uint256 tokenId, CertificateDetails details)
    external onlyIssuanceManager;
```

The second `safeMintAndAssign` overload separates the custodian (`to`, who
holds the NFT) from the legal owner (`owner`, the holder of record) to
support **administered hosting** — e.g. delivery of the token to an admin
multisig while the buyer is registered as owner. `assignCert` and
`updateCertificateDetails` enforce the reserved-units invariant: legal
ownership cannot be reassigned, and `unitsRepresented` cannot drop below
`unitsReserved`, while units are escrowed for a pending deal
(`CertificateReserved` / `ExceedsAvailableUnits`).

## Endorsements and signatures

```solidity
function addEndorsement(uint256 tokenId, Endorsement newEndorsement) public;
function endorseCertificate(uint256 tokenId, address endorser, bytes signature,
    bytes32 agreementId) external onlyIssuanceManagerOrAdmin;
function endorseAndTransfer(uint256 tokenId, Endorsement e, address from, address to) external;
function addIssuerSignature(uint256 tokenId, bytes signature) external onlyIssuanceManagerOrAdmin;
function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (Endorsement);
function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256);
function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes);
```

`addEndorsement` may be called only by the IssuanceManager or the token's
**legal owner** — possession alone does not authorise an endorsement, or a
custodian could endorse a cert to itself and take legal title on delivery.

## Void / status

`voidCert`, `unvoidCert` (both `onlyIssuanceManagerOrAdmin`), `isVoided`.
Voiding does not disturb the legal-owner enumeration, but a fully-voided lot
stops counting its owner in the look-through holder tally.

## Legends, hooks, transferability

Plain-string legends: `addDefaultLegend` / `removeDefaultLegendAt` /
`getDefaultLegendAt` / `getDefaultLegendCount`; `addCertLegend` /
`removeCertLegendAt` / `getCertLegendAt` / `getCertLegendCount`.

Structured **restrictive legends** (`RestrictiveLegend{restrictionType,
title, text, jurisdiction, referenceId, effectiveTimestamp,
expirationTimestamp, active, data}`): `addDefaultRestrictiveLegend` /
`removeDefaultRestrictiveLegendAt` / `getDefaultRestrictiveLegendAt` /
`getDefaultRestrictiveLegendCount` and per-cert `addCertRestrictiveLegend` /
`removeCertRestrictiveLegendAt` / `getCertRestrictiveLegendAt` /
`getCertRestrictiveLegendCount`.

Hooks / transferability: `setRestrictionHook(id, hook)`,
`setGlobalRestrictionHook`, `setGlobalTransferable`,
`setTokenTransferable` / `isTokenTransferable`. Extension data:
`setExtension` (`onlyIssuanceManager`) / `getExtension` /
`getExtensionData`, plus series-scope data `setSeriesData`
(`onlyIssuanceManagerOrAdmin`) / `getSeriesInfo` — the per-cert and series
payloads are both decoded by the printer's single extension contract.

## Reserved units and timestamps

```solidity
function increaseUnitsReserved(uint256 tokenId, uint256 amount) external; // onlyIssuanceManagerOrAdmin
function decreaseUnitsReserved(uint256 tokenId, uint256 amount) external; // onlyIssuanceManagerOrAdmin
function unitsReserved(uint256 tokenId) external view returns (uint256);

function issueTimestamp(uint256 tokenId) external view returns (uint64);
function setIssueTimestamp(uint256 tokenId, uint64 ts) external;          // onlyIssuanceManagerOrAdmin
function acquisitionTimestamp(uint256 tokenId) external view returns (uint64);
function setAcquisitionTimestamp(uint256 tokenId, uint64 ts) external;    // onlyIssuanceManagerOrAdmin
function updateCertificateTackedFromAcquisitionDate(uint256 tokenId, uint64 ts) external; // onlyIssuanceManagerOrAdmin
```

Reserved units escrow part of a cert against a pending deal; a cert with
`unitsReserved > 0` cannot be transferred or reassigned.
`issueTimestamp` is stamped at mint; `acquisitionTimestamp` is (re)stamped
on each legal-owner change; both have admin overrides for migrated
positions. `updateCertificateTackedFromAcquisitionDate` overrides a cert's
Rule 144(d)(3) tacking anchor inside its extension data.

## Token possession vs. registered ownership

Two distinct owners are tracked:

* `ownerOf(tokenId)` — the ERC-721 token holder (possession/custody).
* `legalOwnerOf(tokenId)` — the **registered owner of record**, stored
  separately in the cert's `OwnerDetails`.

The `_update` override enforces this: a transfer only updates the registered
owner when a matching **endorsement** exists (or when `endorsementRequired`
is false). Moving the NFT without an endorsement does not change the
registered owner. This is the onchain mechanism behind the
[dual-token model](../../explanation/dual-token-model.md).

The register is also enumerable by legal owner:

```solidity
function balanceOfLegalOwner(address owner) external view returns (uint256);
function tokenOfLegalOwnerByIndex(address owner, uint256 index) external view returns (uint256);
function isLegalHolder(address owner) external view returns (bool); // holds ≥1 live (non-void) lot
function backfillLegalOwners(uint256 startIndex, uint256 count) external; // permissionless, idempotent
```

## Look-through holder tally

For Investment Company Act §3(c)(1)(A) accounting the printer maintains an
incrementally-updated holder tally, sampling beneficial-owner counts and
residency from a configured [LeXcheXBadge](LexChex.md):

```solidity
function holderCount() external view returns (uint256);
function lookThroughHolderCount() external view returns (uint256);   // Σ max(beneficialOwnerCount, 1)
function usLookThroughHolderCount() external view returns (uint256); // U.S.-resident subset
function usTallyExpiry() external view returns (uint64);             // when the U.S. subtotal stops being trusted
function lookThroughBadge() external view returns (address);
function setLookThroughBadge(address badge) external;                // onlyIssuanceManagerOrAdmin
function resyncHolder(address owner) external;                       // permissionless
function resyncHolders(address[] owners) external;
function backfillLookThroughTally(uint256 startIndex, uint256 count) external;
```

Past `usTallyExpiry` the U.S. subtotal conservatively reports the full
look-through count, because a non-US booking may have lapsed into US
unobserved; keepers `resyncHolder` before that passes.

## Views

`tokenURI`, `getCertificateDetails` (note: reports `unitsRepresented`
**plus** scripified units), `getActiveCertificateDetails` (raw
`unitsRepresented`), `defaultLegend`, `defaultRestrictiveLegends`,
`certificateUri`, `issuanceManager`, `securityType` (`SecurityClass`),
`securitySeries` (`SecuritySeries`), `transferable`, `endorsementRequired`,
`legalOwnerOf`.

## Events

`CyberCertPrinter_CertificateCreated`, `CertificateAssigned`,
`CertificateEndorsed`, `CertificateSigned`, `CertificateVoided`,
`CertificateUnvoided`, `CyberCertTransfer`, `LegalOwnerChanged`,
`RestrictionHookSet`, `GlobalRestrictionHookSet`, `GlobalTransferableSet`,
`LookThroughBadgeSet`, `UnitsReservedUpdated`, `IssueTimestampSet`,
`AcquisitionTimestampSet`, `SeriesDataSet`.

> `CertificateCreated`, `Converted`, `HookStatusChanged`, and
> `WhitelistUpdated` remain declared in `ILedgerEntryToken` (ABI
> compatibility) but are not emitted by the current implementation.
