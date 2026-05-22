# The cyberCORPs app — manage your company

The **cyberCORPs app** (`cybercorps.metalex.tech`) is where a company is
created and its securities are managed. If you are a founder or officer,
this is your company's onchain control panel. Its central screen is the
**Mainframe**.

> **Fundraising rounds are not here.** Rounds are created and run in
> [cyberRAISE](cyberraise.md). The cyberCORPs app is about the company
> itself and its register of holders.

> Creating a cyberCORP is a **desktop-only** flow.

## Getting started

### Do you have a legal entity?

The first question the app asks is whether you **already have an offchain
legal entity** (a real company — a Delaware corp, an LLC, etc.).

* **Yes** — the standard path. You bring your existing entity onchain. The
  network fee is free for early users; setup costs roughly \$2–\$8 in gas.
* **No** — buying a ready-made entity through MetaLeX is **coming soon** and
  not yet available.

A cyberCORP is best understood as a *digital twin* of your real company.

### Create your cyberCORP

Creation is a two-step wizard. Your progress is saved as you go.

**Step 1 — Legal Identity:**

* **Founder identity** — the founder/officer name and title. This is always
  public, and this address holds the company's primary admin authority.
* **Identity** — the cyberCORP name, a primary contact (Telegram, X, email,
  or phone), the legal entity type, and the jurisdiction of formation.
* **Network & treasury** — the chain (Ethereum, Arbitrum, or Base) and a
  *payable address* — the address that receives payments for the company. A
  Safe multisig is recommended here.

**Step 2 — Public Profile:**

* A description, profile image, website, whitepaper, and document links.

The final **Deploy cyberCORP** button is an onchain transaction. When it
confirms, your company exists onchain.

> Bringing a company onchain has legal prerequisites: the company's
> governing documents need to designate the onchain system as its official
> register. MetaLeX provides templates for this — involve your counsel.

> **Under the hood.** “Deploy cyberCORP” calls the protocol's
> [`CyberCorpFactory`](../reference/factories.md), which deploys your
> [`CyberCorp`](../reference/contracts/CyberCorp.md) contract and its suite
> (issuance, deal, and round managers) and a `BorgAuth` access-control
> contract in one transaction. The “founder identity” address becomes an
> officer in [BorgAuth](../reference/access-control.md). For the full
> walkthrough at the contract level, see the tutorial
> [Incorporate a cyberCORP](../tutorials/incorporate-a-cybercorp.md); for
> *why* the chain can be the official register, see
> [Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md).

## The company home

Once your cyberCORP exists, the app home shows your **company overview** —
the company card (name, description, social links) and a **“What's your
next move?”** list of actions:

* **Start a cyberRaise** — jumps to [cyberRAISE](cyberraise.md).
* **Set up another cyberCORP.**
* **Issue / manage tokenized securities** — opens the Mainframe.
* **Start a cyberSign** — opens MetaLeX's standalone agreement-signing app.

Cap-table management and token vesting are shown as **coming soon**.

## The Mainframe — your equity hub

The Mainframe is the company's securities console. You reach it from
“Issue / manage tokenized securities.” It requires you to connect your
wallet, **Authenticate**, and be an owner of the cyberCORP.

The records here are not a copy of the official record — **they are the
official record**.

### Security Classes

Each class of security your company has (a series of preferred stock, a SAFE
class, an option pool, etc.) appears as a panel showing:

* the class and series, and how many shares are issued;
* its status, including whether scrip is enabled;
* **class-wide transferability** (on/off);
* if scrip is enabled — the scrip ratio, the de-scrip threshold, and related
  settings.

### Issued Securities

Below the classes, a table of issued securities. Expanding a class shows:

* its **certificates** — the individual cyberCERTs (your register of
  holders / cap table), and
* its **scrip holders** — holders of the fungible cyberSCRIP form.

If a holder has requested de-scripification, a banner prompts you to review
it.

Two buttons at the top of the Mainframe: **Create new Security Class** and
**Issue new security**.

> **Under the hood.** Each security *class* is a
> [`CyberCertPrinter`](../reference/contracts/CyberCertPrinter.md) contract.
> Each *certificate* is a **cyberCERT** — an ERC-721 “Ledger Entry Token” —
> and the set of them is your register of holders. Each scrip token is a
> [`CyberScrip`](../reference/contracts/CyberScrip.md) ERC-20. A cyberCERT
> and its cyberSCRIP are the same security in two forms; see
> [The dual-token model](../explanation/dual-token-model.md).

