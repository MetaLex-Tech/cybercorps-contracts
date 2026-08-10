---
description: My holdings, certificates, transfers, scripify and de-scripify — the holder's side
---

# For holders: your securities

Most of this documentation is written for founders and officers. This
page is for everyone else: employees, advisors, and investors who
*hold* securities issued through MetaLeX.

Two surfaces matter, and they answer to different wallets and records:

* **My holdings** (`cybercorps.metalex.tech`) — the stakeholder portal.
  Shows the positions a company's ledger records for you, your onchain
  certificates, documents the issuer shares, and your grants. You get
  here by claiming a company's invitation link.
* **My Portfolio** (`cyberraise.metalex.tech`) — the investor view.
  Shows the investments you made through cyberRAISE: pending and closed
  EOIs and deals, your certificates, and your scrip, along with the
  actions on them (transfer, scripify, de-scripify).

## Claiming a stakeholder invitation

Companies onboard stakeholders with a private link, never by email from
the app. When one reaches you, the claim page shows who it was issued
for and when it expires, and walks three steps: connect (or create) a
wallet, prove control of it with a free Sign-In With Ethereum signature,
and open your holdings. Claiming attaches that wallet to the company's
existing record of you; the link itself cannot sign documents or move
assets, and MetaLeX will never ask for a seed phrase or private key.

Links expire after 14 days, and a company can revoke or regenerate one
at any time, so ask for a fresh link if yours has lapsed. Only claim an
invitation you expected.

## My holdings

After SIWE, **My holdings** shows one card per company that has you on
its books: how you're registered ("Registered as Alice Founder ·
employee"), your **ledger positions** (class, units, status, vesting
schedule and, if the issuer enabled it, prices), and your **onchain
certificates**, each with a View link to the full certificate page.

What you see beyond your own positions is the issuer's choice.
Documents attached to your positions and per-unit price terms appear
only if the company enabled those disclosures; your own issued
positions and active certificates always show. Nothing here reveals
other stakeholders or company-wide ownership.

The page is read-only, plus your grants: the **my grants** section
embeds the full recipient view described in
[Token grants and onchain vesting](grants.md#for-grant-recipients),
where signing, claiming, and exercising happen.

## The certificate page

Every cyberCERT has a public detail page: the issuing company and its
jurisdiction details, the security type and series, units represented
(with a note when part of the position is scripified), the investment
amount, share terms and transfer restrictions for equity certs, the
restrictive legends, and the rendered certificate itself, in the style
of an engraved stock certificate, signed by the company's officers. A
voided cert is stamped VOIDED across its face.

The page is public by URL, but holder names are not: an encrypted name
shows as a masked value with a "sign in to decrypt" affordance, and it
decrypts only for the parties to the deal (and the issuer). Sign in
with the wallet that holds the cert to see your own name.

## Your portfolio: the actions

**My Portfolio** lists your pending investments (EOIs awaiting a
decision), closed investments, owned securities, and owned scrips. The
investing journey itself — finding rounds, expressing interest,
countersigning tickets — is covered in
[cyberRAISE](cyberraise.md#for-investors-investing-in-a-round). What
follows are the things you can do with what you already hold.

### Transfer a certificate

If the security's class is transferable (an issuer setting), a
**Transfer** button appears on the certificate row. A transfer is a
legal endorsement, not a bare token send: you enter the recipient's
address and name, sign a free endorsement signature, and then confirm
the transaction that endorses and transfers the cert in one step. The
endorsement is recorded on the certificate's chain of title.

If there is no Transfer button, the class is currently non-transferable
or the cert is voided.

### Scripify: make units fungible

If the issuer has enabled scrip for the class, **Scripify** converts
whole certificated shares into cyberSCRIP, the fungible ERC-20 form, at
the class's fixed ratio. The dialog shows the ratio, your remaining
certificated shares, and your resulting scrip balance before you
confirm the transaction. Scrip can be transferred in fractional
amounts (subject to the token's own transfer rules); your certificate
stays on the register with correspondingly fewer direct units.

### De-scripify: back to the register

Converting scrip back into registered shares is the step with legal
weight, because it puts a holder on the issuer's official ledger. Two
paths:

* If you still hold a certificate from the same class (or the issuer
  has already approved you), **De-scripify** converts directly: pick an
  amount at or above the class's de-scrip threshold and confirm the
  transaction.
* Otherwise, **Request de-scripification** sends the issuer an offchain
  request (a free SIWE-authenticated form, no gas). The founder reviews
  it from the Mainframe; once approved, your button flips to
  De-scripify.

### Transfer scrip

Scrip rows offer **Transfer** when the token's compliance rules allow
it: a plain ERC-20 transfer to the recipient you name.

### Recall an expired EOI

If you bid into a founder-approval round and your offer expired
unanswered, the EOI row offers **Recall**: one transaction that returns
your escrowed funds.

> **Under the hood.** A certificate transfer calls the cert printer's
> endorse-and-transfer path, recording the endorsement in the
> endorsement registry; scripify and de-scripify are
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md) calls
> converting between the
> [cyberCERT](../reference/contracts/LedgerEntryToken.md) and
> [`CyberScrip`](../reference/contracts/CyberScrip.md) forms of the same
> security. The full mechanics, including why re-registration requires
> issuer approval, are in
> [Scripify and settle a secondary trade](../tutorials/scripify-and-settle.md)
> and [The dual-token model](../explanation/dual-token-model.md).

## Good to know

* **Which signatures cost gas.** SIWE sign-ins, de-scrip requests, and
  endorsement signatures are free. Transfers, scripify, de-scripify,
  claims, exercises, and recalls are transactions.
* **Your wallet is the key to everything.** Holdings, grants, and
  decryption all follow the wallet the issuer has on file for you. If
  something you expect is missing, first check you're connected with
  the right wallet.
* **There is no order book.** MetaLeX has no built-in secondary
  market; transfers and scrip are the rails on which privately
  negotiated trades settle.
