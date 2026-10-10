---
description: One cap table for tokenized and untokenized positions, with AI-assisted import, versioned legal terms, partial tokenization and LLC records
---

# The cap table

The **capTable** item in the sidebar, or the **Cap Table** button in the
[Tokenization Hub](tokenization-hub.md), opens the company's cap table.
Positions tokenized as Ledger Entry Tokens (LETs), positions recorded only
in the app, and beneficial holdings derived from scrip balances appear in
one view and go through the same math.

> **The cap table is in beta.** The app asks you to export it regularly
> and keep a local copy. Exports include every position, with cancelled,
> terminated and tokenized history, so a saved `.xlsx` or `.csv` is a
> full backup.

## Who can open it

Only the company's owners can open the full cap table, for reading as
well as writing: connect an owner wallet of the cyberCORP and complete
the free **Authenticate** signature. Holders get their own scoped view,
described in [For holders: your securities](holders.md).

A corporation gets the stock cap table this page describes, and an LLC
gets a unit-based one (see [LLC cap tables](#llc-cap-tables)), following
the legal type recorded on the cyberCORP. Any other type is refused with
"Cap table workflows require an explicitly identified corporation or
LLC. Review the company's legal type in its profile."

Holder names that were encrypted at issuance (see
[The public LET page](holders.md#the-public-let-page)) are decrypted on
the server while the table is assembled. A name the app cannot decrypt
shows as a scrambled placeholder instead of ciphertext.

## How to read the table

Each row's source badge records where the record lives and whether the
units are tokenized:

* **⛓ tokenized**: the units exist as a LET onchain, and the row mirrors
  it.
* **offchain**: the position is recorded and edited in the app, for
  untokenized units. Recording a row documents an issuance without
  effecting one, so the corporate authorization behind it (a board
  consent in [boardRoom](boardroom.md), for instance) must still exist.
* **≈ tokenized (scrips)**: a beneficial claim derived from a scrip
  balance. Holding scrip is an economic position, and the holder is not
  a registered stockholder for those units.
* **⛓ escrowed onchain**: an equity award whose scrip sits in a MetaVesT
  vesting escrow (see [Token grants and onchain vesting](grants.md)).

The company's governing documents, such as its bylaws, decide which
record is its legally definitive securities ledger, whatever a row's
badge says. Where they designate the onchain system (see
[Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md)),
the LETs are that record because of the designation. The app never
infers it from token status or storage location.

Once the company has issued scrip, a lens toggle appears. **Registered**
shows record owners, the view stockholder lists and corporate law use.
**Beneficial** follows the economics and moves scripified shares from
the LET's owner to the scrip holders.

The **Securities cap table** tab has summary cards (issued and
outstanding, semi-diluted and fully diluted shares, stakeholders, total
raised, onchain certificates, offchain entries, duplicates), a donut by
class, and sections for **Equity**, **Convertibles**, **Token
instruments** and **History** (void, terminated, tokenized, exercised
and converted rows, kept for audit). You can group by stakeholder or by
class/series, base the % column on issued and outstanding, semi-diluted
or fully diluted shares, and search for a holder. Per-class subtotals
and each section's **Total** row follow the active lens, basis and
filter. In the stakeholder grouping, a **Class/series** filter narrows
the view to the classes you pick. A class line and its linked LET
contract count as one class there, and row percentages keep the
company-wide denominator.

The **Integrity checks** panel recomputes the table's invariants live,
such as fully diluted shares accounted for, SAFE ownership under 100%,
every position attached to a stakeholder, scrip pools conserving units
and plan reserves backed by their LETs. Investigate a failing check
before relying on the numbers.

### When the onchain source is incomplete

The app reads the onchain half from an indexer. If the read is
incomplete or has not reached the block it needs, a tokenization
allocation is unreconciled, or a class line carries conflicting legal
identities, the app stops presenting totals. A caution banner reads
"Some certificate records are incomplete. Registered exports are
unavailable." and lists the gaps, the summary cards switch to **Known
issued subtotal** and **Known amount raised**, the donut is hidden, and
**Model a round** and **Exit waterfall** show "Analysis requires complete
source quantities and terms." until the source is complete.

## Review banners

Up to four banners above the table flag records that need a decision,
each with its own review dialog.

* **Review duplicates**: offchain positions that share a holder, class
  and unit count, usually left by a re-import. Compare them field by
  field, then delete the accidental copy or dismiss the group.
* **Review unregistered scrip**: plan-reserve scrip in wallets beyond
  what grant withdrawals explain. Flagged rows carry a **⚠ unregistered**
  chip, and the review can stage a draft position (never an active one)
  prefilled from the onchain evidence.
* **Review cert double counts**: a counting LET beside a counting live
  offchain entry for the same holder, class and size, as an unlink or a
  declined import link leaves them. The dialog names the remedy for each
  pair, usually **Link existing cert** on the entry or **Unlink cert** on
  a mis-linked position, and never assumes the LET is the mistake. You
  apply the fix on the rows themselves, and can dismiss pairs that are
  separate holdings.
* **Review cert printer links** and **Review duplicate classes** open
  **Reconcile classes**. A tokenized series is an offchain class line
  linked to its LET contract. Once linked, the pair renders as one class
  everywhere, and until then it counts as two. The dialog lists unlinked
  series lines and lines that look like one class recorded twice (same
  class/series, matching name), and offers a journaled **merge** into a
  survivor whose terms win. A line with an attached legal identity can
  only be the survivor. Display labels derive from the class/series, so
  renaming a line's stored legal name in **Class terms** is safe.

## The header controls

The cap table header has one lime button, **+ Add position**, and four
muted menus beside the **Securities status** link:

| Control | What it opens |
| --- | --- |
| **+ Add position** | The position form in one click. Its arrow (▾) opens a menu with **Stakeholder** and **Position**. |
| **Import** | **Import file (.csv / .xlsx / OCF)**, **Blank template (.csv)**, **Blank template (.xlsx)** |
| **Compliance** | **409A / FMV**, **Rule 701**, **Option exercises (Form 3921)**, **83(b) elections**, **§219 stockholder list** (see [Cap table records, modeling and compliance](captable-tools.md)) |
| **Export** | **CSV (.csv)**, **Excel (.xlsx)**, **OCF package (.zip)** |
| **More** | **Link wallets**, **Invitations**, **Token config**, **Reset ledger** |

**Export** is disabled until the table has loaded. The two blank-template
items and the three Export items download a file. Every other item opens
its panel below the header, and the panel has its own close control.

## Stakeholders

A **stakeholder** has a name, an optional email and mailing address, a
relationship (founder, investor, employee and so on) and any number of
linked wallets. **+ Add position ▾ → Stakeholder** records one. Wallets
join the two halves of the table: a LET whose holder wallet a stakeholder
has linked appears under that stakeholder. A LET that matches no one
shows an **unmatched wallet** badge with a one-click path to a new
stakeholder, and **More → Link wallets** matches in bulk. A wallet
belongs to one stakeholder at most.

### Invite a stakeholder to the holder portal

**More → Invitations** generates a private onboarding link per
stakeholder. The app never emails it, so you send it through a channel
you trust. The invitee connects a wallet and signs in with SIWE, which
attaches the wallet to their record and opens their
[My holdings](holders.md) portal. Links expire after 14 days, and
regenerating one revokes the previous link.

**Holder portal disclosures** decides whether invited holders also see
the documents attached to their positions, and per-unit and exercise
prices. Both are off until you turn them on.

## Record a position

**+ Add position** records an untokenized position offchain, with no
transaction. The form takes:

* the **class**, with inline creation of classes and series. A new class
  whose name matches an existing line of the same class/series is
  refused, and the form points you to that line or to a rename in
  **Class terms**. An equity
  award takes an **award type** (stock option, RSU or restricted stock)
  on its underlying class: a Common option is award type "Stock option"
  on class "Common Stock";
* the **plan pool** an award draws from, which you can create inline
  with its reserve;
* units, investment amount, price per unit, valuation and round label;
* **vesting** (start, end, cliff in months, termination date, vested
  override) and, for paid awards, the strike or repurchase price, the
  post-termination window and the option's term expiration;
* SAFE terms (cap basis, discount) and token-instrument terms (claim,
  amount, unlock schedule);
* a **federal exemption** tag (Rule 701 entries feed the
  [Rule 701 monitor](captable-tools.md)), transfer-restriction chips, a
  paper certificate reference, notes and private PDF attachments, which
  owners can always open and the holder can open once you turn on the
  position-documents disclosure.

**Save as draft** stages a position that counts toward nothing until you
issue it from [Securities status](#securities-status).

**Void** and **Terminate** record real corporate events and keep the row
in History. **Delete** is only for an entry that never reflected a real
holding, and removes it for good.

## Import a cap table

**Import → Import file** opens the import panel. It takes `.csv` and
`.xlsx` sheets (**Import → Blank template (.csv)** and **Blank template
(.xlsx)** download empty ones) and OCF (Open Cap Table Format) as a
`.json` bundle or the `.zip` that Carta or Pulley export. You give each row an action
before anything is written: create an offchain record, update an
existing position (rows exported from this app carry a `position_id`),
link to an existing LET instead of duplicating it, or skip.

Class names are canonicalized, so "Common Stock - Acme, Inc." merges into
"Common Stock". When an import would add class lines beside existing ones
of the same class/series, the preview warns you first. New lines are
right for a new sub-series and wrong for a sheet that only spells a class
differently.
Blocking errors stop the import, grouped by issue so you can fix the
sheet.

**GAIBE**, the AI import below the file input, converts a cap table in
any form (a spreadsheet, a Carta or Pulley export, a PDF, a screenshot,
pasted prose) into the import format. Limits: uploads of about 3 MB,
pasted text of 400k characters, 25 documents per officer per day, and no
legacy `.xls` (re-save as `.xlsx`). GAIBE leaves a field it is unsure of
blank and flagged, carries numbers digit for digit, and skips summary
rows and percentage columns, which the app recomputes. A **column mapping
report** lists every source column, and each extracted field is shown
under its preview row. Converted rows go through the same validation and
per-row actions as a hand-built sheet, and nothing is imported until you
commit.

## Reset the offchain records

**More → Reset ledger** opens *Clear offchain cap-table records?*, which clears
the removable offchain positions, stakeholders, classes and plans so you
can re-import. Tokenized positions, positions tied to a live MetaVesT
escrow, and the audit journal (which dated stockholder lists use) are
kept. You type `RESET` to confirm, and it cannot be undone, so export
first.

The reset is refused while the table holds formation-managed positions
with issued history, or once it carries append-only evidence: a class
line with an attached
[legal identity](#legal-classes-series-and-versioned-terms) or a position
with an approved tokenization source. Correct those entries by voiding,
terminating or re-recording them. Clearing formation-managed drafts
consumes them, and the one-time formation setup cannot be staged again.

## Tokenize a position

**Tokenize →** on a row mints one LET for the whole position, on v4 and
v5 companies. To mint for part of a position, see
[Tokenizing part of a position](#tokenizing-part-of-a-position-v5-companies).

The dialog prefills the certificate form from the entry, lets you pick
the recipient wallet when the holder has several, and lists the cap table
details that stay offchain (vesting schedule, exercise price, discount,
notes and similar fields). Minting is one transaction, preceded by a
board-consent check when a consent in [boardRoom](boardroom.md) covers
the position, and the entry then mirrors the LET. If the transaction
mines but the link-back fails, the dialog lets you retry the link or
enter the LET's number, so you never mint a duplicate.

**Link existing cert** links a LET that already exists on the class's LET
contract, without minting. The app checks the LET number you enter: the
LET must be live, claimed by no other position, held by a wallet of this
stakeholder, and carry exactly the position's registered units. The
position then mirrors it, as after **Tokenize →**, and an unlinked holder
wallet is recorded on the stakeholder. Use it to relink a LET unlinked
from the wrong position, or after importing a table whose LETs already
exist.

**Unlink cert**, the one action on a tokenized row, is a journaled
correction for a mistaken link. The position becomes an active offchain
record again while the LET stays live onchain, so both count and the
double-count review flags the pair. Resolve it promptly with **Link
existing cert** on the correct position, or void the LET onchain.

Equity awards (options, RSUs, vesting restricted stock) never become
LETs: **Escrow award (MetaVesT) →** sends them to [grants](grants.md),
where their scrip escrows onchain. Stock plan reserves have their own
rows, and **Tokenize plan** mints one LET to the company for the full
reserve, which you scripify to fund grants. A fully scripified reserve
shows a "fully scripified" chip.

If the class has no LET contract, the action reads **Create cert
printer →** and takes you through class creation in the
[Tokenization Hub](tokenization-hub.md). If several LET contracts match
the class and the line is linked to none, it reads **Choose cert
printer →** and asks which one mints this class's LETs.

### Tokenizing part of a position (v5 companies)

In the [Tokenization Hub](tokenization-hub.md), a class panel's
**Tokenize cap table units** lists the untokenized positions whose class
line is linked to that LET contract, with each split (for example
"1,000 units · 250 tokenized · 750 untokenized"). A position qualifies
when it is active and offchain, is not an equity award, is not linked
whole to a LET, and is not in a vesting escrow. The class line must be
linked to the LET contract (the **Review cert printer links** banner does
that) and must have
[activated legal terms](#legal-classes-series-and-versioned-terms).
Without them the attempt is refused with a message naming the line.

**Tokenize units** states how many units remain untokenized and that
"The position keeps one cap table row; only its tokenized and untokenized
split changes." Enter fewer than the prefilled remainder in **Number of
units represented by certificate** to tokenize part of it. The holder is
fixed to their linked wallet, with a **Registered owner** choice if they
have several, and **Tokenize these units** sends one transaction from an
owner wallet. A v4 company is refused with "This cyberCORP reports
contract version 4; tokenization allocations require the cyberCORPs v5
protocol."

The app reserves the units before the wallet request, so they cannot be
minted twice, then checks the chain and reports:

* **Units tokenized**: the LET carries the units, and the split updates
  once the indexer reaches the mint's block.
* **Units not tokenized**: nothing was minted (the request never reached
  your wallet, or the transaction reverted), and the units are released.
* **Units held**: the app could not establish that nothing was minted,
  for example after you declined the wallet request or when the outcome
  could not be read. Held units are neither tokenized nor released
  automatically. The panel shows "· N held", the integrity checks fail,
  and registered exports are unavailable until the allocation reconciles.

The dialog warns about held units before you confirm. The first attempt
records a permanent tokenization source tying the position to the LET
contract, the activated terms and the holder's wallet, after which the
position cannot be deleted (**Void** and **Terminate** still work). A
partially tokenized position stays one cap table row with its LETs
folded in, and exports carry `tokenized_units`, `untokenized_units` and
`unresolved_units`. Once you tokenize a position from the Hub, do not
also use **Tokenize →** on it.

## Legal classes, series and versioned terms

The charter or other governing document defines each class, and a class
line holds the app's working terms for it. Legal identity and versioned
terms connect the two: you record which legal class (and series) the line is,
record the exact terms text from the governing document as a numbered
version, have a current officer approve that version, and activate it.
The cap table, its exports and the v5 tokenization paths then read the
activated terms in place of the line's stored values.

The workflow is the **Legal class and terms** section of a class panel
in the [Tokenization Hub](tokenization-hub.md). It needs the LET contract
linked to a cap table line. Until it is, the section says the line has
no legal identity yet and links to the cap table's **Review cert printer
links** banner. Reading needs a signed-in owner wallet, and the other
steps need that wallet to be a current officer of the cyberCORP. No step
is a transaction: identities, versions and approvals are app records,
and the wallet approval is a free signature.

1. **Attach a legal identity.** Choose the **Parent legal class** (or
   **New legal class…**), whether **This line is** a series of it or the
   class itself, the series name, the **Source reference (document and
   clause)** and the **Exact source text**, then **Attach legal
   identity**. The app first verifies the line's history in the cap
   table journal (created or imported in the app, never changed outside
   it) and shows it as **Line history**. If it does not verify, the
   button stays disabled with "A legal identity cannot be attached until
   the history verifies." A plan pool cannot take an identity, and a line
   takes only one.
2. **Propose a terms version.** **Propose terms version** asks for the
   **Document reference**, **Document version**, **Exact terms text from
   the document**, the conversion ratio as numerator and denominator
   (blank means unknown, never 1:1), an optional proposed effective date
   ("Leave blank to take effect on approval.") and optional **Scoped
   rights and voting rules**, recorded verbatim and not evaluated.
   **Propose version** saves an immutable record in state **Proposed**.
3. **Approve it.** One current officer's approval is enough. **Approve
   with wallet** signs the exact version (document, version, text digest,
   class and series). The app verifies the signature, including from a
   Safe or other contract wallet, and checks onchain that the signer is a
   current officer. **Record external approval** instead records
   approvals obtained outside the app, such as a board or stockholder
   consent: the eligible groups, an optional stated effective date, the
   consent PDF and each approval, with the recording officer as
   approver. The version becomes **Approved, not active**.
4. **Activate.** **Activate** makes the version govern from the latest of
   the approval time, the approval's stated effective date and the
   proposed effective date, so a version can show **Activated, effective
   later** before it is **Active**.

To amend, propose, approve and activate a new version, which makes the
previous one **Superseded**. An older version cannot be activated over a
newer active one, and a proposal that changed after approval needs a new
approval.

Activated terms govern:

* **Class terms**, which locks the conversion ratio and names the version,
  effective date and document (see [Class terms](captable-tools.md)).
  Without an identity or an active version, the line's stored terms
  govern and the form says which case applies.
* **Cap table math**, which uses the version's exact conversion ratio.
* **Exports**. The `.csv` carries `class_terms_source` (`legal_version`
  or `app_line`), the reason when the app line governs, and the version
  id and digest. The `.xlsx` adds a **Class terms** sheet, and the OCF
  bundle carries the same facts. A line with no active version still
  exports.
* **Tokenization and conversion**:
  [partial tokenization](#tokenizing-part-of-a-position-v5-companies)
  mints against the activated terms, and a holder's conversion of scrip
  back into a LET is checked against them (see
  [For holders](holders.md#convert-scrip-back-into-a-let)).
* **Imports**, which are refused if they set a conversion ratio that
  contradicts the active terms.

## Positions seeded by formation

For a company formed through the app (see [Form a company](formation.md)),
the cap table starts with a requested **Common Stock** class awaiting
review and a **Proposed initial ownership** section holding the draft
positions from your private setup plan. They are badged *Proposed · not
issued* and stay out of every total until each is recorded. A formed
company with no saved ownership proposal gets a **Start your cap table**
card in the Incorporation Hub instead.

## Securities status

**Securities status**, linked from the cap table header with a live
draft count, is the officer's issuance worklist, with four queues
derived live from the cap table and the chain:

1. **Drafts**: issue (as active or as "promised"), edit or delete staged
   positions. **Formation-managed drafts** go through **Review cash
   terms**, **Review exemption** and **Review board approval**, in that
   order, then **Record issuance**. They cannot be edited, and once
   recorded they cannot return to draft or be deleted, so corrections
   use Edit, Void and Terminate. Only plain Common Stock can be recorded this
   way. A draft with restricted, award, plan, convertible or token terms
   stays a non-counting draft for a custom workflow.
2. **Awaiting signature**: proposed onchain, unsigned by the recipient.
   Copy the cyberSign signing link and send it yourself, since the app
   sends no email.
3. **Awaiting acceptance**: signed, with the escrow not yet finalized.
4. **Awaiting settlement**: escrowed with vested units to sweep or
   post-termination cleanup left.

## Exports

The **Export** menu (**CSV (.csv)**, **Excel (.xlsx)** and **OCF package
(.zip)**) exports the full table, history included. Each export records when it was generated, its
record date if any, and the indexer block its onchain rows were read at
and whether that block was final.

The `.csv` and `.xlsx` always export and note gaps beside the affected
rows. The OCF bundle and the record-date stockholder list are registered
exports, which the app refuses rather than build from an incomplete
source. The refusal starts "Registered export unavailable:" and names
the cause: the indexer has not reached the record date's block or that
block is not final, a tokenization allocation is unreconciled, or a class
line's legal terms evidence is unresolved. A cap table built from an
earlier indexer must be regenerated first.

A current untokenized row also offers **Download statement**, a PDF
position statement that says on its face it is neither a tokenized
certificate nor a stock certificate and does not by itself determine
which record is the company's securities ledger. A row mirroring a LET
offers **Download certificate**, a PDF rendering of the indexed LET that
tells the reader to verify its status onchain.

The **Compliance** menu's panels (the §219 stockholder list, 409A and FMV
records, the Rule 701 and Form 3921 monitors and 83(b) tracking) and the
scenario calculators are in
[Cap table records, modeling and compliance](captable-tools.md).

> **Under the hood.** Tokenized rows are
> [LETs](../reference/contracts/LedgerEntryToken.md) minted through the
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md),
> scrip-derived rows read [`CyberScrip`](../reference/contracts/CyberScrip.md)
> balances, and award escrows are MetaVesT allocations. Quantities are
> exact decimal strings end to end (onchain values are 18-decimal fixed
> point), so forms reject a 19th decimal place rather than let the escrow
> and the cap table drift apart through rounding. See
> [LETs and scrip](../explanation/lets-and-scrip.md).

## LLC cap tables

For an LLC, **capTable** opens the **LLC cap table**: ordinary
capital-interest units grouped by legal class, with its own records and
workflows. It has none of the stock tooling (no §219 list, no 409A, Rule
701, 3921 or 83(b) panel, no round or waterfall model, no Token cap
table, no import). Tabs show **Classes**, **Positions** (the default),
**Holders**, **Members** and **History**, with search, class and status
filters.

* **Classes** have a **Class name**, an **Operating agreement reference**
  and a **Rights summary (ordinary capital interests)**.
* **Positions** are units of a class held by a stakeholder, to 18
  decimal places: a draft, a recorded holding or cancelled. Only recorded
  holdings count. The one percentage shown is "% of recorded class
  units", and the page states that class-unit percentages do not
  determine voting or distribution rights.
* **Memberships** have admission and cessation dates with an evidence
  reference. They are recorded separately from units: holding units does
  not make someone a member, and recording an admission issues no units.

**Add draft position** stages a draft and **Record issuance** turns it
into a recorded holding. **Record transfer** and **Record cancellation**
act on a recorded holding. A transfer closes the source position and
records the recipient, and any units left over, as linked positions in
the same class. **Record admission** and **Record cessation** handle
memberships. Each workflow asks for the effective date, the operating
agreement version, the authority and restrictions relied on, the
approvers and their capacities, the executed approval or consent and its
date, and the executed instrument, all as text references. You confirm
the event occurred with the required approvals, review, and choose
**Confirm and record**. Recording documents an event that already
happened. It does not issue units, admit a member or execute a transfer.
An approval dated after the event is refused, and so is a future-dated
event.

**Plan a unit allocation** is a worksheet of proposed holders, units and
resulting class percentages with a JSON download ("Planning only.
Nothing is saved to your cap table.").

**Tokenize LLC units** mints a LET for a whole active position on an
existing v5 CommonStock LET contract with no certificate extension, used
as a compatibility container. Map the class to that LET contract with
the approval reference for the encoding and its public terms (**Save
class mapping**), pick the position, confirm the recipient wallet
recorded on the stakeholder, then **Reserve whole position** and **Sign,
simulate and submit**. The app refuses unless the company, its issuance
manager and the LET contract all verify as v5. Before mapping, note that
the governing references, rights summaries and approval evidence become
public onchain, holder names are left out, USD amount fields are zero,
and the contract-generated metadata still says "CommonStock / Shares".
The LET stays part of the same LLC position, and a reserved or tokenized
position cannot be changed offchain until its tokenization reconciles. A
reverted transaction releases the reservation, and **Release unsent
reservation** releases an unsent one.

**Export this view (CSV)** uses rounded percentages, and **Export all
records (JSON)** keeps exact quantities and every record and history entry
regardless of filters. If the LLC had imported stock records or onchain
positions before its native LLC records existed, **View legacy cap
table** shows them read-only. Bulk reset is unavailable once native LLC
records exist.

## Good to know

* **Offchain writes are free.** Recording, editing, importing and
  inviting send no transaction. Minting LETs and escrowing awards cost
  gas.
* **Every offchain change is journaled.** The append-only audit trail
  backs the as-of reconstruction behind dated stockholder lists.
* **v4 and v5 companies share most of the cap table.** The app reads each
  company's contract version and refuses visibly where a feature needs
  v5: partial tokenization, LLC tokenization and private sales (see
  [For holders](holders.md#prepare-a-private-sale-v5-companies)).
  Converting scrip back into a LET also works on a v4 company that runs
  the current v4 release of its issuance manager (see
  [Convert scrip back into a LET](holders.md#convert-scrip-back-into-a-let)).
  A company keeps its deployed version until its owners upgrade it (see
  [Run your company](company.md)).
