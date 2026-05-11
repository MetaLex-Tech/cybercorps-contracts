# Upgrade model

All contracts use UUPS upgradeable proxies (with beacon proxies for
`CyberCertPrinter` and `CyberScrip` instances) and **ERC-7201 namespaced
storage**. Upgrades follow a **co-approval** model.

## Co-approval

* MetaLeX publishes new implementations to the relevant factories
  (`*Factory.setRefImplementation` / `setCyberCertPrinterRefImplementation`
  / `setCyberScripRefImplementation`).
* Each cyberCORP's `UPGRADE_AUTHORITY` independently opts in by calling
  `upgradeToAndCall(published, "")` on its own UUPS proxy.
* Neither side can act unilaterally:
  * MetaLeX cannot push an upgrade.
  * An issuer cannot upgrade to an arbitrary implementation outside the
    MetaLeX-published reference.

This keeps MetaLeX in the role of *protocol developer and steward* rather
than a securities intermediary with admin keys over the issuer's stock
ledger.

## V3 vs legacy

V3 architectures use UUPS for top-level contracts (`CyberCorp`,
`IssuanceManager`, `DealManager`, `RoundManager`), giving each cyberCORP
full control over its upgrade cadence.

Legacy architectures use beacon proxies pointing at MetaLeX-owned beacons,
allowing batch upgrades but giving MetaLeX more control. Legacy cyberCORPs
continue to receive upgrades through the beacon pattern; new deployments
are always v3.

A legacy cyberCORP can migrate to v3 architecture in place via the
`*WithMigration.sol` contracts in the repository.

## Beacons for downstream instances

Even in v3, instances *owned by* an `IssuanceManager` (its `CyberCertPrinter`
and `CyberScrip` proxies) use beacon proxies pointing at a beacon **owned by
the IssuanceManager itself**. This keeps the suite upgrading together when
the issuer chooses to upgrade, while preserving co-approval against MetaLeX.

## Architecture diagram

See
[`ownership-and-upgradeability.md`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/ownership-and-upgradeability.md)
in the repository root for the full Mermaid class diagram showing both v3
and legacy paths.

## See also

* [How-to: Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
* [Explanation: Co-approval upgradeability](../explanation/co-approval-upgradeability.md)
