---
description: Stockholder lists, 409A and Rule 701 records, tax trackers, and scenario modeling
---

# Cap-table records, modeling and compliance

Alongside the ledger itself, the [cap table](captable.md) carries a set
of records-and-analysis tools. They share a posture worth stating up
front: MetaLeX tracks what you record and does the arithmetic, and the
app says so wherever a legal judgment is involved. None of these panels
is a valuation, a filing, or legal advice.

Everything on this page is offchain and free; no tool here writes to the
ledger except where noted.

## DGCL §219 stockholder list

The **§219 List** panel reconstructs the registered record holders of
issued and outstanding stock **as of any record date**, by replaying the
offchain stock ledger and the tokenized ledger to that date. Scrip
holders are excluded: scrips are not stock until de-scripification, and
the panel cites the bylaws provision that says so.

Pick a record date, optionally label the snapshot ("2026 annual meeting
record date"), and either **Download list (.csv)** or **Save snapshot**.
Saved snapshots are immutable audit records. Because as-of
reconstruction resolves identities retroactively, regenerating the same
date later may not reproduce a past list exactly, so save the snapshot
you actually used.

## 409A / FMV records

**409A / FMV** records issuer-provided fair-market-value evidence: the
provider, the FMV per common share, effective and expiration dates, and
a privately stored PDF of the valuation report. Records are append-only;
when a valuation is replaced you mark the old one superseded rather than
editing it.

The current FMV feeds the option-granting flow: the Add Position form
shows a green banner when a current 409A covers a new option grant and
an amber one when none does.

## Rule 701 disclosure monitor

Awards tagged with the **Rule 701** federal exemption feed a rolling
monitor of the trailing and peak 12-month totals against the $10M
federal disclosure threshold. Options are valued at exercise price,
other awards at the issuer-recorded FMV covering the grant date, and
missing data is never inferred: a "resolve before relying on the total"
list calls out every position whose data would change the answer. The
panel is a threshold monitor, and it tells you itself that whether an
offering qualifies for Rule 701 is a question for counsel.

## Option exercises and Form 3921

The **Option Exercises / 3921** panel records immutable exercise facts
from mined MetaVesT events (who exercised, how much, at what strike,
when) and flags what's still missing for a filing export: grant dates,
strikes, exercise-date FMV. A repair path re-reads an exercise from
chain by its allocation and transaction hash if the recipient's browser
failed to save the event.

The filing export itself is deliberately not available yet: recipient
tax identity needs an encrypted, purpose-limited storage design first,
and the panel says so rather than collecting taxpayer identifiers
casually.

## 83(b) election tracker

For issued vesting restricted-stock awards, the **83(b)** panel tracks
the 30-day election window and stores issuer-reported filing evidence: a
reported filing date, submission method, and a required PDF. It counts
pending windows, past-due awards with no evidence, and filings on
record. A reminder and evidence system, as the panel puts it, and never
proof the IRS accepted anything.

## Model a round

**Model a Round** converts your post-money SAFEs at a hypothetical
priced round. Enter the new money, the round valuation (pre- or
post-money; the helper reminds you this is the round being priced, not a
SAFE cap), and optionally a new option pool as a percentage of the
post-round company. The results show the price per share, the new
shares, each SAFE's conversion (and whether its cap or the round price
governs), and a before/after ownership table for existing holders, new
money, and the pool. Convertibles whose terms the model can't confirm
are listed rather than silently guessed at, and an integrity line
confirms ownership reconciles to 100%.

A **sequential rounds** variant chains several future rounds. Scenarios
can be saved (inputs only; loading recomputes against the live ledger)
and compared side by side, up to three at a time.

## Exit waterfall

**Exit Waterfall** distributes a hypothetical sale value down the
preference stack: debt, liquidation preferences by seniority,
participation (with caps), as-converted classes, common, and options
net of strike. Cumulative preferred dividends accrue to the exit date
you choose. Results come per class, with each class's treatment
labelled, and per stakeholder. If your company has scrip, you choose
whether to distribute on the **Registered** or **Beneficial** basis; the
panel notes that Registered is the §219-valid default.

Both calculators are scenario-only. Nothing they compute is written to
the ledger.

## Class terms

The waterfall and the fully-diluted math are only as good as the class
terms behind them. **Class terms** is where you enter an offchain
class's charter economics from the certificate of incorporation:
authorized units, conversion ratio, liquidation preference multiple,
participation and its cap, seniority rank, and dividend rate with its
accrual basis. Onchain classes keep their chain-defined terms; only
offchain classes are editable here.

## Token cap table

The **Token cap table** view tracks project-token claims (SAFTs, SAFTEs,
token warrants) separately from company equity, against the token facts
you record in **Token config**: name, ticker, network, decimals, total
supply, launch date, and address, all of which may stay blank before
they are fixed. Fixed claims calculate now; model-based claims (minimum
percentages implied by an instrument's formula) display their recorded
terms but show as pending until each formula is implemented from its
controlling legal text. Percentages stay unavailable until a total
supply is recorded, and the panel says so instead of guessing.

## Good to know

* **Evidence lives with the record.** The FMV, 83(b), and position
  panels all store private PDFs next to the data they support, readable
  only by corp owners (and, for position documents, the holder if you
  enabled that disclosure).
* **Nothing here is advice.** The panels repeat this because it's true:
  they are records and arithmetic, and the legal conclusions belong to
  your counsel.
