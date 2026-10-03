---
description: Officers, directors, governance documents and board consents for a cyberCORP
---

# The boardRoom

The **boardRoom** is the cyberCORPs app's corporate-authority area:
officers and directors, governance documents, board approvals and the
company's payment destination. It opens from the app sidebar for a
signed-in profile that has one of the company's owner wallets linked
(signing in is the free Authenticate signature). Actions that change the
company still need an owner wallet connected on the company's network.
The company's formation record is in the
[Incorporation Hub](company.md#incorporation-hub).

## Corporate authority

### Add and remove officers

The officers table lists everyone holding officer authority: name,
address, title and contact. **+ add officer** is one transaction. Each
row's action depends on who you are: **resign** on your own entry (or an
entry whose wallet is linked to your account), **remove** on anyone
else's. Adding an officer can fill in their name and contact from their
MetaLeX profile, using only fields they have made public.

The app refuses to remove the last officer or let them resign, because
the last officer is the company's last owner and the company would be
left with no one able to manage it, permanently. Add a successor first.
On a v5 company, the contract revokes a resigning officer's authority
only when the wallet has one roster entry and the standard officer role.
Before it sends a resignation, the app checks both, and that no role
adapter is set for the officer, owner, admin or privileged role, which
could keep authorizing the wallet. If a check fails, it explains why and
sends nothing. If an owner changes your role or an adapter while the
transaction is pending, you can keep authority. After the transaction,
the app reads your role and those adapters again and tells you if you
still hold a role or adapter authority. It does not check other roles.

Removing an owner whose wallet holds the company's
[grants authority](grants.md) does not move that authority. Removal,
resignation, a remove-and-re-add retitle and the cyberCORP transfer all
show a **GRANTS AUTHORITY** warning in that case (and when the app cannot
confirm who holds it), and you must tick **I understand, and want to
remove this owner anyway** to continue. Hand the authority over on the
grants page first if you can.

For a company formed through the app, the officers you named during
formation appear here waiting to be published. A panel lists the people
"waiting to be added onchain", and **Publish officer to roster** writes
each one (name, title and wallet) to the public onchain record, one
transaction per officer. The boardRoom is the only place officers are
published. The Incorporation Hub shows the roster read-only.

### Seat the board of directors

Directors are officers whose title contains "Director" or "Chair", and
the app badges the two separately. The roster comes from titles, with
no separate onchain director role, so a director added here holds the
same onchain authority as any officer. Add only people you intend to
trust with it.

**+ add a director** either promotes an existing officer or adds a new
one:

* **Promote an officer** re-titles them ("CEO" becomes "CEO, Director").
  The app rejects "&" in titles, so use commas or "and". Promoting another
  officer takes two transactions, a remove followed by a re-add. If the
  first mines and the second fails, the app tells you the person is
  temporarily off the roster and offers a one-click retry. You can't
  re-title yourself this way, so another officer must do it.
* **Add a different wallet** adds a new officer with a director title.

**Promote an officer** and **keep as officer** (below) run only on
contract implementations MetaLeX has reviewed. If the app cannot verify
the company's implementation, it says so and sends nothing. **Add a
different wallet** is not subject to that check.

**Remove from board** offers two outcomes. **keep as officer** strips
the board words from the title ("CEO, Director" back to "CEO"), and
**remove from company** removes the entry entirely. A director can also
**resign** from the board, which removes their officer entry.

If someone you named a director during formation was published with a
title that doesn't convey board capacity, the section flags it and
points you to **add a director** to re-title them.

