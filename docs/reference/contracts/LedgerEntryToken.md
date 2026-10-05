---
description: The LET contract, the ERC-721 that mints and registers a series' Ledger Entry Tokens (LETs)
---

# LedgerEntryToken

`LedgerEntryToken` is the LET contract: an ERC-721 whose tokens, Ledger
Entry Tokens (LETs), are one security series' entries on a cyberCORP's
register of holders. Each class or series has its own LET contract, which
the company's [IssuanceManager](IssuanceManager.md) creates with
`createCertPrinter`.

* **Source:** [`src/LedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/LedgerEntryToken.sol)
  / interface [`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol)
  / storage library [`LedgerEntryTokenStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/LedgerEntryTokenStorage.sol)
* **Inherits:** `ERC721EnumerableUpgradeable`, `ILedgerEntryToken`
* **Pattern:** beacon proxy; the IssuanceManager owns the beacon
* **Storage position:** `keccak256("cybercorp.cert.printer.storage.v1")`
* **`DEPLOY_VERSION`:** `"5"`; the LET contracts of a company that has not
  upgraded report `"4"` or `"3"`. Some external signatures differ between
  v4 and v5 (the v5 `assignCert` takes a name argument, for example), so
  pick the ABI by the LET contract's version.

Two auth modifiers gate state changes:

* `onlyIssuanceManager`: minting, assignment, details updates,
  `setExtension` and `updateIssuanceManager` accept only the
  IssuanceManager that deployed the LET contract.
* `onlyIssuanceManagerOrAdmin`: the administrative functions (legends,
  hooks, both kinds of transferability switch, voiding, signatures,
  endorsements, timestamps, reserved units, series data, the look-through
  badge, `initializeHolderCount`) also accept callers holding BorgAuth
  `ADMIN_ROLE` or higher, so admins call them directly.

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
holds the token) from the legal owner (`owner`, the holder of record). It
supports **administered hosting**, where the token goes to an admin
multisig while the buyer is registered as owner. Both overloads record the
details and the holder of record before the ERC-721 receiver callback runs.

`safeMintFromAndAssign` mints the buyer's LET in a secondary trade and
names the seller's LET it came from. A reissue moves title but is
technically a mint; naming the source lets the register gate treat it as a
transfer from the seller. It reverts `VoidCertificate` if the source LET is
void.

`assignCert` re-registers an existing LET: `from` must be the current
holder of record (`legalOwnerOf`, not the wallet in possession), and `name`
is the incoming holder's legal name for the register. `assignCert` and
`updateCertificateDetails` enforce the reserved-units invariant: while
units are escrowed for a pending deal, legal ownership cannot be reassigned
and `unitsRepresented` cannot drop below `unitsReserved`
(`CertificateReserved` / `ExceedsAvailableUnits`).
`updateCertificateDetails` emits `CertificateDetailsUpdated(tokenId)`.

## Delivery and registration gates

The LET contract gates two different events separately:

| Event | Flags (both default `false`) | Hook call | Failure |
|---|---|---|---|
| **Delivery** (the token moves between two wallets) | `transferable` (`setGlobalTransferable`), per-LET `setTokenTransferable` | `checkTransferRestriction` | `TokenNotTransferable` / `TransferRestricted` |
| **Registration** (the holder of record changes) | `legalTransferable` (`setGlobalLegalTransferable`), per-LET `setTokenLegalTransferable` | `checkLegalTransferRestriction` | `LegalOwnerNotTransferable` / `TransferRestricted` |

For each event, either the contract-wide flag or the LET's own flag
permits it. Both kinds of check use the contract's `globalRestrictionHook`
and the LET's own hook (see [Hooks](../hooks.md)).

* Original issuance is never gated: a mint has no outgoing holder.
* The company's DealManager and RoundManager are exempt from both flags
  when they are the outgoing party, so they can deliver primary issuances
  out of escrow. Hooks still run for them.
* A void LET cannot be registered to a new holder (`VoidCertificate`).
* A LET with reserved units cannot be transferred or reassigned.

A new LET contract issues freely, but holders cannot move its LETs and its
register cannot change until an admin opens each gate. On a LET contract
upgraded from v4 the registration flags also read `false`: after the
upgrade, `assignCert`, endorsed transfers and secondary-trade settlement on
it revert `LegalOwnerNotTransferable` until an admin opens the register.

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

`addEndorsement` accepts only the IssuanceManager or the token's **legal
owner**. Possession alone does not authorize an endorsement; if it did, a
custodian could endorse a LET to itself and take legal title on delivery.

`endorseAndTransfer` records the endorsement and then moves the token as
`msg.sender`, so moving a token held by someone else needs that holder's
ERC-721 approval. The holder of record cannot take back possession that a
custodian or pledgee holds.

## Void and status

`voidCert` and `unvoidCert` (both `onlyIssuanceManagerOrAdmin`),
`isVoided`. `voidCert` reverts `TokenDoesNotExist` for an unminted id.
Voiding leaves the legal-owner enumeration as it is, but a fully voided LET
stops counting its owner in the look-through holder tally. The
IssuanceManager's `voidEmptyCerts` voids LETs that hold no units and no
scrip-vault claim.

## Legends, hooks and extension data

Plain-string legends: `addDefaultLegend` / `removeDefaultLegendAt` /
`getDefaultLegendAt` / `getDefaultLegendCount`, and per LET
`addCertLegend` / `removeCertLegendAt` / `getCertLegendAt` /
`getCertLegendCount`.

Structured **restrictive legends** (`RestrictiveLegend{restrictionType,
title, text, jurisdiction, referenceId, effectiveTimestamp,
expirationTimestamp, active, data}`): `addDefaultRestrictiveLegend` /
`removeDefaultRestrictiveLegendAt` / `getDefaultRestrictiveLegendAt` /
`getDefaultRestrictiveLegendCount`, and per LET `addCertRestrictiveLegend`
/ `removeCertRestrictiveLegendAt` / `getCertRestrictiveLegendAt` /
`getCertRestrictiveLegendCount`. Each add or remove emits
`DefaultLegendsChanged()` or `CertLegendsChanged(tokenId)`, and `tokenURI`
reads the legends live.

Hooks: `setRestrictionHook(id, hook)` and `setGlobalRestrictionHook`. The
transferability switches are under
[Delivery and registration gates](#delivery-and-registration-gates).

Extension data: `setExtension` (`onlyIssuanceManager`; the extension
applies to the whole LET contract, the `tokenId` argument is ignored, and
the call emits `SeriesExtensionSet`), `getExtension` and
`getExtensionData`, plus series-scope data through `setSeriesData`
(`onlyIssuanceManagerOrAdmin`) and `getSeriesInfo`. The LET contract's
single extension decodes both the per-LET and the series payloads (see
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

Reserved units escrow part of a LET against a pending deal; a LET with
`unitsReserved > 0` cannot be transferred or reassigned.

`issueTimestamp` is stamped at mint, and `acquisitionTimestamp` is stamped
again on each legal-owner change. Admins can override both for migrated
positions. `updateCertificateTackedFromAcquisitionDate` overrides a LET's
Rule 144(d)(3) tacking anchor inside its `FundInterestExtensionV3` data.
`backfillAcquisitionTimestamps` copies that extension's `acquisitionDate`
into the base field of every LET whose base field is unset; on a LET
contract without the fund-interest extension it does nothing.

## Token possession and registered ownership

The LET contract tracks two owners:

* `ownerOf(tokenId)`: the ERC-721 token holder (possession or custody).
* `legalOwnerOf(tokenId)`: the **registered owner of record**, stored
  separately in the LET's `OwnerDetails`.

The `_update` override keeps them apart. A transfer updates the registered
owner only when it delivers the token to the endorsee of the latest live
**endorsement** (or when `endorsementRequired` is false, which only a test
harness sets), and then only if the registration gate allows it. Moving
the token without an endorsement leaves the registered owner unchanged.
Every change of holder of record retires the endorsements written before
it: only an endorsement added since the last change can move title, so a
former owner cannot replay an old one.
[LETs and scrip](../../explanation/lets-and-scrip.md) explains the model
this implements.

The register is also enumerable by legal owner:

```solidity
function balanceOfLegalOwner(address owner) external view returns (uint256);
function tokenOfLegalOwnerByIndex(address owner, uint256 index) external view returns (uint256);
function isLegalHolder(address owner) external view returns (bool); // holds ≥1 live (non-void) LET
function backfillLegalOwners(uint256 startIndex, uint256 count) external; // permissionless, idempotent
```

On a LET contract upgraded from a version without this enumeration, call
`backfillLegalOwners` in batches over `[0, totalSupply())`.

## Holder counts

`holderCount()` counts distinct wallets that **possess** a LET of the
series, updated on delivery. A LET contract upgraded from a version
without this per-wallet counter can hold wallets whose counter reads zero,
and a transfer out of such a wallet reverts. `initializeHolderCount(holder)`
(`onlyIssuanceManagerOrAdmin`) seeds the counter from the wallet's current
balance and reverts `HolderCountAlreadyInitialized` if it is already
nonzero. Seed every such holder before anything is minted or transferred to
or from it; a counter that has already moved off zero cannot be repaired
this way.

For Investment Company Act §3(c)(1)(A) accounting, the LET contract also
keeps an incrementally updated **look-through** tally of holders of
record, reading beneficial-owner counts and residency from a configured
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
unobserved; keepers call `resyncHolder` before that time passes. Set the
badge before the first mint on a new LET contract.
`backfillLookThroughTally` is idempotent and re-reads every holder from
the badge, so running it again after wiring a badge late repairs holders
that were booked without one.

## Views

`tokenURI`, `getCertificateDetails` (reports `unitsRepresented` **plus**
scripified units), `getActiveCertificateDetails` (raw `unitsRepresented`),
`defaultLegend`, `defaultRestrictiveLegends`, `certificateUri`,
`issuanceManager`, `securityType` (`SecurityClass`), `securitySeries`
(`SecuritySeries`), `transferable`, `legalTransferable`,
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

`CertificateCreated`, `Converted`, `HookStatusChanged` and
`WhitelistUpdated` are declared in `ILedgerEntryToken` but never emitted.
