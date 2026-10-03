---
description: Move an existing cyberCORP to v5 by upgrading its four proxies and two beacons together, then backfill and open its LET contracts
---

# Upgrade a cyberCORP

A company deployed through the `CyberCorpFactory` stack puts its CyberCorp,
IssuanceManager, DealManager and RoundManager behind UUPS proxies. Its
Ledger Entry Token (LET) contracts and `CyberScrip` instances use beacon
proxies whose beacons the IssuanceManager owns. An upgrade needs both
sides: MetaLeX publishes a reference implementation on the factory, and the
company's owner opts in. See [Upgrade model](../reference/upgrade-model.md).

New companies are created on v5. An existing company stays on the version
it was deployed with until its owner runs this upgrade. In the cyberCORPs
app, an available upgrade appears as the first task in mission control and
links to the app's **Upgrade** page; [Run your
company](../webapp/company.md) covers the app side.

## 1. Check the company's versions and targets

Read `DEPLOY_VERSION()` on the CyberCorp, IssuanceManager, DealManager and
RoundManager, and on the implementations behind the IssuanceManager's two
beacons (`getCertPrinterBeaconImplementation()`,
`getScripBeaconImplementation()`). Then read the targets from the factory
each contract records:

```solidity
address corpTarget = ICyberCorpSingleFactory(CyberCorp(cyberCorp).upgradeFactory())
    .getRefImplementation();
IIssuanceManagerFactory imf =
    IIssuanceManagerFactory(IIssuanceManager(issuanceManager).getUpgradeFactory());
address imTarget      = imf.getRefImplementation();
address printerTarget = imf.getCyberCertPrinterRefImplementation();
address scripTarget   = imf.getCyberScripRefImplementation();
// DealManager and RoundManager: getRefImplementation() on the
// DealManagerFactory and RoundManagerFactory they were deployed from.
```

If a target is not what you expected, do not upgrade. The
reference-implementation check exists so that neither side can move you to
an arbitrary implementation.

{% hint style="warning" %}
This path needs the CyberCorp, IssuanceManager and DealManager to be UUPS
proxies. The oldest cyberCORPs run those three behind MetaLeX-owned legacy
beacons (`DEPLOY_VERSION` `"3"`). `upgradeToAndCall` on them reverts
`UUPSUnauthorizedCallContext`, and the company cannot upgrade them itself.
See [Upgrade model](../reference/upgrade-model.md).
{% endhint %}

## 2. Upgrade all six contracts in one batch

An existing UUPS company moves to v5 with six calls, made by an owner of
the company's BorgAuth (level 99 or above; officers hold 200):

```solidity
UUPSUpgradeable(cyberCorp).upgradeToAndCall(corpTarget, "");
UUPSUpgradeable(issuanceManager).upgradeToAndCall(imTarget, "");
UUPSUpgradeable(dealManager).upgradeToAndCall(dealManagerTarget, "");
UUPSUpgradeable(roundManager).upgradeToAndCall(roundManagerTarget, "");
IIssuanceManager(issuanceManager).upgradeCertPrinterBeaconImplementation(printerTarget);
IIssuanceManager(issuanceManager).upgradeScripBeaconImplementation(scripTarget);
```

Each call is `onlyOwner` and reverts `NotRefImplementation` unless its
target equals the published reference. Upgrading a beacon moves every
instance of that type under the IssuanceManager at once.

Run the six as one transaction where you can; for a Safe-owned company,
that is one Safe batch. Each version calls functions the other version
lacks, so a company left part-way (a v5 IssuanceManager next to a v4
DealManager, for example) can see deal, round and issuance calls revert
until the rest land. The contracts repository's `script/upgrade-v5.s.sol`
builds this batch for one company (`corpUpgradeCalls`, and
`printCorpUpgradeSafeBatch`, which prints Safe Transaction Builder JSON)
and refuses a company that has no RoundManager.

