# Upgrade a cyberCORP

All contracts use UUPS upgradeable proxies (with beacon proxies for
`CyberCertPrinter` and `CyberScrip`). Upgrades use a **co-approval** model:
MetaLeX publishes a reference implementation, and the cyberCORP's owner opts
in. See [Upgrade model](../reference/upgrade-model.md).

## Upgrade the CyberCorp contract

`CyberCorp._authorizeUpgrade` is `onlyOwner` **and** requires the new
implementation to equal the factory's reference implementation — otherwise
it reverts `NotRefImplementation`.

```solidity
// The target must equal the factory's published reference implementation:
address published =
    ICyberCorpSingleFactory(CyberCorp(cyberCorp).upgradeFactory()).getRefImplementation();

UUPSUpgradeable(cyberCorp).upgradeToAndCall(published, "");
```

If `published` is not what you expected, do not upgrade — the gate exists so
neither side can move you to an arbitrary implementation.

## Upgrade the IssuanceManager, DealManager, RoundManager

The `IssuanceManager`, `DealManager`, and `RoundManager` are UUPS proxies
too; upgrade each with `upgradeToAndCall` against its factory's reference
implementation, gated the same way.

## Upgrade CyberCertPrinter / CyberScrip instances

These are beacon proxies. The beacons are owned by the cyberCORP's
`IssuanceManager`, which exposes:

```solidity
IIssuanceManager(issuanceManager).upgradeCertPrinterBeaconImplementation(newImpl);
IIssuanceManager(issuanceManager).upgradeScripBeaconImplementation(newImpl);
```

Upgrading a beacon moves every instance of that type under the
IssuanceManager at once.

## What you can and cannot do

* You may stay on your current implementation indefinitely.
* You cannot upgrade to an implementation that is not the factory's
  published reference — the call reverts.
* MetaLeX cannot upgrade your contracts; the upgrade call is made by your
  owner.

## Related

* [Upgrade model](../reference/upgrade-model.md).
* Explanation: [Co-approval upgradeability](../explanation/co-approval-upgradeability.md).
