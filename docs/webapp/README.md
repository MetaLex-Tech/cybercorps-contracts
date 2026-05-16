# Using the cyberCORPs apps

This part of the documentation is for the people who **use** the MetaLeX
apps — founders, officers, and investors. No code: just what each app is for
and how to use it.

## The apps, and where they live

The products run as **separate apps on their own subdomains**. A company and
the securities it issues are shared across them — set your company up once
and it shows up everywhere.

| App | Address | What you do there |
|---|---|---|
| [**cyberCORPs app**](mainframe.md) | `cybercorps.metalex.tech` | Create your company; manage its securities, register of holders, and scrip. Home of the **Mainframe**. |
| [**cyberRAISE**](cyberraise.md) | `cyberraise.metalex.tech` | Run fundraising rounds, and invest in them. **This is where rounds are created and configured.** |
| [**ACE**](ace.md) | `ace.metalex.tech` | Token-community-to-equity raises, and investing in them. |
| [**LeXcheX**](lexchex.md) | `lexchex.metalex.tech` | Prove accredited-investor status. |
| **Profiles** | `profile.metalex.tech` | Your founder / investor profile. |

[**MetaDAO**](metadao.md) is a specialised, futarchy-governed entity type —
covered in its own guide.

> **Which app do I need?**
> Setting up or managing a company → the **cyberCORPs app**.
> Raising money, or investing in a raise → **cyberRAISE**.
> Converting a token community to equity → **ACE**.
> Getting accredited → **LeXcheX**.

## Before you start: what you need

1. **A web3 wallet** — a browser wallet such as MetaMask or Rabby. The apps
   connect to it to read your holdings and ask you to sign.
2. **A little ETH for gas** — actions that change onchain state are
   transactions and cost a small network fee. The apps run on **Ethereum,
   Arbitrum, and Base**; you need gas on whichever network the entity uses.
3. **Nothing else** — there is no separate account. Your wallet is your
   identity.

## Signing in

The apps use **Sign-In With Ethereum**: you connect your wallet and sign a
short message to prove it is yours. This signature is **free** — not a
transaction, no gas. It just starts your session.

> MetaLeX never takes custody of your funds or your securities. Money in
> transit during a raise or deal sits in an onchain escrow that no one can
> override.

## Two kinds of "sign"

* **A message signature** — free, instant. Signing in, Expressions of
  Interest, countersigning agreements.
* **A transaction** — costs gas, confirms in seconds. Funding a round,
  issuing a security, closing a deal.

Your wallet always tells you which one it is.

## A note on terms

* A **cyberCORP** is your company, represented onchain.
* A **cyberCERT** is a certificate — one entry on the company's register of
  holders (a stake, a SAFE, an option, etc.).
* A **cyberSCRIP** is the tradable, fungible form of a security.

The full [Glossary](../reference/glossary.md) has the rest.
