# Co-approval upgradeability

Upgradeable contracts are a power-concentration risk. The wrong upgrade key
on a stock-ledger contract is, functionally, the wrong signature on a board
resolution. cyberCORPs solves this with a **co-approval** model: neither
MetaLeX nor any individual issuer can unilaterally upgrade a deployed
cyberCORP.

## How it works

Each cyberCORP's top-level contracts (`CyberCorp`, `IssuanceManager`,
`DealManager`, `RoundManager` in v3) are UUPS-upgradeable proxies. The
`upgradeToAndCall(impl, data)` function is gated on **two** invariants:

1. `impl` must be a MetaLeX-published reference implementation (tracked on
   the relevant factory via `setRefImplementation` / variants).
2. The caller must hold the issuer's `UPGRADE_AUTHORITY` BorgAuth role.

Neither condition is sufficient alone:

* MetaLeX publishing a new implementation does *not* upgrade anyone. The
  factory's reference is just a published address.
* An issuer attempting to upgrade to an arbitrary implementation will
  revert. The implementation must be on the factory's allow-list.

## What this buys you

* **No forced migrations.** A cyberCORP that wants to stay on its current
  implementation can do so indefinitely.
* **No MetaLeX admin keys over your stock ledger.** MetaLeX is a protocol
  developer and steward, not a securities intermediary.
* **No issuer escape to a malicious implementation.** Issuers cannot dodge
  protocol invariants by upgrading to a fork.

## Beacons for downstream instances

`CyberCertPrinter` and `CyberScrip` instances use beacon proxies pointing at
beacons **owned by the IssuanceManager itself**. When the IssuanceManager's
officer upgrades the beacon, every printer/scrip instance under that
IssuanceManager moves together — which is what you usually want, since they
share storage layout and behavioural assumptions.

The same co-approval invariant applies: the beacon will only accept
implementations registered on the factory.

## Legacy paths

Legacy cyberCORPs deployed before v3 use top-level beacon proxies pointing
at MetaLeX-owned beacons. They continue to receive upgrades via the beacon
pattern (which is more MetaLeX-controlled), but the underlying invariant
— co-approval — is preserved at the implementation-publication step. Legacy
deployments can migrate to v3 in place via the `*WithMigration.sol`
variants.

## See also

* [Upgrade model](../reference/upgrade-model.md)
* [How-to: Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
* [The role of MetaLeX](role-of-metalex.md)
