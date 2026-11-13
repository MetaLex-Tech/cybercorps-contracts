---
description: Form the entity a MetaDAO or Umia launch prescribes, see what the app offers it after formation, and browse the companies each launchpad has formed
---

# Launchpads: MetaDAO and Umia

Some token launchpads prescribe the legal entity a project must use, and
[MetaDAO](https://metadao.fi) and Umia are two of them. For each, the
cyberCORPs app has a single-purpose page that forms the prescribed entity as
a cyberCORP: a segregated portfolio of a Cayman Islands segregated portfolio
company. Each page forms the entity once and does nothing else. Governance
of the entity, such as MetaDAO's futarchy, happens on the launchpad's own
platform.

If you are still deciding how to structure a project, the entity guide in
the cyberCORPs app's formation flow asks whether a launchpad will prescribe
your entity structure, naming MetaDAO and Umia as examples. If one will, the
guide sends you to that launchpad's own onboarding, because the C-Corp and
LLC formation form does not create the launchpad's vehicle (see
[Form a company](formation.md)).

## How you reach the formation pages

You arrive from the launchpad's own launch flow, through a link that
carries your token and enterprise details. Opening a page without those
details shows an error.

## What the two pages ask for

Each page presents a **formation agreement** for your entity, shown beside
the form (*Contract Preview / Reference*). A banner says the prefilled
values came from the launchpad's form. Both pages lock the enterprise name,
company name, company type and jurisdiction. They differ in these ways:

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

### Unlock the Umia form

An access password protects the Umia page. A link from Umia can unlock it
directly. Otherwise the page shows **UMIA Form Access**, where you enter
the password you were given and **Continue**. Either way, the browser keeps
access for 24 hours, which covers the formation.

## Form the entity

1. Arrive from the launch flow (the page opens with your details filled
   in), unlock the Umia form if asked, and **connect your wallet**.
2. Check the editable fields: the founder/operator name and contact details
   and, on Umia, the token name and ticker.
3. **Sign the formation agreement**, a free signature.
4. **form cyberCORP.** MetaLeX submits the formation transaction and pays
   its gas, so you pay nothing. The page waits for the transaction to
   confirm before moving on, and shows *Error forming CyberCorp* if it
   fails.
5. A **Formation Summary** page confirms the cyberCORP was minted. It shows
   the entity's details, the operator account and the network, links to
   the executed **Formation Agreement** and **Board Resolutions**, and links
   to the entity's public company page (see [Run your company](company.md)).
   Bookmark it. **Back to MetaDAO** or **Back to UMIA** returns you to the
   launch.

On MetaDAO, the summary data can trail the chain by a minute right after
formation. When it does, the page says the summary is still syncing and
asks you to refresh; the formation has already succeeded.

## After formation

The cyberCORPs app treats a launchpad segregated portfolio as its own legal
form, not as a corporation or an LLC. Its token launch, its fundraising and
its governance happen on the launchpad. In the app, the operator can:

- open **mission control**, which shows a **Segregated portfolio** panel in
  place of the setup cards, the open tasks and recent activity;
- keep the company's **Documents**, including the executed formation
  agreement and board resolutions;
- **sign a contract as the company** in cyberSign. The operator binds the
  segregated portfolio alone, so no launchpad vote is needed to sign.

The app does not show the cap table, the Tokenization Hub, boardRoom, the
Incorporation Hub, grants or [cyberRAISE](cyberraise.md) for a segregated
portfolio. These are corporation and LLC workflows. If you open one of these
pages from a link, the page says that it is not available for a segregated
portfolio and offers the panel instead. cyberRAISE also refuses to start a
round or a deal for a segregated portfolio, from the app and from an AI
agent.

## Browse the launchpad directory

`cybercorps.metalex.tech/company` is a public directory of the companies
formed through one launchpad at a time, MetaDAO or Umia, switched at the top
of the page. It lists them newest first, 50 per page, with a name search.
Each row shows the entity type, jurisdiction, chain and deployment date,
and links to the company's public page. A launchpad company's public page
links back to its list (**All MetaDAO companies**, **All Umia
companies**). Companies formed any other way have a public page but are not
listed.

## Under the hood

Submitting forms a cyberCORP structured as a segregated portfolio of a
Cayman segregated portfolio company and anchors two documents in the same
transaction: the formation agreement and the board resolutions. MetaDAO
formations go through the **MetaDAO / SPC** path and Umia formations
through the **ParentCoFactory**. See [Factories](../reference/factories.md),
[Deploy a MetaDAO SPC](../how-to/deploy-metadao-spc.md), and, for how one
legal entity can hold several independently governed portfolios,
[Legal mappings across jurisdictions](../explanation/legal-mappings.md).
