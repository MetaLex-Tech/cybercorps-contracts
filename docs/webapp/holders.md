---
description: My holdings, LET pages and PDFs, transfers, scripify, conversion back from scrip and private sale drafts, from the holder's side
---

# For holders: your securities

This page is for employees, advisors and investors who hold securities
issued through MetaLeX. Two surfaces serve them, each reading different
records:

* **My holdings** (`cybercorps.metalex.tech`) is the stakeholder portal.
  It shows the positions a company's cap table records for you, your
  Ledger Entry Tokens (LETs), documents the issuer shares with you, and
  your grants. You reach it by claiming a company's invitation link.
* **My Portfolio** (`cyberraise.metalex.tech`) is the investor view of
  what you invested through cyberRAISE: pending and closed EOIs and deals,
  your LETs and your scrip, with the actions on them (transfer, scripify,
  conversion back from scrip).

## Claim a stakeholder invitation

Companies onboard stakeholders with a private link, and the app never
emails it. The claim page shows who the link was issued for and when it
expires, then walks three steps: connect (or create) a wallet, prove you
control it with a free Sign-In With Ethereum signature, and open your
holdings. Claiming attaches that wallet to the company's existing record
of you. The link cannot sign documents or move assets, and MetaLeX never
asks for a seed phrase or private key.

Links expire after 14 days, and a company can revoke or regenerate one at
any time, so ask for a fresh link if yours has lapsed. Claim only an
invitation you expected.

## My holdings

After you **Authenticate**, **My holdings** lists the wallets it read
(**Switch wallet** changes them) and shows a card for each company that
has you on its cap table: how you are registered ("Registered as Alice
Founder · employee"), your **Cap table positions** (class, units,
status, vesting schedule and, if the issuer allows it, prices) and your
**Onchain certificates**.

Each LET row gives its registered units and your wallet's role, a **PDF**
download of the current certificate, and **View** for the LET's full
page. The role is **registered owner** when your wallet is the holder of
record, or **custody only** when your wallet holds the token while
someone else is the registered owner. In that case the page notes that
the quantities describe the registered position and are not assigned to
your wallet. A current untokenized position offers **Statement PDF**, a
position statement that says on its face it is neither a tokenized
certificate nor a stock certificate.

Above the cards, one line per chain gives the indexer block the LET rows
were read at and whether it is final, for example "Chain 8453:
certificates read from the indexer at block …, not yet final (finalized
through …); a reorg could still change what is shown." A LET minted
moments ago appears once the indexer reaches its block.

The issuer decides what you see beyond your own issued positions and
active LETs, which always show. Documents attached to your positions and
per-unit price terms appear only if the company turned on those
disclosures. Nothing here shows other stakeholders or company-wide
ownership.

