---
description: "Form an LLC or incorporate a C-Corp in the cyberCORPs app for a flat $1,000 in USDC, then keep its filings, mail and annual reports in one place"
---

# Form a company

If your company does not exist as a legal entity yet, the cyberCORPs app
(`cybercorps.metalex.tech`) can form it for you. **Form a company** forms
an LLC or incorporates a C-Corporation in one guided, in-app flow, and
creates the company's public onchain record (its cyberCORP) as part of
the same process.

To start, choose **Set up your company** on the app's start screen,
answer **No** to **Has your company already been legally formed?**, and
choose **Form a company**.

* If the company already exists, answer **Yes** and
  [bring it onchain](company.md#bring-an-existing-company-onchain)
  instead. That costs only the network fee.
* If a token launchpad such as MetaDAO or Umia prescribes your entity,
  form it from the launchpad's own flow (see [Launchpads](launchpads.md)).
  This form does not create a launchpad's vehicle.

## What the \$1,000 covers

Formation costs a flat **\$1,000, all inclusive, paid in USDC**. It
covers:

* the state filing and the formation documents;
* filing of the initial tax documents;
* a 30-minute lawyer consultation with @lex\_node on Telegram;
* free lifetime access to the cap table features.

The whole flow runs in the app, with no sales calls. You pay on the
payment chain, Ethereum mainnet, and your wallet shows the network gas
separately. The form states the price only on its final review screen.
Annual reports you file later through the app cost only the state's fee
(see [File annual reports](#file-annual-reports)).

## Save your draft as you go

**Form a company** opens a single long-page form headed **Incorporate
your company**, or **Form your LLC** once you pick an LLC. It gathers
everything the filing and the onchain record need. Nothing is saved
automatically. On a fresh session, a dialog tells you to save with the
disk icon and to keep the session link, which reopens your saved draft in
the same browser.

## Choose an entity with the entity guide

At the top of the form, an **Entity guidance** panel asks **Which entity
fits your plans?** You can work through its questions (**Help me
choose**), talk your plans through with GAIBE, MetaLeX's AI agent
(**Talk to GAIBE first**), or skip to the form (**I already know my
entity type ↓**). The questions cover where the team and the business
are, how you expect to fund the company and capture value, owners and
treasury, and token plans: token holdings, foreign owners, whether a
launchpad will prescribe your structure and when, the proposed sale, and
later token entities. Every question accepts **Not sure yet**.

**Your starting direction** then lists one or more directions. Each
names the role the entity plays, explains why it fits, gives the next
step and recommends a formation state. A venture-backed project is
pointed at a Delaware corporation. Other answers lead to an LLC, an LLC
taxed as a pass-through to hold tokens, or a US nonstock corporation,
which has its own formation process outside this form. When the plan
includes a launchpad that prescribes its own entity structure (the guide
names MetaDAO and Umia), the direction is to follow that launchpad's
onboarding. Depending on your answers, the result adds:

* **Token launch structure and timing**: a staged offshore structure
  (for example a Cayman foundation, with a BVI token issuer evaluated
  later) or the launchpad's prescribed structure, with the sources the
  framework relies on and a cost estimate.
* **Formation state, taxes and additional registrations**: the state
  recommendation, the tax consequences of the choice, and a **One-way
  doors** box listing tax decisions that are expensive or impossible to
  reverse.
* A financing card such as **Prepare your first investment** when you
  plan venture funding or private financing before a token sale. **Save
  and continue my financing plan** saves a private financing plan and
  continues in [cyberRAISE](cyberraise.md).

The guide only advises, and it labels its result "preliminary guidance …
not a legal or tax opinion". The form changes only when you choose **Set
this draft to {state} {C-Corp or LLC} for {role}**, which sets the entity
type and state. If either one changes, the name-search and legal
attestations clear and you make them again.

If your answers call for two companies (an operating corporation and a
treasury LLC), **Prepare the two companies separately** saves one draft
for each in this browser, listed under **My formation orders**. **Talk to
the MetaLeX team ↗** opens a Telegram chat with MetaLeX.

## What the form asks for

The sections, in order:

* **Company**: the entity type (C-Corporation or LLC), the legal name and
  its ending, up to two optional **backup company names**, the state of
  formation, the **Business industry** (picked from the formation
  partner's list) and a **Business Description** of at most 50
  characters, the limit of the IRS EIN application. Backup names are
  saved for manual follow-up, and automated filing submits only the reviewed
  primary name.
* **Responsible party** (mostly private): the IRS responsible party who
  signs the tax paperwork, with the option to also list them as the first
  public officer of the onchain record.
* **Capitalization** (always private): for a C-Corp, the authorized
  share count and par value; for an LLC, the member list, with ownership
  totalling 100%. The share count can be at most 2,147,483,647, the
  formation service's limit.
* **Officer roles**: President, Secretary, Treasurer and Director, each
  defaulting to the responsible party and each optionally listed
  publicly.
* **Proposed initial ownership** (always private): proposed Common Stock
  allocations, saved **encrypted** as a private setup plan. The form
  states that this creates no positions, reserves no shares and promises
  no stock. It pre-stages your cap table for later.
* **Public company record** (always public): the founding wallet, the
  treasury address, the public contact and first public officer, and the
  optional profile. The network is locked to the payment chain, Ethereum
  mainnet.
* A **legal attestation** that the details are accurate and that the
  public values are approved for permanent onchain publication.

### Reuse your profile details

A **Reuse your MetaLeX profile** card in the **Responsible party**
section can fill blank fields (legal name, email, country of residence,
phone and mailing address) from the **Private formation details** saved
in your [profile](profile.md). Nothing is copied until you choose
**Reuse profile details**, and **Undo profile prefill** reverses it.

### Check the company name

For Delaware and a few other states, the form links the state's
business-name database and asks you to attest **"I searched the …
database and my proposed primary name appears available"**. The
attestation resets if you change the name later. For Delaware, a
preflight also catches names that are too long, contain non-printable
characters or use approval-sensitive terms (bank, trust, insurance,
university).

Search results are advisory. The state decides when it reviews the
filing, and you can
[replace a name it rejects](#replace-a-rejected-company-name).

## Review and pay

**Review incorporation** (**Review LLC formation** for an LLC) opens a
**Final review** that groups everything by disclosure (private filing
details, the private setup plan and the public record) and states the
service price: \$1,000 in USDC, with network gas shown separately by your
wallet. **Save and continue** leads to payment.

**Pay 1,000 USDC and start incorporation** (**… and start LLC
formation** for an LLC) asks for two approvals that settle as **one
onchain transaction**:

1. a gasless payment authorization, a free typed-data signature that
   moves no funds by itself;
2. a company-setup transaction that pays the \$1,000 USDC and creates
   your public company record.

The state filing goes to MetaLeX's formation partner, doola, only after
both are verified.

> **Under the hood.** The payment and the company-record deployment are
> one Multicall3 batch: a USDC `transferWithAuthorization` plus the
> factory's `deployCyberCorp`, which execute or revert together. Anyone
> can submit a signed payment authorization, so if yours is mined on its
> own before your batch, the fee (which only ever pays MetaLeX) transfers
> there and the batch reverts on the used nonce without deploying. The
> status page's recovery actions (verify transaction hash, reset payment
> attempt) reconcile exactly this case. See
> [Integrate from a frontend](../how-to/integrate-from-frontend.md).

## Track the order on the Formation Status page

The **Formation Status** page tracks the order. Its **Company formation**
checklist runs from request accepted through state filing, required
signatures, company incorporated (or LLC formed) and EIN issued, to
documents available. The page also holds the signing sessions for IRS
Forms SS-4 and 8821, with **Create fresh signing session**, and
authenticated downloads of your private legal documents. It refreshes
itself while anything is in flight.

**My formation orders**, in the profile dropdown, lists every formation
you have running.

## Continue in the Incorporation Hub and mission control

Once the public company record exists and your profile holds an owner
wallet, the status page opens the
[Incorporation Hub](company.md#incorporation-hub) for you. It keeps you
on the status page while payment, the state submission or replacement
names are pending.

The rest of the setup arrives as tasks in
[mission control](company.md#mission-control):

* publish your selected officers to the onchain roster from the
  [boardRoom](boardroom.md);
* review the **draft** cap table positions created from your private
  setup plan, which are visible but count toward nothing (no stock is
  issued);
* onboard stakeholders who have no wallet yet through invitation links;
* finish each issuance from the cap table's **Securities status** queue
  by reviewing the cash terms, the federal exemption and the board
  approval, then recording it.

Cap table setup opens as soon as the state filing completes, before the
EIN arrives. You can discard a saved setup plan you no longer want at any
time without touching the company or the cap table. The seeded positions
and the Securities status queue are covered in [the cap table](captable.md).

## Read mail, notices and filings from doola

For a company formed through the app, doola provides legal notices, mail
scans and filing records. They appear in the private **Mail, notices &
filings** panel, in the
[Incorporation Hub](company.md#incorporation-hub) and in the
[Documents](company.md#documents) area. The panel is searchable and
filterable by type, and each item has **Open / download ↗**. Only the
account that submitted the formation sees it.

## File annual reports

The Incorporation Hub of a company formed through the app has an
**Annual reports** panel, under **Ongoing compliance**, showing the next
calendar deadline, the last filing and the state's filing requirement.
Mission control also shows notices such as **Annual report due in N
days** or **Annual report overdue** that link to the panel.

1. **Prepare {year} report** opens the report form.
2. **Prepare report and fix fee** saves the report and locks in the state
   fee.
3. Under **Payment and filing confirmation**, pay that fee with **Pay
   \$X state fee** (in USDC on Ethereum mainnet, with no MetaLeX service
   fee), tick the authorization, and choose **Confirm filing with doola**.

A report with no state fee needs only the confirmation. A confirmed
report cannot be replaced.

## Fix a failed filing

A failed formation shows **Formation needs attention** with the reason,
on the status page and in the Incorporation Hub. Until doola accepts the
order, **Edit saved details** reopens the form so you can fix what was
rejected (a business description over 50 characters, for example). Then
choose **Review corrections** and **Save and resubmit filing**. The
company name, entity type, state, share terms and officer selections
stay as recorded, and your payment is reused. **Retry with saved
details** resubmits without changes.

## Replace a rejected company name

If the state rejects every submitted company name, the status page shows
**New company names needed** and lists the names already rejected. Enter
a first-choice replacement and up to two more, then choose **Submit
replacement names**.

The public company record never changes automatically. Once the state
files under a new name, a notice shows the difference, and **Update legal
name with wallet →** opens the
[company profile editor](company.md#edit-the-company-profile), where you
change the onchain name with a transaction.