The roster decides who signs [board consents](#board-approvals). With no
director-titled officers, consents route to all officers standing in for
the board.

### Transfer the cyberCORP

**Transfer cyberCORP** is a two-step hand-over. Add the new owner, who
gets full officer control immediately, then either remove yourself to
complete the transfer or close the dialog to stay on as co-owners.
Removing yourself is blocked until the new owner is confirmed on the
roster, so a failed add can't leave the company without an owner.

### Change the payment destination

Investment and agreement proceeds go directly to the company payable
address set at incorporation. **Change address** updates it in one
transaction, behind a two-step confirmation that shows both addresses
and warns that funds sent to the wrong one cannot be recovered. An owner
wallet signs the change. If the connected wallet is not one, the dialog
names the owner wallets to switch to. Use a company-controlled wallet or
multisig as the destination.

## Governance documents

The governance documents archive, backed by the agreement registry,
holds the company's constitutive documents, stock plans, consents and
anything executed in cyberSign. It is also where you put new documents
onchain.

* **Upload PDF**: upload a PDF of up to 75 MB, give it a title and
  classify it from a taxonomy of about fifty document kinds in three
  groups: *constitutional* (certificate of incorporation, bylaws,
  operating agreement, certificate of designation and others), *stock
  plan*, and *other* (shareholders' agreements, voting agreements,
  meeting minutes, registers, good-standing certificates and more). A
  free-text custom type covers anything else. Then list the signers in
  order (you sign first, and must be a current officer of record) and
  review. One free signature plus one transaction creates the agreement
  in the registry with a 30-day signing window. The PDF goes to **public
  IPFS**, and you send the remaining signers their cyberSign links
  yourself. Creating documents is enabled only on networks where the
  registry deployment has been code-reviewed. The archive and linking
  work on every network.
* **Attach existing agreement** links an agreement that already exists
  in the registry to this company's archive. An agreement that does not
  carry this company's signed corp context needs a current officer who
  is a party to it to attest that it is one of the company's governance
  records.
* **archive link** and **reactivate link**, on each row, curate the
  app's association with the document. They change only the app
  database and never touch the registry agreement.

Each row shows the document type; how the document is bound to the
company (*Factory-linked*, *Signed corp context*, *Linked by officer* or
*Legacy workflow*); where it came from (*Formation discovery*, *App
association* or *Board approvals*); a live status (signed, awaiting
signatures, voided or expired); and links to open the PDF or the
agreement in cyberSign. Board consents appear in this list too, and have
their own workflow under [Board approvals](#board-approvals).

If creating a document is interrupted, the dialog tells you what it
knows and does not let you submit twice:

* **BoardRoom link needs recovery** means the registry transaction
  succeeded but the archive link was not saved. Use **Retry BoardRoom
  link**, or copy the agreement ID and use **Attach existing**, which
  then offers **Finish recovery** for that exact agreement.
* **Outcome unknown** means your wallet may have sent the transaction but
  no receipt was confirmed. Do not submit again. **Check chain evidence**
  looks for it, and if it never landed, the dialog lets you reopen the
  same prepared agreement after you confirm that.

## Board approvals

Board approvals put written consents of the board (in lieu of a meeting,
in the §141(f) shape) onchain, and the cap table's issuance flow can gate
on them: before a position covered by a consent is issued or tokenized,
the app checks the consent's status.

**Create issuance consent** (shown when the company has eligible cap
table positions and the network's registry supports it) is a three-step
wizard:

1. **Positions to cover**: pick the cap table positions the consent
   approves. Covering a position that is already issued ratifies it.
2. **Signers**: the roster is fixed. Every director signs, or every
   officer when the board has no directors, because a written consent in
   lieu of a meeting must be unanimous.
3. **Preview and create**: review the generated PDF, then one free
   signature plus one transaction creates the consent in the agreement
   registry with your signature recorded. The dialog warns that the
   document, including stakeholder names and unit counts, goes to public
   IPFS, as every signed agreement document does.

You then send each remaining signer their cyberSign link yourself,
because the app sends no email. The signing window is 60 days, and a consent is
approved when every signer has signed. The app reads a consent's status
live from the chain and never stores it. The archive shows per-consent
signature counts, whether the board or the officers standing in signed
it, and a saved-workflows list for resuming an interrupted consent.

**Record external consent** records a consent executed outside
cyberSign. It first asks what the consent approves:

* **General board action** archives the fully executed PDF without
  linking it to any cap table position. This document-only record does
  not authorize an issuance.
* **Securities issuance** links the PDF to the uncovered positions it
  covers, and the issuance gate treats them as approved on your
  representation.

Both upload the PDF to **public IPFS** behind an explicit
acknowledgment. No transaction is involved and nothing is verified
onchain. The archive badges these records as external.

**Upload signed approval** serves the formation flow. Reached from the
cap table's Securities status queue for one formation-managed draft, it
stores the approval PDF **privately**, off public IPFS, and links it to
that draft. A **Review formation approvals** button appears here when
formation drafts are waiting on one.

Every other consent route publishes its PDF, with names and unit counts,
to public IPFS. If that disclosure is unacceptable for an issuance, keep
the approval in your minute book instead of recording it in the app. The
issuance flow lets you issue a position with no linked consent as an
explicit choice.

## Agreement templates

A status board for the company's registered award-agreement templates
(one per award kind: RSU, option and restricted stock), with a link to
the registration flow in [grants](grants.md).

## Board multisig

A preview panel for a BORG board multisig: signing threshold, treasury
Safe and pending board actions. A cyberCORP has no onchain board
multisig of its own, so the panel shows placeholders until one is
deployed for your company.

> **Under the hood.** Officer and director changes are `addOfficer` and
> `removeOfficer` calls on your
> [`CyberCorp`](../reference/contracts/CyberCorp.md) contract, and
> officer authority is a role in [BorgAuth](../reference/access-control.md).
> The app does not send CyberCorp's in-place `updateOfficer`. v5 has
> it, but a v5 removal keeps any role other than the standard officer
> role, so a pending update could change a different officer's entry.
> A re-title is a remove and a re-add. CyberCorp has no separate onchain
> director tier,
> so the boardRoom reads its director roster from officer titles. Consents are agreements in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md),
> created and signed in one transaction.

## Good to know

* **Titles carry meaning.** The board roster and consent routing key off
  the words "Director" and "Chair" in officer titles, so title people
  deliberately.
* **Most changes here are transactions.** The exceptions are the
  external consent uploads and archiving or reactivating a document
  link, which change only the app database. Message signatures are free.
