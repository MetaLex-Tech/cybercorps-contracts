---
description: Stockholder lists, 409A and Rule 701 records, tax trackers, token claims and scenario modeling beside a corporation's cap table
---

# Cap table records, modeling and compliance

A corporation's [cap table](captable.md) has toolbar panels and tabs for
records and analysis. They are offchain and free. Each one records what
you enter and does the arithmetic. None is a valuation, a filing or
legal advice, and each panel says so where a legal judgment is
involved. The
FMV, 83(b) and position panels keep private PDFs next to the data they
support, readable only by owners (and, for position documents, by the
holder once you turn on that disclosure). An LLC's cap table has none of
these tools (see [LLC cap tables](captable.md#llc-cap-tables)).

## DGCL §219 stockholder list

**§219 List** reconstructs the registered record holders of issued and
outstanding stock as of any record date, from offchain cap table changes
and the onchain history of Ledger Entry Tokens (LETs) through that date.
Scrip holders are left out because scrip is not stock until it is
converted back into a LET, and the panel cites the bylaws provision that
says so.

Pick a record date, optionally label the snapshot ("2026 annual meeting
record date"), and choose **Download list (.csv)** or **Save snapshot**.
Saved snapshots are immutable audit records. As-of reconstruction
resolves identities retroactively, so regenerating the same date later
may not reproduce a past list exactly. Save the snapshot you used.

The list is a registered export, so the app refuses it rather than build
it from an incomplete source. For the onchain half, the indexer must
have processed the record date's block and that block must be final. A
recent record date can be refused for a short while with "Registered
export unavailable: the record date is not yet final" and the block
numbers. The list is also refused while a tokenization allocation is
unreconciled or a class's legal terms evidence is unresolved, and each
refusal names its cause. The `.csv` records each class's terms source
(activated legal terms or the app's class line), the tokenized and
untokenized units of partially tokenized positions, and the block the
list was read at.

## 409A and FMV records

**409A / FMV** records fair-market-value evidence the issuer provides:
the provider, the FMV per common share, effective and expiration dates,
and a privately stored PDF of the valuation report. Records are
append-only, so a replaced valuation is marked superseded instead of
edited.

The current FMV feeds option grants. The Add Position form shows a green
banner when a current 409A covers a new option grant and an amber one
when none does.

## Rule 701 disclosure monitor

Awards tagged with the **Rule 701** federal exemption feed a rolling
monitor of the trailing and peak 12-month totals against the $10M
federal disclosure threshold. Options are valued at exercise price and
other awards at the issuer-recorded FMV covering the grant date. Missing
data is never inferred: a "resolve before relying on the total" list
names every position whose data would change the answer. The panel
monitors a threshold, and it states that whether an offering qualifies
for Rule 701 is a question for counsel.

## Option exercises and Form 3921

**Option Exercises / 3921** records immutable exercise facts from mined
MetaVesT events (who exercised, how much, at what strike, when) and
counts what a filing export would still need: grant dates, strikes and
exercise-date FMV. If the recipient's browser failed to save an exercise,
a repair path re-reads it from the chain by its allocation and
transaction hash.

The panel has no filing export. It states that the export stays
unavailable until recipient tax identity has an encrypted,
purpose-limited storage and access design, and it stores no taxpayer
identifier.

## 83(b) election tracker

For issued vesting restricted-stock awards, **83(b)** tracks the 30-day
election window and stores the filing evidence the issuer reports: a
filing date, the submission method and a required PDF. It counts pending
windows, past-due awards with no evidence, and filings on record. The
panel describes itself as a reminder and evidence system, never proof
that the IRS accepted a filing.

## Model a round

**Model a round** converts your post-money SAFEs at a hypothetical priced
round. Enter the new money, the round valuation (pre- or post-money,
with helper text reminding you that this prices the round and is not a
SAFE cap), and optionally a new option pool as a percentage of the post-round
company. Results show the price per share, the new shares, each SAFE's
conversion and whether its cap or the round price governs, and a
before-and-after ownership table for existing holders, new money and the
pool. Convertibles whose terms the model cannot confirm are listed
instead of guessed at, and an integrity line confirms that ownership
reconciles to 100%.

A **sequential rounds** variant chains several future rounds. Saved
scenarios keep inputs only and recompute against the live cap table when
loaded, and up to three can be compared side by side.

## Exit waterfall

**Exit waterfall** distributes a hypothetical sale value down the
preference stack: debt, liquidation preferences by seniority,
participation (with caps), as-converted classes, common, and options net
of strike. Cumulative preferred dividends accrue to the exit date you
choose. Results come per class, with each class's treatment labelled,
and per stakeholder. A company with scrip chooses between the
**Registered** and **Beneficial** basis, and the panel notes that
Registered is the §219-valid default.

Both calculators model scenarios and write nothing to the cap table.
Both need a complete source: while the cap table reports incomplete
records, each tab shows "Analysis requires complete source quantities
and terms." in place of a model.

## Class terms

The waterfall and the fully diluted math depend on class terms. **Class
terms** holds an offchain class's charter economics from the certificate
of incorporation: authorized units, conversion ratio, liquidation
preference multiple, participation and its cap, seniority rank, and
dividend rate with its accrual basis. It also holds the class's **legal
name** as the charter spells it. Display labels derive from the
class/series, so renaming is safe, and a rename is the remedy when
creating a class is refused as a duplicate. Classes that exist only
onchain keep their chain-defined terms and cannot be edited here.

When a class line has activated legal terms (see
[Legal classes, series and versioned terms](captable.md#legal-classes-series-and-versioned-terms)),
the conversion ratio field is locked and labelled "set by the activated
legal terms", with a note naming the version, its effective date and its
document. To change the ratio, amend and activate a new version in the
Tokenization Hub. Otherwise the line's stored terms govern, and the note
gives the reason: no legal class attached, no version activated, a
conflict between legal identities, or an activated version that records
no ratio ("A null ratio is unknown, never 1:1.").

## Token cap table

The **Token cap table** tab tracks project-token claims (SAFTs, SAFTEs,
token warrants) apart from company equity, against the token facts you
record in **Token config**: name, ticker, network, decimals, total
supply, launch date and address, any of which can stay blank until
fixed. Fixed claims calculate from those facts. Model-based claims (minimum percentages
implied by an instrument's formula) display their recorded terms and
show as pending until each formula is implemented from its controlling
legal text. Percentages stay unavailable until a total supply is
recorded, and the panel says so. The **Percentage denominator** selector
switches between **Total supply**, **Recorded allocations** and
**Circulating / minted**. **Circulating / minted** stays unavailable
until a token or indexer integration is configured.

**Unlock projection date (UTC)** projects each fixed claim's recorded
unlock schedule to the start of the chosen day and fills the **Projected
unlocked** and **Projected locked** columns. Monthly schedules use
calendar anniversaries, clamped to month end. Where a projection cannot
be made, the **Projection status** column gives the reason: no unlock
schedule recorded, no valid token launch date for a schedule that starts
at the token generation event, no verified agreement execution date, or
an onchain schedule without verified provenance. The panel states that
these are current claims and terms, not a historical ownership record,
and that a projected unlocked amount does not establish token
availability or permission to transfer.

For a calculated claim, the position form has an optional **Agreement
source and calculation inputs** section: the agreement document
reference, version and controlling clause, the measurement event and
date, an input evidence reference, and the event-specific figures the
formula would use (equity ratio, allocable token supply, company
reserve, purchase amount, valuation cap, allocated entitlement and
allocation references). Leave unknown facts blank. The app does not
verify these inputs, and recording them enables no calculation and
changes no token total. They travel with the position through the
`.csv`, `.xlsx` and OCF exports.
