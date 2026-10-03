---
description: Raise capital or invest in rounds, from draft to settlement
---

# cyberRAISE — raising and investing

**cyberRAISE** (`cyberraise.metalex.tech`) is the fundraising app. Companies
run rounds here; investors invest here. It is separate from the
[cyberCORPs app](mainframe.md) — **rounds are created and configured in
cyberRAISE.**

This page has two halves: issuers first, then investors.

![cyberRAISE](../.gitbook/assets/webapp/cyberraise-home.png)

---

## For issuers: running a raise

Starting a raise begins with one choice: **how would you like to
structure your raise?**

If you don't have a cyberCORP yet, the flow first walks you through
creating one (the same Network → Legal Identity → Public Profile wizard as
the cyberCORPs app) and then straight into the raise — company and round
are deployed together at the end. You need a legally formed company to
launch a raise; if you don't have one yet, the cyberCORPs app can
[form an LLC or C-Corp for you](mainframe.md#forming-a-new-company-llc-or-c-corp)
first.

A raise setup you resume, or open from a saved draft link, keeps the
company it was started for. If a saved draft is missing something a
later step needs (the company, the round or the template), the form
shows **Complete your raise setup** with a **Continue setup** button
that takes you back to that step; your other answers are kept.

### Planning the financing first (optional)

Above the two structure choices, a **Want help choosing your
financing?** box links to **Open my financing plans**. A financing plan
(*Your financing plan*) is a guided questionnaire in four parts:
*Issuer and financing direction*, *Existing commitments and token
plans*, *Investors and deal process*, and *Terms and preparation*. At
the end it gives a preliminary financing direction and lists what is
still open **Before detailed setup** and **Before execution**. GAIBE,
MetaLeX's AI agent, can walk you through each part (**Discuss with
GAIBE**). When GAIBE proposes a change to your answers, nothing changes
until you accept it.

Plans are private to your account. You sign in to create one, and you
can pick it up again from another device. If you used the entity guide
while forming a company in the cyberCORPs app, **Save and continue my
financing plan** there carries the relevant answers over for you to
confirm. **Save and prepare a fresh financing draft** opens a new raise
setup. There you choose which company the plan is for (*Which company
will use this financing plan?*), confirm it is the issuer the plan
describes, and **Use reviewed round structure** copies one answer into
the setup: ticket-by-ticket or structured round. Everything else you
set in the normal setup steps. The plan is guidance, not legal
clearance.

### Ticket-by-Ticket vs. Structured Round

* **Ticket by Ticket** — you sell securities to investors **one at a time**,
  each on its own terms. There is no shared target or min/max; each “ticket”
  is an individually configured deal. Suited to privately advertised raises
  or geographically restricted (Regulation S) raises.
* **Structured Round** — an automated round with **standardized terms for
  all investors**: a target raise, min/max ticket sizes, and escrowed
  investor bids. Can be public or private.

![The raise-structure choice](../.gitbook/assets/webapp/start-raise.png)

### Configuring a structured round

A structured round is a three-step wizard. Progress saves as you go, and
the header icons let you **save your progress** locally or **save to the
cloud** for a shareable link.

**Step 1 — Initialize the round.** The form collects, in order:

* **Round stage** — the security series (e.g. Pre-Seed), auto-incrementing
  from your last round.
