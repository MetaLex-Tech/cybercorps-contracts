---
description: Officers, directors, board consents, and the company's formation record
---

# The boardRoom and incorporation records

The **boardRoom** is the cyberCORPs app's corporate-authority hub:
officers and directors, governance documents, board approvals, and the
company's payment destination. Its sibling page, **incorporation**, is
the read-only formation record. Both live in the app sidebar and require
an owner wallet plus the free Authenticate signature.

## Corporate authority

### Officers

The officers table lists everyone holding officer authority: name,
address, title, and contact. **+ add officer** and **remove** are each
one transaction. The app refuses to remove the last officer, because
removing the final owner would permanently brick the corp; add a
successor first.

### The board of directors

Directors are officers whose title contains "Director" or "Chair"; the
roster derives from titles rather than a separate onchain role. Until
the protocol ships a distinct board tier, the app is explicit about what
that means: a seated director holds the same onchain authority as any
officer, so seat only people you intend to trust with it.

**+ seat a director** either promotes an existing officer (re-titling
them, e.g. "CEO" becomes "CEO & Director") or adds a new director
outright. Because there is no onchain title-setter, a promotion is two
transactions, a remove followed by a re-add; if the first mines and the
second fails, the app tells you the person is temporarily off the roster
and offers a one-click retry. You can't change your own seat; another
owner must do it.

Why seat directors at all: the roster determines who signs
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

A read-only list of the onchain agreements attributed to this cyberCORP
on its network: board consents, constitutive documents, stock plans,
anything executed in cyberSign. Each row links the document itself when
its URI is resolvable.

## Board approvals

Board approvals put written consents of the board (in lieu of a
meeting, in the §141(f) shape) onchain, and the cap table's issuance
flow can gate on them: a position covered by a consent checks the
consent's status before it is issued or tokenized.

**New board consent** is a three-step wizard:

1. **Positions to cover** — pick the ledger positions the consent
   approves (covering an already-issued position is ratification).
2. **Signers** — the roster is fixed, not editable: every director
   signs, or every officer when no directors are seated, because a
   written consent in lieu of a meeting is unanimous.
3. **Preview and create** — review the generated PDF, then one free
   signature plus one transaction creates the consent in the agreement
   registry with your signature recorded. The dialog is blunt about
   disclosure: the document, including stakeholder names and unit
   counts, goes to public IPFS, the same posture as every signed
   agreement document.

You then send each remaining signer their cyberSign link yourself; as
everywhere in the app, there is no email rail. The signing window is 60
days, and a consent is approved when every signer has signed. Status
(routing, approved, voided, expired) is derived live from the chain,
never stored.

**Upload signed approval** records a consent executed outside cyberSign:
upload the fully executed PDF (also to public IPFS) and pick the
positions it covers. No transaction is involved and nothing is verified
onchain; the archive badges it as external, and the issuance gate
treats it as approved on your representation.

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

## The incorporation page

**incorporation** is the constitutive register, entirely read-only: the
formation record (legal name, entity type, jurisdiction, dispute
resolution, the cybernation date, treasury address, and the cyberCORP
contract address), the addresses of the onchain suite (BorgAuth,
issuance, deal, and round managers), and the founding documents executed
in cyberSign. It is also where "Incorporate another cyberCORP" lives.

> **Under the hood.** Officer and director changes are calls on your
> [`CyberCorp`](../reference/contracts/CyberCorp.md) contract, and
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
* **Consents are public documents.** Names and unit counts in a consent
  PDF are visible to anyone once on IPFS. If that's a problem for a
  particular issuance, take the approval outside cyberSign and record
  it as external.
* **Everything mutating here is a transaction** except the external
  upload; message signatures are free.
