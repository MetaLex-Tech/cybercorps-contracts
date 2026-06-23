# cyberRAISE — raising and investing

**cyberRAISE** (`cyberraise.metalex.tech`) is the fundraising app. Companies
run rounds here; investors invest here. It is separate from the
[cyberCORPs app](mainframe.md) — **rounds are created and configured in
cyberRAISE.**

This page has two halves: issuers first, then investors.

---

## For issuers: running a raise

Starting a raise (desktop-only) begins with one choice: **how do you want to
raise?**

### Ticket-by-Ticket vs. Structured Round

* **Ticket by Ticket** — you sell securities to investors **one at a time**,
  each on its own terms. There is no shared target or min/max; each “ticket”
  is an individually configured deal. Suited to privately advertised raises
  or geographically restricted (Regulation S) raises.
* **Structured Round** — an automated round with **standardized terms for
  all investors**: a target raise, min/max ticket sizes, and escrowed
  investor bids. Can be public or private.

If you don't have a cyberCORP yet, the raise flow creates one first — you
can **create the company and the round together**.

### Configuring a structured round

The round form collects, in order:

* **Round stage** — the security series (e.g. Pre-Seed), auto-incrementing
  from your last round.
* **Round type** — **Privately Advertised** (invite-only) or **Publicly
  Advertised** (listed on the Marketplace). Public rounds require investors
  to be accredited via [LeXcheX](lexchex.md).
* **Admission mode** — **First-Come, First-Served** (offers are accepted
  automatically in order, funds escrowed immediately, until the round
  fills) or **Investors Bid / Founders Approve** (you review each bidder —
  their profile, socials, reputation — and choose who gets in and for how
  much).
* **Ticket size** — the minimum and maximum any one investor can invest.
* **Funding target** — a hard cap; the round ends automatically when hit.
* **Start and end dates.**
* **Exploding offers** (founder-approval rounds only) — optionally let
  investors send time-limited offers outside the min/max.
* **Pitch deck** — an optional description and up to three uploaded files.

Filling the form is free; the round is deployed onchain at the final step,
where you also configure the standard agreement investors will sign.

> **Under the hood.** A round is created on your cyberCORP's
> [`RoundManager`](../reference/contracts/RoundManager.md). The contract-
> level walkthrough — building the round, taking EOIs, allocating, and
> closing — is the tutorial
> [Run a cyberRAISE round](../tutorials/run-a-cyberraise-round.md).

### Managing your rounds

The **rounds list** for your company shows active and closed rounds, each
with its series, public/private label, structure, raised-vs-target progress,
and a flag when EOIs are waiting for you.

Opening a round shows the **management view** — three summary cards (Round,
Offer, Raised) and, for founder-approval rounds, tables of:

* **Open Interests** — EOIs awaiting your decision,
* **Exploding Offers** — time-limited offers,
* **Closed Interests** — EOIs you've allocated, and
* the round's issued cyberCERTs.

(First-come rounds need no review, so they only show closed interests and
certs.)

From here you can switch to the **Investor view**, **Edit Pitch deck**
(requires Authenticating), and **Close Round**.

### Reviewing an EOI

Opening an EOI shows the investor's profile, bio, the offer (min–max amount,
their message, any expiry), the agreement details, their trading activity,
and their LeXcheX accreditation status. You then either:

* **Allocate** — enter an amount within the offer's min–max and confirm the
  onchain transaction that accepts them, or
* **Reject** — confirm the onchain transaction that declines the offer.

> **Under the hood.** Allocating an EOI releases the investor's escrowed
> funds to the company and mints their security as a cyberCERT through the
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md). The legal
> agreement each party signs is anchored in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md).

### Closing a round

**Close Round** is a single transaction. It stops new EOIs immediately; you
can still review and allocate any EOIs already submitted. When a round hits
its cap, the app prompts you to open the next round.

---

## For investors: investing in a round

### Find a round

Browse the **Marketplace** (the public-rounds list) — searchable, split into
open and past rounds. Only publicly advertised rounds appear here. Private
rounds are reached through a link the issuer shares with you.

If you don't hold a valid [LeXcheX](lexchex.md) accreditation, the
Marketplace shows a **“Get accredited”** card explaining the paths to
accreditation — you'll need it for public rounds.

### Express interest

The *Express Interest* screen has the form on one side and the legal
agreement on the other. You provide:

* **Your investor details** — name, contact, investor type, and (if not an
  individual) jurisdiction of formation. These pre-fill from your
  [profile](profile.md) and can be encrypted.
* **Investment amount** — a fixed amount, or a min/max range, within the
  round's ticket limits and your wallet balance.
* an optional **message** to the founder.

If the round requires accreditation, you either confirm an existing LeXcheX
credential or mint one here.

Then:

1. **Sign the agreement** — a free signature.
2. **Approve the payment token** if needed — an onchain transaction.
3. **Submit** — the onchain transaction that places your EOI.

In a founder-approval round your maximum amount is held in escrow until the
founder accepts your offer or the round closes — any unused remainder is
returned. In a first-come round, accepted investments mint the certificate
without delay.

> **Under the hood.** Your EOI is an EIP-712-signed offer recorded on the
> [`RoundManager`](../reference/contracts/RoundManager.md); your funds sit
> in an onchain escrow until the round resolves. The security you receive is
> a **cyberCERT** — a real entry on the company's register, not a receipt.
> See [The dual-token model](../explanation/dual-token-model.md).

### Track it in your Portfolio

Your **Portfolio** shows your pending investments (EOIs awaiting a decision,
with their expiry), your closed investments, the certificates you hold, and
any scrip. You can also withdraw an EOI that hasn't been allocated yet.

## Good to know

* **MetaLeX never holds your money.** Funds in flight are in an onchain
  escrow with no override — see
  [The role of MetaLeX](../explanation/role-of-metalex.md).
* **Signing the agreement is free; approving the token and submitting are
  transactions.**
* **Your security is real and onchain** — a cyberCERT is the actual register
  entry for your stake.
