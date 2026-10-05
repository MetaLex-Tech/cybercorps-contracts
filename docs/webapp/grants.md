---
description: Equity awards with onchain vesting, covering options, RSUs and restricted stock escrowed through MetaVesT
---

# Token grants and onchain vesting

The **grants** area issues equity awards to service providers (stock
options, RSUs and restricted stock) and escrows them onchain in
**MetaVesT**, so the chain enforces the vesting schedule. The recipient
signs the award agreement in **cyberSign**, and the award appears on the
[cap table](captable.md) like any other position. Grants run on Base and
Ethereum mainnet.

A grant is a cap table position on an underlying stock class (Common or
Preferred) whose scrip sits in a vesting escrow. It never becomes a
Ledger Entry Token (LET) of its own: the recipient becomes a registered
holder only when they convert vested scrip back into a LET. The award
type must be recorded. A position on an ordinary class with no award
type is a direct holding, and the grant and MetaVesT actions refuse it
instead of assuming an RSU.

## The lifecycle

The grants page draws this lifecycle as a diagram:

1. **Reserve** (company): mint shares to the company and scripify them,
   so there is scrip to escrow.
2. **Grant** (company): record the award on the cap table.
3. **Sign** (grantee): the recipient e-signs the award in cyberSign.
4. **Escrow** (automatic): when they sign, the scrip moves from the
   company wallet into the vesting contract.
5. **Vest** (grantee): the schedule accrues onchain, and the recipient
   withdraws vested shares as they unlock.
6. **Exercise** (options only): the recipient pays the strike in USDC to
   convert vested options into shares.
7. **Settle** (grantee): the recipient converts the scrip back into a
   LET, a registered holding.

| Award type | What it is | What the grantee does |
|---|---|---|
| **RSU / vesting** | Shares vest over time, with no purchase price | Vests, then claims the shares |
| **Stock option** | A right to buy shares at a strike price | Vests, pays the strike in USDC to exercise, then claims |
| **Restricted (RSA)** | Shares escrowed up front, with unvested shares bought back by the company on early exit | Holds from day one, keeps what vested and is paid for the rest |

## Before your first grant

The app prompts for both prerequisites when they are missing.

**Reserve and scripify.** Grants escrow scrip that already exists.
**Reserve shares** on the grants page walks you through minting the
reserve (for a stock plan, one "Corp--Plan" LET held by the company) and
scripifying it. The scripify form is described on the
[Tokenization Hub](tokenization-hub.md) page, and two of its choices
matter for grants:

* A grant that promises irrevocable vested shares cannot escrow into
  scrip that keeps the issuer's force-transfer, freeze and burn
  override. Turn on the **No clawback** switch when you scripify a class
  for such grants.
* The **Who can scripify** whitelist is on by default and starts with the
  LETs the cap table links as the class's plan reserve, so other holders
  cannot turn unvested or restricted shares into transferable scrip. A
  reserve LET minted after the scrip was deployed is not on the list, and
  scripifying it stops with "This certificate isn't on the class's
  scripify whitelist" until an officer adds it in the class's
  **Scripify whitelist** section of the Tokenization Hub.

**An award-agreement template.** **Register award template** uploads your
award document, registers it onchain in one transaction, and binds new
grants of that award type to it. Each award type needs its own template,
because an option carries strike fields an RSU does not. Adopting
identical content that is already registered needs no transaction. You
can also pin a recipient-specific document to a single grant from its
Tokenize dialog.

## Create a grant

**New grant** records the award on the cap table without touching the
chain. The form asks for the award type, the recipient and underlying
class, the granting plan (drawing down its pool), the units, and the
schedule: vesting start and end, a cliff in months (12 by default), and
an optional lockup that keeps vested shares in escrow and releases them
linearly through a later date.

Paid awards add the strike or repurchase price in USDC per share, the
post-termination exercise window (90 days by default for options) or the
repurchase waiting period, and the option's term expiration (ten years
by default). A preview beside the form restates it as one sentence about
what the grantee experiences.

The **issuer override on vested shares** needs a deliberate choice:

* **None (recommended)**: vested shares are irrevocable. Once they vest
  and are withdrawn, the company has no onchain way to reclaim, freeze or
  burn them.
* **Issuer keeps force-transfer / freeze / burn**: the company keeps the
  scrip's admin override, which reaches even vested, withdrawn shares.

