```
/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________
```

# CyberCorps Contracts

**Natively tokenized private securities on Ethereum, anchored in each issuer's governing law.**

CyberCorps is MetaLeX's smart contract protocol for turning a legal entity (a Delaware C-corp or LLC, a Cayman LLC or SPC, a BVI fund, an English company, or any analogous structure) into a *cyberCORP*: an onchain entity that issues legally constitutive digital securities, maintains its register of holders, conducts fundraising rounds, and settles deals through a composable system of contracts where the blockchain can *be* the official register, not merely a pointer to an offchain ledger/intermediated system.

The protocol is entity-type and jurisdiction agnostic. Delaware C-corp stock is the most fully worked-out reference implementation, with deeply integrated templates and statutory mappings, but the contract architecture treats entity type, jurisdiction, and governing law as configuration. LLC membership interests, LP interests, segregated portfolio company shares, and non-US equity all flow through the same primitives.

The contracts in this repository underlie a growing application stack: *cyberRAISE* for primary fundraising, *cyberTRADE* for secondary settlement, *ACE* (Asset Conversion to Equity) for converting token communities into equity holders, *LiquiLeX* for AMM native scrip liquidity, and *cyberSign* for cybernetic legal agreement execution, all surfaced to issuers through the cyberCORPs *Mainframe*.

Live on **Ethereum mainnet**, **Arbitrum**, and **Base**.

---

## Constitutive vs. Pointer Tokenization

Most "tokenized securities" today are pointer tokens. The official cap table lives at a transfer agent, on Carta, or in a law firm's filing cabinet, and the chain is a notification layer. Onchain transfers are not the legal transfer; they are a request to update an offchain register that the issuer or its agents may decline to honor. The blockchain does no essential work and could be removed without changing the underlying legal reality.

CyberCorps takes the opposite approach. Each cyberCORP's governing documents (certificate of incorporation and bylaws, operating agreement, articles of association, partnership agreement, fund constitutional documents, or analogous instrument under the entity's governing law) designate the onchain contract system as the entity's official register of holders, with the fungible scrip layer authorized by the same instruments. The legal state transition function and the chain state transition function are unified: changing onchain state is the legal change. There is no offchain register to reconcile against, no transfer agent to instruct, and no possibility of the chain and the legal record diverging.

Delaware corporate law is the most fully worked-out worked example, with statutory hooks at DGCL §224 (any books and records, including the stock ledger, may be kept in any form, including a blockchain) and §155 (scrip authorization). Comparable provisions or contractual workarounds exist under Delaware LLC law, Cayman, BVI, English, and other corporate and fund regimes. The protocol does not assume any specific statute; it assumes the entity's governing law permits the onchain register to be designated as authoritative through the entity's governing documents.

This is what allows cyberCORPs to deliver real disintermediation. A *cyberCERT* (Ledger Entry Token) is the register entry, not a pointer to one. A *cyberSCRIP* is itself a security in scrip form, with a deterministic in-protocol tieback to the cyberCERT it was minted from. Not a wrapper, not a derivative, not a receipt for a receipt.

---

## Architecture

