---
description: My holdings, certificates and PDFs, transfers, scripify, de-scripify and private sale drafts, from the holder's side
---

# For holders: your securities

Most of this documentation is written for founders and officers. This
page is for everyone else: employees, advisors, and investors who
*hold* securities issued through MetaLeX.

Two surfaces matter, and they answer to different wallets and records:

* **My holdings** (`cybercorps.metalex.tech`) — the stakeholder portal.
  Shows the positions a company's cap table records for you, your
  onchain certificates, documents the issuer shares, and your grants.
  You get here by claiming a company's invitation link.
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

After you **Authenticate**, **My holdings** lists the wallets it read
for (with **Switch wallet** to change) and shows one card per company
that has you on its books: how you're registered ("Registered as Alice
Founder · employee"), your **Cap table positions** (class, units,
status, vesting schedule and, if the issuer enabled it, prices), and
your **Onchain certificates**.

Each certificate row gives its registered units and your wallet's role
in it, a **PDF** download of the current certificate, and **View** for
the full certificate page. The role is **registered owner** when your
wallet is the holder of record, or **custody only** when your wallet
holds the certificate token while someone else is the registered owner;
in that case the page notes that the quantities describe the registered
position and are not assigned to your wallet. A current untokenized
position offers **Statement PDF**, a position statement that says on
its face it is not a cyberCERT or a stock certificate.

Above the cards, one line per chain says which indexer block the
certificate rows were read at and whether that block is final, for
example "Chain 8453: certificates read from the indexer at block …,
not yet final (finalized through …); a reorg could still change what
is shown." A certificate minted moments ago may not appear until the
indexer reaches its block.

What you see beyond your own positions is the issuer's choice.
Documents attached to your positions and per-unit price terms appear
only if the company enabled those disclosures; your own issued
positions and active certificates always show. Nothing here reveals
other stakeholders or company-wide ownership.

