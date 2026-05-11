---
description: >-
  Natively tokenized private securities on Ethereum, anchored in each issuer's
  governing law.
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

These docs follow the [Diátaxis](https://diataxis.fr/) framework. Each section
serves a different need:

| Section | When to read it |
|---|---|
| [**Tutorials**](tutorials/README.md) | You're new and want to *learn by doing*. Start here. |
| [**How-to Guides**](how-to/README.md) | You have a specific goal and want a recipe. |
| [**Reference**](reference/README.md) | You need the dry technical facts (contract APIs, roles, events, addresses). |
| [**Explanation**](explanation/README.md) | You want to *understand why* the protocol is the way it is. |

## The two-minute version

1. A **cyberCORP** is an onchain entity whose constitutional documents
   (certificate of incorporation, operating agreement, partnership agreement,
   fund constitutional documents, articles of association, etc.) designate the
   onchain contract system as the entity's official register of holders.
2. A **cyberCERT** (ERC-721) is a *Ledger Entry Token* — a single entry on that
   register, encoding the holder, units, class/series, restrictions,
   endorsements, signatures, and the governing agreement URI.
3. A **cyberSCRIP** (ERC-20) is the *fungible* form of that same security. It
   is minted from a cyberCERT via `scripifyCert()` and convertible back via
   `convertScripToCert()`. It is itself a security in scrip form (e.g., DGCL
   §155), not a wrapper or derivative.
4. A growing **application stack** runs on this single contract suite:
   **cyberRAISE** (primary fundraising), **cyberTRADE** (secondary
   settlement), **ACE** (Asset Conversion to Equity), **LiquiLeX** (AMM-native
   scrip liquidity), and **cyberSign** (cybernetic legal agreement execution),
   all surfaced to issuers through the cyberCORPs **Mainframe**.

## Illustrative applications

The [metalex-webapp](https://github.com/MetaLex-Tech/metalex-webapp) monorepo
hosts reference UIs built on these contracts. They are not the protocol; they
are *examples* of what an issuer or front-end provider can build on top of it.
See [Application Stack](explanation/application-stack.md) for a mapping.

## Contracts repository

[github.com/MetaLex-Tech/cybercorps-contracts](https://github.com/MetaLex-Tech/cybercorps-contracts)