Neither choice changes the schedule, and unvested shares forfeit on early
termination either way.

The **award agreement** section picks the signing method. **Sign in
cyberSign** is the method that supports onchain escrow. You can instead
**import** a separately signed document (wet ink, DocuSign) or record
**no agreement**. Those grants stay offchain cap table positions that
cannot be escrowed, and the form says so when you pick them.

**Create grant** issues the award. **Save as draft** stages it without
counting toward anything, to issue later from
[Securities status](captable.md#securities-status).

## Escrow a grant onchain

**Tokenize** on a grant proposes the onchain deal and produces a
cyberSign signing link for the recipient. A **pre-flight checklist**
runs first, with a fix-it link for anything that fails:

* you are connected as the corp owner;
* the template is registered and the recipient wallet is linked;
* scrip of the matching class exists, and the company wallet holds enough
  of it;
* the plan reserve is tokenized;
* the clawback mode is consistent with the scrip's override;
* no termination is recorded and the option term has not expired;
* an advisory, when a transfer-restriction hook will need the escrow (and
  later the grantee) allowlisted.

Two checks refuse a grant that could never complete. The recipient's
selected wallet must differ from the company wallet that controls grants,
because an award agreement cannot have the same wallet on both sides.
Link a separate personal wallet for the recipient. The company's
issuance manager must also be a build with the scrip vault and
recertification that let a grantee settle vested scrip into shares. On
an older build the checklist says "Upgrade the company's contracts
before escrowing grants.", and the grantee's cyberSign page applies the
same check and refuses with "The award can't be created". Before
anything is sent, the server also re-checks that your signed-in profile
is an owner of the corporation.

Then come the transactions:

1. **Set up grants for this corp**, for the first grant only: one
   transaction deploys the corp's MetaVesT controller.
2. **Sign as grantor**: a free signature.
3. **Approve & propose**: two transactions, an ERC-20 approval of the
   scrip to the controller and then the deal proposal.

The result is a signing link scoped to the grantee's wallet. The app
sends no email, so copy the link and send it to the recipient yourself.
Nothing moves until they sign, and the shares escrow when they do.

Onchain vesting follows the market convention. Nothing vests before the
cliff, the earned portion vests as a lump at the cliff, and the rest
accrues linearly, per second, to the end date. At any moment the
recipient can withdraw the lesser of vested and unlocked shares, minus
what they already withdrew.

## Manage grants

The grants hub lists every award in two groups: **escrowed onchain**,
where the chain enforces the schedule, and **awaiting tokenization**, for
awards recorded offchain that you tokenize to escrow. Each row shows the
recipient, class, award type, units, vested percentage and a stage track
from `GRANTED` through `SIGNING` and `VESTING` to `VESTED`, with
per-group subtotals and an all-grants total. Award-shaped positions from
an in-app formation sit in a separate **FORMATION-MANAGED** group. They
stay cap table entries, and MetaVesT tokenization is not available for
them.

Each row has one primary action for its stage, plus a menu:

* **Check status**: after the recipient signs, confirms that the escrow
  finalized and stamps it on the cap table.
* **Sync cap table**: mirrors onchain events (exercises, withdrawals,
  buybacks, terminations) into the cap table. It runs once automatically
  when drift is detected.
* **Backing certificate…**: for a grant funded from a company-held LET
  instead of a plan reserve (for a founder, typically a LET in the name
  of the company FBO the founder), links the live LET of exactly the
  grant's size whose scrip funds the grant. The cap table then counts
  those shares once, on the grant, and the row notes the nominee holding
  or warns "⚠ backing cert #N left the company wallet" if the LET moves.
  **Unlink** reverses it.
* **Copy signing link**, **Open in cyberSign** and **Vesting chart**:
  navigation and handoff.
* **Void proposal**: cancels a signing link that has not been signed (a
  free signature plus one transaction). **Re-propose** voids the stale
  deal and starts a fresh one.
* **Terminate grant**: the unilateral, irreversible stop, confirmed by
  typing the recipient's name. An option keeps its post-termination
  window and then forfeits, an RSA stays repurchasable after the waiting
  period, and an RSU's unvested shares return to the company at once.
* **Recover forfeited** (options, after the window closes) and
  **Repurchase unvested** (RSAs) sweep the company's side of a
  termination. Repurchase is two transactions (approve USDC, then buy
  back), and the payment waits in the award for the recipient to
  collect.

## The grants authority

Each corp's MetaVesT controller has one **authority**, the wallet that
terminates grants, repurchases unvested shares and funds escrows. The
**Grants authority** panel on the grants page shows the **Controller**
and the **Authority (terminates, repurchases, funds escrows)**, marked
"· connected" when the authority is your wallet.

Moving the authority to another corp owner takes one transaction from
each side:

1. The current authority picks the new owner under **Hand over to**,
   checks the address against that owner's own record, and clicks
   **Start handover**.
2. The nominee connects their wallet on the same panel, sees the
   handover notice, and clicks **Accept authority**.

The handover is refused while proposals still wait for a grantee's
signature, because only the authority that proposed them can void them,
so finish or void those first. Only current corp owners can be nominated or
accept. The handover moves control only. Unescrowed reserve scrip, the
scrip allowance to the controller and company-held reserve LETs stay
with the old wallet, so move them to the new authority and approve the
controller from it before funding new grants.

Keep the owner who first set up grants on the corp after a handover. The
app confirms that the controller belongs to the company by deriving it
from that owner, and removing the owner pauses new proposals and reserve
minting until it is restored. The officer removal, resignation,
ownership transfer and board removal forms show a **GRANTS AUTHORITY**
notice, and ask you to tick "I understand, and want to remove this owner
anyway.", when the wallet being removed holds the authority or set up the
controller.

If the authority sits with a wallet that is no longer a corp owner, the
panel shows **GRANTS PAUSED**: "Grants are paused until that wallet
hands the authority to a current owner (or is restored as one)." Grants
also stop, with an explanation in the panel and in the Tokenize dialog,
when the company's grant records point at more than one controller or at
one the app cannot confirm belongs to the company.

## For grant recipients

Recipients need no company login. The **my grants** page reads awards
for the connected wallet straight from the chain. Connect the wallet the
award was issued to, and each grant appears with its status (awaiting
your signature, vesting, fully vested, terminated), a vested progress
bar, and figures for vested, exercisable, claimable and already-claimed
shares.

All actions run from the recipient's own wallet:

* **Review & sign** opens cyberSign. Nothing escrows until you sign.
* **Claim** withdraws vested and unlocked shares, in part or in full.
* **Exercise** (options) pays the strike in USDC for vested options, in
  two transactions (approve, then exercise). Exercised shares stay in
  escrow and are claimed as they unlock. The dialog quotes the exact cost
  from the contract and checks your balance first.
* **Collect** (RSAs) collects, in one transaction, the payment a company
  buyback left in the award.

Claimed shares arrive in your wallet as scrip. To turn them into a
registered holding, convert them back into a LET from My Portfolio (see
[For holders](holders.md#convert-scrip-back-into-a-let)).

Each card shows its deadlines: an option's closing exercise window counts
down in days, and a terminated RSA shows the date from which the company
can repurchase. Grants that are fully vested, claimed and settled move to
an archive list. If you also hold positions and LETs, the same view is
embedded in [My holdings](holders.md).

> **Under the hood.** Each corp gets its own MetaVesT controller,
> deployed once from a factory. An award maps to a MetaVesT allocation
> contract for its type (vesting allocation, token option, restricted
> token award) that holds [`CyberScrip`](../reference/contracts/CyberScrip.md)
> in escrow, denominated in scrip base units at the class's scrip ratio.
> The award agreement, its template and any bespoke document live in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md),
> the registry cyberSign uses. Termination and recovery are controller
> calls, and exercise and claim are calls on the allocation.

## Good to know

* **Recording is free, and moving scrip costs gas.** Recording a grant and
  issuing a draft are cap table writes, and the grantor's and grantee's
  agreement signatures are free. Escrowing, claiming, exercising,
  terminating and repurchasing are transactions.
* **The app and the agreement enforce the option term.** The app stops
  exercise and tokenization after the expiration date you set, and the
  award agreement governs, but MetaVesT does not enforce the term
  onchain. The post-termination window does go onchain.
* **Imported and no-agreement grants stay offchain.** They count fully
  on the cap table but cannot be escrowed.
* **Treat a signing link as private.** Send it only to the recipient.