The protocol is built to satisfy the requirements of corporate, LLC, partnership, and fund governing law, with [Delaware General Corporation Law](https://delcode.delaware.gov/title8/) (DGCL §§151, 155, 158, 202, 219, 224) as the primary worked-out statutory reference. Each component knows its relationship to the others, and every authority required to mutate state corresponds to an explicit role under BorgAuth, mapping cleanly to the governance roles defined in the entity's constitutional documents (officers, managers, general partners, directors, or analogues).

### Core Contracts

| Contract | Role |
|---|---|
| **CyberCorp** | Onchain legal entity. Stores legal name, entity type (C-corp, LLC, LP, SPC, fund, etc.), jurisdiction, governance structure, officer/manager/GP identities, escrowed authorized signatures, default dispute resolution, and references to all subsidiary contracts. Root of the knowledge graph. Entity type and jurisdiction are configuration; the contract makes no assumption about which is in use. |
| **CyberCorpFactory / CyberCorpSingleFactory** | Deploys new cyberCORPs and their full contract suite. |
| **IssuanceManager** | Issuance authority. Issues and revokes securities, manages scripification and de-scripification, deploys CyberScrip contracts, enforces conversion conditions and whitelists, and gates registration approval flows. Knows what authorities are required for each action. |
| **CyberCertPrinter** | ERC-721 minting engine. Each token is a *Ledger Entry Token* (cyberCERT) encoding holder name, unit count, class and series, restriction legends, endorsement history, authorized signatures, agreement URIs, and a fully onchain Base64 SVG certificate visualization. Uses pluggable extensions for instrument specific metadata. In the Delaware C-corp case, the metadata fields map to DGCL §§158, 202, and 219 requirements; in other jurisdictions, the same fields satisfy analogous statutory or contractual requirements. |
| **CyberScrip** | ERC-20 fungible token generated from cyberCERTs via scripification. Includes USDC style compliance powers (force transfer, force burn, freeze, blocklist, max holder count) with **independent, irreversible disable toggles**: an issuer can permanently renounce specific admin powers, and once renounced, no party (including MetaLeX) can restore them. |
| **CyberShares** | Share tracking and accounting layer for outstanding share counts, authorized share limits, and reservation accounting. |
| **DealManager** | Deal lifecycle management with integrated escrow. Proposes deals, manages counterparty signing, escrows assets, releases on condition satisfaction, and adds endorsements to cyberCERTs on close. The atomic settlement primitive used by cyberTRADE. |
| **RoundManager** | Multi-investor fundraising rounds. Supports first come first served and admission mode rounds, configurable ticket sizes, raise caps, timed offers, EIP-712 signed Expressions of Interest, and per-round conditions. |
| **LeXscroWLite** | Atomic deal closing engine. Escrows ERC-20 and ERC-721 assets against condition contracts and releases when all conditions are met. |
| **SafeCertificateConverter** | Computes SAFE to equity conversion plans using round pricing and cap table snapshots. |
| **CyberAgreementRegistry** | Onchain anchor for cybernetic legal agreements. Templates, executed agreements, party signatures, and escrow linkage. The repository through which securities know their governing documents. |
| **LexChex / LexChexMinter** | Compliance gating. Manages KYC/AML and accreditation credentials for onchain participation. |
| **CertificateUriBuilder / CertificateImageBuilder** | Constructs fully onchain token URI metadata (JSON + SVG) for each cyberCERT, including the rendered certificate image. |

### Specialized Factories

| Factory | Purpose |
|---|---|
| **PumpCorpFactory** | Powers *ACE* (Asset Conversion to Equity), MetaLeX's product for converting token communities into equity stakeholders of the issuing corporation. Supports party specific allocations and global price/cap configuration with Reg S compliance defaults. |
| **MetaDAOFactory** | Deploys MetaDAO style futarchy governance corporations (segregated portfolio company structures) with onchain prediction market governance. |
| **ParentCoFactory** | Deploys parent and subsidiary cyberCORP structures for holding company configurations. |

### Certificate Extensions

Pluggable metadata extensions for each security type, deployed as independent upgradeable contracts and registered to a CyberCertPrinter:

| Extension | Security Type |
|---|---|
| **ShareExtension** | Preferred and common stock. NVCA aligned series terms, liquidation preferences, conversion ratios, anti-dilution, voting power. |
| **SAFEExtension** | SAFEs. Custom provisions, valuation cap, discount, MFN. |
| **ACESAFEExtension** | ACE specific SAFE variant for token to equity conversions. |
| **SAFTExtension / SAFTExtensionV2** | SAFTs. Unlock schedules, cliff periods, vesting intervals. |
| **SAFTEExtension / SAFTEExtensionV2** | SAFTEs (Simple Agreement for Future Tokens or Equity). |
| **TokenWarrantExtension / TokenWarrantExtensionV2** | Token warrants. Exercise price, token calculation method, unlock parameters. |

### Hooks

| Hook | Purpose |
|---|---|
| **BaseTransferHook** | Common base for cyberSCRIP transfer restriction hooks. |
| **WhitelistTransferHook** | Restricts cyberSCRIP transfers to whitelisted addresses. |
| **ToggleTransferHook** | Per cyberCERT transfer toggling by the issuer, with a configurable default. |
| **MetalexIssuerFeeHook** | Uniswap v4 hook for *LiquiLeX* AMM pools. Splits swap fees between MetaLeX and the issuer at configured BPS, enabling cyberSCRIP / stablecoin pools that pay the issuer onchain on every trade. |

### Conditions

The `ICondition` interface lets any onchain primitive (issuance, descripification, deal close, round acceptance, secondary trade settlement) be gated on arbitrary checks. Built in conditions include:

| Condition | Purpose |
|---|---|
| **lexchexCondition** | Requires a valid LeXcheX credential (KYC/AML, accreditation, qualified purchaser). |
| **NonUSNationalityCondition** | zkPassport based check that the address is held by a non US person, for Regulation S issuances. |
| **IssuerApprovalRecertificationCondition** | Requires explicit issuer approval before a non registered scrip holder can present scrip for de-scripification into a fresh cyberCERT. |
| **OrCondition** | Composes multiple conditions with disjunctive logic. |

Custom conditions are first class. Anything that can be expressed onchain can gate any state transition.

### Access Control

All contracts use **BorgAuth** role based access control with multi-authority requirements, mirroring the corporate governance rules that determine who can authorize what on behalf of the entity. See [borg-core](https://github.com/MetaLex-Tech/borg-core) for the underlying authorization framework.

### Upgrade Model

All contracts use UUPS upgradeable proxies (with beacon proxies for CyberCertPrinter and CyberScrip instances) and ERC-7201 namespaced storage. Upgrades use a co-approval system: MetaLeX publishes new implementations, but each cyberCORP independently opts in. No unilateral pushes, no forced migrations. An issuer can stay on its original contracts indefinitely. This keeps MetaLeX in the role of protocol developer and steward rather than a securities intermediary with admin keys over the issuer's stock ledger. See [`ownership-and-upgradeability.md`](./ownership-and-upgradeability.md) for the full model.

---

## The Dual-Token Model

The protocol's defining architectural innovation is a dual-token model that resolves the tension between legal fidelity and DeFi composability.

**cyberCERTs (ERC-721)** are *Ledger Entry Tokens*. Each token is an entry on the entity's onchain register of holders, encoding all information required by the relevant governing law: holder name, unit count (shares, membership interest units, partnership interest units, or fund interest units), class and series, restriction legends, endorsement history, authorized signatures, acquisition price, and governing agreement URIs. NFT transfer alone does not change registered ownership. Metadata must be explicitly mutated through the IssuanceManager, maintaining the distinction between token possession and registered ownership that corporate, LLC, partnership, and fund law requires.

**cyberSCRIPs (ERC-20)** are fungible tokens generated from cyberCERTs via `scripifyCert()` and convertible back via `convertScripToCert()`. They are the DeFi composable layer: usable in AMMs (including LiquiLeX pools), lending protocols, vesting contracts, and as collateral. cyberSCRIPs are not wrappers or derivatives. They are securities in scrip form (DGCL §155 in the Delaware corp case, or the analogous contractual or statutory authority under the entity's governing law), with limited contingent rights specified in their Terms of Service and a deterministic in-protocol tieback to the cyberCERTs they were minted from. Every circulating cyberSCRIP traces, through the protocol's own logic, to a specific cyberCERT on the authoritative register.

The plain English version: a cyberCERT is your interest in the entity as it lives in the official records (a share of stock, an LLC membership interest, an LP unit, a fund interest, etc.). A cyberSCRIP is what you can trade or post as collateral when you do not need to be registered as a holder of record at that moment. Both are the same security in different forms, with bidirectional conversion always available.

### Scripification Features

- **Partial scripification.** Scripify a subset of a cyberCERT's share units; the cyberCERT remains active with reduced unit count.
- **Configurable scrip ratios.** Numerator/denominator based conversion between share units and scrip tokens.
- **Scripify whitelist.** Optional per cyberCERT gating of which tokens may be scripified.
- **Conversion conditions.** Pluggable condition contracts for both scripification and de-scripification (KYC/AML, minimum amounts, accreditation, jurisdiction).
- **Minimum presentment amount.** Configurable minimum scrip quantity for de-scripification.
- **Two recertification paths.** Existing registered holders de-scripify directly onto their existing cyberCERTs without further approval. New holders must first receive registration approval (with stockholder name, certificate details, and officer signature pre-set by the issuer), after which presentment mints a fresh cyberCERT with the approved metadata.
- **Scripified Share Pool.** ERC-4626 style vault accounting tracks each registered holder's scripified units, with proportional withdrawal on de-scripification.
- **Granular admin renunciation.** Force transfer, force burn, freeze, and blocklist powers each have independent, permanent disable toggles.

---

## Application Stack

CyberCorps is the protocol; the cyberCORPs *Mainframe* is the issuer facing app surface. Several products run on top of the same contract suite:

### cyberRAISE

Onchain primary fundraising. Issuers configure rounds with raise caps, ticket sizes, pricing, payment tokens (typically USDC), security types (SAFE, SAFT, SAFTE, equity rounds), and round modes (first come first served or admission based). Investors submit Expressions of Interest with EIP-712 signatures, funds are escrowed onchain via LeXscroWLite, and closing mints the corresponding cyberCERTs with full onchain metadata. MetaLeX never takes custody.

### cyberTRADE

Post negotiation settlement for secondary trades of fund interests, LLC membership interests, LP units, private company stock, and other private securities, across US and non-US jurisdictions. Counterparty discovery and bilateral negotiation happen wherever they happen (a partner platform's portal, direct introduction, broker matchmaking); cyberTRADE handles compliance verification, agreement execution, escrow, and atomic settlement. Two settlement paths are supported:

- **Registered ledger path.** Edits to the existing cyberCERT (or burn-and-mint with new metadata) under issuer approval, with full holder cap, accreditation, qualified purchaser, and jurisdiction gating as configured per entity.
- **Scrip path.** Settlement at the cyberSCRIP layer with deferred descripification, including the AMM native variant powered by LiquiLeX.

### ACE (Asset Conversion to Equity)

Live at [ace.metalex.tech](https://ace.metalex.tech). Powered by `PumpCorpFactory` and the `ACESAFEExtension`, ACE lets a token community convert into equity stakeholders of an issuing corporation through a structured Reg S compliant offering with zkPassport based jurisdictional gating. 

### LiquiLeX

AMM native secondary liquidity for cyberSCRIPs. Uniswap v4 pools paired against stablecoins, with the `MetalexIssuerFeeHook` routing swap fees to MetaLeX and the issuer at configured rates. Two compliance models are supported: a whitelisted pool (full credential check on every swap via LeXcheX) and an open pool with compliance gated at the descripification boundary, optionally with a lighter zkPassport gate at the swap layer for sanctions and Reg S screening.

### cyberSign

Cybernetic legal agreement execution. Templates registered in the `CyberAgreementRegistry`, parties countersign onchain with EIP-712, and execution is anchored to the resulting cyberCERTs and deal records. cyberSign is unbundled from cyberRAISE and usable as a standalone signing layer for any legal instrument that should run on the same chain as the assets it governs.

### Mainframe

Issuer facing hub within the cyberCORPs app. Cap table or holder register view by class, fundraising round configuration, deal management, agreement signing, scripification controls, transfer hook configuration, BorgAuth role management, holder of record reporting, and 12(g) (or jurisdictional analogue) threshold monitoring across cyberCERT and cyberSCRIP holder bases.

---

## Supported Security Types

Native issuance and lifecycle management for: SAFEs, SAFTs, SAFTEs, Token Purchase Agreements, Token Warrants, Convertible Notes, Common Stock, Preferred Stock (Pre-Seed through Series F), Stock Options, Restricted Stock Purchase Agreements, Restricted Stock Units, Restricted Token Purchase Agreements, and Restricted Token Units.

Reusable agreement templates are maintained in [`/templates`](./templates), including cyberSAFE, cyberSAFT, and cyberTokenWarrant variants for both Reg D (US) and Reg S (UK/Cayman/jurisdiction neutral) issuances, MetaDAO Futarchy governance templates, and the LeXcheX agreement.

---

## Reference Deployments

CyberCorps is live on Ethereum mainnet, Arbitrum, and Base.

MetaLeX dogfoods the protocol with its own Delaware C-corp. The [cyberRAISE](https://metalex.substack.com/p/metalexs-cyberraise-v2-automate-your) SAFE certificates from MetaLeX's prior fundraises are visible onchain as cyberCERTs, and MetaLeX's official stock ledger is maintained via this contract suite, making MetaLeX (so far as we are aware) the first company to keep its DGCL §224 stock ledger natively onchain rather than at a transfer agent or on Carta.

ACE is live in production via [ace.metalex.tech](https://ace.metalex.tech).

The protocol has been used or piloted across Delaware C-corps, Delaware LLCs, Cayman SPCs (via `MetaDAOFactory`), and structures designed for non-US holders under Regulation S.

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/)
- A Base Sepolia RPC endpoint (for fork dependent tests)

### Build

```sh
forge build --via-ir
```

### Test

Some tests depend on contracts deployed on Base Sepolia:

```sh
forge test --via-ir --fork-url <your-base-sepolia-rpc-endpoint> -vvvv
```

---

## Further Reading

- [MetaLeX Substack](https://metalex.substack.com/): protocol design rationale, legal analysis, and product updates
- [What Is Slop Tokenization and Why Is It Bad?](https://metalex.substack.com/): the architectural case for constitutive tokenization
- [5 Ways of Tokenizing Securities (& One Which is Best)](https://x.com/lex_node/status/2030322576208068616): token ontology framework
- [SEC January 2026 Joint Staff Statement on Tokenized Securities](https://www.sec.gov/newsroom/speeches-statements/corp-fin-statement-tokenized-securities-012826): regulatory context
- SEC April 2026 Staff Statement on Covered User Interface Providers (File No. 4-894): UI provider safe harbor relevant to cyberTRADE and LiquiLeX front ends

---

## License

All software, documentation, and other files in this repository are copyright **MetaLeX Labs, Inc.**, a Delaware corporation. All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or mechanical, including photocopying, recording, or by any information storage and retrieval system, except with the express prior written permission of the copyright holder.