The page is read-only, plus your grants: the **My grants** section
embeds the full recipient view described in
[Token grants and onchain vesting](grants.md#for-grant-recipients),
where signing, claiming, and exercising happen.

## The certificate page

Every cyberCERT has a public detail page: the issuing company and its
jurisdiction details, the security type and series, the investment
amount, share terms and transfer restrictions for equity certs, the
restrictive legends, and the rendered certificate itself. A
**Registration and custody** block lists the **Registered owner** (the
holder of record), the **NFT custody** wallet that holds the token, and
the **Registered units** (with a note when part of the position is
scripified). The two wallets are usually the same; they can differ when
a certificate is held in custody for its registered owner.

The rendered certificate follows the Ledger Entry Token layout the
contracts draw onchain: token ID and units at the top, the company
name, "Ledger Entry Token" with an active or voided marker, the issuer
and registered owner addresses linked to a block explorer, class and
series, tiles for units, consideration and issue date, the authorizing
officer, and the numbered transfer restrictions. Share classes show the
consideration per share; SAFEs, SAFTs and other convertibles show the
whole amount. A voided cert is stamped VOIDED across its face.

If you are signed in as the certificate's current holder, or as an
owner of the issuing company, **Download PDF** saves a rendering of the
current onchain certificate. The PDF says it is a generated rendering,
not the onchain record itself, and gives the chain, contract and token
ID to verify against.

The page is public by URL. Whether your name is too depends on the
choice made at issuance: encryption is optional, chosen in the privacy
settings when you invest or by the issuer when issuing by hand. An
encrypted name shows as a masked value with a "sign in to decrypt"
affordance and decrypts only for the parties to the deal and the
issuer (sign in with the wallet that holds the cert to see your own).
A name issued unencrypted appears in plaintext on the certificate and
in its public metadata, and no sign-in gate protects it.

## Your portfolio: the actions

**My Portfolio** lists your pending investments (EOIs awaiting a
decision), closed investments, your **Certificates**, and your **Owned
Scrips**. The
investing journey itself — finding rounds, expressing interest,
countersigning tickets — is covered in
[cyberRAISE](cyberraise.md#for-investors-investing-in-a-round). What
follows are the things you can do with what you already hold.

### Transfer a certificate

A certificate you are the registered owner of shows **Transfer
ownership**. A transfer is a legal endorsement, not a bare token send:
you enter the recipient's address and name, sign a free endorsement
signature, and then confirm the transaction that endorses the cert to
the recipient and moves both registered ownership and custody in one
step. The endorsement is recorded on the certificate's chain of title.
Whether the class and the certificate allow transfers (issuer settings)
is checked when the dialog prepares the transfer; if they don't, it
stops and says so, for example "Registered-owner transfers are disabled
for this lot."

If your wallet holds a certificate in custody for someone else, the
row offers **Return custody** instead. It returns the token to the
registered owner and changes nothing about who is registered; no
endorsement signature is needed.

There is no button on a voided cert, on one with units reserved onchain
(for example, committed to a sale offer), or when the certificate's
registration, custody and terms don't read back completely.

### Scripify: make units fungible

If the issuer has enabled scrip for the class, **Scripify** converts
whole certificated shares into cyberSCRIP, the fungible ERC-20 form, at
the class's fixed ratio. The dialog shows the ratio, the shares
available to scripify after any reservations, and your resulting scrip
balance before you confirm the transaction. Scrip can be transferred in
fractional amounts (subject to the token's own transfer rules); your
certificate stays on the register with correspondingly fewer direct
units. Only the registered owner can scripify a certificate.

A class can limit scripification to a whitelist of certificates, which
the app recommends to issuers of private shares so that unvested or
restricted shares can't become transferable scrip. On such a class, scripifying a
certificate that isn't listed stops with "This certificate isn't on the
class's scripify whitelist. A company officer must add it on the
Tokenization Hub before it can be scripified."

### De-scripify: back to the register

Converting scrip back into registered shares is the step with legal
weight, because it puts a holder back on the company's register of
holders. Two paths:

* If you still hold a certificate from the same class (or the issuer
  has already approved you), **De-scripify** opens **Convert scrip to a
  certificate**. Enter the **Scrip amount to convert** and choose
  **Review conversion**: the app shows where the units will land (your
  existing certificate, chosen by the protocol as the first non-void
  certificate you hold of record, or a new certificate under the
  issuer's approval), the units added, your total registered units
  afterwards and the scrip remaining. **Confirm conversion** sends the
  transaction. The amount must be at least the class's de-scrip
  minimum.
* Otherwise, **Request de-scripification** sends the issuer an offchain
  request (a free SIWE-authenticated form, no gas). The founder reviews
  it from the Tokenization Hub; once approved, your button flips to
  De-scripify.

The review checks the conversion against the class's activated legal
terms (see
[Legal classes, series and versioned terms](captable.md#legal-classes-series-and-versioned-terms)),
so in the app it works for classes on v5 contracts whose company has
approved and activated those terms. Otherwise the review stops with an
explanation, such as that the class's legal terms are not activated,
and the company has to act first. The dialog notes that the conversion
creates a tokenized cap table position, and that whether it is part of
the company's securities ledger depends on the company's governing
documents.

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

## Prepare a private sale (v5 companies)

Below the certificate on its detail page, **Private sales** opens a
workspace for selling some or all of a certificate's units to one buyer
you name. In production it covers preparing and reviewing a sale; it
does not yet post an onchain offer.

The registered owner (the holder of record, not a custody-only wallet)
chooses **Prepare sale draft** and enters the **Named buyer address**,
**Units to sell**, **Payment token address**, **Total consideration
(token units)**, and the **Seller party values** and **Buyer party
values** for the sale agreement, one value per line. Delivery is
directly to the buyer's wallet. **Save private draft** stores it. Saved
drafts are visible only to the two named parties when signed in, and
the app sends no invitation, so tell the buyer yourself. Saving doesn't
reserve any units, and a saved draft's terms can't be edited; a change
means a new draft and new reviews.

Each party then reviews the draft card (exact units, consideration,
delivery and the original agreement), ticks the acknowledgement and
clicks **Record my review**. That records an app acknowledgement, not a
signature or a transaction authorization. The seller can **Cancel
draft**. If the certificate changes after the draft was saved, the
review is refused and a fresh draft is needed.

When both parties have reviewed, the card reads "Both parties reviewed ·
submission unavailable" and its control reads **Post sale
unavailable**. Posting needs the company's deal manager to be a v5
contract set up for named-buyer sales: an enabled exemption pathway, a
buyer-approval condition among the conditions every sale must satisfy,
a designated approver, a separate closing condition at which a fill can
be held or released, and approval helpers whose code the app has
reviewed for that chain. Hovering the control shows the first missing
piece as a sentence; on a v4 company it says the deal manager reports a
different protocol version. As of October 2, 2026 the app has not
recorded a reviewed approval-helper deployment on any chain, so no
company passes this check yet, and the app has no buyer acceptance or
officer approval screen.

The workspace opens with the limit a seller should understand before
any sale is posted: "Approving a buyer does not approve their terms."
The company's approval names who may accept; it doesn't fix the units,
payment or party values a buyer accepts on. A fill that departs from
what you reviewed can be stopped only by the company's designated
approver withholding its release, or by the buyer agreeing to void it,
never by you alone.

**Check an existing sale or recover an interrupted operation** reads an
existing offer's status onchain from its deal manager address and offer
ID. Its action buttons are disabled.

## Good to know

* **Which signatures cost gas.** SIWE sign-ins, de-scrip requests,
  endorsement signatures, and sale-draft reviews are free. Transfers,
  custody returns, scripify, de-scripify, claims, exercises, and recalls
  are transactions. PDF downloads are free and need no signature beyond
  being signed in.
* **Your wallet is the key to everything.** Holdings, grants, and
  decryption all follow the wallet the issuer has on file for you. If
  something you expect is missing, first check you're connected with
  the right wallet.
* **There is no order book.** MetaLeX has no built-in secondary
  market. Transfers and scrip are the rails on which privately
  negotiated trades settle, and private sale drafts name one buyer
  each.