* **Round type** — **Privately Advertised** (invite-only), **Publicly
  Advertised** (listed on the public-rounds Marketplace; investors must be
  accredited via [LeXcheX](lexchex.md)), or **Publicly or Privately
  Advertised — U.S. Excluded** (a Regulation S round: participants prove
  non-U.S.-person status with a passport scan in the zkPassport mobile app,
  unless you manually approve them as an exception — the how-to, and a
  caution about override scope, is
  [zkPassport overrides](ace.md#zkpassport-overrides)). The Reg S option is
  not available on every network.
* **Admission mode** — **First-Come, First-Served** (offers are accepted
  automatically in order, funds escrowed immediately, until the round
  fills) or **Investors Bid / Founders Approve** (you review each bidder —
  their profile, socials, reputation — and choose who gets in and for how
  much).
* **Ticket size** — the minimum and maximum any one investor can invest.
* **Funding target/cap** — a hard cap; the round ends automatically when
  hit.
* **Start and end dates** — or tick **Open ended** to run without an end
  date. (An open-ended founder-approval round automatically makes all
  offers exploding.)
* **Exploding offers** (founder-approval rounds only) — optionally let
  investors send time-limited offers.
* **Closing conditions** — **Allow early close** lets you close the round
  before its scheduled end date or once fully funded. Investors see a
  “may close early” note on the round.
* **Pitch deck** — an optional description and up to three uploaded files.

**Step 2 — Choose the ticket type.** Pick the deal paper: SAFE, SAFT,
SAFTE, or SAFE + Token Warrant, each in Reg D and Reg S variants. Custom
templates approved in the MetaLeX console appear as extra cards, in
structured rounds and ticket-by-ticket raises alike; each card says
whether the template was registered for your company or approved by
MetaLeX for any company. There is also a *Custom* option where you
enter a template name or registry ID agreed with MetaLeX (checked against
the onchain registry). If the series already has an existing line, you
add a **sub-series label** (e.g. “2” to run Series A-2) so the new
round's onchain identifiers stay unique. If the company already has a
cert printer matching the series and deal type, the step says it will be
reused for this round.

**Step 3 — Set up the agreement.** Configure the standard agreement
investors will sign. Submitting opens a **round summary** — network, round
type, admission mode, ticket size, funding cap, valuation, dates, dispute
resolution — and **Confirm & Submit** deploys the round onchain.

Signing the round agreement is a free signature. If the company is being
created in the same flow, your wallet asks for a second free signature
that approves the company's deployment details, which the agreement
signature does not cover. For an existing company, the app reads which
round manager the company uses now and that contract's version, before
you sign and again before the transaction is sent. If the wallet, the
round or the contract changed in between, it stops with “The wallet,
round or contract changed. Review and sign again.” A round manager
reporting a version the app doesn't support is refused rather than
sent.

Filling the forms is free. MetaLeX applies a **0.3% fee to funds claimed by
the issuer**; investors pay nothing, and no fees are charged on rejected
bids. (Forming a new legal entity is a separate, flat-fee product of the
cyberCORPs app — see [the costs overview](README.md#before-you-start-what-you-need).)

> **Under the hood.** A round is created on your cyberCORP's
> [`RoundManager`](../reference/contracts/RoundManager.md). The contract-
> level walkthrough — building the round, taking EOIs, allocating, and
> closing — is the tutorial
> [Run a cyberRAISE round](../tutorials/run-a-cyberraise-round.md).

### Managing your rounds

The **rounds list** for your company shows active and closed rounds, each
with its series, public/private label, structure, raised-vs-target progress,
and a flag when EOIs are waiting for you.

Opening a round shows the **management view** — three summary cards (Round,
Offer, Raised) and, for founder-approval rounds, tables of:

* **Pending Offers** — EOIs awaiting your decision,
* **Exploding Offers** — time-limited offers,
* **Completed Offers** — EOIs you've allocated,
* **Issued Certificates** — the round's issued cyberCERTs, and
* a checkbox to reveal **expired and rejected offers**.

(First-come rounds need no review, so they show completed tickets and
certificates.)

From here you can switch to the **Investor view**, **Edit Pitchdeck**
(requires Authenticating), and — if you enabled early close — **Close
Round**. A round that hasn't raised anything yet can also be **hidden**,
which permanently removes it from public view.

On a **ticket-by-ticket** round, the management view lists pending and
completed tickets, and **Set up a Ticket** starts a new individually
configured deal (a dropdown, if your round has more than one agreement
template). Ticket tables show each ticket's template by name, custom
templates included.

The rounds list and management view end with a link to the company's
**public company page**, which anyone can read without a wallet (see
[Public company pages](metadao.md#public-company-pages)).

### Setting up a ticket for an existing company

A ticket for a company that already exists mints its securities from the
company's cert printers. How the offer gets those printers depends on
the company's contract version (see
[v4 and v5 companies](#v4-and-v5-companies)):

* **v4 companies.** The app reuses the printer that matches each
  certificate's type, series, legal document and payment token. If
  there is none, as with a company's first ticket, the offer creates the
  printers in the same transaction as the offer itself.
* **v5 companies.** Each security in the offer needs a class identity
  and active class terms before the ticket can be signed. The form
  opens **Set up the security for this offer** (or use **Review security
  class setup** to open it yourself). For each certificate, pick the
  **Cap table class or series** it belongs to, or create one (**New
  class name**, **Series name**, **Governing document reference**, then
  **Save class identity**). Then save, approve and activate the class
  terms; these steps need a current officer wallet of the company, and
  **Approve class terms with wallet** is a free signature. Finally link
  a printer: choose a compatible existing one and **Link selected
  printer**, or **Prepare a new printer** and **Deploy reviewed
  printer**, which is a transaction. If the deployment is interrupted,
  paste its transaction hash and **Check transaction and finish
  linking** instead of deploying again. **Return to ticket and sign**
  takes you back to the ticket with your entries intact. Saving the
  class records no position and issues no units; it ties tokenized and
  untokenized positions of that class together in the
  [cap table](captable.md#legal-classes-series-and-versioned-terms).

For a company on any other contract version, the ticket form stays
blocked with “This company's contract version is unknown or
unsupported.” The same rules apply to ACE tickets. Once you have signed
a ticket, a change to its template, the company, the network, the class
terms, the printer or your wallet invalidates the signature and asks you
to review and sign again.

### Reviewing an EOI

**Review** on a pending offer opens the EOI: the investor's profile, bio,
the offer (min–max amount, their message, any expiry), the agreement
details, their trading activity, and their LeXcheX accreditation status.
You then either:

* **Allocate** — for a min–max offer, enter an amount within the range —
  and confirm the onchain transaction that accepts them, or
* **Reject** — confirm the onchain transaction that declines the offer.

An agreement stays with the round manager that finalized it, so
allocation goes to that manager even if the company has since switched
to a new one. Before you confirm, the app checks onchain that this
manager still holds the investor's escrow, unallocated, and that its
contract version is one it supports. When a check fails (the offer is
already allocated, the escrow belongs to another investor, the version
is unsupported) it tells you before you sign, rather than sending a
transaction that would revert.

> **Under the hood.** Allocating an EOI releases the investor's escrowed
> funds to the company and mints their security as a cyberCERT through the
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md). The legal
> agreement each party signs is anchored in the
> [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md).

### Closing a round

**Close Round** is a single transaction. It stops new EOIs immediately; you
can still review and allocate any EOIs already submitted. When a round hits
its cap, the app prompts you to **initialize the next round**.

### Reviewing a term sheet with GAIBE

**Term sheet** in the sidebar, or **Review a term sheet** on the
cyberRAISE home page, opens *Term sheet review*. Upload one financing
term sheet as a PDF (up to about 3 MB) and GAIBE, MetaLeX's AI agent,
reads it and returns a report:

* counts of **Terms identified**, terms that **Need review**, terms
  **Outside / partial** the cap table model, and **Pages cited**;
* **Core terms**: valuation, liquidation preference, participation,
  anti-dilution, board composition and protective provisions. Each is
  marked *Identified*, *Ambiguous* or *Not found*, with what GAIBE
  extracted, quoted evidence with its page number, and a **MetaLeX
  fit** label saying how far the cap table can record it (*Cap table
  supported*, *Partially represented* or *Outside cap table model*);
* **Additional material terms** it found, such as the option pool,
  dividends, pro rata rights or redemption, each with the same fit
  label.

You can copy the report or download it as Markdown. A review can take a
few minutes. Any signed-in user can run one, up to a daily limit per
account. The PDF and the report are not kept and are not added to a
cyberCORP or cap table. The page is marked “AI review — not legal
advice.”: a term GAIBE reports as absent is not necessarily favorable,
and it can miss or misread text, so use the report to focus your review
with counsel.

---

## For investors: investing in a round

### Find a round

Browse **Public Rounds** (the marketplace) — searchable, split into **Open
Rounds** and **Past Rounds**. Only publicly advertised rounds appear here.
Private rounds are reached through a link the issuer shares with you.

![The public-rounds marketplace](../.gitbook/assets/webapp/public-rounds.png)

Opening a round shows its detail page: the company, the security and
series, the round's terms and progress, its eligibility badges, and the
**Invest** or **Express Interest** call to action. The terms panel is
headed by the round's security class, for example *SAFE Details* (or
*Round Details* when the class can't be read). Links to a public round
page and to its express-interest page carry a preview image, so they
show a card when pasted into apps that build link previews.

![A round's public detail page](../.gitbook/assets/webapp/round-detail.png)

If you don't hold a valid [LeXcheX](lexchex.md) accreditation, the list
shows an **“I am investing as:”** card — toggle between *an individual* and
*a legal entity* — explaining the paths to accreditation: LeXcheX
verification, investing above a threshold (\$200k+ individual / \$1M+
entity), or manual verification by a MetaLeX attorney. You'll need one of
these for public U.S. rounds; **Regulation S rounds** instead require a
non-U.S. passport scan via zkPassport.

### Express interest

The *Express Interest* screen (titled *Invest in …* on first-come rounds)
has the form and the legal agreement side by side on desktop; on a phone
you swipe between the two panels. On first visit it opens with a
plain-language notice that this is a legally binding investment, issued
as a tokenized security and countersigned by the company.

![The invest screen, with the deal notice and the agreement alongside](../.gitbook/assets/webapp/express-interest.png)

You provide:

* **Your investor details** — name, contact, investor type, and (if not an
  individual) jurisdiction of formation. These pre-fill from your
  [profile](profile.md) and can be encrypted — the first time you submit,
  a **privacy settings** dialog opens so you choose what is encrypted.
* **Investment amount** — a fixed amount or (in founder-approval rounds
  with a range) a min/max range, within the round's ticket limits and your
  wallet balance.
* an optional **message** to the founder (founder-approval rounds), and
  optionally your own **exploding offer** expiry (24/48/72 hours or a
  custom date).

If the round requires accreditation, you either confirm an existing LeXcheX
credential or mint one here; a Reg S round asks for zkPassport verification
instead.

Then:

1. **Sign the agreement** — a free signature.
2. **Approve the payment token** if needed — an onchain transaction.
3. **Submit** — the onchain transaction that places your EOI.

In a founder-approval round your maximum amount is held in escrow until the
founder accepts your offer or the round closes — any unused remainder is
returned. In a first-come round, accepted investments mint the certificate
without delay. If the issuer enabled early close, the round may end before
its scheduled end date.

Your signature covers the round's terms as they stand when you sign.
Before the token approval and again before submitting, the app reads the
round's company, round manager and terms onchain and simulates the exact
transaction. If the terms changed, the company now uses a different
round manager, or that manager was upgraded to a new major version (v4
to v5, for example) since you signed, it stops with a message such as
“Round terms changed. Review and sign again.” and you sign the current
agreement. An upgrade within the same major version doesn't ask you to
sign again. A round whose manager reports a version the app doesn't
support is refused rather than submitted.

> **Under the hood.** Your EOI is an EIP-712-signed offer recorded on the
> [`RoundManager`](../reference/contracts/RoundManager.md); your funds sit
> in an onchain escrow until the round resolves. The security you receive is
> a **cyberCERT** — a real entry on the company's register, not a receipt.
> See [The dual-token model](../explanation/dual-token-model.md).

### Track it in your Portfolio

**My Portfolio** shows your **pending investments** (EOIs awaiting a
decision, with their expiry), your **closed investments**, the securities
you hold (**Owned Securities**), and any scrip (**Owned Scrips**) —
checkboxes reveal voided, expired, and rejected entries. If an EOI
expires unanswered, **Recall** returns your escrowed funds. From the
portfolio you can also scripify a certificate, transfer certificates and
scrip, request re-certification — those actions are walked through in
[For holders: your securities](holders.md) — and bridge ACE-round tokens
to Solana (see [ACE](ace.md#the-solana-bridge)).

## v4 and v5 companies

Version 5 of the cyberCORPs protocol is live on Ethereum, Base and
Arbitrum, so a company created now, including one created inside a
cyberRAISE flow, is a v5 company. A company created before the upgrade
keeps the version it was deployed with until its owners upgrade it from
the cyberCORPs app's [Upgrade](mainframe.md#upgrade) area. cyberRAISE
supports both, and it reads the version of the specific company and
contract it is about to use instead of assuming one for the whole chain.
An unknown version, or one newer than the app supports, is refused
visibly.

What differs in practice:

* **Structured rounds** are set up, signed, funded and allocated the
  same way on v4 and v5 companies.
* **Tickets for an existing company** differ: on a v4 company the app
  reuses or creates the cert printers as part of the offer, while on a
  v5 company you first choose each security's class and set up its
  terms and printer, as described in
  [Setting up a ticket for an existing company](#setting-up-a-ticket-for-an-existing-company).
* **Upgrades in the middle of a raise.** A signature, the founder's or
  an investor's, is tied to the major version of the manager it was
  given for. If the company upgrades that manager from v4 to v5 before
  the transaction is sent, the app asks for a fresh review and signature
  rather than sending the old one.

To see which version a company runs, open its
[public company page](metadao.md#public-company-pages): *Contracts and
deployed versions* reads each contract's version live and says whether
it matches the reference its factory currently publishes.

## The MetaLeX console (staff)

MetaLeX staff operate a read-only **console** (at `/console` on any of the
app subdomains, gated to an admin allowlist). Its **Raises** explorer lists
every raise on the platform — structured rounds and ticket-by-ticket deals,
across every cyberCORP and chain — with search, filters, and sortable
columns (cyberCORP, round, type, chain, created, participations, progress,
status). Opening a raise shows its full terms, documents, and
participations, including each participation's **signed legal document**
with its parties and signature status. A **cyberCERTs** explorer lists
every issued certificate across the platform, grouped by company. A
**Round templates** page is where staff register and approve custom
templates, for one company or for all, that then appear in the
ticket-type step of structured rounds and ticket-by-ticket raises.

Nothing in the console mutates a raise — it is an inspection surface.

## Good to know

* **MetaLeX never holds your money.** Funds in flight are in an onchain
  escrow with no override — see
  [The role of MetaLeX](../explanation/role-of-metalex.md).
* **Signing the agreement is free; approving the token and submitting are
  transactions.**
* **Your security is real and onchain** — a cyberCERT is the actual register
  entry for your stake.
