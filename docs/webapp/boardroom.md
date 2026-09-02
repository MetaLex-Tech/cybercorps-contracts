---
description: Officers, directors, board consents, and the company's formation record
---

# The boardRoom and company records

The **boardRoom** is the cyberCORPs app's corporate-authority hub:
officers and directors, governance documents, board approvals, and the
company's payment destination. Its sibling page, **company record**, is
the formation record. Both live in the app sidebar and require an owner
wallet plus the free Authenticate signature.

## Corporate authority

### Officers

The officers table lists everyone holding officer authority: name,
address, title, and contact. **+ add officer** is one transaction; each
row's action depends on who you are — **resign** on your own entry (or
an entry whose wallet is linked to your account), **remove** on someone
else's. Adding an officer can auto-fill their name and contact from
their MetaLeX profile — only fields they have made public. The app
refuses to remove (or let resign) the last officer, because removing the
final owner would permanently brick the corp; add a successor first.

For a company formed through the app, the officers you named during
formation appear here waiting to be published: a panel lists the people
"waiting to be added onchain," and **Publish officer to roster** writes
each one — name, title, and wallet — to the public onchain record, one
transaction per officer. The boardRoom is the single place officers get
published; the company record page shows the roster read-only.

### The board of directors

Directors are officers whose title contains "Director" or "Chair" (the
app badges the two separately); the roster derives from titles rather
than a separate onchain role. Until the protocol ships a distinct board
tier, the app is explicit about what that means: a director added here
holds the same onchain authority as any officer, so add only people you
intend to trust with it.

**+ add a director** either promotes an existing officer (re-titling
them — "CEO" becomes "CEO, Director"; the app rejects "&" in titles,
use commas or "and") or adds a new director outright. The protocol now
has an in-place `updateOfficer` title-setter, and the app supports it —
but only for changing your *own* entry, and only on contract versions
MetaLeX has reviewed for it, which no deployed cyberCORP is on yet. So
today a promotion of another officer is still two transactions, a
remove followed by a re-add; if the first mines and the second fails,
the app tells you the person is temporarily off the roster and offers a
one-click retry. Under that two-step flow you can't re-title yourself;
another officer must do it.

**Remove from board** offers two outcomes: **keep as officer** (strips
the board words from the title — "CEO, Director" back to "CEO") or
**remove from company** entirely. A director can also **resign** from
the board themselves, which removes their officer entry.

If someone you named a director during formation was published with a
title that doesn't convey board capacity, the section flags it and
points you at **add a director** to re-title them.

Why add directors at all: the roster determines who signs
[board consents](#board-approvals). With no director-titled officers,
consents route to all officers standing in for the board.

### Transferring the cyberCORP

**Transfer cyberCORP** is a two-step hand-over: add the new owner (they
get full officer control immediately), then either remove yourself to
complete the transfer or close the dialog to stay on as co-owners. The
removal is blocked until the new owner is confirmed on the roster, so a
failed add can't strand the company ownerless.

### Company payment destination

Investment and agreement proceeds are sent directly to the company
payable address set at incorporation. **Change address** updates it in
one transaction, behind a two-step confirm that shows both addresses and
warns that funds sent to the wrong one cannot be recovered. Use a
company-controlled wallet or multisig.

## Governance documents

The registry-backed archive of the company's governance paperwork —
constitutive documents, stock plans, consents, anything executed in
cyberSign — and, now, the place to put new ones onchain:

* **New governance document** — upload a PDF (up to 75 MB), give it a
  title, and classify it from a taxonomy of about fifty document kinds in
  three groups — *constitutional* (certificate of incorporation, bylaws,
  operating agreement, certificate of designation, and the rest),
  *stock plan*, and *other* (shareholders' agreements, voting
  agreements, meeting minutes, registers, good-standing certificates…),
  with a free-text custom type as the escape hatch. You then list the
  signers in order (you sign first, and must be a current officer of
  record), review, and one free signature plus one transaction creates
  the agreement in the registry with a 30-day signing window. The PDF
  goes to **public IPFS**. Remaining signers get cyberSign links you
  send yourself. Creating documents is enabled per network only where
  the registry deployment has been code-reviewed; the archive and
  linking work everywhere.
* **Attach existing agreement** — link an agreement that already exists
  in the registry to this company's archive (an agreement created
  before this feature needs an explicit officer attestation).
* Per-row actions **archive link** / **reactivate link** curate the
  app-side association — database-only, the registry agreement itself
  is never changed.

