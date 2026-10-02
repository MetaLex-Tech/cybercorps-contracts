---
description: Form the entity a MetaDAO or Umia launch prescribes, and read any company's public record
---

# Launchpads: MetaDAO and Umia

Some token launchpads prescribe the legal entity a project must use.
[MetaDAO](https://metadao.fi) and Umia are two of them. For each, the
cyberCORPs app has a narrow, single-purpose page that forms the
prescribed entity as a cyberCORP: a segregated portfolio of a Cayman
Islands segregated portfolio company. These pages are **not** a
governance or prediction-market surface — each does one thing, once.

If you are still deciding how to structure a project, the entity guide in
the cyberCORPs app's formation flow asks whether you are launching
through a launchpad that prescribes its own entity structure, naming
MetaDAO and Umia as examples. If you are, it sends you to that
launchpad's own onboarding: the C-Corp / LLC formation form does not
create the launchpad's vehicle (see
[Choosing an entity](mainframe.md#choosing-an-entity)).

## When you'd use it

You would not navigate to these pages directly. You arrive from the
launchpad's own launch flow, via a link that carries the details of your
token and enterprise. Opening a page without those details just shows an
error.

## What the pages do

Each page presents a **formation agreement** for your entity, with the
agreement shown alongside the form (*Contract Preview / Reference*). A
banner says the prefilled values were transmitted from the launchpad's
form. The enterprise name, company name, company type and jurisdiction
are locked on both pages. The differences:

| | MetaDAO | Umia |
|---|---|---|
| Company name | *{enterprise} S.P., a segregated portfolio of Futarchy Governance SPC* | *{enterprise} S.P.* |
| Company type | Segregated Portfolio of Segregated Portfolio Company | Segregated Portfolio of Umia Launcher SPC, a Segregated Portfolio Company |
| Jurisdiction | Cayman Islands | Cayman Islands |
| Network | Base | Ethereum |
| Access | anyone with the launch link | password-protected (below) |
| Token name and ticker | locked | editable |
| Founder/operator address | the wallet you connect | the address in the Umia link, or the wallet you connect if the link has none |

On both, you fill in or confirm the **founder/operator name and contact
details**.

### Unlocking the Umia form

The Umia page is protected by an access password. A link from Umia can
unlock it directly. Otherwise the page shows **UMIA Form Access**: enter
the password you were given and **Continue**. The browser then keeps
access for 24 hours, which covers the formation itself.

## The steps

1. Arrive from the launch flow (the page opens with your details
   already populated), unlock the Umia form if asked, and **connect your
   wallet**.
2. Check the editable fields: the founder/operator name and contact
   details, and on Umia the token name and ticker.
3. **Sign the formation agreement** — a free signature.
4. **form cyberCORP.** MetaLeX submits the formation transaction and pays
   the gas — you pay nothing. The Umia page waits for the transaction to
   confirm before moving on, and shows *Error forming CyberCorp* instead
   if it fails.
5. A **Formation Summary** page confirms the cyberCORP was minted: the
   entity's details, the operator account, the network, links to the
   executed **Formation Agreement** and **Board Resolutions**, and a link
   to the entity's [public company page](#public-company-pages). Bookmark
   it — then **Back to MetaDAO** or **Back to UMIA** returns you to
   continue the launch.

On MetaDAO, the summary data can lag the chain by a minute right after
formation; if so, the page says the summary is still syncing and asks you
to refresh — the formation itself has already succeeded.

That's the whole flow. Once the entity is formed, you manage it like any
other cyberCORP — see [The cyberCORPs app](mainframe.md).

## Public company pages

Every cyberCORP, launchpad-formed or not, has a **public company page**
that anyone can read without a wallet or an account, at
`cybercorps.metalex.tech/company/{chainId}/{address}`. Token holders can
use it to check the entity behind a project. It shows what the chain and
the public MetaLeX indexer record, and every address links to the block
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
  *Differs from factory reference*).
* **Officers**: the officer roster kept in the company's contract, with
  the names and titles the company recorded.
* **Security classes onchain**: each certificate contract (cert printer)
  the company deployed, with its class, series, the number of
  certificates minted (voided ones included) and any scrip token.
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

A closing section, **What this page does not show**, spells out the
gaps: filing status or good standing with any registry; the cap table
(no holders, positions or ownership percentages, and no claim about
which record is the company's securities ledger, which depends on its
governing documents); document contents; private rounds, deals,
investors and anyone's contact details; and anything held offchain. A
section that can't be read says so and shows nothing in its place.

The launchpad pages, their formation summaries and a company's
cyberRAISE rounds pages link here, and a shared link to a public company
page shows a preview image.

### The launchpad directory

`cybercorps.metalex.tech/company` is a public directory of the companies
formed through one launchpad at a time: MetaDAO or Umia, switched at the
top of the page. It lists them newest first, 50 per page, with a name
search; each row shows the entity type, jurisdiction, chain and
deployment date, and links to the company's public page. A launchpad
company's public page links back to its list (**All MetaDAO companies**,
**All Umia companies**). Companies formed any other way have a public
page but are not listed.

## Under the hood

Submitting forms a cyberCORP structured as a segregated portfolio of a
Cayman segregated portfolio company, and anchors two documents in the
same transaction: the formation agreement and the board resolutions.
MetaDAO formations go through the **MetaDAO / SPC** path and Umia
formations through the **ParentCoFactory**. See the
[Factories](../reference/factories.md) reference and, for how a single
legal entity can hold multiple independently-governed portfolios,
[Legal mappings across jurisdictions](../explanation/legal-mappings.md).
The *governance* of the entity, such as MetaDAO's futarchy, happens on
the launchpad's own platform; these pages only handle the onchain
legal-entity formation.

## Good to know

* These pages are a **handoff**, not an app you spend time in.
* **Formation costs you no gas** — MetaLeX submits the transaction.
* For everything you do *after* formation — issuing securities, raising —
  you use the [cyberCORPs app](mainframe.md) and [cyberRAISE](cyberraise.md)
  like any other company.
