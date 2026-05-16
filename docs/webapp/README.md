# Using the cyberCORPs apps

This part of the documentation is for the people who **use** the cyberCORPs
apps — not for developers. If you are a company raising capital, an investor
putting money into a round, or a token community converting into equity, you
are in the right place.

## The apps at a glance

| App | It lets you… | Who it's for |
|---|---|---|
| [**The Mainframe**](mainframe.md) | Set up and run your company onchain — cap table, fundraising, deals, agreements, roles. | Company founders and officers (issuers). |
| [**cyberRAISE**](cyberraise.md) | Run a fundraising round, or invest in one. | Issuers and investors. |
| [**ACE**](ace.md) | Convert a token community into equity holders of a company. | Token projects and their communities. |
| [**LeXcheX**](lexchex.md) | Prove you are an accredited investor, onchain. | Investors. |
| [**MetaDAO**](metadao.md) | Take part in a futarchy-governed entity. | Governance participants. |

All of them run on the same underlying protocol, so a security you receive in
one app (say, a SAFE from a cyberRAISE round) is visible and manageable in the
others.

## Before you start: what you need

1. **A web3 wallet.** A browser wallet such as MetaMask or Rabby. The apps
   connect to your wallet to read your holdings and to ask you to sign
   transactions and agreements.
2. **A little ETH for gas.** Actions that change onchain state (investing,
   issuing, signing) are blockchain transactions and cost a small network
   fee. The apps run on **Ethereum, Arbitrum, and Base** — you'll need gas on
   whichever network the entity you're dealing with uses. (Arbitrum and Base
   fees are typically very low.)
3. **Nothing else.** There is no separate account to create. Your wallet *is*
   your identity.

## Signing in

The apps use **Sign-In With Ethereum**: you connect your wallet and sign a
short message to prove the wallet is yours. This signature is free — it is not
a transaction and costs no gas. It simply starts your session.

> You stay in control of your assets at all times. MetaLeX never takes
> custody of your funds or your securities. Money in transit during a deal is
> held by an onchain escrow contract that no one can override.

## Two kinds of "sign"

You'll be asked to sign two different things; it's worth knowing the
difference:

* **A message signature** — free, instant, no gas. Used for signing in, for
  Expressions of Interest, and for countersigning legal agreements.
* **A transaction** — costs gas, takes a few seconds to confirm. Used when
  something actually changes onchain: funding a round, issuing a security,
  closing a deal.

Your wallet always tells you which one it is before you approve.

## Where to go next

* Running a company? Start with [The Mainframe](mainframe.md).
* Raising or investing? See [cyberRAISE](cyberraise.md).
* Coming from a token community? See [ACE](ace.md).
* Need to prove accreditation first? See [LeXcheX](lexchex.md).

## A note on terms

The apps use a few protocol words. The short version:

* A **cyberCORP** is your company, represented onchain.
* A **cyberCERT** is a certificate — one entry on the company's register of
  holders (a stake, a SAFE, an option, etc.).
* A **cyberSCRIP** is the tradable, fungible form of a security.

The full [Glossary](../reference/glossary.md) has the rest, and Part 1 of
this book explains the protocol in depth if you're curious.
