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
| [**cyberCORPs app**](mainframe.md) | `cybercorps.metalex.tech` | Create your company; issue and manage its securities, register of holders, and scrip. Home of the **Mainframe**. |
| [**cyberRAISE**](cyberraise.md) | `cyberraise.metalex.tech` | Run fundraising rounds, and invest in them. **Rounds are created and configured here.** |
| [**ACE**](ace.md) | `ace.metalex.tech` | Token-community fundraising — raises denominated in a community token. Currently early-access. |
| [**LeXcheX**](lexchex.md) | `lexchex.metalex.tech` | Prove accredited-investor status. |
| [**Your profile**](profile.md) | `profile.metalex.tech` | Your MetaLeX identity, accreditation status, and signing delegation. |

Two more surfaces are covered separately:

* [**MetaDAO**](metadao.md) — a one-step entity-formation page for tokens
  launched via MetaDAO.
* **cyberSign** — standalone agreement signing, on MetaLeX's main app at
  `app.metalex.tech`.

> **Which app do I need?**
> Setting up or running a company → the **cyberCORPs app**.
> Raising money, or investing in a raise → **cyberRAISE**.
> A token community converting to equity → **ACE**.
> Getting accredited → **LeXcheX**.
> Editing your identity → **your profile**.

## Before you start: what you need

1. **A web3 wallet** — a browser wallet such as MetaMask or Rabby. The apps
   connect to it to read your holdings and ask you to sign. A **Safe
   multisig** is supported and recommended for company treasuries.
2. **A little ETH for gas** — actions that change onchain state are
   transactions and cost a small network fee. cyberCORPs run on **Ethereum,
   Arbitrum, and Base**; you need gas on whichever network the entity uses.
3. **A desktop browser** for company setup — creating a cyberCORP and a
   round are desktop-only flows.
4. **Nothing else** — there is no separate account. Your wallet is your
   identity.

## Signing in

The apps connect to your wallet automatically. For actions that need a
verified session — managing a company, editing your profile, encrypting
data — you complete a one-time **Authenticate** step: you sign a short
Sign-In With Ethereum message. This signature is **free** — not a
transaction, no gas.

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
Every meaningful button is a call to a contract; nothing important happens
in a database that the chain doesn't already record.

* When you **deploy a cyberCORP**, the app calls the protocol's factory,
  which deploys your company's contracts. The chain becomes your company's
  *official register* — not a copy of one. This is the core idea of the
  protocol: see
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
