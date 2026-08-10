---
description: One cap table for tokenized and un-tokenized positions, with AI-assisted import
---

# The cap table

The **cap table** is the cyberCORPs app's unified register of who owns what
in your company. Its strapline says it plainly: *one table, onchain and
offchain*. Positions you have tokenized as cyberCERTs, positions that exist
only as ledger records, and beneficial holdings derived from cyberSCRIP
balances all appear in the same view, with the same math.

You reach it from the **capTable** item in the app sidebar, from the
"Manage your capTable" card on the company home, or from the Mainframe's
"Cap Table" button.

> **The cap table is in beta.** The feature is complete and validated
> end-to-end, but the app tells you the safe posture itself: export your
> cap table regularly and keep a local copy. Exports include every
> position, including cancelled, terminated, and tokenized history, so a
> saved `.xlsx` or `.csv` is a full backup.

## Who can open it

The full cap table is **founder-only, on reads as well as writes**. You
must be connected with a wallet that is an owner of the cyberCORP and
complete the free **Authenticate** signature. Holders don't see this
screen; they get their own scoped view, covered in
[For holders: your securities](holders.md).

Holder identities on certificates are encrypted when that choice was
made at issuance (it is optional; see
[the certificate page](holders.md#the-certificate-page)). For encrypted
names, the app decrypts server-side during assembly, and a name it
cannot decrypt renders as a scrambled placeholder rather than leaking
ciphertext. A name issued in plaintext, and signing-officer names in
general, live in the certificate's public metadata regardless.

## How to read the table

Every position carries a source badge, and the badge tells you which
record is definitive:

* **⛓ tokenized** — the position is an onchain cyberCERT. The chain is the
  system of record; the ledger row just mirrors it.
* **📄 offchain** — the position lives on the offchain stock ledger,
  which is the company's record of un-tokenized holdings, in the role a
  traditional stock ledger plays. Recording a row documents an issuance
  rather than effecting one: the corporate authorization behind it (a
  [board consent](boardroom.md#board-approvals), for instance) must
  still exist, and once the position is tokenized the chain takes over
  as the register. The badge links to the first attached document.
* **≈ tokenized (scrips)** — a *beneficial* claim derived from a
  cyberSCRIP balance. Scrips are fungible tokens, and holding them is an
  economic position without being registered stock.
* **⛓ escrowed onchain** — an equity award whose scrip sits in a MetaVesT
  vesting escrow; the chain enforces the schedule. See
  [Token grants and onchain vesting](grants.md).

Because scrip exists, the table supports two ownership lenses. The
**Registered** lens shows record owners (the view that matters for
stockholder lists and corporate law). The **Beneficial** lens follows the
economics: scripified shares move from the certificate owner to the scrip
holders. The toggle only appears once your company has issued scrip.

The ledger view itself shows summary cards (issued & outstanding,
semi-diluted, fully diluted, stakeholders, total raised, onchain
certificates, offchain entries, suspected duplicates), a capitalization
donut by class, and section tables for **Equity**, **Convertibles**,
**Token instruments**, and **History** (void, terminated, tokenized,
exercised, converted, kept for audit). You can group rows by stakeholder
or by class/series, pick the basis for the % column (issued &
outstanding, semi-diluted, or fully diluted), and search for a holder.

An **Integrity checks** panel at the bottom recomputes the table's
invariants live: fully-diluted shares accounted for, SAFE ownership under
100%, every position attached to a stakeholder, scrip pools conserving
units, plan reserves backed by their certificates, and more. A failing
check is a prompt to investigate before relying on the numbers.

## Stakeholders

A **stakeholder** is a person or entity on your register: a name, an
optional email and mailing address, a relationship (founder, investor,
employee, and so on), and any number of linked wallets.

Wallets are the merge key between the two halves of the table. When a
cyberCERT's holder wallet matches a stakeholder's linked wallet, the cert
appears under that stakeholder; when it matches nothing, the row shows an
**unmatched wallet** badge and a one-click path to save the holder as a
new stakeholder. The **Link Wallets** panel does this in bulk. A wallet
can belong to only one stakeholder.

### Inviting a stakeholder to the holder portal

The **Invitations** panel generates a private onboarding link per
stakeholder. The app never emails it; you copy the link and send it
through a channel you already trust. The invitee connects a wallet, signs
in with SIWE, and that wallet is attached to their stakeholder record,
opening their [My holdings](holders.md) portal. Links expire after 14
days, and regenerating one revokes the previous link.

The nested **Holder portal disclosures** setting controls what invited
holders see beyond their own positions and certificates: whether they can
open documents attached to their positions, and whether per-unit and
exercise prices are shown. Both are off until you enable them.

## Recording positions

**+ Add Position** records an un-tokenized position on the offchain
ledger. No transaction is involved; the ledger write is the record. The
form covers the full range of instruments:

* the **class** (with inline creation of new classes and series) and, for
  equity awards, an **award type** (stock option, RSU, or restricted
  stock) sitting on its *underlying* class — a Common option is Award
  type "Stock option" on class "Common Stock";
* a **plan pool** the award draws from, with inline creation of a new
  plan and its reserve;
* units, investment amount, price per unit, valuation, round label;
* **vesting** (start, end, cliff in months, termination date, vested
  override) and, for paid awards, the strike or repurchase price, the
  post-termination window, and the option's term expiration;
* SAFE-specific terms (post-money or pre-money cap basis, discount) and
  token-instrument terms (claim, amount, unlock schedule);
* a **federal exemption** tag (Rule 701 entries feed the disclosure
  monitor), transfer-restriction chips, a paper certificate reference,
  notes, and attached PDFs. Uploads are stored privately: corp owners
  can always open them, and the position's holder can too once you
  enable the position-documents disclosure in the
  [holder portal settings](#inviting-a-stakeholder-to-the-holder-portal).

**Save as draft** stages a position that counts toward nothing until you
issue it from the [Securities status](#securities-status) queues.

Getting rid of a position is deliberately three different verbs. **Void**
and **Terminate** record real corporate events and stay in History for
audit. **Delete** is only for erroneous entries that never reflected a
real holding; it removes the record entirely and can't be undone.

A **Review duplicates** dialog surfaces groups of offchain positions that
share a holder, class, and unit count — usually the residue of a re-import
— and lets you compare them field by field before deleting the accidental
copy or dismissing the group as distinct.

## Importing a cap table

The **Import** panel accepts `.csv` and `.xlsx` sheets (blank templates
are downloadable from the toolbar) and **OCF** — the Open Cap Table
Format, either a single `.json` bundle or the `.zip` a platform like
Carta or Pulley exports. Every row gets an explicit action before
anything is written: create a new offchain record, update an existing
position in place (rows exported from this app carry a `position_id`),
link to an existing onchain cert instead of duplicating it, or skip.
Blocking validation errors stop the import; the error worklist groups
them by issue so you fix the sheet rather than hunt row by row.

### AI-assisted import (GAIBE)

Below the file input sits **GAIBE**, the AI import. It takes whatever
form your cap table is currently in — any spreadsheet, a Carta or Pulley
export, a PDF, a screenshot, even pasted prose — and converts it into the
import format. Practical limits: uploads to about 3 MB, pasted text to
400k characters, legacy `.xls` not supported (re-save as `.xlsx`), and
25 documents per officer per day.

The conversion is conservative by design. GAIBE never invents data: a
field it isn't sure about is left blank and flagged, numbers are carried
digit-for-digit, and summary rows and ownership-percentage columns are
skipped (the app recomputes those). Every source column is listed in a
**column mapping report**, including the ones that mapped to nothing, and
every extracted field is printed under its preview row for you to check
against the source.

Nothing is imported until you review that preview and commit; converted
rows land in exactly the same validation and per-row action flow as a
hand-built sheet. The AI replaces the hand-transcription step, never the
review.

### Starting over

**Reset Ledger** clears all offchain positions, stakeholders, classes,
and plans so you can re-import from scratch. Tokenized positions, which
mirror onchain certs, are kept, and the audit journal is preserved so
dated stockholder lists still work. It requires typing `RESET` to
confirm, and it can't be undone, so export first.

## Tokenizing a position

**Tokenize →** on an offchain position mints an onchain certificate for
it and links the ledger entry to the cert, which becomes the system of
record from then on. The dialog pre-fills the certificate form from the
ledger (investor, units, amounts, terms), lets you pick the recipient
wallet if the holder has several, and warns you which ledger details do
*not* carry onchain (vesting schedule, exercise price, discount, notes,
and similar record-keeping fields).

Minting is one onchain transaction, preceded by a board-consent check
when the position is covered by one (see
[the boardRoom](boardroom.md#board-approvals)). If the transaction mines
but the link-back fails, the dialog offers a repair path — retry the
link, or enter the cert number by hand — so you never mint a duplicate.

Two kinds of position tokenize differently:

* **Equity awards** (options, RSUs, vesting restricted stock) don't
  become certs. **Escrow award (MetaVesT) →** routes them to the grants
  flow, where the scrip escrows onchain and the chain enforces the
  schedule. See [Token grants and onchain vesting](grants.md).
* **Stock plan reserves** appear as their own rows. **Tokenize plan**
  mints one jumbo certificate to the company itself for the plan's full
  reserve; you then **scripify** out of that cert to fund grants.

If no cert printer exists yet for the position's class, the action
becomes **Create cert printer →** and routes you through the standard
create-class flow first.

## Securities status

**Securities status** (linked from the cap-table header, with a live
draft count) is the officer's worklist over the issuance loop, four
queues derived live from the ledger and the chain:

1. **Drafts** — staged positions; issue (as active or as "promised"),
   edit, or delete them here.
2. **Awaiting signature** — proposed onchain, the recipient hasn't
   signed. Copy the cyberSign signing link and send it yourself; there is
   no email rail by design.
3. **Awaiting acceptance** — signed, escrow not yet finalized.
4. **Awaiting settlement** — escrowed with something left to settle:
   vested units to sweep or post-termination cleanup.

## Exports

The toolbar exports the full table as `.csv`, `.xlsx`, or an OCF
bundle, at any time, including history. Records-and-compliance tooling —
the DGCL §219 stockholder list, 409A/FMV records, Rule 701 and Form 3921
monitors, 83(b) tracking, and the round-modeling and exit-waterfall
calculators — is covered in
[Cap-table records, modeling and compliance](captable-tools.md).

> **Under the hood.** Tokenized rows are
> [cyberCERTs](../reference/contracts/LedgerEntryToken.md) minted through
> the [`IssuanceManager`](../reference/contracts/IssuanceManager.md);
> scrip-derived rows read
> [`CyberScrip`](../reference/contracts/CyberScrip.md) balances; award
> escrows are MetaVesT allocations. Quantities are exact decimal strings
> end to end (onchain values are 18-decimal fixed point), which is why
> forms reject a 19th decimal place: a silently rounded value would let
> the escrow and the ledger drift apart. Why one security has a
> registered and a fungible form is
> [The dual-token model](../explanation/dual-token-model.md).

## Good to know

* **Offchain writes are free; tokenizing costs gas.** Recording,
  editing, importing, and inviting involve no transaction. Minting certs
  and escrowing awards do.
* **Every offchain change is journaled.** An append-only audit trail
  backs as-of reconstruction, which is what makes dated stockholder
  lists possible.
* **Export regularly while the feature is in beta.** The app's own
  advice, and good practice regardless.