## Creating a security class

Before you can issue a security, its class must exist. The *Create New
Class / Series* form asks for:

* the **network** (fixed to your cyberCORP's chain),
* the **series** (e.g. Pre-Seed, Series A),
* the **security type** — chosen from the template library (SAFE, SAFT,
  SAFTE, token warrant — each in Reg D and Reg S variants — plus common and
  preferred stock, options, convertible notes, and restricted stock/token
  agreements),
* a **security name** (auto-generated from the series and company),
* the **legal document** — either upload a PDF or paste a link to it.

Submitting deploys the class onchain and returns you to the Mainframe.

> **Under the hood.** This deploys a new `CyberCertPrinter` for the chosen
> [security type](../reference/security-types.md). The instrument-specific
> terms are handled by a [certificate extension](../reference/extensions.md).

## Issuing a certificate

*Issue new security* lets you mint a cyberCERT to a holder. You pick the
class, then fill in the **certificate details**:

* **Investor detail** — the holder's name (with profile lookup) and address.
* **Security detail** — units represented, purchase amount in USDC, and the
  issuance date (which must be in the past).
* **Certificate-specific terms** — instrument terms that depend on the
  security type (a SAFE's custom provisions; a SAFT's unlock schedule; etc.).
* **Signing officers** — the officer(s) signing the certificate.
* **Agreement** — the governing legal document.

Issuing takes **two approvals**: first the signing officer signs the
certificate (a free signature), then you confirm the onchain transaction
that mints it.

> **Under the hood.** The transaction calls the
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md), which
> mints the cyberCERT on the class's `CyberCertPrinter` and records the
> holder as the registered owner. See the how-to
> [Issue a cyberCERT](../how-to/issue-a-cybercert.md).

## Enabling scrip (scripify)

To give a security a tradable, fungible form, you *scripify* its class. The
*Scrip Configuration* screen asks for:

* the **scrip ratio** — how many scrip tokens equal one share. **This is
  permanent once the first certificate is issued**, so choose carefully; the
  form includes a primer.
* the **de-scrip threshold** — the minimum amount of scrip that can be
  converted back to a certificate (adjustable later).
* de-scrip handling — currently fixed to **founder approval** (an automatic
  mode is planned but not yet enabled).

Scripify requires your Issuance Manager to be on the latest version; if it
isn't, the form points you to the **Upgrade** page first.

> **Under the hood.** Scripify deploys a
> [`CyberScrip`](../reference/contracts/CyberScrip.md) ERC-20 for the class.
> Holders can then convert certificate units to scrip and back. The
> mechanics — partial scripification, the scrip ratio, and the two
> recertification paths — are covered in the tutorial
> [Scripify and settle a secondary trade](../tutorials/scripify-and-settle.md).

## Approving de-scripification

When a scrip holder wants to become a registered holder, they request
de-scripification. You approve it from the Mainframe's pending-request
banner: the *Approve De-scripification* screen pre-fills the holder and
share amount, you complete and sign the certificate details, and confirm.
The holder is then put on the register.

> **Under the hood.** Issuer approval is the moment that matters legally —
> it is when a new holder is added to the register of record. See
> [The dual-token model](../explanation/dual-token-model.md) and
> [Compliance architecture](../explanation/compliance-architecture.md).

## Admin

The **admin** area lets you edit the company's **public profile**
(description, image, links). It does not change the legal identity set at
creation.

## Upgrade

The **upgrade** area lists your company's contracts — CyberCorp, Deal
Manager, Issuance Manager, Round Manager, and the cyberCERT/cyberSCRIP
implementations — and shows, for each, whether a newer MetaLeX-published
version is available. You upgrade each one individually, and only when you
choose; upgrades are never forced.

> **Under the hood.** Upgrades use a **co-approval** model: MetaLeX
> publishes a new implementation, and your company opts in — neither side
> can act alone. See [Upgrade model](../reference/upgrade-model.md) and
> [Co-approval upgradeability](../explanation/co-approval-upgradeability.md).

## Good to know

* **Every change is a transaction.** Issuing, transferring, scripifying, and
  approving cost a small amount of gas.
* **You keep control.** MetaLeX cannot issue your securities, move your
  funds, or change your register — see
  [The role of MetaLeX](../explanation/role-of-metalex.md).
* **Nothing is hidden offchain.** Anyone you authorise can verify the
  register directly.
