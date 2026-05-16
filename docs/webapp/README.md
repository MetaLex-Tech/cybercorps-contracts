# The metalex-webapp monorepo

[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp) is the
monorepo that implements the **illustrative applications** built on the
cyberCORPs protocol. It is not the protocol — the protocol is the contracts in
[`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts).
The webapp is one possible set of front ends and supporting services for it.

> The repository is MetaLeX-internal. These docs describe it for two
> audiences: **external builders** who want to understand the reference
> implementation (or build their own front end), and **internal developers**
> who work on the monorepo directly. Pages note which audience they target
> when it matters.

## What's in it

The monorepo is a [Turborepo](https://turbo.build/repo) workspace managed with
[Bun](https://bun.sh/). It contains **apps** (deployable Next.js apps and
standalone services) and **packages** (shared libraries).

### Apps

| App | What it is |
|---|---|
| [`cybercorps-web`](apps/cybercorps-web.md) | The cyberCORPs platform UI — the Mainframe, cyberRAISE, ACE, MetaDAO, profiles. The closest thing to "the cyberCORPs app." |
| [`web`](apps/web.md) | The main MetaLeX webapp (BORG OS surface). |
| [`lexchex-web`](apps/lexchex-web.md) | The LeXcheX onchain-accreditation app. |
| [`landing`](apps/landing.md) | The marketing landing site. |
| [`cybercorps-indexer`](apps/cybercorps-indexer.md) | A Ponder indexer projecting protocol events into a queryable store. |
| [`lexchex-oracle`](apps/lexchex-oracle.md) | The LeXcheX backend oracle (identity / portfolio verification). |
| [`notifier`](apps/notifier.md) | A cron service sending Telegram notifications for cyberRAISE activity. |
| [`snapshot-executor`](apps/snapshot-executor.md) | A service that executes successful Snapshot / BORG governance votes onchain. |

### Packages

Shared libraries consumed by the apps — ABIs, database schemas, the design
system, EVM clients, encryption, governance utilities, and more. See
[Apps and packages](apps-and-packages.md) for the full inventory.

## How it relates to the protocol

Every product surface in the webapp is a thin client over the protocol
contracts:

* `cybercorps-web` routes (`/cybercorps`, `/cyberraise`, `/ace`, `/metadao`)
  call `CyberCorpFactory`, `RoundManager`, `IssuanceManager`, `DealManager`,
  etc.
* `lexchex-web` + `lexchex-oracle` mint the LeXcheX credentials that the
  protocol's `lexchexCondition` checks.
* `cybercorps-indexer` reads protocol events; `notifier` reads the indexer.
* `snapshot-executor` bridges off-chain governance to on-chain authority.

See the protocol-side [Application stack](../explanation/application-stack.md)
for the product-to-contract mapping.

## Where to go next

* New to the repo? Start with [Local development setup](local-setup.md).
* Want the layout? See [Monorepo structure](project-structure.md).
* Building a feature? See [Add a feature to cybercorps-web](add-a-feature.md).
* Just want to know what an app does? Jump to its page under
  **Web App — Apps and Services**.
