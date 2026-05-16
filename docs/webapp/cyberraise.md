# cyberRAISE — raising and investing

**cyberRAISE** (`cyberraise.metalex.tech`) is the fundraising app. Companies
run fundraising rounds here, and investors invest here. It is a separate app
from the [cyberCORPs app](mainframe.md) — **rounds are created and configured
in cyberRAISE, not in the Mainframe.**

This page has two halves: one for issuers, one for investors.

---

## For issuers: running a raise

### Start a raise

From cyberRAISE you start a raise. You can:

* add a round to a company you already created in the
  [cyberCORPs app](mainframe.md), or
* **create the cyberCORP and the round together** — if you are setting up
  the company and its first raise at the same time.

### Choose the round type

cyberRAISE supports two styles of round:

* a **ticket round**, and
* a **structured round**.

You pick the one that fits your raise when you create it.

### Configure the round

When creating the round you set its terms — the security being offered (SAFE,
SAFT, SAFTE, token warrant, or a priced equity round), the payment token,
the raise cap, ticket sizes, the dates, who is eligible to invest, and the
legal agreement investors will sign.

### Manage the round

Once the round is open, the **Rounds** area lists your company's rounds and
lets you open a round to manage it. Investors submit **Expressions of
Interest (EOIs)**; depending on the round type you either accept them
automatically or review and allocate each one. Reviewing an EOI and an
investor's ticket is done from the round.

### The Marketplace

Public rounds appear in the **Marketplace** (the public-rounds view), where
any investor can discover them.

---

## For investors: investing in a round

### Find a round

Browse the **Marketplace** for public rounds, or open a round from a direct
link an issuer shared with you.

### Check eligibility

Some rounds are restricted — for example to accredited investors, or to
non-US persons for a Regulation S round. If a round requires accreditation,
get a [LeXcheX](lexchex.md) credential first. The round page tells you
what's required.

### Express interest

Submit an **Expression of Interest**: state how much you want to invest and
sign the EOI. **Signing the EOI is free** — a message signature, not a
transaction.

### Fund your ticket

Once your EOI is accepted, fund it — you send your payment (usually USDC)
into the round's onchain escrow. This is a transaction and costs gas.

> Your money sits in an escrow contract — not with the company, not with
> MetaLeX — until the round closes.

### Receive your security and track it

When the round closes you receive your security as a **cyberCERT**. Your
**Portfolio** in cyberRAISE tracks your tickets, EOIs, and the securities
you hold.

## Good to know

* **MetaLeX never holds your money.** Funds in flight are in an onchain
  escrow with no override.
* **An EOI signature is free; funding is a transaction.**
* **Your security is real and onchain** — a cyberCERT is the actual register
  entry for your stake.

> This guide describes what cyberRAISE does and the shape of each flow. It is
> not a click-by-click walkthrough.
