---
description: The ERC-721 register of cyberCERTs (formerly CyberCertPrinter)
---

# LedgerEntryToken (formerly CyberCertPrinter)

The ERC-721 contract for one security series' cyberCERTs (Ledger Entry
Tokens, "LETs"). The contract was renamed from `CyberCertPrinter` to
`LedgerEntryToken`; the rename is source-level only — the storage layout
(`"cybercorp.cert.printer.storage.v1"` slot) and the event names (including
`CyberCertPrinter_CertificateCreated`) are intentionally unchanged so
already-deployed beacon proxies stay compatible. Docs and code still refer
to a deployment as a "printer".

* **Source:** [`src/LedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/LedgerEntryToken.sol)
  / interface [`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol)
  / storage library [`LedgerEntryTokenStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/LedgerEntryTokenStorage.sol)
* **Inherits:** `ERC721EnumerableUpgradeable`, `ILedgerEntryToken`
* **Pattern:** beacon proxy (beacon owned by the IssuanceManager)
* **`DEPLOY_VERSION`:** `"5"` in the current source; printers of companies
  that have not upgraded report `"4"` or `"3"`. The v5 release changed some
  external signatures (`assignCert` gained a name argument, for example), so
  pick the ABI by the printer's version.

Two auth modifiers gate state changes:

* `onlyIssuanceManager` — minting, assignment, details updates,
  `setExtension` and `updateIssuanceManager` may only come from the
  IssuanceManager that deployed the printer.
* `onlyIssuanceManagerOrAdmin` — administrative functions (legends, hooks,
  both kinds of transferability switch, voiding, signatures, endorsements,
  timestamps, reserved units, series data, the look-through badge,
  `initializeHolderCount`) also accept BorgAuth `ADMIN_ROLE`+ callers
  directly, so admins do not have to route these through the
  IssuanceManager.

## Minting and assignment

```solidity
function safeMint(uint256 tokenId, address to, CertificateDetails details)
    external onlyIssuanceManager returns (uint256);
function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails details,
    string investorName) external onlyIssuanceManager returns (uint256);
function safeMintAndAssign(address to, address owner, uint256 tokenId,
    CertificateDetails details, string ownerName)
    external onlyIssuanceManager returns (uint256); // custodian ≠ legal owner
function safeMintFromAndAssign(uint256 sourceTokenId, address to, address owner,
    uint256 tokenId, CertificateDetails details, string ownerName)
    external onlyIssuanceManager returns (uint256); // secondary-trade reissue
function assignCert(address from, uint256 tokenId, address to,
    CertificateDetails details, string name) external onlyIssuanceManager returns (uint256);
function updateCertificateDetails(uint256 tokenId, CertificateDetails details)
    external onlyIssuanceManager;
```

The second `safeMintAndAssign` overload separates the custodian (`to`, who
holds the NFT) from the legal owner (`owner`, the holder of record) to
support **administered hosting** — e.g. delivery of the token to an admin
multisig while the buyer is registered as owner. Both overloads record the
details and the holder of record before the ERC-721 receiver callback runs.

`safeMintFromAndAssign` mints the buyer's lot in a secondary trade and names
the seller's lot it came from. A reissue moves title but is technically a
mint; naming the source lets the register gate treat it as a transfer from
the seller, and it reverts `VoidCertificate` if the source lot is void.

`assignCert` re-registers an existing lot: `from` must be the current holder
of record (`legalOwnerOf`, not the wallet in possession), and `name` is the
incoming holder's legal name for the register. `assignCert` and
`updateCertificateDetails` enforce the reserved-units invariant: legal
ownership cannot be reassigned, and `unitsRepresented` cannot drop below
`unitsReserved`, while units are escrowed for a pending deal
(`CertificateReserved` / `ExceedsAvailableUnits`). `updateCertificateDetails`
emits `CertificateDetailsUpdated(tokenId)`.

## Delivery and registration gates

The printer gates two different events separately:

| Event | Flags (both default `false`) | Hook call | Failure |
|---|---|---|---|
| **Delivery** (the token moves between two wallets) | `transferable` (`setGlobalTransferable`), per-lot `setTokenTransferable` | `checkTransferRestriction` | `TokenNotTransferable` / `TransferRestricted` |
| **Registration** (the holder of record changes) | `legalTransferable` (`setGlobalLegalTransferable`), per-lot `setTokenLegalTransferable` | `checkLegalTransferRestriction` | `LegalOwnerNotTransferable` / `TransferRestricted` |

For each event, either the printer-wide flag or the lot's own flag permits
it. Both kinds of check use the printer's `globalRestrictionHook` and the
lot's per-id hook (see [Hooks](../hooks.md)).

* Original issuance is never gated: a mint has no outgoing holder.
* The company's DealManager and RoundManager are exempt from both flags when
  they are the outgoing party, so they can deliver primary issuances out of
  escrow. Hooks still run for them.
* A void lot cannot be registered to a new holder (`VoidCertificate`).
* A lot with reserved units cannot be transferred or reassigned.

A new printer issues freely, but holders cannot move its certificates and
its register cannot change until an admin opens each gate. The
registration flags are new storage in v5, so a printer upgraded from v4
reads them as `false` too: after the upgrade, `assignCert`, endorsed
transfers and secondary-trade settlement on that printer revert
`LegalOwnerNotTransferable` until an admin opens the register.

Views: `transferable()`, `isTokenTransferable(id)`, `legalTransferable()`,
`isTokenLegalTransferable(id)`. Events: `GlobalTransferableSet`,
`TokenTransferableSet`, `GlobalLegalTransferableSet`,
`TokenLegalTransferableSet`.

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

`endorseAndTransfer` records the endorsement and then moves the token as
`msg.sender`, so moving a token held by someone else needs that holder's
ERC-721 approval. The holder of record cannot take back possession that a
custodian or pledgee holds.

## Void / status

`voidCert`, `unvoidCert` (both `onlyIssuanceManagerOrAdmin`), `isVoided`.
`voidCert` reverts `TokenDoesNotExist` for an unminted id. Voiding does not
disturb the legal-owner enumeration, but a fully-voided lot stops counting
its owner in the look-through holder tally. The IssuanceManager's
`voidEmptyCerts` voids lots that hold no units and no scrip-vault claim.

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
`getCertRestrictiveLegendCount`. Each add or remove emits
`DefaultLegendsChanged()` or `CertLegendsChanged(tokenId)`; `tokenURI` reads
the legends live.

Hooks: `setRestrictionHook(id, hook)`, `setGlobalRestrictionHook`. The
transferability switches are described above. Extension data: `setExtension`
(`onlyIssuanceManager`; the extension is printer-wide, the `tokenId`
argument is ignored, and it emits `SeriesExtensionSet`) / `getExtension` /
`getExtensionData`, plus series-scope data `setSeriesData`
(`onlyIssuanceManagerOrAdmin`) / `getSeriesInfo` — the per-cert and series
payloads are both decoded by the printer's single extension contract (see
[Certificate extensions](../extensions.md)).

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
function backfillAcquisitionTimestamps(uint256 startIndex, uint256 count) external; // permissionless
```

