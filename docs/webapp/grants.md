---
description: Equity awards with onchain vesting — options, RSUs and restricted stock via MetaVesT
---

# Token grants and onchain vesting

The **grants** area of the cyberCORPs app issues equity awards to
service providers — stock options, RSUs, and restricted stock — and
escrows them onchain so that **the chain itself enforces the vesting
schedule**. The escrow layer is **MetaVesT**; the award agreement is
signed in **cyberSign**; the result shows up on your
[cap table](captable.md) like any other position.

A grant is not a cyberCERT. It is a cap-table position on an underlying
stock class (Common or Preferred) whose scrip sits in a vesting escrow.
When the recipient eventually settles — de-scripifying vested shares
back into a registered holding — *that* is when they join the register
of record.

Grants are currently enabled on **Base and Ethereum**.

## The lifecycle

The grants page draws this as a diagram, and it's the right mental
model:

1. **Reserve** (company) — mint shares to the company and scripify them,
   so there is scrip to escrow.
2. **Grant** (company) — record the award on the ledger.
3. **Sign** (grantee) — the recipient e-signs the award in cyberSign.
4. **Escrow** (automatic) — the moment they sign, the scrip is pulled
   from the company wallet into the vesting contract.
5. **Vest** (grantee) — the schedule accrues onchain; the recipient
   withdraws vested shares as they unlock.
6. **Exercise** (options only) — pay the strike in USDC to convert
   vested options into shares.
7. **Settle** (grantee) — de-scripify into a registered holding.

## The three award types

| Type | What it is | What the grantee does |
|---|---|---|
| **RSU / vesting** | Shares vest over time, no purchase price | Vests, then claims the shares |
| **Stock option** | A right to buy shares at a strike price | Vests, pays the strike in USDC to exercise, then claims |
| **Restricted (RSA)** | Shares escrowed up front; the company buys back unvested on early exit | Holds from day one; keeps what vested, is paid for the rest |

## Before your first grant

Two prerequisites, both prompted by the app when missing:

