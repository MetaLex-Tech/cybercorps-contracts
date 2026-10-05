# Upgrade model

The company-owned contracts use UUPS proxies, with beacon proxies for
`LedgerEntryToken` (LET contract) and `CyberScrip` instances, and
**ERC-7201 namespaced storage**. An upgrade needs both MetaLeX and the
company: MetaLeX publishes the implementation, and the company's owner
installs it (**co-approval**).

## Co-approval

* MetaLeX publishes new implementations to the factories
  (`*Factory.setRefImplementation`, `setCyberCertPrinterRefImplementation`,
  `setCyberScripRefImplementation`).
* The cyberCORP's owner opts in separately by calling
  `upgradeToAndCall(published, "")` on each of its own UUPS proxies and
  running the two beacon upgrades on its IssuanceManager. "Owner" means
  any address at BorgAuth level 99 or above on the company's BorgAuth,
  which includes the company's officers (level 200). Each contract's
  `_authorizeUpgrade` is `onlyOwner` **and** requires the new
  implementation to equal the published `getRefImplementation()` of the
  factory recorded in that contract (`upgradeFactory` /
  `getUpgradeFactory()`); otherwise it reverts `NotRefImplementation`.
* An issuer cannot upgrade to an implementation MetaLeX has not
  published, and the factories have no function that upgrades a company's
  contracts.

Implementation contracts call `_disableInitializers()` in their
constructors, so only the proxies are ever initialized.

{% hint style="warning" %}
The factory that deploys a company is the initial owner of the company's
BorgAuth (level 99) and does not renounce that level. The factory is
itself an upgradeable proxy that MetaLeX controls. Read
`userRoles(<factory>)` on the company's BorgAuth to see whether a company
still grants it; see
[Access control](access-control.md#roles-the-protocol-assigns).
{% endhint %}

[Upgrades and what MetaLeX controls](../explanation/upgrades-and-control.md) explains
what this model lets MetaLeX do and not do.

## Versions in production

Each company-owned contract reports a `DEPLOY_VERSION`. The source is at
`"5"`, and the factories on Ethereum, Base and Arbitrum (and on the Base
Sepolia and Ethereum Sepolia testnets) publish v5 reference
implementations, so every new company is a v5 company.

An existing company keeps the version it was deployed with until its
owner upgrades it. v4 companies run `"4"` (IssuanceManager `"4.1"`,
DealManager `"4.0.1"`), and older ones `"3"`. Integrations must read
`DEPLOY_VERSION()` on the specific contract and pick the matching ABI.

A company upgrades **all six** of its contracts together: the CyberCorp,
IssuanceManager, DealManager and RoundManager proxies, and the
IssuanceManager's LedgerEntryToken and CyberScrip beacons. The contracts
call each other's functions, and v4 and v5 differ in some of them: the v5
IssuanceManager lacks functions a v4 DealManager calls, and the v5
managers call LET contract functions a v4 LET contract lacks. A company
with some contracts on v4 and others on v5 can therefore see deal, round
and issuance calls revert. See
[Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md).

The MetaLeX-owned singletons (factories, the agreement registry, the URI
builder, the certificate extensions) serve every company at once and keep
the interfaces that v4 and older companies call.

## UUPS companies and legacy beacon companies

Companies deployed through the `CyberCorpFactory` stack put the
CyberCorp, IssuanceManager, DealManager and RoundManager behind their own
ERC-1967 (UUPS) proxies, so each cyberCORP decides when it upgrades.

The oldest cyberCORPs use beacon proxies for the CyberCorp,
IssuanceManager and DealManager, pointing at beacons owned by legacy
factories that MetaLeX controls. MetaLeX can move those beacons for all
such companies at once; the company owner cannot, and `upgradeToAndCall`
on those proxies reverts `UUPSUnauthorizedCallContext`. The legacy beacons
on Ethereum, Base and Arbitrum point at `DEPLOY_VERSION` `"3"` code, and
the v5 upgrade scripts do not move them.

`DealManagerWithMigration` is a one-time beacon implementation that
re-points a legacy DealManager's `upgradeFactory` at the current
DealManagerFactory, for its fee settings. It does not convert a beacon
proxy into a UUPS proxy.

## Beacons inside a UUPS company

Even in a UUPS company, the instances an `IssuanceManager` owns (its
`LedgerEntryToken` and `CyberScrip` proxies) are beacon proxies pointing
at a beacon **owned by the IssuanceManager itself**, created in
`IssuanceManager.initialize` and seeded from the factory's reference
implementations. One call moves every LET contract (or every scrip) of
the company, still gated to the factory's published reference.

## Architecture diagram

[`ownership-and-upgradeability.md`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/ownership-and-upgradeability.md)
in the repository root has the full Mermaid class diagram of the UUPS and
legacy paths.

## See also

* [Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
* [Upgrades and what MetaLeX controls](../explanation/upgrades-and-control.md)
