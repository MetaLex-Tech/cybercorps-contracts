# The cyberCORPs app — manage your company

The **cyberCORPs app** (`cybercorps.metalex.tech`) is where a company is
created and its securities are managed. If you are a founder or officer,
this is your company's onchain control panel.

Its central screen is the **Mainframe** — the view of your company's
securities and scrip.

> **Fundraising rounds are not here.** Rounds are created, configured, and
> run in [cyberRAISE](cyberraise.md) (`cyberraise.metalex.tech`). The
> cyberCORPs app is about the company and its register of holders; cyberRAISE
> is about raising money.

## Creating your company

Connect your wallet, sign in, and create a cyberCORP. You provide the
entity's details — legal name, entity type, jurisdiction, contact details —
and the officer who is setting it up. This deploys your cyberCORP and its
supporting contracts.

> You can also create a cyberCORP from within [cyberRAISE](cyberraise.md) —
> useful if you are setting up the company and its first raise together.

> Setting up a company onchain has legal prerequisites: the company's
> governing documents need to designate the onchain system as its official
> register. MetaLeX provides templates for this; talk to your counsel.

## The Mainframe

The Mainframe shows your company's securities. The records here are not a
copy of the official record — **they are the official record**.

### Security classes

Your company's securities are organised into **classes** (Common Stock,
Preferred, SAFEs, options, and the other
[supported types](../reference/security-types.md)). You create a new
security class before issuing securities of that type.

### Certificates (the register of holders)

Each holder's stake is a **cyberCERT** — a certificate showing the holder,
the units, the class, restrictions, and signatures. The Mainframe lists
them; together they are your cap table / register of holders.

* **Issue a certificate** to a founder, employee, or investor.
* **Approve a recertification** when a new holder needs to be put on the
  register (for example, after acquiring scrip — see below).

### Scrip

A security can be given a tradable, fungible form — **cyberSCRIP**. From the
Mainframe you can set a class up for scrip ("scripify"), and the Mainframe
shows the scrip alongside the certificates.

### Transferability

Transferability controls let you set whether (and which) certificates and
scrip can move.

## Admin

The app's **admin** area is where company-level settings and authority
(officers / roles) are managed.

## Upgrades

The **upgrade** area lets the company opt in to new versions of the
underlying contracts when MetaLeX publishes them. Upgrades are never forced —
you choose if and when. (Background:
[Co-approval upgradeability](../explanation/co-approval-upgradeability.md).)

## Good to know

* **Every change is a transaction.** Issuing, transferring, scripifying, and
  approving cost a small amount of gas.
* **You keep control.** MetaLeX cannot issue your securities, move your
  funds, or change your register.
* **Nothing is hidden offchain.** Anyone you authorise can verify the
  register directly.

> This guide describes what each area of the app is for. It is not a
> click-by-click walkthrough.
