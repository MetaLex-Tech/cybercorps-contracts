---
description: >-
  Natively tokenized private securities on Ethereum, anchored in each issuer's
  governing law — and how to use the apps built on them.
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
| [**Reference**](reference/README.md) | You need the dry technical facts (contract APIs, roles, events). |
| [**Explanation**](explanation/README.md) | You want to *understand why* the protocol is the way it is. |

**Part 2 — Web App** is for people *using* the cyberCORPs apps — issuers,
investors, and token communities. No code, no setup: just what each app does
and how to use it.

| Guide | For |
|---|---|
| [Using the cyberCORPs apps](webapp/README.md) | Everyone — start here. |
| [The cyberCORPs app](webapp/mainframe.md) | Issuers managing their cyberCORP. |
| [cyberRAISE](webapp/cyberraise.md) | Issuers raising capital; investors funding rounds. |
| [ACE](webapp/ace.md) | Token communities converting to equity; investors. |
| [LeXcheX](webapp/lexchex.md) | Anyone who needs to prove accredited-investor status. |
| [Your profile](webapp/profile.md) | Everyone — identity, wallets, and entities. |
| [MetaDAO](webapp/metadao.md) | Participants in futarchy-governed entities. |

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
   surfaced through the **cyberCORPs app**. Part 2 explains how to use
   them.

## Protocol repository

[github.com/MetaLex-Tech/cybercorps-contracts](https://github.com/MetaLex-Tech/cybercorps-contracts)