The page is read-only apart from **My grants**, which embeds the
recipient view from
[Token grants and onchain vesting](grants.md#for-grant-recipients), where
you sign, claim and exercise.

## The public LET page

Every LET has a public detail page: the issuing company and its
jurisdiction details, the security type and series, the investment
amount, share terms and transfer restrictions for equity, the
restrictive legends, and the rendered certificate. A **Registration and
custody** block lists the **Registered owner** (the holder of record),
the **NFT custody** wallet that holds the token, and the **Registered
units**, with a note when part of the position is scripified. The two
wallets usually match. They differ when someone holds the token in
custody for its registered owner.

The rendered certificate follows the layout the contracts draw onchain:
token ID and units at the top, the company name, "Ledger Entry Token"
with an active or voided marker, the issuer and registered owner
addresses linked to a block explorer, class and series, tiles for units,
consideration and issue date, the authorizing officer, and the numbered
transfer restrictions. Share classes show the consideration per share,
and SAFEs, SAFTs and other convertibles show the whole amount. A voided
LET is stamped VOIDED across its face.

Signed in as the LET's current holder or as an owner of the issuing
company, you can **Download PDF**, a rendering of the current onchain
certificate. The PDF says it is a generated rendering and not the
onchain record itself, and gives the chain, contract and token ID to
verify against.

Anyone with the URL can open the page. Whether your name shows depends
on the choice made at issuance: encryption is optional, chosen in the
privacy settings when you invest or by the issuer when issuing by hand.
An encrypted name shows masked, with a prompt to sign in to decrypt, and
decrypts only for the parties to the deal and the issuer. Sign in with
the wallet that holds the LET to see your own. A name issued unencrypted
appears in plaintext on the certificate and in its public metadata, with
no sign-in gate. Signing officers' names are in the public metadata
regardless of that choice.

## Act on what you hold

**My Portfolio** lists your pending investments (EOIs awaiting a
decision), closed investments, your **Certificates** and your **Owned
Scrips**. Finding rounds, expressing interest and countersigning tickets
are covered in [cyberRAISE](cyberraise.md). The actions below work on
what you already hold.

### Transfer a LET

A LET you are the registered owner of shows **Transfer ownership**. A
transfer is a legal endorsement: you enter the recipient's address and
name, sign a free endorsement, and confirm the transaction that endorses
the LET to the recipient and moves registered ownership and custody
together. The endorsement joins the LET's chain of title. The dialog
checks whether the class and the LET allow transfers (issuer settings)
while preparing the transfer, and stops if they do not, for example with
"Registered-owner transfers are disabled for this lot."

If your wallet holds a LET in custody for someone else, the row offers
**Return custody** instead. It returns the token to the registered owner
without changing who is registered, and needs no endorsement.

Neither button appears on a voided LET, on one with units reserved
onchain (for example, committed to a sale offer), or when the LET's
registration, custody and terms do not read back completely.

### Scripify a LET

If the issuer has enabled scrip for the class, **Scripify** converts
whole units of a LET into scrip, the fungible ERC-20 form, at the class's
fixed ratio. Before you confirm the transaction, the dialog shows the
ratio, the units available to scripify after any reservations, and your
resulting scrip balance. Scrip can move in fractional amounts, subject
to the token's own transfer rules, and your LET keeps correspondingly
fewer units. Only the registered owner can scripify a LET.

A class can limit scripification to a whitelist of LETs, which the app
recommends for private shares so that unvested or restricted shares
cannot become transferable scrip. On such a class, scripifying a LET that
is not listed stops with "This certificate isn't on the class's scripify
whitelist. A company officer must add it on the Tokenization Hub before
it can be scripified."

### Convert scrip back into a LET

Converting scrip back into registered units carries legal weight,
because it makes you a registered holder again. There are two paths:

* If you still hold a LET of the same class, or the issuer has approved
  you, **De-scripify** opens **Convert scrip to a certificate**. Enter the
  **Scrip amount to convert** and choose **Review conversion**. The
  review shows where the units will land (your existing LET, which the
  protocol picks as the first non-void LET you hold of record, or a new
  LET under the issuer's approval), the units added, your total
  registered units afterwards and the scrip remaining. **Confirm conversion** sends
  the transaction. The amount must be at least the class's de-scrip
  minimum.
* Otherwise, **Request de-scripification** sends the issuer an offchain
  request through a free, SIWE-authenticated form. The company reviews it
  from the Tokenization Hub, and once it approves, your button becomes
  **De-scripify**.

What the review checks depends on the company's version:

* **On a v5 company**, the review checks the conversion against the
  class's activated legal terms (see
  [Legal classes, series and versioned terms](captable.md#legal-classes-series-and-versioned-terms)).
  If the company has not approved and activated those terms, the review
  stops with an explanation, and the company has to act first.
* **On a v4 company**, the LET contract has no protocol class, so there are
  no activated terms to check. The review shows the company's onchain terms
  for the destination instead: the terms on your LET, or the terms in the
  issuer's approval. The protocol also picks the LET differently. It takes
  the first non-void LET that is both in your wallet and registered to you.
  A LET registered to you that another address holds, such as an escrow,
  does not count. Conversion works on the current v4 release of the
  company's issuance manager. On an earlier v4 release, the review stops
  with an explanation, and the company can upgrade to v5.

The app refuses the conversion if the issuer has frozen your scrip. The
dialog notes that the conversion creates a tokenized cap table position,
and that the company's governing documents decide whether that position is
part of its securities ledger.

### Transfer scrip

Scrip rows offer **Transfer** when the token's compliance rules allow
it, a plain ERC-20 transfer to the recipient you name.

### Recall an expired EOI

If you bid into a founder-approval round and your offer expired
unanswered, the EOI row offers **Recall**, one transaction that returns
your escrowed funds.

> **Under the hood.** A LET transfer calls the LET contract's
> `endorseAndTransfer`, which records the endorsement and moves the
> token. Scripify and conversion back are
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md) calls
> that move units between the [LET](../reference/contracts/LedgerEntryToken.md)
> and [`CyberScrip`](../reference/contracts/CyberScrip.md), the class's
> scrip token. Why re-registration needs the issuer's approval is
> explained in [LETs and scrip](../explanation/lets-and-scrip.md).

## Prepare a private sale (v5 companies)

Below the certificate on a LET's page, **Private sales** opens a
workspace for selling some or all of the LET's units to one buyer you
name. The workspace prepares and reviews a sale. It cannot post the
onchain offer.

The registered owner (the holder of record, not a custody-only wallet)
chooses **Prepare sale draft** and enters the **Named buyer address**,
**Units to sell**, **Payment token address**, **Total consideration
(token units)**, and the **Seller party values** and **Buyer party
values** for the sale agreement, one value per line. Delivery goes
directly to the buyer's wallet. **Save private draft** stores the draft,
visible only to the two named parties when signed in. The app sends no
invitation, so tell the buyer yourself. Saving reserves no units. A
saved draft's terms cannot be edited, so a change means a new draft and
new reviews.

Each party reviews the draft card (exact units, consideration, delivery
and the original agreement), ticks the acknowledgement and clicks
**Record my review**. That records an app acknowledgement, which is
neither a signature nor a transaction authorization. The seller can **Cancel
draft**. If the LET changes after the draft was saved, the review is
refused and a fresh draft is needed.

When both parties have reviewed, the card reads "Both parties reviewed ·
submission unavailable" and its control reads **Post sale
unavailable**. Posting needs the company's deal manager to be a v5
contract set up for named-buyer sales: an enabled exemption pathway, a
buyer-approval condition among the conditions every sale must satisfy, a
designated approver, a separate closing condition at which a fill can be
held or released, and approval helpers whose code the app has reviewed
for that chain. Hovering over the control names the first missing piece.
On a v4 company it says the deal manager reports a different protocol
version. The app has no reviewed approval-helper deployment recorded for
any chain, so no company passes this check, and it has no buyer
acceptance or officer approval screen.

The workspace opens with the limit a seller should understand before any
sale is posted: "Approving a buyer does not approve their terms." The
company's approval names who may accept. It does not fix the units,
payment or party values the buyer accepts on. A fill that departs from what
you reviewed can be stopped only by the company's designated approver
withholding its release, or by the buyer agreeing to void it, never by
you alone.

**Check an existing sale or recover an interrupted operation** reads an
existing offer's status onchain from its deal manager address and offer
ID. Its action buttons are disabled.

## Good to know

* **Which signatures cost gas.** SIWE sign-ins, de-scrip requests,
  endorsement signatures and sale-draft reviews are free. Transfers,
  custody returns, scripify, conversion back from scrip, claims,
  exercises and recalls are transactions. PDF downloads are free and need
  only a sign-in.
* **Your wallet is the key to everything.** Holdings, grants and
  decryption follow the wallet the issuer has on file for you. If
  something you expect is missing, check that you are connected with the
  right wallet.
* **There is no order book.** MetaLeX has no built-in secondary market.
  Transfers and scrip are the rails on which privately negotiated trades
  settle, and each private sale draft names one buyer.