Reserved units escrow part of a cert against a pending deal; a cert with
`unitsReserved > 0` cannot be transferred or reassigned.
`issueTimestamp` is stamped at mint; `acquisitionTimestamp` is (re)stamped
on each legal-owner change; both have admin overrides for migrated
positions. `updateCertificateTackedFromAcquisitionDate` overrides a cert's
Rule 144(d)(3) tacking anchor inside its `FundInterestExtensionV3` data.
`backfillAcquisitionTimestamps` copies that extension's `acquisitionDate`
into the base field for lots minted before the field existed.

## Token possession vs. registered ownership

Two distinct owners are tracked:

* `ownerOf(tokenId)` — the ERC-721 token holder (possession/custody).
* `legalOwnerOf(tokenId)` — the **registered owner of record**, stored
  separately in the cert's `OwnerDetails`.

The `_update` override enforces this: a transfer only updates the registered
owner when it delivers the token to the endorsee of the latest live
**endorsement** (or when `endorsementRequired` is false, which only a test
harness sets), and then only if the registration gate above allows it.
Moving the NFT without an endorsement does not change the registered owner.
Every change of holder of record retires the endorsements written before
it: only an endorsement added since the last change can move title, so a
former owner cannot replay an old one. This is the onchain mechanism behind
the [dual-token model](../../explanation/dual-token-model.md).

The register is also enumerable by legal owner:

```solidity
function balanceOfLegalOwner(address owner) external view returns (uint256);
function tokenOfLegalOwnerByIndex(address owner, uint256 index) external view returns (uint256);
function isLegalHolder(address owner) external view returns (bool); // holds ≥1 live (non-void) lot
function backfillLegalOwners(uint256 startIndex, uint256 count) external; // permissionless, idempotent
```

## Holder counts

`holderCount()` counts distinct wallets that **possess** a lot of the
series, updated on delivery. A printer whose lots were minted before it
kept this per-wallet counter can hold wallets whose counter reads zero; a
transfer out of such a wallet reverts. `initializeHolderCount(holder)`
(`onlyIssuanceManagerOrAdmin`) seeds the counter from the wallet's current
balance, reverting `HolderCountAlreadyInitialized` if it is already
nonzero. Seed every such holder before anything is minted or transferred to
or from it; a counter that has already moved off zero cannot be repaired
this way.

For Investment Company Act §3(c)(1)(A) accounting the printer separately
maintains an incrementally-updated **look-through** tally of holders of
record, sampling beneficial-owner counts and residency from a configured
[LeXcheXBadge](LexChex.md):

```solidity
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
unobserved; keepers `resyncHolder` before that passes. Set the badge before
the first mint on a new printer. `backfillLookThroughTally` is idempotent
and re-reads every holder off the badge, so running it again after wiring a
badge late repairs holders that were booked without one.

## Views

`tokenURI`, `getCertificateDetails` (note: reports `unitsRepresented`
**plus** scripified units), `getActiveCertificateDetails` (raw
`unitsRepresented`), `defaultLegend`, `defaultRestrictiveLegends`,
`certificateUri`, `issuanceManager`, `securityType` (`SecurityClass`),
`securitySeries` (`SecuritySeries`), `transferable`, `legalTransferable`,
`endorsementRequired`, `legalOwnerOf`.

## Events

`CyberCertPrinter_CertificateCreated`, `CertificateAssigned`,
`CertificateEndorsed`, `CertificateSigned`, `CertificateVoided`,
`CertificateUnvoided`, `CertificateDetailsUpdated`, `CyberCertTransfer`,
`LegalOwnerChanged`, `RestrictionHookSet`, `GlobalRestrictionHookSet`,
`GlobalTransferableSet`, `TokenTransferableSet`,
`GlobalLegalTransferableSet`, `TokenLegalTransferableSet`,
`DefaultLegendsChanged`, `CertLegendsChanged`, `LookThroughBadgeSet`,
`UnitsReservedUpdated`, `IssueTimestampSet`, `AcquisitionTimestampSet`,
`SeriesDataSet`, `SeriesExtensionSet`, `IssuanceManagerUpdated`,
`HolderCountInitialized`.

> `CertificateCreated`, `Converted`, `HookStatusChanged`, and
> `WhitelistUpdated` remain declared in `ILedgerEntryToken` (ABI
> compatibility) but are not emitted by the current implementation.
