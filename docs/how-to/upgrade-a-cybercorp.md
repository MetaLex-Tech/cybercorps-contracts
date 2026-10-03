---
description: Upgrade the UUPS core suite and beacon-proxied printers
---

# Upgrade a cyberCORP

All company-owned contracts use UUPS upgradeable proxies (with beacon proxies
for the cert printer (`LedgerEntryToken`) and `CyberScrip`). Upgrades use a
**co-approval** model: MetaLeX publishes a reference implementation, and the
cyberCORP's owner opts in. See [Upgrade model](../reference/upgrade-model.md).

New companies are created on the current release (v5). An existing company
stays on the version it was deployed with until its owner runs the upgrade
below. In the cyberCORPs app, an available upgrade appears as the first
task in mission control and links to the
[Upgrade page](../webapp/mainframe.md#upgrade).

## 1. Check the company's versions

Read `DEPLOY_VERSION()` on the CyberCorp, IssuanceManager, DealManager and
RoundManager, and on the implementations behind the IssuanceManager's two
beacons (`getCertPrinterBeaconImplementation()`,
`getScripBeaconImplementation()`). Then read the targets, from the factory
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

If a target is not what you expected, do not upgrade — the gate exists so
neither side can move you to an arbitrary implementation.

{% hint style="warning" %}
This path needs the CyberCorp, IssuanceManager and DealManager to be UUPS
proxies. The oldest cyberCORPs run those three behind MetaLeX-owned legacy
beacons (`DEPLOY_VERSION` `"3"`); `upgradeToAndCall` on them reverts
`UUPSUnauthorizedCallContext`, and the company cannot move them itself. See
[Upgrade model](../reference/upgrade-model.md#uups-companies-and-legacy-beacon-companies).
{% endhint %}

## 2. Upgrade all six together

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
that is one Safe batch. Contracts of different versions call functions the
other version removed or does not have yet, so a company left part-way
(for example a v5 IssuanceManager next to a v4 DealManager) can see deal,
round and issuance calls revert until the rest land. The app's Upgrade page
sends each upgrade as its own transaction, so finish all six there before
running deals, rounds or issuance. The contracts
repository's `script/upgrade-v5.s.sol` builds this batch for one company
(`corpUpgradeCalls` / `printCorpUpgradeSafeBatch`, which prints Safe
Transaction Builder JSON) and refuses a company that has no RoundManager.

## 3. After the upgrade

* The upgraded printers keep their data, but the v5 register gate is new
  storage and starts closed: until an admin calls
  `setGlobalLegalTransferable(true)` (or `setTokenLegalTransferable` per
  lot) on a printer, `assignCert`, endorsed transfers and secondary-trade
  settlement on that printer revert `LegalOwnerNotTransferable`. Issuance and
  manager deliveries out of escrow are not affected. See
  [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md#delivery-and-registration-gates).
* Printers keep the certificate extension they were created with. New
  printers can bind the [V3 extensions](../reference/extensions.md), which
  need a v5 printer and IssuanceManager.
* On a printer whose lots were minted before it kept a per-wallet
  possession counter, a holder's counter reads zero and a transfer out of
  that wallet reverts. An admin seeds each such holder with
  `initializeHolderCount(holder)`, before anything is minted or transferred
  to or from it.
* The legal-owner enumeration and the look-through holder tally are also
  new storage and start empty on an upgraded printer. Until they are
  backfilled, existing holders read zero through `balanceOfLegalOwner` and
  `isLegalHolder`, and `lookThroughHolderCount()` starts at zero, so a
  configured `HolderCapCondition` can admit a buyer although the real cap
  is already full. Before enabling registration or secondary settlement on
  the printer:
  1. if the SPV uses look-through counting, wire the badge with
     `setLookThroughBadge(badge)` first;
  2. run `backfillLegalOwners(start, count)` and
     `backfillLookThroughTally(start, count)` in batches over
     `[0, totalSupply())`. Both are permissionless and idempotent, so a
     batch can be re-run safely.

  See [Holder counts](../reference/contracts/LedgerEntryToken.md#holder-counts).
* Each lot's `acquisitionTimestamp` is also new and reads zero for lots
  minted before the upgrade. `HoldingPeriodCondition` (Rule 144) and
  `RegSDistributionComplianceCondition` fail closed on a zero timestamp, so
  secondary trades on those pathways stay refused until it is set. Before
  enabling them:
  1. On a printer whose extension supports the fund-interest type, run
     `backfillAcquisitionTimestamps(start, count)` in batches. It copies
     each lot's recorded acquisition date, and does nothing on other
     printers.
  2. For the remaining lots, an admin sets each known date with
     `setAcquisitionTimestamp(tokenId, ts)`. The date anchors the holding
     period, so take it from the company's records.

  See [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md).

## What you can and cannot do

* You may stay on your current implementation indefinitely.
* You cannot upgrade to an implementation that is not the factory's
  published reference — the call reverts.
* The upgrade calls are made by your company's owner. Check whether the
  deploying factory still holds owner level on your BorgAuth; see
  [Access control](../reference/access-control.md#roles-the-protocol-assigns).

## Related

* [Upgrade model](../reference/upgrade-model.md).
* Explanation: [Co-approval upgradeability](../explanation/co-approval-upgradeability.md).
