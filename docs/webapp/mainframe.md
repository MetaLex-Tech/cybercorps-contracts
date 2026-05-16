# The Mainframe — for issuers

The **Mainframe** is the control panel for your company (your *cyberCORP*).
If you are a founder or officer, this is where you run the company's onchain
life: its register of holders, its fundraising, its deals, and its
governance.

## What the Mainframe is for

Think of it as your company's cap-table software, transfer agent, and deal
room — except the records it shows are not a copy of the official record.
**They are the official record.** When you issue a security or record a
transfer here, that *is* the legal change to your company's register.

## Getting set up

1. **Connect your wallet** and sign in (see
   [Using the cyberCORPs apps](README.md)).
2. If your company has not been set up onchain yet, you create it: you
   provide the entity's details — legal name, entity type (C-corp, LLC, etc.),
   jurisdiction, and the people who serve as its officers. This step deploys
   your cyberCORP and its supporting contracts.
3. Once created, your company has a register with no securities issued yet.
   You add securities as you issue them.

> Setting up a company onchain has legal prerequisites — your company's
> governing documents need to designate the onchain system as the official
> register. MetaLeX provides the templates for this. Talk to your counsel
> before relying on the onchain register as authoritative.

## What you can do in the Mainframe

### View the register (cap table)

See every holder of record, by class and series — common stock, preferred,
SAFEs, options, and so on. Each entry is a **cyberCERT**: a certificate
showing the holder's name, the number of units, the class, restrictions, and
signatures.

### Issue securities

Issue new cyberCERTs to founders, employees, or investors — stock, options,
SAFEs, and the other [supported security types](../reference/security-types.md).
Each issuance is a transaction; once confirmed, the new holder appears on the
register.

### Run fundraising rounds

Configure and manage rounds. The round itself is run through
[cyberRAISE](cyberraise.md), but you set it up and monitor it from here.

### Manage deals

Propose and track deals — secondary transfers, buybacks, and other
transactions. Deals move assets through an onchain escrow and settle only
when all agreed conditions are met.

### Sign agreements

Countersign legal agreements (SAFEs, side letters, board and stockholder
consents) onchain. The signed agreement is permanently linked to the
securities and deals it governs.

### Manage roles

Grant and revoke authority — who can issue securities, who can sign on the
company's behalf, who can approve upgrades. Each role corresponds to a
governance role in your company's constitutional documents.

### Monitor holder thresholds

Keep an eye on how many holders of record you have, so you can stay on the
right side of regulatory thresholds (such as the US 12(g) threshold, or its
equivalent in your jurisdiction).

## A typical first month

1. Create the cyberCORP.
2. Issue founder stock.
3. Set up an option pool and issue option grants.
4. Open a SAFE round in [cyberRAISE](cyberraise.md).
5. As investors come in, watch the register update in real time.

## Good to know

* **Every change is a transaction.** Issuing, transferring, and signing cost
  a small amount of gas and take a few seconds to confirm.
* **You keep control.** MetaLeX cannot issue your securities, move your
  funds, or change your register. Authority lives with your company's own
  roles.
* **Nothing is hidden offchain.** Anyone you authorise — an auditor, an
  investor, a regulator — can verify the register directly.
