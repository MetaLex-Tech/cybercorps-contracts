---
description: >-
  Private securities recorded as Ledger Entry Tokens, anchored in each
  issuer's governing law, and the MetaLeX apps that run on them.
---

# Welcome to cyberCORPs

cyberCORPs is MetaLeX's smart-contract protocol for keeping a company's
securities onchain, together with the apps built on it. A company joins as a
**cyberCORP**: its governing documents designate the protocol's contracts as
the register for the shares they tokenize, and those contracts issue its
securities, record transfers, run fundraising rounds and settle trades. For
those shares the onchain record is the register itself, and the tokens do not
point at a register kept somewhere else.

The protocol works for any entity type and jurisdiction. Delaware C-corp
stock is the most complete implementation, and LLC membership interests, LP
interests, segregated portfolio company shares and non-US equity use the same
contracts. It runs on Ethereum, Base and Arbitrum.

## Core terms

* A **cyberCORP** is the company's onchain presence: its `CyberCorp` contract
  plus the managers that issue its securities, run its rounds and settle its
  deals.
* A **Ledger Entry Token (LET)** is an ERC-721 token that records one entry
  on the register: who holds how many units of which class or series, on what
  terms and restrictions. Each class or series has its own **LET contract**.
* **Scrip** is a fungible ERC-20 token that tracks a LET's units in a fixed
  ratio. A holder moves units from a LET into scrip and can convert scrip
  back into a LET. The rights scrip carries come from the company's governing
  documents and the scrip's terms: under MetaLeX-form bylaws, scrip is not
  stock and gives no stockholder rights on its own.
* **cyberSign** records agreements in the `CyberAgreementRegistry`, where
  every party's signature is checked onchain. Rounds, deals and trades are
  signed there.

[Ledger Entry Tokens and scrip](explanation/lets-and-scrip.md) explains how
the two forms relate, and the [glossary](reference/glossary.md) defines the
rest.

## How this book is organized

| Part | Written for | Start with |
|---|---|---|
| **Using the apps** | Founders, officers, investors and holders using the MetaLeX apps. No code. | [Getting started](webapp/README.md) |
| **How cyberCORPs works** | Anyone evaluating the model: lawyers, investors, integrators. | [Constitutive vs. pointer tokenization](explanation/constitutive-vs-pointer.md) |
| **Building on the protocol** | Developers integrating with or extending the contracts. | [Guides](how-to/README.md), then the [reference](reference/README.md) |

## What runs on the protocol

| Product | What it does | Guide |
|---|---|---|
| **cyberCORPs app** | Form a company or bring an existing one onchain, then run its cap table, board, grants and securities. | [Run your company](webapp/company.md) |
| **cyberRAISE** | Primary fundraising rounds: SAFEs, SAFTs, SAFTEs, token warrants and priced equity. | [cyberRAISE](webapp/cyberraise.md) |
| **ACE** | Rounds paid in a token community's own token. | [ACE](webapp/ace.md) |
| **cyberSign** | Propose and sign agreements, each signature recorded onchain. | [cyberSign](webapp/cybersign.md) |
| **LeXcheX** | Accredited-investor and compliance credentials attached to a wallet. | [LeXcheX](webapp/lexchex.md) |
| **cyberTRADE** | Settlement of negotiated secondary trades under an elected exemption pathway. | [Run a secondary trade](how-to/run-a-secondary-trade.md) |
| **LiquiLeX** | Uniswap v4 liquidity pools for scrip. | [Deploy a LiquiLeX pool](how-to/deploy-liquilex-pool.md) |

## Source code

The contracts are in
[MetaLex-Tech/cybercorps-contracts](https://github.com/MetaLex-Tech/cybercorps-contracts),
and the apps in
[MetaLex-Tech/metalex-webapp](https://github.com/MetaLex-Tech/metalex-webapp).