* **Reserve and scripify.** Grants escrow *existing* scrip. **Reserve
  shares** on the grants page walks you through minting the reserve
  (for a stock plan, one jumbo "Corp--Plan" certificate held by the
  company) and scripifying it. When you scripify a class for equity
  awards, mind the **clawback** choice on the
  [scripify form](mainframe.md#enabling-scrip-scripify): a grant whose
  vested shares are meant to be irrevocable cannot escrow into a scrip
  that still has issuer force-transfer, freeze, or burn enabled.
* **An award-agreement template.** **Register award template** uploads
  your award document (one template per award type, since an option
  carries strike fields an RSU doesn't), registers it onchain in one
  transaction, and binds new grants of that type to it. If identical
  content is already registered, adopting it needs no transaction. A
  recipient-specific document can also be pinned to any single grant
  from its Tokenize dialog.

## Creating a grant

**New grant** records the award on the ledger; nothing touches the
chain yet. The form walks through the award type, the recipient and
underlying class, the granting plan (drawing down the plan's pool), the
units, and the schedule: vesting start and end, a cliff in months
(default 12), and an optional lockup that keeps vested shares in escrow
and releases them linearly through a later date.

Paid awards add their economics: the strike or repurchase price in USDC
per share, the post-termination exercise window (default 90 days for
options) or repurchase waiting period, and the option's term expiration
(default ten years). A right-rail preview re-reads the whole form as one
plain sentence describing what the grantee experiences, worth a glance
before you submit.

One choice deserves care: the **issuer override on vested shares**.

* **None (recommended)** — vested shares are irrevocable. Once vested
  and withdrawn, the company has no onchain way to reclaim, freeze, or
  burn them.
* **Issuer keeps force-transfer / freeze / burn** — the company retains
  the scrip's admin override, which reaches even vested, withdrawn
  shares.

Neither mode changes the schedule; unvested shares forfeit on early
termination either way.

The **award agreement** section picks the signing method. **Sign in
cyberSign** is the path that supports onchain escrow today. You can also
**import** a separately signed document (wet ink, DocuSign) or record
**no agreement**, but such grants stay ledger-only until a direct-escrow
path ships; the form says so when you pick them.

**Create grant** issues the award; **Save as draft** stages it without
counting toward anything (issue drafts later from
[Securities status](captable.md#securities-status)).

## Tokenizing: escrowing the award onchain

**Tokenize** on a grant proposes the onchain deal and produces a
cyberSign signing link for the recipient. The dialog runs a **pre-flight
checklist** first — template registered, recipient wallet linked,
matching-class scrip exists, company wallet holds enough of it, plan
reserve tokenized, clawback mode consistent with the scrip's force-ops —
with a fix-it link for anything that fails.

Then the transaction ladder:

1. **Set up grants for this corp** — first grant only; one transaction
   deploys the corp's MetaVesT controller.
2. **Sign as grantor** — a free signature, no gas.
3. **Approve & propose** — two transactions: an ERC-20 approval of the
   scrip to the controller, then the deal proposal.

The result is a signing link scoped to the grantee's wallet. **There is
no email rail by design**: you copy the link and send it to the
recipient yourself. The shares escrow the moment they sign; nothing
moves before that.

Vesting math onchain follows the market convention: nothing vests
before the cliff, the earned portion vests as a lump at the cliff, and
the remainder accrues linearly, per second, to the end date. Withdrawable
at any moment is the lesser of vested and unlocked, minus what's already
withdrawn.

## Running grants day to day

The grants hub lists every award in two groups — **escrowed onchain**
(the chain enforces the schedule) and **ledger only** (tokenize to
escrow) — with the recipient, class, award type, units, vested
percentage, and a stage track from `GRANTED` through `SIGNING` and
`VESTING` to `VESTED`. Each row carries one stage-appropriate primary
action plus a menu:

* **Check status** — after the recipient signs, confirms the escrow
  finalized and stamps it on the ledger.
* **Sync ledger** — mirrors onchain events (exercises, withdrawals,
  buybacks, terminations) into the cap table. Runs automatically once
  when drift is detected.
* **Copy signing link / Open in cyberSign / Vesting chart** —
  navigation and handoff.
* **Void proposal** — kills a signing link that hasn't been signed
  (a free signature plus one transaction); **Re-propose** starts a fresh
  deal, voiding the stale one first.
* **Terminate grant** — the unilateral, irreversible stop, gated behind
  typing the recipient's name. What follows depends on the type: an
  option keeps its post-termination window and then forfeits; an RSA
  stays repurchasable after the waiting period; an RSU's unvested
  shares return to the company immediately.
* **Recover forfeited** (options, after the window closes) and
  **Repurchase unvested** (RSAs) sweep the company's side of a
  termination. Repurchase is two transactions (approve USDC, then buy
  back); the payment waits in the award for the recipient to collect.

## For grant recipients

Recipients don't need a company login. The **my grants** page reads
awards for the connected wallet straight from the chain: connect the
wallet the award was issued to, and every grant appears with its status
(awaiting your signature, vesting, fully vested, terminated), a vested
progress bar, and figures for vested, exercisable, claimable, and
already-claimed shares.

The actions, all from the recipient's own wallet:

* **Review & sign** — opens cyberSign. Nothing escrows until you sign.
* **Claim** — withdraw vested (and unlocked) shares, in part or in
  full.
* **Exercise** (options) — pay the strike in USDC for vested options;
  two transactions (approve, then exercise). Exercised shares stay in
  escrow and are claimed as they unlock. The dialog quotes the exact
  cost from the contract and checks your balance first.
* **Collect** (RSAs) — after a company buyback, the payment sits in the
  award; one transaction collects it.

Deadlines are surfaced on the card: an option's closing exercise window
counts down in days, and a terminated RSA shows the date from which the
company can repurchase. Grants that are fully vested, claimed, and
settled collapse into an archive list.

If you hold positions and certificates too, the same view is embedded in
[My holdings](holders.md).

> **Under the hood.** Each corp gets its own MetaVesT controller,
> deployed once from a factory. An award maps to a MetaVesT allocation
> contract per type (vesting allocation, token option, restricted token
> award) holding [`CyberScrip`](../reference/contracts/CyberScrip.md)
> in escrow, denominated in scrip base units at the class's scrip
> ratio. The award agreement, its template, and any bespoke document
> live in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md),
> the same registry cyberSign uses. Termination and recovery are
> controller calls; exercise and claim are calls on the allocation
> itself.

## Good to know

* **Free vs. gas.** Recording a grant and issuing a draft are ledger
  writes. Grantor and grantee agreement signatures are free. Escrowing,
  claiming, exercising, terminating, and repurchasing are transactions.
* **The option term is a legal term, not an onchain one.** The app
  stops exercise and tokenization after the expiration date you set,
  and the award agreement governs, but MetaVesT does not enforce the
  term onchain yet. The post-termination window, by contrast, does
  flow onchain.
* **Imported and no-agreement grants can't escrow yet.** They live on
  the ledger, fully counted, until the direct-escrow path ships.
* **A signing link is the handoff.** Treat it like the private link it
  is and send it only to the recipient.
