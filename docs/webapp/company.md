---
description: "Bring an existing company onchain and run it in the cyberCORPs app: mission control, the Incorporation Hub, Documents, the public company page and v5 upgrades"
---

# Run your company

The cyberCORPs app (`cybercorps.metalex.tech`) is where founders and
officers run a company once it has a cyberCORP, its public onchain
company record. With a company selected, a sidebar on the left lists its
areas:

* **mission control** shows what is true about the company now and what needs action.
* **Incorporation Hub** holds the onchain formation record and founding documents.
* **Documents** collects formation mail, notices and filings, with links to boardRoom and cyberSign.
* **boardRoom** manages officers, governance documents and board approvals.
* **capTable** shows tokenized and untokenized positions in one cap table.
* **grants** manages equity awards (options, RSUs, restricted stock) with onchain vesting.
* **cyberRaise** opens your raises in [cyberRAISE](cyberraise.md).
* **Tokenization Hub** configures, issues and manages the company's LETs and scrip.
* **cyberSign** opens MetaLeX's signing app, where you sign and countersign the company's agreements.

Hovering a sidebar item shows a short description of the area. The
larger areas have their own guides: [the boardRoom](boardroom.md),
[the cap table](captable.md) and its
[records, modeling and compliance tools](captable-tools.md),
[grants](grants.md), the [Tokenization Hub](tokenization-hub.md) and
[cyberSign](cybersign.md). Fundraising rounds are created and run in
[cyberRAISE](cyberraise.md).

Stakeholders join through invitation links from the cap table's
**Invitations** panel. Claiming one attaches the stakeholder's wallet to
their record and opens **My holdings**, where they see their own
positions, Ledger Entry Tokens (LETs), documents and grants.
[For holders](holders.md) covers that side of the app.

## Bring an existing company onchain

**Set up your company** on the app's start screen leads to one
question: **Has your company already been legally formed?** (as a
Delaware corporation, an LLC and so on).

* **Yes**: **Set up existing company on MetaLeX** brings the company
  onchain free of charge, apart from the network fee. One wallet
  transaction creates its public onchain company record, through the
  wizard below.
* **No**: **Form a company** forms an LLC or C-Corp for a flat \$1,000
  in USDC and creates the onchain record as part of the process. See
  [Form a company](formation.md).

The setup wizard has three steps and saves your progress as you go.

![Step 1 of the wizard: Network & Treasury Setup](../.gitbook/assets/webapp/cybercorps-create-network.png)

1. **Network**: under **Network & Treasury Setup**, choose the chain
   (Ethereum, Arbitrum or Base) and the *payable address* that receives
   payments for the company. A Safe multisig is recommended, and an
   auto-fill button can insert your connected wallet.
2. **Legal Identity**: the **Founder identity** gives the founder or
   officer's name and title. It is always public, and the founder's
   address holds the company's primary admin authority. **Identity** gives the
   cyberCORP name, a primary contact (Telegram, X, email or phone), the
   legal entity type and the jurisdiction of formation.
3. **Public Profile**: a description, a profile image, and website,
   whitepaper and document links.

**Deploy cyberCORP** sends the onchain transaction. When it confirms,
the company exists onchain.

> For the onchain records to be the company's securities ledger, the
> company's governing documents must designate the onchain system as that
> ledger. MetaLeX provides templates for this. Involve your counsel.

> **Under the hood.** **Deploy cyberCORP** calls the protocol's
> [`CyberCorpFactory`](../reference/factories.md), which deploys your
> [`CyberCorp`](../reference/contracts/CyberCorp.md) contract, its
> issuance, deal and round managers, and a `BorgAuth` access-control
> contract in one transaction. The founder identity address becomes an
> officer in [BorgAuth](../reference/access-control.md). The
> contract-level walkthrough is
> [Incorporate a cyberCORP](../how-to/incorporate-a-cybercorp.md), and
> [Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md)
> explains how the chain can be the securities ledger.

To add another company later, use **Form a new company** in the
Incorporation Hub, or **Setup your cyberCORP** in the cyberCORP
selector, which restarts the onboarding choice.

## mission control

**mission control** shows the live company record: a compact identity
strip at the top and, below it, an **Operations** dashboard built from the
same data as the cap table. A badge counts the open tasks and jumps to
the **Tasks and reminders** card, which collects what needs action:

* **Contract upgrades.** When any of the company's contracts differs
  from the reference implementation its factory publishes, the first
  task reads **Contract upgrade available** (or **N contract upgrades
  available**), names the contracts and opens the Upgrade page. This is
  how an existing company's owners learn that a newer protocol release,
  such as v5, is available to them. If the company runs v5 and older
  contracts side by side, the task reads **Finish the v5 upgrade** and
  shows as a blocking task, because deals, rounds and issuance are
  paused until the upgrade is complete. If the app cannot run the
  upgrade for the company, the task reads **Contract upgrade needs
  MetaLeX** and gives the reason. See
  [Upgrade an existing company to v5](#upgrade-an-existing-company-to-v5).
* **LET contract migrations.** After the upgrade, **Migrate N LET
  contracts after the v5 upgrade** stays open until each upgraded LET
  contract has its holder counters, legal-owner index and holder tally,
  and **Set acquisition and issue dates of pre-upgrade lots** stays open
  until those dates are set. Both open the Upgrade page.
* **Formation steps.** A formation in progress surfaces here (payment,
  filing, signatures, replacement company names, officer publishing and
  setup steps) until it is complete. See [Form a company](formation.md).
* **Annual reports.** For a company formed through the app, notices
  such as **Annual report due in N days** or **Annual report overdue**
  link to the [annual reports](formation.md#file-annual-reports) panel.
* **Cap table and compliance.** Failed cap table checks, draft
  securities waiting, valuation (FMV) and 83(b) reminders, project-token
  setup, and stakeholders not yet onboarded.

If a live check cannot be read, the list starts with **Some live checks
are unavailable**. Reload before relying on the dashboard, because the
app never treats unreadable data as clear.

A brand-new company, with no stakeholders or positions, first gets a
grid of setup cards: **Start or manage a cyberRaise** (which opens
[cyberRAISE](cyberraise.md)), **Open Tokenization Hub**, **Manage your
capTable** and **Enter the boardRoom**. On smaller screens, where the
sidebar is hidden, the grid adds cards for the Incorporation Hub, grants
and cyberSign and doubles as the app's navigation. Once the company has
a record, those destinations live in the sidebar and mission control
leads with the record itself.

## Search the app

The **Search** button in the header, or Ctrl+K / ⌘K, searches the app's
pages and, for a company your profile owns, its stakeholders and cap
table positions.

## Incorporation Hub

The **Incorporation Hub** is the company's formation record. For a
company formed through the app, it combines the private state filing
with the public onchain record. For any other company, it shows the
public record and the founding documents. Its header links to **My
formation orders** and **Form a new company**. It holds:

* **Company identity**: the legal name, entity type and jurisdiction
  from the formation order.
* **State formation record** (private, for a company formed through the
  app): the overall status, the state filing status, the filing date and
  number, the EIN, and any **Required signatures** (IRS Form SS-4 or
  8821, each with **Review and sign**). Failure and name notices from the
  formation appear above it (see
  [Fix a failed filing](formation.md#fix-a-failed-filing)).
* **Public company record** (onchain, public): the legal name, entity
  type, jurisdiction, dispute-resolution method, the date the company
  went onchain, the contact, the treasury (company payable) address, and
  the addresses of the company's contracts (cyberCORP, BorgAuth, and the
  issuance, deal and round managers), each linked to a block explorer.
* A read-only officer roster with a **Manage officers in boardRoom →**
  hand-off. Officers are added, removed and published in the
  [boardRoom](boardroom.md).
* **Mail, notices & filings** (private), for a company formed through
  the app. See
  [Read mail, notices and filings from doola](formation.md#read-mail-notices-and-filings-from-doola).
* **Annual reports**, under **Ongoing compliance**, for a company formed
  through the app. See [File annual reports](formation.md#file-annual-reports).
* **Public onchain agreements**: the agreements permanently published to
  the company record at formation.

A company formed through the app with no saved ownership proposal also
gets a **Start your cap table** card here, which points to
[the cap table](captable.md).

> **Under the hood.** The public record shows the state your deploy
> transaction wrote to the company's contracts. See
> [Incorporate a cyberCORP](../how-to/incorporate-a-cybercorp.md).

## Documents

The **Documents** area gathers the company's document stores in one
place:

* **Mail, notices & filings**: the same private panel as in the
  Incorporation Hub.
* **Governance documents**: **Open governance documents** goes to the
  boardRoom's registry-backed
  [governance documents](boardroom.md#governance-documents) archive.
* **Sign with cyberSign**: **Open cyberSign ↗** opens MetaLeX's signing
  app. An existing agreement's own signing link opens that agreement.

The page also shows **Formation documents** and **Standalone templates**
cards. Document preparation and templates are not enabled in the
production app, and both cards say so. The formation card links to the
Incorporation Hub for filing status and company records.

## Edit the company profile

The **edit profile** link in mission control's identity strip opens the
**admin** area. Its top half is the **public profile** (description,
image and links), saved without a transaction. Below it, **onchain
details** lets an owner update the cyberCORP name, the payable address
and the officer roster. Each of those changes is an onchain transaction
sent from an owner wallet. Removing an officer whose wallet holds the
company's grants authority shows a warning you must acknowledge first.
The [grants guide](grants.md) explains the grants authority.

## Public company pages

Every cyberCORP has a **public company page** that anyone can read
without a wallet or an account, at
`cybercorps.metalex.tech/company/{chainId}/{address}`. Token holders can
use it to check the entity behind a project. It shows what the chain and
the public MetaLeX indexer record, and every address links to a block
explorer so you can check it yourself:

* **Entity**: the entity type and jurisdiction the company recorded
  onchain at formation (not checked against any government registry),
  the formation source (the MetaDAO or Umia launchpad, or *Self-formed*
  through the MetaLeX cyberCORP factory), the date its contracts were
  deployed (the legal formation date may differ), the chain and the
  formation factory.
* **Contracts and deployed versions**: the CyberCorp, Issuance Manager,
  Deal Manager, Round Manager and BorgAuth contracts. Each version is
  read live when the page loads and compared with the reference
  implementation its factory publishes (*Matches factory reference* or
  *Differs from factory reference*), which also shows whether the
  company runs v4 or v5.
* **Officers**: the officer roster kept in the company's contract, with
  the names and titles the company recorded.
* **Security classes onchain**: each LET contract the company deployed,
  with its class, series, the number of LETs minted (voided ones
  included) and any scrip token.
* **Registered agreements**: agreements registered in the same
  transaction that deployed the company, which is how the launchpad
  factories register formation documents, each with its status,
  agreement ID and an **Open the document on IPFS** link. Agreements
  registered later are not listed.
* **Public rounds**: the company's publicly advertised rounds, marked
  *Scheduled*, *Open*, *Cap reached*, *Ended* or *Closed*, each with a
  **View round** link. Private rounds are not listed.
* **Chronology**: indexed onchain events, oldest first, with a list of
  what it leaves out.

A closing section, **What this page does not show**, lists the gaps:
filing status or good standing with any registry; the cap table (no
holders, positions or ownership percentages, and no claim about which
record is the company's securities ledger, which depends on its
governing documents); document contents; private rounds, deals,
investors and anyone's contact details; and anything held offchain. A
section that can't be read says so and shows nothing in its place.

The launchpad formation pages, their formation summaries and a company's
cyberRAISE round pages link here, and a shared link to a public company
page shows a preview image. Companies formed through the MetaDAO and Umia
launchpads are also listed in a public directory at
`cybercorps.metalex.tech/company` (see [Launchpads](launchpads.md)).

## Company access follows your profile

* Company pages open for a signed-in profile that has one of the
  company's owner wallets linked, whichever wallet you are browsing
  with. If yours has none, the page names the owner wallets on record so
  you can switch to or [link](profile.md) the right one.
* Signing a company transaction needs an owner wallet connected on the
  company's network. A notice on the page says which wallet and offers
  to switch.
* If the company record can't be verified, the page says **Could not
  load cyberCORP** and offers **Retry company record**. If a page fails
  to load at all, it shows **Unable to load this page** with **Try
  again**.
* Issuing, transferring, scripifying and approving change the company's
  onchain records, so each is a transaction and costs a small amount of
  gas. Offchain cap table entries, drafts and profile edits are plain
  saves.
* MetaLeX cannot issue your securities, move your funds or change your
  company's onchain records.
  [Upgrades and control](../explanation/upgrades-and-control.md) sets
  out what MetaLeX does and does not control.

## Upgrade an existing company to v5

A new company is created on the current protocol release, v5. An
existing company keeps the contract version it was deployed with until
its owners upgrade it, and the app adapts to whichever version the
company runs. When an upgrade is available, mission control lists it as
its first task, which opens the **Upgrade** page. The scripify form also
sends you there when the Issuance Manager is out of date. You upgrade
only when you choose to.

The **Upgrade** page lists the six steps of the v5 upgrade in the order
the v5 release uses: **CyberCorp**, **Issuance Manager**, **Deal
Manager**, **Round Manager**, then the two beacons the Issuance Manager
owns, **LET contracts (CyberCertPrinter)** and **CyberScrip**. Upgrading
a beacon moves every LET contract or scrip token of the company at once.
Each step shows the contract, the factory it is bound to, its current
implementation and the reference that factory publishes, the current
and latest versions, and a status:

* **Up to date**: the contract runs the factory's reference.
* **Upgrade available**: a newer version is published. **Switch
  available** means the implementation differs from the reference at
  the same version number.
* **Shared beacon**: the contract runs shared code that the company
  cannot upgrade from here. The oldest cyberCORPs run their core
  contracts on MetaLeX-owned beacons and cannot upgrade those contracts
  themselves.
* **Not deployed**, **Implementation unknown** or **Reference
  unavailable**: nothing can be sent until the reads succeed.

The page starts a v4 to v5 upgrade only if every step can finish at
that time. It refuses, with the reason, a company that has a contract
older than v4, a shared-beacon contract, no Issuance Manager or Deal
Manager, or a factory reference below v5. Mission control then shows
**Contract upgrade needs MetaLeX**. A v4 company without a Round
Manager upgrades in five steps.

To upgrade:

1. Open the **Contract upgrade available** task in mission control, or
   the Upgrade page, and review the versions.
2. If a Safe that your wallet owns holds the owner role on the company,
   choose **Propose to Safe**. The Safe receives one transaction with
   every step that is not done, followed by the LET contract
   migrations below that need no dates. The steps run in order and
   revert together, so the company never runs v5 and older contracts
   side by side. Collect the Safe signatures and execute it in the Safe
   app. If the same batch already waits in the Safe queue, the page
   shows its signature count instead of proposing it again.
3. Otherwise, send the steps from a wallet that holds the owner role.
   Only the next step's **Upgrade** button is active. Each step is its
   own transaction, and the page reads the chain again before each one.
   The LET contract migrations follow in later transactions, so read
   the warning about scrip conversion below before you start.
4. Choose **Refresh versions** to reread the versions afterwards.

{% hint style="warning" %}
**Finish every step in one sitting.** Contracts on different versions
call functions the other version does not have. While the company runs
v5 and older contracts side by side, mission control shows **Finish the
v5 upgrade**, and the app refuses deals, rounds and issuance, both for
officers and for investors, with a message that names the Upgrade page.
Closing a round early, refunds, rejections and recalls are not refused.
{% endhint %}

{% hint style="danger" %}
**From a wallet, clear all recertification approvals first.**
After the LET contract beacon upgrade, each wallet that holds a
pre-upgrade LET has a holder counter of zero until the checklist seeds
it. If a LET is minted
or transferred to that wallet first, its counter stays below its
balance. The deployed contracts cannot correct this, because
`initializeHolderCount` accepts only a zero counter.

The app refuses issuance in this period. But a holder can still call
`convertScripToCert` on the Issuance Manager directly. If the company
has a recertification approval on file for that holder, the call mints
a new LET to the holder's wallet. If the LET contract allows transfers,
a wallet that receives a new LET can also pass it to a wallet that
holds a pre-upgrade LET. So before you upgrade from a wallet:

* Clear every recertification approval on the company's LET
  contracts. The **Scrips** table shows **Revoke** for approved
  investors who hold no LET. For an investor who already holds a LET,
  the table shows **Auto-approved** and has no **Revoke**, but an
  approval set earlier can still be on file. An admin checks it with
  `getRecertificationApproval` and clears it with
  `clearRecertificationApproval` on the Issuance Manager.
* Do not mint or transfer LETs outside the app.

Set the cleared approvals again only after the checklist shows every
required migration done, so that the app no longer pauses the LET
contract. The holder counters are not enough: until the legal-owner
index is backfilled, a conversion with an approval also takes its units
from the shared scrip vault instead of the holder's own positions. A
Safe does not have this problem: the Safe batch seeds the counters and
runs the backfills in the same transaction as the upgrade. If a counter does
go wrong, the checklist reports a mismatched holder counter, and the
app keeps issuance, deal settlement and scrip conversion paused on that
LET contract. Contact MetaLeX in that case.
{% endhint %}

### Finish the LET contract migrations

v5 adds records to each LET contract that start empty for every LET
minted before the upgrade. Once the company runs v5, the Upgrade page
shows a checklist for each LET contract, read directly from the
contract:

* **Holder counters.** A wallet whose possession counter reads zero
  cannot transfer a pre-upgrade LET out, and a LET minted to it first
  leaves its counter wrong for good. **Run next call** seeds each
  counter (an owner call).
* **Legal-owner index.** Until it is backfilled, converting scrip back
  to a LET can fail or draw on the shared scrip vault instead of the
  holder's own positions.
* **LeXcheX badge.** If the company has a holder cap configured, the
  badge is wired before the holders are counted. The tally then reads
  each holder's beneficial-owner count, U.S. status and credential
  expiry from the badge. Otherwise wiring it is optional; after a late
  wiring, **Recount** counts the holders again.
* **Holder tally.** The count a holder-cap check reads, including
  whether a buyer already holds the class. Until it is backfilled, the
  check undercounts existing holders and can admit a buyer although the
  cap is already full.

Until the holder counters, legal-owner index and holder tally of a LET
contract are complete, the app refuses issuance, deal settlement and
scrip conversion on it, and mission control shows **Migrate N LET
contracts after the v5 upgrade**. With a holder cap, the tally is
complete only when it agrees with the badge for every counted holder.
Anyone can send the index and tally backfills; the counters and the
badge need the owner or admin role.
Holders can still call the contract directly, which is why the Safe
batch carries these calls in the same transaction as the upgrade.

The checklist also handles the dates. Missing dates do not cause the
app to refuse issuance, deal settlement or scrip conversion as above.
But a missing acquisition date still blocks Rule 144 and Reg S trades
of that LET, so set the acquisition dates before holders need to trade:

* **Acquisition dates (Rule 144 and Reg S).** Each pre-upgrade LET's
  acquisition date reads zero, and Rule 144 and Reg S trades refuse it.
  The page proposes the time the current holder of record took the LET
  onchain, which is usually the same as or later than the real
  acquisition. On a LET contract whose extension records fund-interest
  acquisition dates, **Copy recorded dates** copies them first.
* **Issue dates (certificate image).** The certificate image shows a
  blank **Issue Date**. The page proposes the company's cap table issue
  date for a tokenized position, else the issuance endorsement, else
  the mint.

Review each date against the company's records, change any that are
wrong, and confirm the table before you send. A date earlier than the
onchain record is allowed, but the page flags it. The Rule 144 and Reg
S conditions add their fixed period to this date, so an earlier date
makes more of that period count as served, and the LET can trade
sooner. From a wallet, each date is its own transaction; a Safe sends
them as one. Mission control shows **Set acquisition and issue dates of
pre-upgrade lots** until they are set.

Each class panel in the Tokenization Hub shows **Registered-owner
transfer permission (v5)**, which starts off on an upgraded LET
contract. Until it is on, changing a LET's registered owner and
settling secondary trades on that class fail. Turn it on for the
classes that should allow them (see
[Transfer permissions](tokenization-hub.md#transfer-permissions)), after
the checklist's migrations are done. The checklist shows its state and
links there.

> **Under the hood.** Upgrades use a co-approval model: MetaLeX
> publishes a new implementation, and your company opts in, so neither
> side can act alone. Each contract is compared with the reference
> published by the factory it is bound to, which is the factory its own
> upgrade check reads. See [Upgrade model](../reference/upgrade-model.md)
> and [Upgrades and control](../explanation/upgrades-and-control.md).