The app's **Upgrade** page runs the same calls in the same order. If a
Safe that the connected wallet owns holds the owner role, it proposes
every call that is not done as one Safe transaction, followed by the LET
migrations of step 3 that need no dates. Its gas grows with the holders
(one `initializeHolderCount` each) and the lots (each backfill touches
each lot). The page estimates it from bounds measured on a Base fork and
does not offer a batch above half the block gas limit; such a company
needs a plan with MetaLeX, because running the migrations after the
upgrade in a separate transaction reopens the period described in step
3. Otherwise it sends one call at
a time from a wallet with the owner role, and only the next call is
available. From a wallet, the LET migrations follow in later
transactions, so read the scrip conversion risk in step 3 first. It
starts the sequence only for a company with all contracts on a v4
release (any 4.x `DEPLOY_VERSION`, such as `"4"`, `"4.0.1"` or
`"4.1"`), UUPS proxies, an IssuanceManager and a DealManager, and
v5 references for every call. A v4 company without a RoundManager
takes the five other calls; a fork test of a deal and an issuance after
those five calls passed before the app allowed it. While a company runs
v5 and older contracts side by side, the app refuses new deals, rounds
and issuance. See [Run your company](../webapp/company.md#upgrade-an-existing-company-to-v5).

## 3. Prepare the upgraded LET contracts

The upgraded LET contracts keep their data, but v5 adds storage that starts
empty, zero or closed. Work through the steps below on each LET contract as
soon as the upgrade lands, because holders can call `convertScripToCert` at
any time. [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md)
documents each function and the holder-counting rules.

The app's Upgrade page runs these steps from a checklist for each LET
contract once the company runs v5. It reads which lots and holders still
need each step from the contract's storage. It sends the required calls
in this order: holder counters, legal-owner backfill, the badge when the
company has a `HolderCapCondition` configuration, tally backfill. It
refuses issuance, deal settlement and scrip conversion on a LET contract
until its holder counters, legal-owner index and holder tally are
complete. It proposes dates from onchain and company records, and sends
them only after the owner confirms them.

Existing LET contracts keep the certificate extension they were created
with. New LET contracts can bind the [V3 extensions](../reference/extensions.md),
which need a v5 LET contract and IssuanceManager.

### Seed each holder's possession counter

On a LET contract whose lots were minted before it kept a per-wallet
possession counter, a holder's counter reads zero and a transfer out of
that wallet reverts. An admin seeds each such holder with
`initializeHolderCount(holder)` before anything is minted or transferred to
or from it.

A mint or transfer that reaches a holder first sets the counter to 1,
below the holder's balance. `initializeHolderCount` then reverts
`HolderCountAlreadyInitialized`, and no deployed function corrects the
counter. A holder can cause this without the company:
`convertScripToCert` looks up the holder's lot through the legal-owner
enumeration, which is empty until the backfill below. With a
recertification approval on file, it then mints a new LET to the
holder. An FCFS round that has not ended does the same without the
company once it opens:
`RoundManager.submitEOI` is public, and for an FCFS round it calls
`allocate` in the same transaction, which mints a LET to the investor.
A new LET also reaches a legacy holder indirectly: if the LET contract
is `transferable`, the wallet that received it can transfer possession
to a legacy holder without an endorsement. Seed the counters in the
same transaction as the beacon upgrade where you can, as the app's Safe
batch does. A batch is built when it is proposed, so a lot minted while
it waits for signatures is not in it. So for a wallet upgrade and for a
Safe batch, close every FCFS round that has not ended, including one
that has not started, with `closeRoundNow(roundId)`, and clear every
outstanding approval with
`clearRecertificationApproval(certAddress, investor)`, before the
upgrade. `closeRoundNow` sets `endTime` to the current
block's timestamp, and `submitEOI` reverts `RoundNotOpen` only when
`block.timestamp > endTime`. So wait for a block with a later timestamp
before the beacon upgrade. `closeRoundNow` reverts
`EndTimeReductionRestricted` for a round that restricts it; for such a
round, wait until the round ends. Set the approvals
again only after the counters are seeded
and the legal-owner enumeration is backfilled (see below), because
until then a conversion with an approval also draws on the shared
vault.

### Backfill legal owners and the look-through tally

The legal-owner enumeration and the look-through holder tally start empty.
Until they are backfilled, existing holders read zero through
`balanceOfLegalOwner` and `isLegalHolder`, and `lookThroughHolderCount()`
starts at zero, so a configured `HolderCapCondition` can admit a buyer
although the real cap is already full.

Scrip redemption depends on the enumeration too: `convertScripToCert` finds
the holder's lot and draws down the holder's own vault positions through
it. Before the backfill it cannot find the lot, and reverts for a missing
recertification approval. With an approval on file, it takes the
withdrawal from the shared vault instead of the holder's positions. Run
these steps before enabling registration or secondary settlement on the LET
contract:

1. If the SPV uses look-through counting, wire the badge first with
   `setLookThroughBadge(badge)`.
2. Run `backfillLegalOwners(start, count)` and
   `backfillLookThroughTally(start, count)` in batches over
   `[0, totalSupply())`. Both are permissionless and idempotent, so a batch
   can be re-run safely.

### Set acquisition timestamps for Rule 144 and Reg S trades

Each lot's `acquisitionTimestamp` reads zero for lots minted before the
upgrade. `HoldingPeriodCondition` (Rule 144) and
`RegSDistributionComplianceCondition` fail closed on a zero timestamp, so
secondary trades on those pathways stay refused until it is set. Before
enabling them:

1. On a LET contract whose extension supports the fund-interest type, run
   `backfillAcquisitionTimestamps(start, count)` in batches. It copies each
   lot's recorded acquisition date, and does nothing on other LET
   contracts.
2. For the remaining lots, an admin sets each known date with
   `setAcquisitionTimestamp(tokenId, ts)`. The date anchors the holding
   period, so take it from the company's records.

### Record issue dates for the certificate image

v4 LET contracts never stored `issueTimestamp`, so it reads zero for every
lot minted before the upgrade, and the certificate image built by
`CertificateUriBuilder` shows a blank **Issue Date** for each one. Nothing
backfills it automatically. An admin sets each lot's issuance date with
`setIssueTimestamp(tokenId, ts)`, taking the date from the company's
records (for example the lot's original issuance endorsement). The date
fixes the certificate's displayed record and blocks no transfer or trade.

### Open the registration gate

The v5 registration gate is new storage and starts closed. Until an admin
calls `setGlobalLegalTransferable(true)` on a LET contract (or
`setTokenLegalTransferable` per lot), `assignCert`, endorsed transfers and
secondary-trade settlement on it revert `LegalOwnerNotTransferable`.
Issuance and the managers' deliveries out of escrow are not affected. Open
the gate after the legal-owner backfill.

## Who controls the upgrade

* The company may stay on its current implementation indefinitely.
* An upgrade to anything other than the factory's published reference
  reverts.
* The company's owner makes the upgrade calls. The deploying factory may
  still hold owner level on your BorgAuth; [Access
  control](../reference/access-control.md) shows how to check.

[Upgrade model](../reference/upgrade-model.md) has the version and proxy
details, and [Upgrades and control](../explanation/upgrades-and-control.md)
explains why an upgrade needs both MetaLeX and the company.
