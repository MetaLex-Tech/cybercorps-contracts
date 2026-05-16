# cyberRAISE — raising and investing

**cyberRAISE** is how companies raise capital onchain and how investors put
money into those rounds. This page has two halves: one for issuers running a
round, one for investors joining one.

---

## For issuers: running a round

### 1. Set up the round

From the [Mainframe](mainframe.md), create a new round and choose:

* **What you're selling** — a SAFE, a SAFT, a SAFTE, a token warrant, or a
  priced equity round.
* **The payment token** — usually USDC.
* **The raise cap** — the most you want to raise.
* **Ticket sizes** — the minimum and maximum a single investor can put in.
* **Open and close dates.**
* **Who can invest** — you can require investors to be verified (for example,
  to hold a valid [LeXcheX](lexchex.md) accreditation credential, or to pass
  a non-US check for a Regulation S round).
* **The agreement** — the standard legal document investors will sign.

### 2. Share it with investors

Once open, the round has a page investors can visit to review the terms and
express interest.

### 3. Review interest

Investors submit **Expressions of Interest (EOIs)** — a signed statement of
how much they want to invest. Depending on how you configured the round, EOIs
are either accepted automatically (first come, first served) or reviewed and
admitted by you one by one.

### 4. Close

When the round hits its cap or its closing date, it closes. Investor funds
— which were held in an onchain escrow, never by you or by MetaLeX — are
released to the company, and each investor receives their security as a
cyberCERT on your register.

---

## For investors: joining a round

### 1. Open the round page

Review the terms: the instrument (SAFE, etc.), the valuation cap or price,
the minimum and maximum ticket, and the legal agreement.

### 2. Check whether you need to be verified

Some rounds are restricted. If a round requires accredited-investor status,
you'll need a [LeXcheX](lexchex.md) credential first. If it's a Regulation S
round, you may need to complete a non-US verification. The round page tells
you what's required.

### 3. Submit an Expression of Interest

State how much you want to invest and sign the EOI. **Signing the EOI is
free** — it's a message signature, not a transaction. It signals your intent
and your agreement to the round's standard terms.

### 4. Fund your investment

Once your EOI is accepted, you fund it: you approve and send your payment
(usually USDC) into the round's onchain escrow. This is a transaction and
costs gas.

> Your money sits in an escrow contract — not with the company and not with
> MetaLeX — until the round closes. If the round's conditions aren't met, the
> escrow is where your refund comes from.

### 5. Receive your security

When the round closes, the escrow releases your funds to the company and you
receive your **cyberCERT** — your SAFE (or other security) as an entry on the
company's official register. You can view it any time from your wallet or
your profile.

## What happens to your SAFE later

When the company later does a priced round, SAFEs convert into shares. That
conversion happens through the protocol and the resulting shares appear as a
new cyberCERT on the register. You don't need to do anything to trigger it;
the company runs the conversion.

## Good to know

* **MetaLeX never holds your money.** Funds in flight are in an onchain
  escrow with no override.
* **An EOI signature is free; funding is a transaction.** Your wallet tells
  you which is which.
* **Your security is real and onchain.** A cyberCERT is the actual register
  entry for your stake — not a receipt or a placeholder.
