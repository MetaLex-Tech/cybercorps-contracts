---
description: >-
  What MetaLeX can and cannot do to a cyberCORP: published implementations,
  opt-in upgrades, fees, templates, shared contracts, and the owner role the
  deploying factory keeps.
---

# Upgrades and what MetaLeX controls

A platform that held admin keys over every issuer's records would be acting
as each issuer's transfer agent. It would take on the registration and
intermediary liability that come with that role, and the issuers' control of
their own companies would be nominal. cyberCORPs is designed so that MetaLeX
develops and maintains the protocol without holding authority inside a
company's contracts. The exceptions are the deploying factory's owner role,
the oldest companies' beacons and the contracts all companies share, and
this page states each one.

## An upgrade needs a MetaLeX release and the company's opt-in

Each company's `CyberCorp`, `IssuanceManager`, `DealManager` and
`RoundManager` sit behind their own UUPS proxies. Every one of them
authorizes `upgradeToAndCall` only when two checks pass. The caller must
hold `OWNER_ROLE` on the company's BorgAuth (the function is `onlyOwner`),
and the new implementation must equal the reference implementation that the
contract's recorded factory publishes (`getRefImplementation()`). Anything
else reverts `NotRefImplementation`.

MetaLeX publishing an implementation therefore upgrades no company, and a
company can stay on its implementation indefinitely. A company also cannot
move to an implementation MetaLeX has not published, so it cannot escape the
protocol's invariants by upgrading to a fork, and because the check is an
exact match, the only target is the factory's current release. A company's
LET contracts and scrip run as beacon proxies on two beacons that its own
IssuanceManager owns. The owner moves each beacon with one call
(`upgradeCertPrinterBeaconImplementation`, `upgradeScripBeaconImplementation`),
which moves every LET contract, or every scrip contract, of the company at
once, and each call is held to the factory's published reference in the
same way.

Because each company opts in, versions coexist on the same chain. On
Ethereum, Base and Arbitrum the factories publish v5 reference
implementations, so a new company starts on v5, and an existing company
keeps its deployed version until its owners upgrade it. Integrations read
`DEPLOY_VERSION` on each contract instead of assuming one version per chain.
A company upgrades its six contracts together, since mixed versions break
deal, round and issuance calls. [Upgrade a cyberCORP](../how-to/upgrade-a-cybercorp.md)
gives the steps, and [Run your company](../webapp/company.md) covers the
upgrade in the app.

The oldest companies run on beacon proxies whose beacons MetaLeX owns. Their
owners cannot upgrade them, and MetaLeX can move those beacons for all such
companies at once.

## The deploying factory keeps OWNER_ROLE

Every address at level 99 or above on a company's BorgAuth holds
`OWNER_ROLE`. That includes the officers (level 200), the company's own
manager contracts, and the factory that deployed the company:
`CyberCorpFactory` for most companies, with `PumpCorpFactory`,
`MetaDAOFactory` and `ParentCoFactory` deploying the same way. BorgAuth gives
its deployer `OWNER_ROLE`, and the factory code does not give it up.

An owner can change any address's role on BorgAuth and call every
owner-gated function in the company's contracts, upgrades included. The
current factory code never uses the role after the deployment transaction,
but the factories are upgradeable by MetaLeX. While a factory holds the
role, the guarantee that MetaLeX cannot push an upgrade, or change the
company's roles, rests on MetaLeX not upgrading that factory to code that
would. Anyone can check a company by reading
`BorgAuth.userRoles(<factory address>)`, and an owner can remove the role
with `updateRole(<factory address>, 0)`.
[Access control](../reference/access-control.md) lists the roles the
protocol assigns.

## MetaLeX publishes releases, sets fees and owns the shared contracts

MetaLeX develops the contracts and publishes new implementations to the
factories. It sets the platform fees on the factories: a primary rate for
rounds and deals, a separate rate for secondary trades, and per-company
overrides of either. It maintains a library of agreement templates, but
template creation on the `CyberAgreementRegistry` is permissionless, so
anyone can register a template, and a standalone agreement creates its own
template when it is made. MetaLeX operates LeXcheX as an oracle, which means
MetaLeX or a delegate signs accreditation attestations into the credential
registry.

MetaLeX also owns the contracts every company shares, among them the
factories, the agreement registry, the `CertificateUriBuilder` that renders
each LET's metadata and certificate image, and the certificate extensions.
An upgrade to one of them reaches every company that uses it, with no
opt-in. A company's owner can point its IssuanceManager at a different URI
builder with `setUriBuilder`.

The reference apps (the cyberCORPs app, cyberRAISE, ACE, cyberSign and
LeXcheX onboarding) are MetaLeX's as well. Nothing in the contracts depends
on them or on the services behind them, and any front end can call the
contracts directly ([Integrate from a frontend](../how-to/integrate-from-frontend.md)).
A front end that helps investors find issuers may fall under the SEC staff's
April 2026 statement on covered user interface providers, whoever runs it.
[Regulatory context](regulatory-context.md) has the details.

## Funds, approvals and the register stay with the company

MetaLeX holds no issuer funds. Money in flight sits in the LeXscroW escrow
logic built into each company's own DealManager and RoundManager, and it
moves only along the deal's signature, finalization and expiry paths. Deals
are proposed and approved by the company's own BorgAuth owner and its
signing officers, with no MetaLeX approval step. The company's BorgAuth
roles belong to its officers, its governance addresses (board or officer
multisigs) and its own contracts, and no MetaLeX wallet holds one. The only
MetaLeX-controlled entry is the deploying factory described above.

MetaLeX keeps no register that overrides or competes with the chain. For
tokenized units, the register of holders is the company's Ledger Entry
Token (LET) contracts onchain. The cyberCORPs app's
[cap table](../webapp/captable.md) is the company's own working record. It
mirrors the LETs and can also hold untokenized positions recorded offchain.
The company's officers keep it in the app, and it exports to CSV, Excel and
OCF. Which record is the company's legally definitive securities ledger
depends on its governing documents. MetaLeX-form bylaws designate the
onchain LETs for tokenized shares (see
[Constitutive vs. pointer tokenization](constitutive-vs-pointer.md)).

## See also

* [Upgrade model](../reference/upgrade-model.md)
* [Factories](../reference/factories.md)