Each row shows the document type, how the document is bound to the
company (factory-linked, signed corp context, linked by an officer, or
legacy), where it came from (formation discovery, app association, or
board approvals), a live status (signed, awaiting signatures, voided,
expired), and links to open the PDF or the agreement in cyberSign.
Board consents appear in this list too — see the next section for their
dedicated workflow.

## Board approvals

Board approvals put written consents of the board (in lieu of a
meeting, in the §141(f) shape) onchain, and the cap table's issuance
flow can gate on them: a position covered by a consent checks the
consent's status before it is issued or tokenized.

**Create issuance consent** (shown when the company has eligible
cap-table positions and the network's registry supports it) is a
three-step wizard:

1. **Positions to cover** — pick the ledger positions the consent
   approves (covering an already-issued position is ratification).
2. **Signers** — the roster is fixed, not editable: every director
   signs, or every officer when no directors are on the board, because a
   written consent in lieu of a meeting is unanimous.
3. **Preview and create** — review the generated PDF, then one free
   signature plus one transaction creates the consent in the agreement
   registry with your signature recorded. The dialog is blunt about
   disclosure: the document, including stakeholder names and unit
   counts, goes to public IPFS, the same posture as every signed
   agreement document.

You then send each remaining signer their cyberSign link yourself; as
everywhere in the app, there is no email rail. The signing window is 60
days, and a consent is approved when every signer has signed. Status is
derived live from the chain, never stored — the archive shows live
per-consent signature counts, whether the board or the officers standing
in signed it, and a saved-workflows list that lets you resume an
interrupted consent.

**Record external consent** records a consent executed outside
cyberSign. It first asks what the consent approves:

* **General board action** — archives the fully executed PDF without
  linking it to any cap-table position. A document-only record; it does
  not authorize an issuance.
* **Securities issuance** — links the PDF to the uncovered positions it
  covers, and the issuance gate treats them as approved on your
  representation.

Both upload the PDF to **public IPFS** behind an explicit
acknowledgment. No transaction is involved and nothing is verified
onchain; the archive badges these as external.

**Upload signed approval** is a third, narrower rail used by the
formation journey: reached from the cap table's Securities status queue
for one specific formation-managed draft, it stores the approval PDF
**privately** (not on public IPFS) and links it to that draft. A
**Review formation approvals** button appears here when formation
drafts are waiting on one.

## Agreement templates

A status board for the corp's registered award-agreement templates (one
per award kind: RSU, option, restricted stock), with a link to the
[registration flow](grants.md#before-your-first-grant) on the grants
side.

## Board multisig

A preview surface for the coming BORG board multisig: signing
threshold, treasury Safe, and pending board actions. A generic cyberCORP
today has no onchain board multisig, so the panel shows placeholders
until one is deployed for your company.

## The company record page

**company record** (formerly *incorporation*) is the constitutive
register: the public formation record (legal name, entity type,
jurisdiction, dispute resolution, the cybernation date, treasury
address, and the cyberCORP contract address), the addresses of the
onchain suite (BorgAuth, issuance, deal, and round managers), and the
founding documents executed in cyberSign. For a company formed through
the app it also carries the **private** state formation record — filing
status, filing date and number, EIN, and required signatures. The
officer roster shows here read-only, with a **Manage officers in
boardRoom →** hand-off.

> **Under the hood.** Officer and director changes are calls on your
> [`CyberCorp`](../reference/contracts/CyberCorp.md) contract —
> `addOfficer` / `removeOfficer`, plus the newer `updateOfficer` the app
> adopts per contract version as MetaLeX reviews each deployment — and
> authority is the flat officer role in
> [BorgAuth](../reference/access-control.md); there is no separate
> onchain director tier yet. Consents are agreements in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md)
> created and signed in one transaction. The formation record reads the
> state your deploy transaction wrote; see
> [Incorporate a cyberCORP](../tutorials/incorporate-a-cybercorp.md).

## Good to know

* **Titles carry meaning.** The board roster and consent routing key
  off the word "Director" in officer titles, so title people
  deliberately.
* **Consents are public documents** — with one exception. cyberSign
  consents and recorded external consents publish the PDF to public
  IPFS, so names and unit counts are visible to anyone. The exception
  is the formation journey's **Upload signed approval**, which stores
  its PDF privately. If public disclosure is unacceptable for a
  particular issuance, keep the approval in your minute book rather
  than recording it in the app; the issuance flow lets you issue a
  position with no linked consent as an explicit choice.
* **Everything mutating here is a transaction** except the external
  uploads and the archive/reactivate of a document link (database-only);
  message signatures are free.
