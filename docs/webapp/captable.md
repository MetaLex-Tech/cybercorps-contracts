---
description: One cap table for tokenized and untokenized positions, with AI-assisted import, versioned legal terms, partial tokenization and LLC records
---

# The cap table

The **cap table** is the cyberCORPs app's unified register of who owns what
in your company. Its strapline says it plainly: *one table, onchain and
offchain*. Positions you have tokenized as cyberCERTs, positions recorded
only in the app, and beneficial holdings derived from cyberSCRIP balances
all appear in the same view, with the same math.

You reach it from the **capTable** item in the app sidebar or from the
Tokenization Hub's "Cap Table" button.

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

Which cap table you get follows the company's legal type as recorded on
its cyberCORP. A corporation gets the stock cap table this page
describes. An LLC gets a unit-based register instead (see
[LLC cap tables](#llc-cap-tables)). Any other type is refused with
"Cap table workflows require an explicitly identified corporation or
LLC. Review the company's legal type in its profile."

Holder identities on certificates are encrypted when that choice was
made at issuance (it is optional; see
[the certificate page](holders.md#the-certificate-page)). For encrypted
names, the app decrypts server-side during assembly, and a name it
cannot decrypt renders as a scrambled placeholder rather than leaking
ciphertext. A name issued in plaintext, and signing-officer names in
general, live in the certificate's public metadata regardless.

## How to read the table

Every position carries a source badge. The badge answers two independent
questions — *where the record lives* (onchain or in the app) and
*whether the units are tokenized* — and nothing more. Which record is
the company's legally definitive securities ledger is set by the
company's own bylaws and board action, not by token status or by where
the data is stored:

* **⛓ tokenized** — the position's units exist as an onchain cyberCERT;
  the cap-table row mirrors that cert.
* **📄 offchain** — the position is recorded and edited in the app, as a
  cap-table record of untokenized holdings. Recording a row documents an
  issuance rather than effecting one: the corporate authorization behind
  it (a [board consent](boardroom.md#board-approvals), for instance)
  must still exist. The badge links to the first attached document.
* **≈ tokenized (scrips)** — a *beneficial* claim derived from a
  cyberSCRIP balance. Scrips are fungible tokens, and holding them is an
  economic position without being registered stock.
* **⛓ escrowed onchain** — an equity award whose scrip sits in a MetaVesT
  vesting escrow; the chain enforces the schedule. See
  [Token grants and onchain vesting](grants.md).

For a company whose governing documents designate the onchain system as
its official register (see
[Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md)),
the cyberCERTs *are* that register — but that is the bylaws' doing, and
the app never infers it from a badge.

Because scrip exists, the table supports two ownership lenses. The
**Registered** lens shows record owners (the view that matters for
stockholder lists and corporate law). The **Beneficial** lens follows the
economics: scripified shares move from the certificate owner to the scrip
holders. The toggle only appears once your company has issued scrip.

The **Securities cap table** tab itself shows summary cards (issued &
outstanding, semi-diluted, fully diluted, stakeholders, total raised,
onchain certificates, offchain entries, duplicates), a capitalization
donut by class, and section tables for **Equity**, **Convertibles**,
**Token instruments**, and **History** (void, terminated, tokenized,
exercised, converted, kept for audit). You can group rows by stakeholder
or by class/series, pick the basis for the % column (issued &
outstanding, semi-diluted, or fully diluted), and search for a holder.
Each section closes with per-class subtotal rows and an emphasized
**Total** row that follow whatever lens, basis, and filter you have
active; in the stakeholder grouping, a **Class/series** filter narrows
the whole view to the classes you pick (a pinned class line and its cert
printer count as one class; row percentages keep the company-wide
denominator).

Above the table, up to four review banners surface things that need a
decision: **duplicate offchain entries**, **unregistered plan-reserve
scrip**, **cert double counts**, and **class reconciliation** (unlinked
cert printers and duplicate class lines). Each opens its own review
dialog; all four are covered below.

An **Integrity checks** panel at the bottom recomputes the table's
invariants live: fully-diluted shares accounted for, SAFE ownership under
100%, every position attached to a stakeholder, scrip pools conserving
units, plan reserves backed by their certificates, and more. A failing
check is a prompt to investigate before relying on the numbers.

The onchain half of the table is read from an indexer. When the app
can't establish a complete source for the registered view (the indexer
read is incomplete or hasn't reached the block it needs, a tokenization
allocation is unreconciled, or a class line carries conflicting legal
identities), it stops presenting partial numbers as totals. A caution
banner reads "Some certificate records are incomplete. Registered
exports are unavailable." and lists what it found, the summary cards
switch to **Known issued subtotal** and **Known amount raised**, the
capitalization donut is hidden, and **Model a round** and **Exit
waterfall** show "Analysis requires complete source quantities and
terms." until the source is complete again.

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

**+ Add Position** records an untokenized position on the offchain
cap table. No transaction is involved; the record write is the record.
The form covers the full range of instruments:

* the **class** (with inline creation of new classes and series — though
  creating a class whose name matches an existing line of the same
  class/series is refused, pointing you at the existing line or a rename
  via Class terms) and, for equity awards, an **award type** (stock
  option, RSU, or restricted stock) sitting on its *underlying* class —
  a Common option is Award type "Stock option" on class "Common Stock";
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
Class names are matched after canonicalization — "Common Stock - Acme,
Inc." merges into your "Common Stock" line instead of creating a
duplicate — and when an import *would* create new class lines beside
existing ones of the same class/series, the preview warns you before
you commit (right for a genuine new sub-series, wrong if the sheet just
spells a class differently). Blocking validation errors stop the
import; the error worklist groups them by issue so you fix the sheet
rather than hunt row by row.

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

**Reset Ledger** (the dialog is titled *Clear offchain cap-table
records?*) clears the removable offchain positions, stakeholders,
classes, and plans so you can re-import from scratch. Kept: tokenized
positions, which mirror onchain certs, and positions tied to a live
MetaVesT escrow; the audit journal is preserved so dated stockholder
lists still work. It requires typing `RESET` to confirm, and it can't be
undone, so export first. Two formation caveats: the reset is unavailable
while the table holds formation-managed positions with issued history,
and clearing formation-managed *drafts* consumes them permanently — the
one-time formation setup cannot be re-staged.

Reset also refuses once the cap table carries append-only legal or
tokenization evidence: a class line with an attached
[legal identity](#legal-classes-series-and-versioned-terms), or a
position with an approved tokenization source. Correct those entries
through their own flows (void, terminate or re-record) instead.

## Tokenizing a position

There are two paths. **Tokenize →** on a cap table row mints one
certificate for the whole position and works on v4 and v5 companies.
**Tokenize units** in the Tokenization Hub mints a certificate for part
or all of a position against the class's activated legal terms, and
needs a v5 company (see
[Tokenizing part of a position](#tokenizing-part-of-a-position-v5-companies)).

**Tokenize →** on an offchain position mints an onchain certificate for
it and links the cap table entry to the cert; the row mirrors the cert
from then on (and where the company's governing documents designate the
onchain system as its official register, the cert *is* the registered
entry). The dialog pre-fills the certificate form from the cap table
entry (investor, units, amounts, terms), lets you pick the recipient
wallet if the holder has several, and warns you which cap table details
do *not* carry onchain (vesting schedule, exercise price, discount, notes,
and similar record-keeping fields).

Minting is one onchain transaction, preceded by a board-consent check
when the position is covered by one (see
[the boardRoom](boardroom.md#board-approvals)). If the transaction mines
but the link-back fails, the dialog offers a repair path — retry the
link, or enter the cert number by hand — so you never mint a duplicate.

Beside **Tokenize →**, every eligible row also offers **Link existing
cert** — the mint-free path. It links a certificate that *already
exists* on the class's cert printer (the onchain contract that mints a
class's tokenized certificates) to this position: you enter the cert
number, the app verifies it — the cert must be live, unclaimed by any
other position, held by a wallet belonging to this stakeholder, and
carry exactly the position's registered units — and the position flips
to tokenized, mirroring that cert, the same end state as Tokenize with
nothing new minted. Use it to relink an orphaned cert after unlinking
it from the wrong position, or when importing a table whose certs
already exist onchain. If the cert's holder wallet wasn't yet linked to
the stakeholder, completing the link records it.

The reverse exists too: a **tokenized** row's one action is **Unlink
cert**, a journaled correction for a mistaken link. The position
returns to the cap table as an active offchain record and the cert
itself is untouched — it stays live onchain — so until you resolve it
the table shows *both* records and flags the pair in the cert
double-count review. Resolve it promptly: relink the cert to the
correct position with Link existing cert, or void the cert onchain.

Two kinds of position tokenize differently:

* **Equity awards** (options, RSUs, vesting restricted stock) don't
  become certs. **Escrow award (MetaVesT) →** routes them to the grants
  flow, where the scrip escrows onchain and the chain enforces the
  schedule. See [Token grants and onchain vesting](grants.md).
* **Stock plan reserves** appear as their own rows. **Tokenize plan**
  mints one jumbo certificate to the company itself for the plan's full
  reserve; you then **scripify** out of that cert to fund grants. Once
  the reserve is fully scripified, the Scripify action retires into a
  passive "fully scripified" chip.

If no cert printer exists yet for the position's class, the action
becomes **Create cert printer →** and routes you through the standard
create-class flow first. If *several* printers match the class and the
line isn't linked to one, the action becomes **Choose cert printer →**,
asking which cert printer mints this class's certs.

### Tokenizing part of a position (v5 companies)

Partial tokenization runs from the Tokenization Hub, not from the cap
table row. Expand a class panel's details and find **Tokenize cap table
units** ("Mints on this line's pinned printer, against its activated
terms."). It lists the untokenized positions whose class line is linked
to that printer, each with its split, for example "1,000 units · 250
tokenized · 750 untokenized". A position qualifies when it is an active
offchain position, not an equity award (awards go through
[grants](grants.md)), not already linked whole to a certificate, and not
in a vesting escrow. Two things must be in place first: the class line
must be linked to the printer (the cap table's **Review cert printer
links** banner does that), and the line must have activated legal terms
(see [Legal classes, series and versioned terms](#legal-classes-series-and-versioned-terms)).
Without activated terms the attempt is refused with a message naming the
line and pointing you to the Tokenization Hub.

**Tokenize units** opens a dialog that states how many units remain
untokenized and that "The position keeps one cap table row; only its
tokenized and untokenized split changes." The certificate form is
prefilled with every remaining unit; enter fewer in **Number of units
represented by certificate** to tokenize part of the position. The
holder is fixed to their linked wallet (with a **Registered owner**
choice if they have several), and **Tokenize these units** sends one
transaction from a corp owner wallet. On a v4 company the request is
refused: "This cyberCORP reports contract version 4; tokenization
allocations require the cyberCORPs v5 protocol."

The units are reserved before the wallet request, so the same units
cannot be minted twice. The app then confirms the mint against the chain
and reports one of three outcomes:

* **Units tokenized**: the certificate carries the units, and the
  position's split updates once the indexer reaches the mint's block.
* **Units not tokenized**: nothing was minted (the request never reached
  your wallet, or the transaction reverted), so the units are released
  and available again.
* **Units held**: the app could not establish that nothing was minted,
  for example because you declined the wallet request after the units
  were reserved, or the transaction's outcome could not be read. Held
  units are not tokenized and are not released automatically. The panel
  shows them as "· N held", the cap table's integrity checks fail on the
  unresolved allocation, and registered exports are unavailable until it
  reconciles.

The dialog warns you about held units before you confirm. The first
attempt also records an approved source for the position that ties it to
the printer, the activated terms and the holder's wallet; that record is
permanent, so the position can no longer be deleted afterwards. Void or
Terminate remain available.

On the cap table a partially tokenized position stays one row, with its
certificates folded into it, and the exports carry the split in
`tokenized_units`, `untokenized_units` and `unresolved_units` columns.
Use one path per position: don't also run **Tokenize →** on a position
you have started tokenizing from the Hub.

## Keeping classes and certs reconciled

Three review worklists keep the two halves of the table honest. Each
surfaces as a banner above the table when it has findings:

* **Reconcile classes** — a tokenized legal series is one offchain class
  line *linked to* its cert printer; linked, the pair renders as one
  class everywhere (breakdown, donut, filters, subtotals). The dialog
  lists series lines not yet linked to a matching printer (until the
  link is set, the line and its certs count as two classes) and groups
  of class lines that look like one class recorded twice — same
  class/series, matching name — offering a journaled **merge** into a
  survivor whose terms win. A line with an attached legal identity can
  only be the survivor, never the line merged away. Class display labels
  derive from the class/series, so renaming a line's stored legal name
  (via Class terms) is safe.
* **Review cert double counts** — pairs where a counting onchain cert
  sits beside a counting live offchain entry for the same holder,
  class, and size (the state an unlink or a declined import link leaves
  behind). The dialog compares each pair field by field and tells you
  the remedy per shape — usually Link existing cert on the entry, or
  Unlink cert on a mis-linked position; it never assumes the cert is
  the mistake. Pairs that are genuinely separate holdings can be
  dismissed. The dialog only surfaces; every fix happens on the rows
  themselves.
* **Review unregistered scrip** — plan-reserve scrip sitting in wallets
  beyond what grant withdrawals explain. Flagged positions carry an
  **⚠ unregistered** chip, and the review can stage a *draft* position
  prefilled from the onchain evidence — never an active row.

## Legal classes, series and versioned terms

A class line carries the app's working terms for a class, but the
company's charter or other governing document is what defines the
class. Legal identity and versioned terms connect the two. You record
which legal class (and series) a line is, record the exact terms text
from the governing document as a numbered version, have a current
officer approve that exact version, and activate it. From then on the
cap table, its exports and the v5 tokenization paths read the activated
terms instead of the line's own stored values.

The workflow lives in the Tokenization Hub: expand a class panel and
open **Legal class and terms**. It needs the printer to be linked to a
cap table line; until then it says "This printer is not linked to a cap
table class or series line, so it has no legal identity yet." and links
to the cap table, where the **Review cert printer links** banner sets
the link. Reading needs a signed-in owner wallet; attaching, proposing,
approving and activating also need that wallet to be a current officer
of the cyberCORP. None of it is a transaction. Identities, versions and
approvals are app records, and the wallet approval is a free signature.

1. **Attach a legal identity.** Choose the **Parent legal class** (an
   existing one or **New legal class…**), say whether **This line is**
   one series of the parent class or the class itself, name the series,
   and give the **Source reference (document and clause)** and the
   **Exact source text**, then **Attach legal identity**. The app first
   verifies the line's history in the cap table journal (created or
   imported in the app, never changed outside it) and shows it as **Line
   history**; if it doesn't verify, the button stays disabled with "A
   legal identity cannot be attached until the history verifies." A plan
   pool is not a security class and can't take an identity, and a line
   takes only one.
2. **Propose a terms version.** **Propose terms version** asks for the
   **Document reference**, the **Document version**, the **Exact terms
   text from the document**, the conversion ratio as a numerator and
   denominator (blank means unknown, never 1:1), an optional proposed
   effective date ("Leave blank to take effect on approval.") and
   optional **Scoped rights and voting rules**, which the app records
   verbatim and does not evaluate. **Propose version** saves an
   immutable record in state **Proposed**.
3. **Approve it.** One approval from a current officer is enough.
   **Approve with wallet** signs the exact version (document, version,
   text digest, class and series) with the connected officer wallet; the
   app verifies the signature, including from a Safe or other contract
   wallet, and checks onchain that the signer is a current officer.
   **Record external approval** instead records approvals obtained
   outside the app, such as a board or stockholder consent: the eligible
   groups, an optional stated effective date, the consent PDF and each
   approval obtained, with the recording officer as approver. The
   version becomes **Approved, not active**.
4. **Activate.** **Activate** makes the version govern from the latest
   of the approval time, the approval's stated effective date and the
   proposed effective date, so a version can show **Activated, effective
   later** before it is **Active**.

To amend, propose a new version, then approve and activate it; the
previous version becomes **Superseded**. An older version can't be
activated over a newer active one, and a proposal that changed after it
was approved needs a new approval.

Activated terms show up in several places:

* **Class terms** locks the line's conversion ratio and names the
  version, effective date and document it came from. Without an
  identity, or with no active version, the line's own stored terms
  govern and the form says which case applies.
* **Cap table math** uses the active version's exact conversion ratio.
* **Exports** record where each class's terms came from. The `.csv`
  carries `class_terms_source` (`legal_version` or `app_line`), the
  reason when the app line governs, and the version id and digest; the
  `.xlsx` adds a **Class terms** sheet; the OCF bundle carries the same
  facts. A line with no active version still exports.
* **Tokenization and conversion**:
  [partial tokenization](#tokenizing-part-of-a-position-v5-companies)
  mints against the activated terms, and converting a holder's scrip
  back into a certificate is checked against them (see
  [De-scripify](holders.md#de-scripify-back-to-the-register)).
* **Imports** that would set a conversion ratio contradicting the active
  terms are refused.

## Positions seeded by formation

For a company formed through the app, the cap table starts with the
formation journey's output: a requested **Common Stock** class awaiting
review, and a **Proposed initial ownership** section holding the draft
positions from your private setup plan — badged *Proposed · not issued*
and excluded from every issued, outstanding, diluted, and stakeholder
total until each is recorded. A formed company with no saved ownership
proposal gets a **Start your cap table** card in the Incorporation Hub
instead, which points here.

## Securities status

**Securities status** (linked from the cap-table header, with a live
draft count) is the officer's worklist over the issuance loop, four
queues derived live from the cap table and the chain:

1. **Drafts** — staged positions; issue (as active or as "promised"),
   edit, or delete them here. **Formation-managed drafts** work
   differently: their action chain is **Review cash terms**, **Review
   exemption**, **Review board approval** (in that order), then
   **Record issuance** — no edit, and once recorded the entry can't
   return to draft or be deleted; later corrections use the ordinary
   Edit / Void / Terminate verbs. Only plain Common Stock qualifies for
   direct recording; anything with restricted, award, plan,
   convertible, or token terms stays a non-counting draft for a custom
   workflow.
2. **Awaiting signature** — proposed onchain, the recipient hasn't
   signed. Copy the cyberSign signing link and send it yourself; there is
   no email rail by design.
3. **Awaiting acceptance** — signed, escrow not yet finalized.
4. **Awaiting settlement** — escrowed with something left to settle:
   vested units to sweep or post-termination cleanup.

## Exports

The toolbar exports the full table as `.csv`, `.xlsx`, or an OCF
bundle, including history. Each export carries a provenance record:
when it was generated, the record date if it has one, and the indexer
block its onchain rows were read at and whether that block was final.

The `.csv` and `.xlsx` exports always work and state any gaps beside
their rows. The OCF bundle and the record-date stockholder list are
*registered* exports, which the app refuses rather than produce from an
incomplete source. The refusal starts "Registered export unavailable:"
and names the cause: the indexer hasn't reached the record date's block
or that block isn't final yet, a tokenization allocation is unreconciled,
or a class line's legal terms evidence is unresolved. A cap table built
from an earlier indexer must be regenerated first.

Single positions export as PDFs too. A current untokenized row offers
**Download statement**, a position statement that says on its face that
it is not a cyberCERT or a stock certificate and does not by itself
determine which record is the company's securities ledger. A row
mirroring a cyberCERT offers **Download certificate**, a rendering of
the indexed certificate that tells the reader to verify its current
status onchain.

Records-and-compliance tooling —
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
> the escrow and the cap table drift apart. Why one security has a
> registered and a fungible form is
> [The dual-token model](../explanation/dual-token-model.md).

## LLC cap tables

For an LLC the **capTable** item opens the **LLC cap table**: ordinary
capital-interest units grouped by legal class. It has its own records
and workflows and none of the stock tooling. There is no §219 list, no
409A, Rule 701, 3921 or 83(b) panel, no round or waterfall model, no
Token cap table, and no import. Tabs show **Classes**, **Positions** (the
default), **Holders**, **Members** and **History**, with search, class
and status filters.

Three kinds of record make up the register:

* **Classes**: a **Class name**, the **Operating agreement reference**,
  and a **Rights summary (ordinary capital interests)**.
* **Positions**: units of a class held by a stakeholder, up to 18
  decimal places. A position is a draft, a recorded holding, or
  cancelled, and only recorded holdings count. The one percentage shown
  is "% of recorded class units", within a class; the page states that
  class-unit percentages do not determine voting or distribution rights.
* **Memberships**: admission and cessation dates with an evidence
  reference. Membership is recorded separately from units, so holding
  units does not make someone a member, and recording an admission
  issues no units.

Changes to positions go through workflows that record a completed event
together with its approval evidence. **Add draft position** stages a
draft; **Record issuance** turns it into a recorded holding;
**Record transfer** and **Record cancellation** act on a recorded
holding; **Record admission** and **Record cessation** handle
memberships. Each workflow asks for the event's effective date, the
operating agreement version, the authority and restrictions relied on,
the approvers and their capacities, the executed approval or consent
reference and its date, and the executed instrument reference. These
are text references, not uploads. You confirm that the event occurred
and the required approvals were obtained, review, then **Confirm and
record**. Recording documents an event that already happened; it does
not issue units, admit a member or execute a transfer. An approval dated
after the event is refused, as is a future-dated event. A transfer
closes the source position and records the recipient, and any units
left over, as linked positions in the same class.

**Plan a unit allocation** is a planning worksheet: a class name,
proposed holders and units, each holder's resulting percentage of the
class, and a JSON download. "Planning only. Nothing is saved to your cap
table."

**Tokenize LLC units** mints a certificate for a whole active position
through an existing v5 CommonStock printer with no certificate extension,
used as a compatibility container. First map the class to the printer
with the approval reference for that encoding and its public terms
(**Save class mapping**). Then pick the position, confirm the recipient
wallet recorded on the stakeholder, **Reserve whole position**, and
**Sign, simulate and submit**. The app refuses printers outside a
verified v5 company, manager and printer. Before you map, note what goes
onchain: the governing references, rights summaries and approval
evidence become public; holder names are left out; USD amount fields
are zero; and the contract-generated metadata still says "CommonStock /
Shares". The certificate stays part of the same LLC position, and a
reserved or tokenized position can't be changed offchain until its
tokenization is reconciled. A reverted transaction releases the
reservation; an unsent one can be released with **Release unsent
reservation**.

Exports are **Export this view (CSV)**, with rounded percentages, and
**Export all records (JSON)**, which keeps exact quantities and every
record and history entry regardless of filters. If the LLC had imported
stock records or onchain positions before these native records existed,
**View legacy cap table** shows them read-only. Bulk reset is not
available once native LLC records exist.

## Good to know

* **Offchain writes are free; tokenizing costs gas.** Recording,
  editing, importing, and inviting involve no transaction. Minting certs
  and escrowing awards do.
* **Every offchain change is journaled.** An append-only audit trail
  backs as-of reconstruction, which is what makes dated stockholder
  lists possible.
* **Most of the cap table works for v4 and v5 companies alike.** The
  app reads each company's contract version and refuses visibly where a
  feature needs v5: partial tokenization from the Tokenization Hub, LLC
  tokenization, converting a holder's scrip back into a certificate,
  and private certificate sales (see
  [For holders](holders.md#prepare-a-private-sale-v5-companies)). A
  company keeps its deployed version until its owners upgrade it.
* **Export regularly while the feature is in beta.** The app's own
  advice, and good practice regardless.
