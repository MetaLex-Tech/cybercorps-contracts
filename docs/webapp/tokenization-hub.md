---
description: "Set up a company's security classes and series, issue Ledger Entry Tokens (LETs), enable scrip and approve de-scripification"
---

# Tokenization Hub

The **Tokenization Hub** is the cyberCORPs app area where a company sets
up its security classes and series, issues Ledger Entry Tokens (LETs) to
holders, and manages scrip, the fungible form of a class. Like every
company area, it opens for a signed-in profile that has one of the
company's owner wallets linked (see
[Run your company](company.md#company-access-follows-your-profile)).

The Hub displays and changes the company's onchain securities records.
When a company's governing documents designate those records as its
securities ledger (MetaLeX-form bylaws call it the Tokenized Stock Ledger
System), they form part of that ledger. The app does not infer that
legal status from tokenization.

Three buttons sit at the top of the Hub: **Cap Table**, **Add class or
series** and **+ Issue security**.

> **Under the hood.** Each class or series has its own LET contract, a
> [`LedgerEntryToken`](../reference/contracts/LedgerEntryToken.md)
> deployment that mints ERC-721 LETs. A class with scrip also has a
> [`CyberScrip`](../reference/contracts/CyberScrip.md) ERC-20. How a LET and
> the class's scrip relate, and what rights scrip carries, is covered in
> [LETs and scrip](../explanation/lets-and-scrip.md).

## Classes and series

The Hub's main view, **Classes and series**, groups the company's LET
contracts under their legal class (**Legal class · …**), each with an
**Add series** button. A LET contract with no recorded legal identity
sits under **Unclassified or unresolved**, and a saved cap table line
that has no LET contract yet offers **Configure or resume tokenization**
or **Record legal identity**. Each class or series panel shows:

* its **Registered units** and status, including whether scrip is
  enabled;
* its **Class delivery permission**;
* if scrip is enabled, the scrip ratio, the de-scrip threshold, and how
  much of the class is held as LETs and how much as scrip;
* an **Ownership State** summary of active LETs and registered holders,
  with any it could not resolve counted separately, and the
  [transfer permission](#transfer-permissions) switches.

Expanding a panel adds three working sections:

* **Legal class and terms** records the legal identity behind the line
  and its versioned terms: **Attach legal identity**, **Propose terms
  version**, then a current officer's **Approve with wallet** (a free
  signature) or **Record external approval**, and **Activate**. The
  [cap table guide](captable.md) walks through the workflow under *Legal
  classes, series and versioned terms*.
* **Tokenize cap table units** lists the untokenized cap table positions
  linked to this LET contract. **Tokenize units** mints a LET for some or
  all of a position's units to the holder's linked wallet. It needs a v5
  company and activated legal terms. The [cap table guide](captable.md)
  covers it under *Tokenizing part of a position*.
* **Scripify whitelist**, on classes with scrip, controls which LETs can
  be scripified (see [Choose who can scripify](#choose-who-can-scripify)).

## Transfer permissions

Two class-level switches control how a class's LETs move. You change
either one from the class panel, and each change is an onchain
transaction.

| Switch | Controls | Available on |
|---|---|---|
| **Class delivery permission** | the class default for moving LETs between wallets | v4 and v5 LET contracts |
| **Registered-owner transfer permission (v5)** | changes of a LET's registered owner, including settling secondary trades | v5 LET contracts |

On a new v5 LET contract both start off, and issuing a LET is not
subject to either. A v4 LET contract has the delivery switch only. On a
LET contract upgraded to v5, the registered-owner switch also starts
off, and until it is on, changing a LET's registered owner and settling
secondary trades on that class fail. Turn it on only after the
post-upgrade steps in
[Upgrade an existing company to v5](company.md#upgrade-an-existing-company-to-v5).
Per-LET overrides and restriction hooks apply on top of both switches.

## Add a class or series

A security can be issued only once its class exists, and each class or
series line gets its own LET contract. **Add class or series** walks
through three steps, and only the last one is onchain:

1. **Legal class and series**: **What are you adding?** (a class without
   a series, or a series of a class), the legal class (new or existing),
   the **Legal class name** and **Legal series name**, the **Governing
   document reference**, the **Instrument type** (SAFE, SAFT, SAFTE,
   token warrant, token purchase agreement, convertible note, common
   stock or preferred stock) and an optional protocol series category.
   **Save legal identity** saves this offchain.
2. **Tokenization settings**: the **Certificate template** (for example
   the Reg D or Reg S variant of a SAFE), a **Token name** and
   **Ticker** (both prefilled), and the certificate document, uploaded as
   a PDF or given as a URI. **Save tokenization settings** saves them.
3. **Review and deploy**: **Deploy printer** sends the transaction that
   deploys the LET contract. If the wallet's result is lost, paste the
   **Transaction hash from your wallet** and choose **Check transaction
   and finish linking**.

Setting up a LET contract needs a current company officer and supported
company and Issuance Manager versions on the network. v4 and v5
companies are both supported. The instrument list does not include stock
options or restricted stock and token awards. A cap table line of an
unsupported type shows **This cap table line cannot be configured here**
and points back to the cap table.

> **Under the hood.** The company's
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md) deploys
> the LET contract (`createCertPrinter`) for the chosen
> [security type](../reference/security-types.md). A
> [certificate extension](../reference/extensions.md) handles the
> instrument-specific terms.

## Issue a LET

**+ Issue security** opens **Issue New Security**, where you mint a LET
to a holder. Pick the class or series, then fill in the certificate
details:

* **Investor details**: the holder's name (with profile lookup) and
  address.
* **Security detail**: the number of units represented, the investment
  amount (in the class's payment token, USDC by default) and the
  issuance date, which must be in the past.
* **Certificate-specific terms**: terms that depend on the security
  type, such as a SAFE's custom provisions or a SAFT's unlock schedule.
* **Signing officers**: the officer or officers signing the certificate.
* **Legal terms**: the dispute-resolution method and the governing legal
  document.

Issuing takes two approvals. The signing officer signs the certificate
(a free signature), then you confirm the onchain transaction that mints
the LET. To mint a LET for a position already on the cap table, use the
cap table's tokenize actions instead (see [the cap table](captable.md)).

> **Under the hood.** The transaction calls the
> [`IssuanceManager`](../reference/contracts/IssuanceManager.md), which
> mints the LET on the class's LET contract and records the holder as the
> registered owner. See [Issue a LET](../how-to/issue-a-let.md).

## Issued securities

Below the classes, the **Issued Securities** table lists each security
with its active LETs, status, units represented and whether delivery is
enabled. Expanding a security shows:

* its LETs, each with the registered owner (and the custody wallet,
  where different), wallet, ID, agreement, units, issue date and contact;
* its scrip holders.

Tick **hide VOIDed positions** to hide voided LETs. When a holder has
requested de-scripification, a banner prompts you to review it. Opening
a LET shows its certificate page, where the company's owners and the
current holder can **Download PDF**. The holder's side of these pages is
in [For holders](holders.md).

## Enable scrip for a class

Scripifying a class gives it a tradable, fungible form. **Scrip
Configuration** asks for:

* the **scrip ratio**: how many scrip tokens equal one share. The ratio
  is permanent, and a confirmation step repeats the exact ratio back to
  you before anything is deployed.
* the **de-scrip threshold**: the minimum amount of scrip that can be
  converted back into a LET. You can adjust it later.
* **De-scrip Configuration**, fixed to **Founder Approval**: registered
  holders de-scripify automatically, and new holders need your approval.
  The **Auto** option is shown but cannot be selected.
* **Who can scripify**: see
  [Choose who can scripify](#choose-who-can-scripify).
* **clawback**: an optional, one-way **No clawback** switch that
  permanently disables the issuer's force-transfer, freeze and burn
  override for the class. Turn it on for a class whose grants promise
  that vested shares belong irrevocably to the recipient. Leave it off to
  keep the issuer override for compliance.

Scripifying needs the Issuance Manager on the latest version. Until it
is, the form says "The Issuance Manager must be upgraded before
scripifying." and links to the
[Upgrade page](company.md#upgrade-an-existing-company-to-v5).

> **Under the hood.** Scripifying deploys a
> [`CyberScrip`](../reference/contracts/CyberScrip.md) ERC-20 for the
> class through the IssuanceManager (`deployCyberScrip`). Holders can
> then convert LET units to scrip and back. Partial scripification, the
> scrip ratio and the two recertification paths are covered in
> [Scripify and settle a secondary trade](../how-to/scripify-and-settle.md).

## Choose who can scripify

On the Scrip Configuration screen, **Who can scripify** offers "Only
whitelisted certificates can be scripified (recommended for private
shares)", checked by default. The whitelist starts with the LETs the cap
table links as a stock plan's reserve in this class. Without a
whitelist, any holder of record can turn shares into transferable scrip,
including unvested and restricted shares.

After scripifying, manage the list from the class panel's **Scripify
whitelist**. **Turn on** and **Turn off** switch the restriction, and
**Add** and **Remove** list or unlist each LET. For private shares the
app recommends turning it on and listing only the company's reserve and
FBO LETs, so vesting and restricted shares cannot become transferable
scrip. Each change is an onchain transaction, on v4 and v5 companies
alike. A holder who tries to scripify an unlisted LET is told that a
company officer must add it first.

## Approve de-scripification

A holder who already holds a LET of the class converts scrip back
without your approval. A scrip holder who is not yet a registered holder
sends a de-scripification request instead, and a banner in the Hub
prompts you to review it. **Approve De-scripification** pre-fills the
holder and share amount, and you complete and sign the certificate
details and confirm. The holder then becomes a registered holder.

Approval needs activated legal terms for the class or series (see
**Legal class and terms** under [Classes and series](#classes-and-series)).
Without them, the screen explains why and links back to the class in the
Hub.

> **Under the hood.** Issuer approval is the step with legal effect,
> because it adds a new holder of record. See
> [LETs and scrip](../explanation/lets-and-scrip.md) and
> [Compliance architecture](../explanation/compliance-architecture.md).
