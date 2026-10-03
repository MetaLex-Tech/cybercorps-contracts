---
description: Who the MetaLeX apps are for, how to sign in, which app does what, and what it costs
---

# Getting started

These guides are for the people who use the MetaLeX apps: founders,
officers and directors running a company, investors in its rounds,
employees and other holders of its securities, and token projects forming
an entity through a launchpad. They describe what you click and what each
step does, with no code.

The apps run on the cyberCORPs protocol. To learn how the protocol works,
read [How cyberCORPs works](../explanation/README.md); to build on it, start
with the [guides](../how-to/README.md) and the
[reference](../reference/README.md).

## Which app does what

The apps run on separate subdomains and share one MetaLeX account. A
company and the securities it issues appear in every app once they exist.

| App | Address | What you do there |
|---|---|---|
| [**cyberCORPs app**](company.md) | `cybercorps.metalex.tech` | Form a new LLC or C-Corp, or bring an existing company onchain. Run its cap table, board, grants and documents, and issue its securities from the **Tokenization Hub**. |
| [**cyberRAISE**](cyberraise.md) | `cyberraise.metalex.tech` | Create and run fundraising rounds, and invest in them. |
| [**ACE**](ace.md) | inside cyberRAISE | Raise from a token community with a SAFE priced in the community token. Links to `ace.metalex.tech` redirect to cyberRAISE. |
| [**cyberSign**](cybersign.md) | `app.metalex.tech/cybersign` | Propose, review, sign and countersign agreements. The cyberCORPs app's **cyberSign** sidebar item opens it. |
| [**LeXcheX**](lexchex.md) | `lexchex.metalex.tech` | Prove accredited-investor status and hold the credential in your wallet. |
| [**Profile**](profile.md) | `profile.metalex.tech` | Edit your MetaLeX identity, manage linked wallets, turn on notifications and delegate signing for a Safe. |

## Find the right guide

| Guide | Read it to |
|---|---|
| [Form a company](formation.md) | Form an LLC or C-Corp through the app, pay for it, and follow the filing to completion. |
| [Run your company](company.md) | Bring an existing company onchain, use mission control, the Incorporation Hub and Documents, read the public company page, and upgrade to v5. |
| [Tokenization Hub](tokenization-hub.md) | Set up classes and series, issue Ledger Entry Tokens (LETs), and enable scrip. |
| [The cap table](captable.md) | See tokenized and untokenized positions together, import a cap table and tokenize positions. |
| [Cap-table records, modeling and compliance](captable-tools.md) | Export §219 stockholder lists, keep 409A, Rule 701, 3921 and 83(b) records, model a round and run an exit waterfall. |
| [Grants](grants.md) | Award options, RSUs and restricted stock that vest onchain. |
| [boardRoom](boardroom.md) | Manage officers and directors, governance documents and board consents. |
| [cyberSign](cybersign.md) | Propose and sign agreements, and find them in your Contract Library. |
| [cyberRAISE](cyberraise.md) | Run a raise as an issuer, or invest in one. |
| [ACE](ace.md) | Run or join a token-community raise, and bridge tokens between Solana and Base. |
| [For holders](holders.md) | See what you hold, transfer it, and convert between LETs and scrip. |
| [Profile](profile.md) | Set up your identity, link wallets and delegate signing. |
| [LeXcheX](lexchex.md) | Get accredited. |
| [Launchpads](launchpads.md) | Form the entity a MetaDAO or Umia launch prescribes. |

## Sign in and set up your account

Signing in the first time creates your MetaLeX account and its profile
record, and links the wallet you signed in with. There is no separate
registration. Your profile belongs to the account, so it follows you across
every wallet you link; you add, switch and unlink wallets in **Wallet
Settings** (see [Profile](profile.md)). If you sign in without a wallet of
your own, the account gets an embedded wallet that MetaLeX creates as part
of your profile.

Signing in is a free Sign-In With Ethereum message and costs no gas.
Screens that show private data, such as a company workspace or your
holdings, ask you to **Authenticate** when you are not signed in.

