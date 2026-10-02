---
description: What the cyberCORPs apps do and which one you need
---

# Using the cyberCORPs apps

This part of the documentation is for the people who **use** the MetaLeX
apps — founders, officers, and investors. No code: just what each app is for
and how to use it.

If you want to understand the machinery beneath the apps — what a cyberCORP,
a cyberCERT, or a cyberSCRIP actually *is*, and why the design works the way
it does — that is **Part 1, Protocol**. Each guide here links into it at the
relevant points; see [How the apps relate to the protocol](#how-the-apps-relate-to-the-protocol)
below.

## The apps, and where they live

The products run as **separate apps, each on its own subdomain**. Your
company and the securities it issues are shared across them — set things up
once and they appear everywhere.

| App | Address | What you do there |
|---|---|---|
| [**cyberCORPs app**](mainframe.md) | `cybercorps.metalex.tech` | Form a new LLC or C-Corp, or bring your existing company onchain; run its cap table, board, grants, and register of holders; issue and manage its securities and scrip. Home of the **Tokenization Hub**. |
| [**cyberRAISE**](cyberraise.md) | `cyberraise.metalex.tech` | Run fundraising rounds, and invest in them. **Rounds are created and configured here.** |
| [**ACE**](ace.md) | inside cyberRAISE | Token-community fundraising — raises denominated in a community token. (Old `ace.metalex.tech` links redirect to cyberRAISE.) |
| [**cyberSign**](cybersign.md) | `app.metalex.tech` | Propose, review, sign and countersign agreements. The cyberCORPs app's **cyberSign** sidebar item opens it. |
| [**LeXcheX**](lexchex.md) | `lexchex.metalex.tech` | Prove accredited-investor status. |
| [**Your profile**](profile.md) | `profile.metalex.tech` | Your MetaLeX identity, accreditation status, and signing delegation. |

The cyberCORPs app is big enough that its largest areas get their own
guides:

* [**The cap table**](captable.md) — the unified cap table of tokenized
  and untokenized positions, importing (including the AI-assisted
  import), and tokenizing.
* [**Cap-table records, modeling and compliance**](captable-tools.md) —
  §219 stockholder lists, 409A / Rule 701 / 3921 / 83(b) records, round
  modeling, and the exit waterfall.
* [**Token grants and onchain vesting**](grants.md) — options, RSUs, and
  restricted stock escrowed onchain via MetaVesT.
* [**The boardRoom and Incorporation Hub**](boardroom.md) — officers,
  directors, board consents, and the formation record.
* [**For holders: your securities**](holders.md) — the stakeholder and
  investor side: My holdings, certificates, transfers, scrip.

One more surface is covered separately:

* [**Launchpads: MetaDAO and Umia**](metadao.md) — one-step
  entity-formation pages for tokens launched via MetaDAO or Umia, plus
  the public company pages and the launchpad directory.

> **Which app do I need?**
> Forming a new company, or setting up or running one → the **cyberCORPs
> app**.
> Managing who owns what → [the cap table](captable.md).
> Vesting stock to your team → [grants](grants.md).
> Signing or sending an agreement → [**cyberSign**](cybersign.md).
> Raising money, or investing in a raise → **cyberRAISE**.
> A token community converting to equity → **ACE**.
> Getting accredited → **LeXcheX**.
> Holding securities someone issued you → [For holders](holders.md).
> Editing your identity → **your profile**.

## Before you start: what you need

1. **A web3 wallet** — a browser wallet such as MetaMask or Rabby. The apps
   connect to it to read your holdings and ask you to sign. A **Safe
   multisig** is supported and recommended for company treasuries.
2. **A little ETH for gas** — actions that change onchain state are
   transactions and cost a small network fee. cyberCORPs run on **Ethereum,
   Arbitrum, and Base**; you need gas on whichever network the entity uses.
   (A company formed through the in-app formation flow gets its onchain
   record on the payment chain — Ethereum mainnet.)
3. **A desktop browser is recommended** for company setup and other
   heavier flows, though the apps work on mobile.
4. **No separate account setup** — your first wallet sign-in creates a
   MetaLeX account and its profile record, and links that wallet to the
   account. Your profile follows the account across all linked wallets;
   add or switch wallets later in **Wallet Settings**.

On cost: signing with cyberSign, setting up an **existing** company on
MetaLeX, and manual securities issuance and management in the Tokenization
Hub are free (gas aside). **Forming a new company** through the app is a
flat **\$1,000 fee, paid in USDC** — state filing, formation documents,
initial tax filings, and a lawyer consultation included. Filing a later
annual report for a company formed this way costs only the state's fee.
MetaLeX charges a **0.3% fee on funds an issuer claims from a cyberRAISE
round** — investors pay nothing.

## Signing in

The apps connect to your wallet automatically. For actions that need a
verified session — managing a company, editing your profile, encrypting
data — you complete a one-time **Authenticate** step: you sign a short
Sign-In With Ethereum message. This signature is **free** — not a
transaction, no gas.

Access to a company follows your profile: its pages open for a signed-in
profile that has one of the company's owner wallets linked, whichever
wallet you are browsing with. Signing for the company still needs an
owner wallet connected on the company's network, and the app tells you
which wallet to switch to.

> MetaLeX never takes custody of your funds or your securities. Money in
> transit during a raise or deal sits in an onchain escrow that no one can
> override.

## Two kinds of “sign”

You'll be asked to sign two different things:

* **A message signature** — free, instant, no gas. Authenticating, agreeing
  to a legal document, expressing interest in a round.
* **A transaction** — costs gas, confirms in a few seconds. Deploying a
  company, issuing a security, funding a round, closing a round.

Your wallet always tells you which one it is before you approve. Each app
guide notes which steps are which.

## A note on terms

* A **cyberCORP** is your company, represented onchain.
* A **cyberCERT** is a certificate — one entry on the company's register of
  holders (a share position, a SAFE, an option, etc.).
* A **cyberSCRIP** is the tradable, fungible form of a security.
* An **EOI** (Expression of Interest) is an investor's signed offer to
  invest in a round.

The full [Glossary](../reference/glossary.md) has the rest.

## How the apps relate to the protocol

The apps are **front ends over the cyberCORPs smart-contract protocol**.
Creating a company, issuing and transferring securities, and signing
agreements are contract calls. The app also keeps offchain records
(untokenized cap table positions, drafts, formation details, legal terms
versions), and each guide says which actions are which.

* When you **deploy a cyberCORP**, the app calls the protocol's factory,
  which deploys your company's contracts. When the company's governing
  documents designate it, the chain is the company's *official register*,
  not a copy of one. This is the core idea of the protocol: see
  [Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md).
* When you **issue a security**, the app mints a **cyberCERT** — an entry on
  that register.
* When you **scripify**, the app deploys a **cyberSCRIP** — the same
  security in fungible form. Why two forms exist is explained in
  [The dual-token model](../explanation/dual-token-model.md).

Throughout these guides, **“Under the hood”** boxes link the action you're
taking to the protocol contract behind it. You never need to read Part 1 to
use the apps — but if you want to know exactly what you are signing, it is
all there.

A good starting point for the protocol side is the
[Protocol welcome / overview](../README.md) and the tutorial
[Incorporate a cyberCORP](../tutorials/incorporate-a-cybercorp.md).
