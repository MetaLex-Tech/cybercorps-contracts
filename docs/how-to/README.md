---
description: What developers can build on the cyberCORPs contracts, which contracts each MetaLeX product uses, and the order to read the guides in
---

# Building on the protocol

These guides call the cyberCORPs contracts directly. With them you can form
a company onchain and issue its securities as Ledger Entry Tokens (LETs),
raise money into it, execute agreements through the agreement registry,
settle secondary trades on LETs or in scrip, list scrip in an AMM pool, and
deploy specialized structures such as an ACE offering or a MetaDAO SPC.

MetaLeX's apps (see [Using the apps](../webapp/README.md)) are one front end
on these contracts. A script, another dApp or a back-office system can make
the same calls, and the contracts do not depend on any MetaLeX app or its
backend services.

The code samples use the real signatures from
[`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts)
(`develop`) and show the order of calls. Several structs are long, so check
every field against the source before you deploy.

## What you need

* [Foundry](https://book.getfoundry.sh/) and a clone of `cybercorps-contracts`
  on which `forge build` succeeds (the default profile compiles with
  `via_ir`).
* An RPC endpoint for Base Sepolia and a funded test wallet there, or a local
  fork of Base Sepolia. None of the guides needs live funds.
* Enough Solidity to read a contract.

## Reading order

Start with the two end-to-end guides. They build the company and the LETs
that the task guides start from.

1. [Incorporate a cyberCORP](incorporate-a-cybercorp.md) deploys a company
   and its contract suite, creates a LET contract for its common stock, and
   issues the founder's first LET.
2. [Run a cyberRAISE round](run-a-cyberraise-round.md) creates a SAFE round,
   takes an investor's Expression of Interest, allocates it and closes the
   round.

Then pick the task you need.

**Issue and control securities**

* [Issue a LET](issue-a-let.md)
* [Scripify and settle a secondary trade](scripify-and-settle.md)
* [Restrict scrip and LET transfers](restrict-transfers.md)
* [Configure BorgAuth roles](configure-roles.md)
* [Gate state transitions with conditions](gate-with-conditions.md)

**Sign agreements and settle trades**

* [Sign a cyberAgreement](sign-a-cyberagreement.md)
* [Run a secondary trade](run-a-secondary-trade.md)
* [Convert SAFEs to equity](convert-safe-to-equity.md)

**Deploy specialized structures**

* [Deploy a PumpCorp for ACE](deploy-pumpcorp-ace.md)
* [Deploy a MetaDAO SPC](deploy-metadao-spc.md)
* [Deploy a LiquiLeX pool](deploy-liquilex-pool.md)

**Operate and integrate**

* [Upgrade a cyberCORP](upgrade-a-cybercorp.md)
* [Integrate from a frontend](integrate-from-frontend.md)

Function-level detail is in the [Reference](../reference/README.md), and the
design behind it in [How cyberCORPs works](../explanation/README.md).

## Which contracts each product uses

| Product | What it does onchain | Contracts | Guides |
|---|---|---|---|
| cyberCORPs app | Forms and administers a company: officers, LET contracts, issuance, scrip and transfer controls | `CyberCorpFactory`, `CyberCorp`, `BorgAuth`, [`IssuanceManager`](../reference/contracts/IssuanceManager.md), [`LedgerEntryToken`](../reference/contracts/LedgerEntryToken.md), [`CyberScrip`](../reference/contracts/CyberScrip.md) | [Incorporate](incorporate-a-cybercorp.md), [Issue a LET](issue-a-let.md), [Roles](configure-roles.md), [Transfers](restrict-transfers.md), [Upgrade](upgrade-a-cybercorp.md) |
| cyberRAISE | Primary fundraising rounds | [`RoundManager`](../reference/contracts/RoundManager.md), [`DealManager`](../reference/contracts/DealManager.md), [`LeXscroWLite`](../reference/contracts/LeXscroWLite.md) | [Run a cyberRAISE round](run-a-cyberraise-round.md) |
| cyberTRADE | Settlement of negotiated secondary trades | [`DealManager`](../reference/contracts/DealManager.md), [`LeXscroWLite`](../reference/contracts/LeXscroWLite.md), [`IssuanceManager`](../reference/contracts/IssuanceManager.md), [`CyberScrip`](../reference/contracts/CyberScrip.md) | [Run a secondary trade](run-a-secondary-trade.md), [Scripify and settle](scripify-and-settle.md) |
| cyberSign | Agreement templates and multi-party execution | [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md) | [Sign a cyberAgreement](sign-a-cyberagreement.md) |
| ACE | Token-community conversion into equity | [`PumpCorpFactory`](../reference/factories.md), [`ACESAFEExtension`](../reference/extensions.md) | [Deploy a PumpCorp for ACE](deploy-pumpcorp-ace.md) |
| LiquiLeX | AMM liquidity for scrip | [`MetalexIssuerFeeHook`](../reference/hooks.md) on Uniswap v4, [`CyberScrip`](../reference/contracts/CyberScrip.md) | [Deploy a LiquiLeX pool](deploy-liquilex-pool.md) |
| MetaDAO | Futarchy-governed Cayman SPC | [`MetaDAOFactory`](../reference/factories.md) | [Deploy a MetaDAO SPC](deploy-metadao-spc.md) |
| LeXcheX | Soulbound accreditation and KYC/AML credentials | [`LexChex`, `LeXcheXBadge`, `LexChexMinter`](../reference/contracts/LexChex.md) | [Gate state transitions with conditions](gate-with-conditions.md) |

### cyberRAISE

Issuers configure rounds with raise caps, ticket sizes, pricing, payment
tokens (typically USDC), security types (SAFE, SAFT, SAFTE and equity
rounds) and a round mode: first-come or founder-approved. Investors submit
EIP-712-signed Expressions of Interest, the round and deal managers hold
their payments in escrow, and allocation mints the investors' LETs.

### cyberTRADE

cyberTRADE settles secondary trades of fund interests, LLC membership
interests, LP units, private company stock and other private securities,
in US and non-US jurisdictions. The parties find each other and negotiate
elsewhere. cyberTRADE verifies compliance, executes the agreement, holds
escrow and settles atomically, along one of two paths:

* **LET path.** The DealManager's offer flow. At settlement the seller's LET
  is reduced or used up, and a new LET carrying the seller's endorsement is
  minted to the buyer. The buyer elects an exemption pathway (Rule 144,
  §4(a)(7), §4(a)(1½), Rule 144A or Regulation S), and the trade must pass
  that pathway's conditions plus the issuer's own: holder caps,
  accreditation, qualified-purchaser status, holding periods, jurisdiction
  screens and, where the issuer installs one, a per-deal approval condition.
  Settlements pay the DealManager's secondary fee, which is set separately
  from the primary fee on rounds and deals.
* **Scrip path.** Settlement in scrip, with conversion back into a LET
  deferred until the holder asks for it. LiquiLeX pools run on this path.

### cyberSign

Anyone can register a template in the `CyberAgreementRegistry`, and a
standalone agreement creates its template in the same transaction. Parties
countersign onchain with EIP-712 signatures, and executed agreements are
linked to LETs and deal records. cyberSign works as a signing layer for any
legal instrument, with or without a raise.

### LiquiLeX

LiquiLeX pairs a company's scrip against a stablecoin in a Uniswap v4 pool
whose `MetalexIssuerFeeHook` routes swap fees to MetaLeX and the issuer. A
whitelisted pool lets only whitelisted addresses hold or move the scrip. An
open pool enforces compliance when scrip converts back into a LET, optionally
with a zkPassport check at the swap.

### LeXcheX

LeXcheX issues soulbound credentials: the original accreditation NFT and the
`LeXcheXBadge` registry, which covers accreditation, qualified-purchaser and
QIB status, jurisdiction and beneficial-owner attestations, and per-issuer
whitelists. Conditions read these credentials to gate rounds and trades.

## Where the reference front ends live

MetaLeX's reference front ends are in the
[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp) monorepo:

| Product | Route | Source |
|---|---|---|
| cyberCORPs app | `/cybercorps` | [`apps/cybercorps-web/src/app/(frame-layout)/cybercorps`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cybercorps) |
| cyberRAISE | `/cyberraise` | [`apps/cybercorps-web/src/app/(frame-layout)/cyberraise`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cyberraise) |
| ACE | `/ace`, with `/ace/bridge-to-solana` and `/ace/bridge-from-solana` | [`apps/cybercorps-web/src/app/ace`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/ace) |
| cyberSign | `/cybersign` | [`apps/web/src/app/(frame-layout)/cybersign`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/web/src/app/%28frame-layout%29/cybersign) |
| MetaDAO | `/metadao` | [`apps/cybercorps-web/src/app/(frame-layout)/metadao`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/metadao) |
| LeXcheX | lexchex.metalex.tech | [`apps/lexchex-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-web), with the oracle service in [`apps/lexchex-oracle`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-oracle) |

The cyberCORPs app's **cyberSign** sidebar entry opens cyberSign. The app
works with v4 and v5 companies side by side and chooses each call's shape
from the targeted contract's `DEPLOY_VERSION`; [Integrate from a
frontend](integrate-from-frontend.md) shows how to do the same.
