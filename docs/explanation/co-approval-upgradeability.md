# Co-approval upgradeability

Upgradeable contracts are a power-concentration risk. The wrong upgrade key
on a stock-ledger contract is, functionally, the wrong signature on a board
resolution. cyberCORPs solves this with a **co-approval** model: neither
MetaLeX nor any individual issuer can unilaterally upgrade a deployed
cyberCORP.

## How it works

Each cyberCORP's top-level contracts (`CyberCorp`, `IssuanceManager`,
`DealManager`, and, from v3 on, `RoundManager`) are UUPS-upgradeable
proxies. The `upgradeToAndCall(impl, data)` function is gated on **two**
invariants:

1. `impl` must be a MetaLeX-published reference implementation (tracked on
   the relevant factory via `setRefImplementation` / variants).
2. The caller must hold the issuer's BorgAuth owner role (`OWNER_ROLE`) —
   the upgrade entry points are `onlyOwner`.

Neither condition is sufficient alone:

* MetaLeX publishing a new implementation does *not* upgrade anyone. The
  factory's reference is just a published address.
* An issuer attempting to upgrade to an arbitrary implementation will
  revert. The implementation must be on the factory's allow-list.

{% hint style="warning" %}
`OWNER_ROLE` is held by every address at level 99 or above on the
company's BorgAuth, not only by the issuer's officers. The company's own
manager contracts hold it, and so does the factory that deployed the
company (`CyberCorpFactory` for most companies; `PumpCorpFactory`,
`MetaDAOFactory`, and `ParentCoFactory` deploy the same way): BorgAuth
gives its deployer `OWNER_ROLE`, and the factory does not give it up
(confirmed onchain for an existing Ethereum company on 2026-10-02). The
current factory code never uses that role after the deployment
transaction, but the factories are themselves upgradeable by MetaLeX.
While a factory holds the role, the guarantee that MetaLeX cannot push an
upgrade rests on MetaLeX not upgrading that factory to code that would. An
issuer can read the factory's level with
`BorgAuth.userRoles(<factory address>)`.
{% endhint %}

## What this buys you

* **No forced migrations.** A cyberCORP that wants to stay on its current
  implementation can do so indefinitely.
* **No MetaLeX admin keys over your stock ledger.** MetaLeX is a protocol
  developer and steward, not a securities intermediary.
* **No issuer escape to a malicious implementation.** Issuers cannot dodge
  protocol invariants by upgrading to a fork.

## Beacons for downstream instances

`LedgerEntryToken` (formerly `CyberCertPrinter`) and `CyberScrip` instances
use beacon proxies pointing at beacons **owned by the IssuanceManager
itself**. When the issuer's owner upgrades the beacon through the
IssuanceManager, every printer/scrip instance under that IssuanceManager
moves together — which is what you usually want, since they share storage
layout and behavioural assumptions.

The same co-approval invariant applies: the beacon upgrade functions will
only accept the corresponding reference implementation registered on the
factory.

## Legacy paths

Legacy cyberCORPs deployed before v3 use top-level beacon proxies pointing
at MetaLeX-owned beacons. They continue to receive upgrades via the beacon
pattern (which is more MetaLeX-controlled), but the underlying invariant
— co-approval — is preserved at the implementation-publication step. Of the
in-place migration contracts for those deployments, only
`DealManagerWithMigration` remains active in the source:
`CyberCorpWithMigration` has been removed and `IssuanceManagerWithMigration`
is commented out.

## Versions coexist

Because each company opts in to its own upgrades, companies on different
versions run side by side. The v5 release changed the factories' reference
implementations on Ethereum, Base, and Arbitrum, so companies created since
then start on v5, while each existing company stays on its deployed version
until its owners upgrade it. Integrations read each contract's
`DEPLOY_VERSION` rather than assuming one version per chain (see
[Integrate from a frontend](../how-to/integrate-from-frontend.md#abis-and-versions)).

## See also

* [Upgrade model](../reference/upgrade-model.md)
* [How-to: Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
* [The role of MetaLeX](role-of-metalex.md)