You also need:

* **A wallet.** A browser wallet such as MetaMask or Rabby works. A Safe
  multisig is supported and recommended for a company's treasury, and a
  Safe can delegate its agreement signing to one wallet (see
  [Profile](profile.md)).
* **ETH for gas** on the company's network. cyberCORPs run on Ethereum,
  Arbitrum and Base. A company formed through the app gets its onchain
  record on Ethereum mainnet, the chain the formation fee is paid on.
* **A desktop browser** for company setup and the longer flows. The apps
  also work on a phone.

A company's pages open for any signed-in profile that has one of the
company's owner wallets linked, whichever wallet you are browsing with.
Signing for the company still needs an owner wallet connected on the
company's network, and the app tells you which wallet to switch to (see
[Run your company](company.md)).

## Signatures and transactions

Your wallet asks you to approve two kinds of action, and it shows which
kind before you approve:

* **A message signature** is free and instant. Signing in, agreeing to a
  legal document and expressing interest in a round are signatures.
* **A transaction** costs gas and confirms in a few seconds. Deploying a
  company, issuing a security, funding a round and closing a round are
  transactions.

Each guide says which steps are which.

## What it costs

* **Forming a new company** through the app is a flat **\$1,000, paid in
  USDC**. It covers the state filing, the formation documents, the initial
  tax filings and a lawyer consultation (see [Form a company](formation.md)).
  A later annual report for that company costs the state's fee only.
* **Bringing an existing company onchain** is free apart from gas.
* **Issuing and managing securities** by hand in the Tokenization Hub is
  free apart from gas.
* **Signing with cyberSign** is free apart from gas.
* **cyberRAISE** charges the issuer **0.3% of the funds it claims** from a
  round. Investors pay nothing, and rejected bids are never charged.
* **Launchpad formation** costs the founder nothing: MetaLeX submits the
  transaction and pays its gas.

MetaLeX never takes custody of your funds or your securities. Money in
transit during a raise or a deal sits in an onchain escrow that no one can
override (see [Upgrades and control](../explanation/upgrades-and-control.md)).

## Terms used in these guides

* A **cyberCORP** is your company's onchain record and the contracts that
  run it.
* A **Ledger Entry Token (LET)** is an ERC-721 token for one ledger entry:
  a share position, a SAFE, an option. Each class or series has its own
  **LET contract** that mints its LETs.
* **Scrip** is a fungible ERC-20 token that tracks a class's LET units,
  which holders can trade. Its rights come from the company's governing
  documents; under MetaLeX-form bylaws, scrip is not stock on its own.
* The **cap table** is the record the app assembles from LETs, scrip and
  the positions you record offchain.
* The **securities ledger** is the company's legally definitive record.
  The company's governing documents, such as its bylaws, decide which
  record that is; tokenizing a class does not decide it.
* An **EOI** (expression of interest) is an investor's signed offer to
  invest in a round.

The [Glossary](../reference/glossary.md) defines the rest.

## How the apps use the protocol

The apps are front ends over the cyberCORPs smart contracts. Creating a
company, issuing and transferring securities, and signing agreements are
contract calls. The app also keeps offchain records, such as untokenized
cap table positions, drafts, formation details and versions of legal
terms, and each guide says which actions are which.

* **Deploying a cyberCORP** calls the protocol's factory, which deploys the
  company's contracts. When the company's governing documents designate the
  onchain record as its securities ledger, the chain is that ledger (see
  [Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md)).
* **Issuing a security** mints a LET from the class's LET contract.
* **Enabling scrip** for a class deploys its scrip token, and holders can
  then convert LETs to scrip and back (see
  [LETs and scrip](../explanation/lets-and-scrip.md)).

**Under the hood** boxes in each guide name the contract behind the action
you are taking. You can use the apps without reading them. To see the whole
path at the contract level, follow
[Incorporate a cyberCORP](../how-to/incorporate-a-cybercorp.md).
