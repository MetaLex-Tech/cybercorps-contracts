# Reference

Reference is information-oriented: dry, neutral, and complete. Use it to look
up what something *is*, not to learn or to do.

> **The contract source is authoritative.** These pages are generated from
> the contracts in
> [`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts)
> as of the `develop` branch (contracts in the `DEPLOY_VERSION` `"4"` line —
> per contract: `CyberCorp`, `RoundManager`, `CyberScrip`, and
> `LedgerEntryToken` at `"4"`, `IssuanceManager` at `"4.1"`, `DealManager`
> at `"4.0.1"`). The
> protocol is under active development — some contracts contain stubbed or
> in-progress functions, noted on the relevant pages. Always check the
> current `.sol` source before relying on an exact signature, and treat the
> code samples in the Tutorials and How-to sections as *illustrative of the
> flow* rather than copy-paste-ready.

## Contents

* [Core contracts](contracts.md) — every contract with a one-line role.
* [Factories](factories.md) — `CyberCorpFactory` and the sub-factories.
* [Certificate extensions](extensions.md) — per-security-type metadata.
* [Hooks](hooks.md) — transfer-restriction hooks and the LiquiLeX fee hook.
* [Conditions](conditions.md) — the `ICondition` and
  `ISecondaryTradingCondition` interfaces and the built-in conditions.
* [Access control (BorgAuth)](access-control.md) — the numeric role model.
* [Upgrade model](upgrade-model.md) — UUPS + beacon proxies, co-approval.
* [Agreement templates](templates.md) — the `/templates` library.
* [Security types](security-types.md) — the `SecurityClass` enum.
* [Deployments](deployments.md) — canonical addresses.
* [Glossary](glossary.md) — protocol terms.
