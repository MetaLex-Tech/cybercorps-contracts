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
of record. The award type must be declared: a position on an ordinary
class with no award type recorded is a direct holding, and the grant
and MetaVesT actions refuse it rather than assuming an RSU.

Grants are currently enabled on **Base and Ethereum**.

## The lifecycle

The grants page draws this as a diagram, and it's the right mental
model:

1. **Reserve** (company) — mint shares to the company and scripify them,
   so there is scrip to escrow.
2. **Grant** (company) — record the award on the cap table.
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
  that still has issuer force-transfer, freeze, or burn enabled. The
  same form's **Who can scripify** choice, "Only whitelisted
  certificates can be scripified (recommended for private shares)", is
  on by default. It starts the whitelist with the certificates the cap
  table links as the class's plan reserve, so other holders can't turn
  unvested or restricted shares into transferable scrip. A reserve
  certificate minted after the scrip was deployed isn't on the list;
  scripifying it stops with "This certificate isn't on the class's
  scripify whitelist" until an officer adds it in the class's
  **Scripify whitelist** section in the Tokenization Hub. That section
  also turns the whitelist on for scrip deployed before the option
  existed, which starts with it off.
* **An award-agreement template.** **Register award template** uploads
  your award document (one template per award type, since an option
  carries strike fields an RSU doesn't), registers it onchain in one
  transaction, and binds new grants of that type to it. If identical
  content is already registered, adopting it needs no transaction. A
  recipient-specific document can also be pinned to any single grant
  from its Tokenize dialog.

## Creating a grant

**New grant** records the award on the cap table; nothing touches the
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
**no agreement**, but such grants stay on the cap table only until a
direct-escrow path ships; the form says so when you pick them.

**Create grant** issues the award; **Save as draft** stages it without
counting toward anything (issue drafts later from
[Securities status](captable.md#securities-status)).

## Tokenizing: escrowing the award onchain

**Tokenize** on a grant proposes the onchain deal and produces a
cyberSign signing link for the recipient. The dialog runs a **pre-flight
checklist** first — connected as the corp owner, template registered,
recipient wallet linked, matching-class scrip exists, company wallet
holds enough of it, plan reserve tokenized, clawback mode consistent
with the scrip's force-ops, no recorded termination or expired option
term, and an advisory when a transfer-restriction hook will need the
escrow (and later the grantee) allowlisted — with a fix-it link for
anything that fails.

Two checks refuse a grant that could never complete. The recipient's
selected wallet must not be the company wallet that controls grants,
since an award agreement can't have the same wallet on both sides; link
a separate personal wallet for the recipient. And the company's
issuance manager must be a build with the scrip vault and
recertification that let a grantee settle vested scrip into shares; on
an older build the checklist says "Upgrade the company's contracts
before escrowing grants." The grantee's cyberSign page applies the same
settlement check and refuses with "The award can't be created". Before
anything is sent, the app also re-checks on the server that your
signed-in profile is an owner of the corporation.

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
(the chain enforces the schedule) and **awaiting tokenization**
(recorded offchain; tokenize to escrow) — with the recipient, class,
award type, units, vested percentage, and a stage track from `GRANTED`
through `SIGNING` and `VESTING` to `VESTED`, plus per-group subtotal
rows and an all-grants total. Award-shaped positions that came from an
in-app formation sit in a separate **FORMATION-MANAGED** group: they
stay cap table entries, and MetaVesT tokenization is not available for
them. Each row carries one stage-appropriate primary action plus a
menu:

* **Check status** — after the recipient signs, confirms the escrow
  finalized and stamps it on the cap table.
* **Sync cap table** — mirrors onchain events (exercises, withdrawals,
  buybacks, terminations) into the cap table. Runs automatically once
  when drift is detected.
* **Backing certificate…** — for a grant funded from a company-held
  certificate rather than a plan reserve (for a founder, typically a
  certificate in the name of the company FBO the founder), links the
  live certificate of exactly the grant's size whose scrip funds the
  grant. The cap table then counts those shares once, on the grant,
  instead of also as a company holding, and the row notes the nominee
  holding, or warns "⚠ backing cert #N left the company wallet" if the
  certificate moves. **Unlink** reverses it.
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

## The grants authority

Each corp's MetaVesT controller has one **authority**: the wallet that
terminates grants, repurchases unvested shares and funds escrows. The
**Grants authority** panel on the grants page shows the **Controller**
and the **Authority (terminates, repurchases, funds escrows)**, marked
"· connected" when that is your wallet.

When the authority should move to another corp owner, it takes one
transaction from each side:

1. The current authority chooses the new owner under **Hand over to**,
   checks the address against that owner's own record, and clicks
   **Start handover**.
2. The nominee connects their wallet on the same panel, sees the
   handover notice, and clicks **Accept authority**.

The handover refuses while proposals are still waiting for a grantee's
signature, because only the authority that proposed them can void them;
finish or void those first. Only current corp owners can be nominated
or accept. The handover moves control only. Unescrowed reserve scrip,
the scrip allowance to the controller and company-held reserve
certificates stay with the old wallet, so move them to the new
authority and approve the controller from it before funding new grants.
Keep the owner who first set up grants on the corp even after a
handover: the app confirms the controller belongs to the company by
deriving it from that owner, and removing that owner pauses new
proposals and reserve minting until it is restored. The officer
removal, resignation, ownership transfer and board removal forms warn
you with a **GRANTS AUTHORITY** notice, and ask you to tick "I
understand, and want to remove this owner anyway.", when the wallet
being removed holds the authority or set up the controller.

If the authority sits with a wallet that is no longer a corp owner, the
panel shows **GRANTS PAUSED**: "Grants are paused until that wallet
hands the authority to a current owner (or is restored as one)." Grants
also stop, with an explanation in the panel and the Tokenize dialog,
when the company's grant records point at more than one controller or
at one the app can't confirm belongs to the company.

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

Claimed shares arrive in your wallet as scrip. Settling them into a
registered holding is the **De-scripify** step in My Portfolio,
described in
[For holders](holders.md#de-scripify-back-to-the-register).

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

* **Free vs. gas.** Recording a grant and issuing a draft are cap table
  writes. Grantor and grantee agreement signatures are free. Escrowing,
  claiming, exercising, terminating, and repurchasing are transactions.
* **The option term is a legal term, not an onchain one.** The app
  stops exercise and tokenization after the expiration date you set,
  and the award agreement governs, but MetaVesT does not enforce the
  term onchain yet. The post-termination window, by contrast, does
  flow onchain.
* **Imported and no-agreement grants can't escrow yet.** They live on
  the cap table, fully counted, until the direct-escrow path ships.
* **A signing link is the handoff.** Treat it like the private link it
  is and send it only to the recipient.
