# Upgrade model

The company-owned contracts use UUPS upgradeable proxies (with beacon proxies
for `LedgerEntryToken` — formerly `CyberCertPrinter` — and `CyberScrip`
instances) and **ERC-7201 namespaced storage**. Upgrades follow a
**co-approval** model.

## Co-approval

* MetaLeX publishes new implementations to the relevant factories
  (`*Factory.setRefImplementation` / `setCyberCertPrinterRefImplementation`
  / `setCyberScripRefImplementation`).
* The cyberCORP's owner independently opts in by calling
  `upgradeToAndCall(published, "")` on each of its own UUPS proxies, and the
  two beacon upgrades on its IssuanceManager. "Owner" means any address at
  BorgAuth level 99 or above on the company's BorgAuth, which includes the
  company's officers (level 200). Each contract's `_authorizeUpgrade` is
  `onlyOwner` **and** requires the new implementation to equal the published
  `getRefImplementation()` of the factory recorded in that contract
  (`upgradeFactory` / `getUpgradeFactory()`); otherwise it reverts
  `NotRefImplementation`.
* An issuer cannot upgrade to an arbitrary implementation outside the
  MetaLeX-published reference, and the factories hold no function that
  upgrades a company's contracts.

Implementation contracts call `_disableInitializers()` in their
constructors, so only the proxies are ever initialised.

{% hint style="warning" %}
The factory that deploys a company is the initial owner of the company's
BorgAuth (level 99), and the factory code on `develop` does not renounce
that level. The factory is itself an upgradeable proxy controlled by
MetaLeX. Read `userRoles(<factory>)` on the company's BorgAuth to see
whether a given company still grants it; see
[Access control](access-control.md#roles-the-protocol-assigns).
{% endhint %}

This keeps MetaLeX in the role of *protocol developer and steward* rather
than a securities intermediary with admin keys over the issuer's records.

## Versions and the v5 release

Each company-owned contract reports a `DEPLOY_VERSION`. The current source
is `"5"`, and the factories on Ethereum, Base and Arbitrum (and on the Base
Sepolia and Ethereum Sepolia testnets) publish v5 reference
implementations, so every company created now is a v5 company.

An existing company keeps the version it was deployed with until its owner
upgrades it: companies created by the previous release run `"4"`
(IssuanceManager `"4.1"`), and older ones `"3"`. Integrations must read
`DEPLOY_VERSION()` on the specific contract and pick the matching ABI.

A company upgrades **all six** of its contracts together: the CyberCorp,
IssuanceManager, DealManager and RoundManager proxies, and the
IssuanceManager's LedgerEntryToken and CyberScrip beacons. The versions
call each other's functions, and v5 removed or changed some of them (the v5
IssuanceManager drops functions a v4 DealManager calls, and the v5 managers
call printer functions a v4 printer lacks), so a company with some
contracts on v4 and others on v5 can see deal, round and issuance calls
revert. See [Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md).

The MetaLeX-owned singletons (factories, the agreement registry, the URI
builder, the certificate extensions) were upgraded for every company at
once; those upgrades kept the interfaces an older company calls.

## UUPS companies and legacy beacon companies

Companies deployed through the current `CyberCorpFactory` stack put the
CyberCorp, IssuanceManager, DealManager and RoundManager behind their own
ERC-1967 (UUPS) proxies, giving each cyberCORP control over its upgrade
cadence.

The oldest cyberCORPs use beacon proxies for the CyberCorp,
IssuanceManager and DealManager, pointing at beacons owned by the legacy
factories that MetaLeX controls. MetaLeX can move those beacons for all such
companies at once; the company owner cannot, and `upgradeToAndCall` on
those proxies reverts `UUPSUnauthorizedCallContext`. As of October 2, 2026
the legacy beacons on Ethereum, Base and Arbitrum still point at
`DEPLOY_VERSION` `"3"` code, and the v5 release scripts do not move them.

`DealManagerWithMigration` in the repository is a one-time beacon
implementation that re-points a legacy DealManager's `upgradeFactory` at
the current DealManagerFactory, for its fee settings. The IssuanceManager
variant is commented out, and the CyberCorp variant (which re-pointed legacy
CyberCorps at the current `CyberCorpSingleFactory`) has been removed from
the source. None of them converts a beacon proxy into a UUPS proxy.

## Beacons for downstream instances

Even in a UUPS company, instances *owned by* an `IssuanceManager` (its
`LedgerEntryToken` cert-printer and `CyberScrip` proxies) use beacon
proxies pointing at a beacon **owned by the IssuanceManager itself**
(created in `IssuanceManager.initialize`, seeded from the factory's
reference implementations). One call moves every printer (or every scrip)
of the company, still gated to the factory's published reference.

## Architecture diagram

See
[`ownership-and-upgradeability.md`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/ownership-and-upgradeability.md)
in the repository root for the full Mermaid class diagram showing both the
UUPS and legacy paths.

## See also

* [How-to: Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
* [Explanation: Co-approval upgradeability](../explanation/co-approval-upgradeability.md)
