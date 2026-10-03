---
description: "Contract APIs, roles, events and deployed addresses"
---

# Reference

Look up contract functions, access rules, events, errors and addresses
here. The [guides](../how-to/README.md) show how to put them together.

> **The contract source is authoritative.** These pages follow the
> `develop` branch of
> [`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts),
> where `CyberCorp`, `IssuanceManager`, `DealManager`, `RoundManager`,
> `LedgerEntryToken` and `CyberScrip` all report `DEPLOY_VERSION` `"5"`.
> Companies that have not upgraded run v4 components (`"4"`, with
> `IssuanceManager` at `"4.1"` and `DealManager` at `"4.0.1"`), and the pages
> mark v4 differences wherever an integrator can meet both. `CyberShares`
> and `SafeCertificateConverter` are partly stubbed, as their pages say.
> Check the `.sol` source before relying on an exact signature, and treat
> the code in the guides as an outline of each flow that you verify against
> the source before use.

## Contents

| Page | What it covers |
|---|---|
| [Core contracts](contracts.md) | Every contract and its role, with a page per contract. |
| [Factories](factories.md) | `CyberCorpFactory`, its sub-factories and the specialised factories. |
| [Certificate extensions](extensions.md) | Per-security-type metadata contracts and how their scopes merge. |
| [Hooks](hooks.md) | Transfer-restriction hooks and the LiquiLeX fee hook. |
| [Conditions](conditions.md) | The `ICondition` and `ISecondaryTradingCondition` interfaces and the built-in conditions. |
| [Access control (BorgAuth)](access-control.md) | The numeric role model and the levels the protocol assigns. |
| [Upgrade model](upgrade-model.md) | UUPS and beacon proxies, co-approval, versions in production. |
| [Agreement templates](templates.md) | The `/templates` library and custom templates. |
| [Security types](security-types.md) | The `SecurityClass`, `SecuritySeries` and `SecurityStatus` enums. |
| [Deployments](deployments.md) | Contract addresses by chain. |
| [Glossary](glossary.md) | Protocol and app terms. |
