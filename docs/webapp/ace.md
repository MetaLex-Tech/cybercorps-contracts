---
description: Token-community equity conversion rounds inside cyberRAISE
---

# ACE — token-community raises

**ACE** is MetaLeX's fundraising product for token communities. An ACE raise
is a **tokenized SAFE** denominated in a project's community token — it lets
a token community become equity holders of the company behind the project.

> **ACE lives inside cyberRAISE.** What used to be a separate app at
> `ace.metalex.tech` has been folded into
> [cyberRAISE](cyberraise.md) (`cyberraise.metalex.tech`); old ACE links
> redirect there. ACE rounds run on **Base**.

## How ACE differs from cyberRAISE

* ACE raises are **token-denominated** — priced and funded in a community
  token, not USDC. The token can be a Base **ERC-20** (the default) or a
  **Solana token**, in which case funding involves bridging it between
  Solana and Base.
* The deal paper is an **ACE SAFE** (in Reg D and Reg S variants).
* Everything else — round types, admission modes, escrow — works like any
  other cyberRAISE round.

## For founders: setting up an ACE raise

An ACE raise is created through the normal cyberRAISE flow — create your
cyberCORP if you don't have one, initialize the round (dates, ticket size,
funding cap, round type, admission mode), and pick **ACE SAFE (Reg D)** or
**ACE SAFE (Reg S)** as the ticket type. What's specific to ACE is the
final **SAFE Setup** step:

1. **Identify your token.** Choose the **token type** — ERC-20 or Solana
   token (Solana bridging is only supported on Base) — and paste the token
   address or Solana mint address. The token name, ticker, and image load
   automatically.
2. **Set the terms.** Enter the **entity valuation** (as a token amount)
   and the **current token percentage**, choose a dispute-resolution
   method, and add any optional **custom provisions**. The raise cap,
   min/max investment, company identity, and payable address carry over
   read-only from the earlier steps.
3. **Sign.** Sign the agreement preview — a free signature. (A Solana-token
   raise that also creates the company asks for a second free signature for
   token metadata.)
4. **Review the summary** — the *New ACE Round Summary* shows the network,
   round type, admission mode, ticket size, funding cap, valuation, dates,
   and dispute resolution — then **Confirm & Submit** deploys the round
   onchain.

Drafts save automatically as you fill the form, and the header icons let
you save to the cloud and share a resumable draft link. A **support chat
link** (“Need help?”) sits on the form throughout.

Once the round is live, the round header offers the usual management
actions plus ACE extras: **Bridge your token to Solana**, **Manage
zkPassport Overrides** (on non-U.S.-gated rounds), and **Set up a Ticket**
for individually negotiated tickets (Reg D or Reg S).

### zkPassport overrides

If a round restricts investment to non-U.S. persons, founders can
manually approve a verified investor as an exception.

Where to find it: open your round from the rounds list so you are on
its **management view** — the founder console with the Round / Offer /
Raised summary cards, not the public investor page — with your owner
wallet connected. On an ACE round carrying the non-U.S. condition, the
action bar at the top (the same row as **Investor view** and **Edit
Pitchdeck**) shows a **Manage zkPassport Overrides** button, sitting
between **Bridge \<token\> to Solana** and **Set up a Ticket**. On a
non-ACE Regulation S round the button doesn't appear yet; reach the
same page by adding `/zkpassport-overrides` to the end of the
management view's address.

On the overrides page, enter the **investor wallet** and **Add
override** (an onchain transaction; removing one is too). The page
lists active overrides with when and by whom they were added.

One caution: an override is granted against your company's round
manager, not against the single round you opened it from. It satisfies
the non-U.S. check on **every** round of yours that shares the
condition, so grant one only to an investor you would except from all
of them.

## For investors: taking part

1. **Open the round.** The round detail page shows the company, the
   security, the status (open / funded / closed), an elevator pitch, the
   founder's profile, and any resource documents. A “Help with sharing
   your signal?” prompt lets you choose **Stay Anon** or **Amplify** —
   opting in lists you among the round's key investors.
2. **Verify eligibility.** If the round is restricted to non-U.S. persons,
   you complete a **zkPassport** verification — a privacy-preserving
   passport check in the zkPassport mobile app that proves you are not a
   U.S. national and not from a sanctioned country, without revealing your
   identity. Submitting the proof is an onchain transaction — you'll need
   a small amount of ETH on the round's network (typically under \$1).
3. **Invest.** The invest flow opens with a notice that this is a legally
   binding investment issued as a tokenized SAFE. You provide your name,
   contact, investor type (plus jurisdiction of formation for entities),
   and investment amount. In a first-come round your investment is
   accepted instantly and the certificate mints without delay; in a
   founder-approval round your funds sit in escrow until the founder
   decides.
4. **Bridge if needed.** Solana-token ACE rounds are funded in a
   Base-wrapped version of the token. If your Base balance is short, an
   in-page bridge card walks you through connecting a **Solana wallet**
   and bridging. See [the Solana bridge](#the-solana-bridge) below.
5. **Track your holdings.** Your ACE SAFEs appear in the cyberRAISE
   **Portfolio** alongside any other investments.

## The Solana bridge

A Solana-token ACE raise runs on Base, so the community token moves
between the two chains over the **Base ↔ Solana native bridge**.
Standalone *Bridge to Solana* and *Bridge from Solana* pages handle each
direction (a header toggle switches between them), and the same
Solana-to-Base flow is embedded in the invest form for investors whose
Base balance is short.

You'll need both wallets connected — your Solana wallet and your EVM
wallet — and a little SOL (about 0.01) for account rent and relay fees,
separate from the token you're bridging. Each bridge action asks you to
accept the Terms of Service before signing.

**Solana → Base** is one signature: a single Solana transaction sends the
token into the bridge and pays for relay, then the page watches Base
until the wrapped token arrives in your wallet (it allows up to ten
minutes, though it's usually much faster).

**Base → Solana** takes three actions, spread over the bridge's
validation cycle:

1. **Bridge** — a Base transaction locks the wrapped token for your
   Solana address. The transaction hash is written into the page URL, so
   you can close the tab and resume later; a "past transfers" list
   re-enters any transfer mid-flight.
2. **Prove** — after validators post the checkpoint to Solana (about 20
   minutes), a Solana transaction proves your message.
3. **Claim** — a final Solana transaction releases the token, creating
   your token account if needed.

Neither page charges a protocol fee; the costs are Base gas, Solana
fees, and rent.

## Under the hood

ACE is the cyberCORPs protocol's **ACE / PumpCorp** path. An ACE raise
deploys a cyberCORP configured for a token-to-equity offering and issues
**ACE SAFE** cyberCERTs — a SAFE variant whose security series is `ACE`.
The non-U.S. eligibility check is an onchain **condition** (a
zkPassport-backed `NonUSNationalityCondition`); a founder override writes
to that condition contract.

* Protocol view of the offering type:
  [Deploy a PumpCorp for ACE](../how-to/deploy-pumpcorp-ace.md) and
  [Factories](../reference/factories.md).
* How eligibility gating works:
  [Conditions](../reference/conditions.md) and
  [Compliance architecture](../explanation/compliance-architecture.md).
* What an ACE SAFE is as a security:
  [Security types](../reference/security-types.md).

## Good to know

* **Eligibility is privacy-preserving** — the non-U.S. check proves your
  status without revealing who you are (though recording the proof onchain
  costs a little gas).
* **You're getting a real security** — an ACE SAFE is an actual claim on the
  company, not a points balance or an airdrop.
* **MetaLeX never holds your funds** — the same onchain escrow model as the
  other apps.
