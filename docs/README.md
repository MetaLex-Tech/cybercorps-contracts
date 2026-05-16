---
description: >-
  Natively tokenized private securities on Ethereum, anchored in each issuer's
  governing law — plus the web app that demonstrates them.
---

# Welcome to cyberCORPs

**cyberCORPs** is MetaLeX's smart-contract protocol for turning a legal entity
(a Delaware C-corp or LLC, a Cayman LLC or SPC, a BVI fund, an English company,
or any analogous structure) into an *onchain entity* that issues legally
constitutive digital securities, maintains its register of holders, conducts
fundraising rounds, and settles deals through a composable system of contracts.

In a cyberCORP, **the blockchain IS the official register** — not a pointer to
one.

The protocol is entity-type and jurisdiction agnostic. Delaware C-corp stock is
the most fully worked-out reference implementation. LLC membership interests,
LP interests, segregated-portfolio-company shares, and non-US equity all flow
through the same primitives.

Live on **Ethereum mainnet**, **Arbitrum**, and **Base**.

## How this documentation is organised

This book has two parts.

**Part 1 — Protocol** documents the smart contracts
([`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts)).
It follows the [Diátaxis](https://diataxis.fr/) framework:

| Section | When to read it |
|---|---|
| [**Tutorials**](tutorials/README.md) | You're new and want to *learn by doing*. Start here. |
| [**How-to Guides**](how-to/README.md) | You have a specific goal and want a recipe. |
| [**Reference**](reference/README.md) | You need the dry technical facts (contract APIs, roles, events, addresses). |
| [**Explanation**](explanation/README.md) | You want to *understand why* the protocol is the way it is. |

**Part 2 — Web App** documents the
[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp) monorepo: the
Next.js applications and backend services that implement the illustrative
products (the cyberCORPs Mainframe, cyberRAISE, ACE, LeXcheX, and more).

| Section | When to read it |
|---|---|
| [**Overview**](webapp/README.md) | What the monorepo is and what's in it. |
| [**Building**](webapp/local-setup.md) | Set up, develop, and extend the apps. |
| [**Apps and Services**](webapp/apps/cybercorps-web.md) | Per-app reference. |
| [**Operations**](webapp/deployment.md) | Deploy and run the apps and services. |

## The two-minute version

1. A **cyberCORP** is an onchain entity whose constitutional documents
   designate the onchain contract system as the entity's official register of
   holders.
2. A **cyberCERT** (ERC-721) is a *Ledger Entry Token* — a single entry on that
   register.
3. A **cyberSCRIP** (ERC-20) is the *fungible* form of that same security,
   minted from a cyberCERT and convertible back.
4. A growing **application stack** runs on this single contract suite —
   **cyberRAISE**, **cyberTRADE**, **ACE**, **LiquiLeX**, **cyberSign** — all
   surfaced through the cyberCORPs **Mainframe**. The reference
   implementations of these products live in `metalex-webapp` and are
   documented in Part 2.

## Repositories

* Protocol: [github.com/MetaLex-Tech/cybercorps-contracts](https://github.com/MetaLex-Tech/cybercorps-contracts)
* Web app: [github.com/MetaLex-Tech/metalex-webapp](https://github.com/MetaLex-Tech/metalex-webapp)
