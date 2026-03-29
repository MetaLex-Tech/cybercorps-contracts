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

**Natively tokenized corporate equity on Ethereum, grounded in Delaware corporate law.**

CyberCorps is MetaLeX's smart contract protocol for turning a corporation into a **cyberCORP** — an onchain entity that issues legally constitutive digital securities, manages its cap table, conducts fundraising rounds, and settles deals, all through a composable system of interacting contracts where the blockchain *is* the stock ledger, not a pointer to one.

Live on **Ethereum mainnet**, **Arbitrum**, and **Base**.

---

## Architecture

The protocol starts from [Delaware General Corporation Law](https://delcode.delaware.gov/title8/) (DGCL §§151, 155, 158, 202, 219, 224) and builds token architecture to satisfy its requirements. Every component in the system knows its relationship to the others.

### Core Contracts

| Contract | Role |
|---|---|
| **CyberCorp** | Onchain corporate entity. Stores the legal entity's name, type, jurisdiction, governance structure, officer identities, and references to all subsidiary contracts. The root of the knowledge graph. |
| **CyberCorpFactory** | Deploys new cyberCORPs with their full contract suite. |
| **IssuanceManager** | Issuance authority. Issues and revokes securities, manages scripification/de-scripification, deploys CyberScrip contracts, enforces scrip conversion conditions and whitelist logic. Knows what legal authorities are necessary for each action. |
| **CyberCertPrinter** | ERC-721 minting engine. Each token is a **Stock Ledger Entry Token** (cyberCERT) encoding stockholder name, share count, class/series, restriction legends, endorsement history, officer signatures, agreement URIs, and a fully onchain Base64-encoded SVG visualization. Uses `ShareExtension` for NVCA-aligned series terms metadata. |
| **CyberScrip** | ERC-20 fungible token generated from cyberCERTs via scripification. Includes USDC-style compliance features (force transfer, force burn, freeze, max holder count) with **irreversible disable toggles** — the issuer can permanently renounce specific admin powers, and once renounced, no party (including MetaLeX) can restore them. |
| **CyberShares** | Share tracking and accounting layer. |
| **DealManager** | Deal lifecycle management with integrated escrow. Proposes deals, manages counterparty signing, escrows assets, and releases on condition satisfaction. |
| **RoundManager** | Multi-investor fundraising rounds. Supports first-come-first-served and admission-mode rounds, configurable ticket sizes, raise caps, timed offers, and per-round conditions. Handles Expression of Interest (EOI) submission, acceptance, and closing. |
| **LeXscroWLite** | Atomic deal closing engine. Escrows assets (ERC-20, ERC-721) against condition contracts and releases when all conditions are met. Adds endorsements to cyberCERTs on close. |
| **SafeCertificateConverter** | Computes SAFE-to-equity conversion plans using round pricing and cap table snapshots. |
| **CyberAgreementRegistry** | Onchain legal document anchoring. Templates, executed agreements, party signatures, and escrow linkage. The repository through which securities know their governing documents. |
| **LexChex / LexchexMinter** | Compliance gating. Manages KYC/AML verification status for onchain deal participation. |
| **CertificateUriBuilder** | Constructs fully onchain token URI metadata (JSON + SVG) for cyberCERTs. |
| **CertificateImageBuilder** | Generates the onchain SVG certificate visualization rendered inside each cyberCERT's metadata. |

### Certificate Extensions

Pluggable metadata extensions for different security types, deployed as independent upgradeable contracts:

| Extension | Security Type |
|---|---|
| **ShareExtension** | Preferred/common stock — series terms, liquidation preferences, conversion ratios, anti-dilution, voting power |
| **SAFEExtension** | SAFEs — custom provisions |
| **SAFTExtension / SAFTExtensionV2** | SAFTs — unlock schedules, cliff periods, vesting intervals |
| **TokenWarrantExtension** | Token warrants — exercise price, token calculation method, unlock parameters |

### Access Control

All contracts use [**BorgAuth**](https://github.com/MetaLex-Tech/borg-core) role-based access control with multi-authority requirements, mirroring the corporate governance rules that determine who can authorize what on behalf of the entity.

### Upgrade Model

All contracts use UUPS upgradeable proxies (with beacon proxies for CyberCertPrinter instances) and ERC-7201 namespaced storage. Upgrades use a **co-approval system**: MetaLeX publishes new implementations, but each cyberCORP independently opts in. No unilateral pushes, no forced migrations. An issuer can stay on its original contracts indefinitely.

---

## The Dual-Token Model

The protocol's defining innovation is a dual-token architecture that resolves the tension between legal fidelity and DeFi composability:

**cyberCERTs** (ERC-721) are Stock Ledger Entry Tokens — each one is an entry on the corporation's onchain stock ledger. Each token encodes all information required under DGCL §§158 and 219: stockholder name, share count, class/series, restriction legends (§202), endorsement history, officer authorizations, acquisition price, and governing agreement URIs. NFT transfer alone does not change registered ownership — metadata must be explicitly mutated, maintaining the distinction between token possession and registered ownership that corporate law requires.

**cyberSCRIPs** (ERC-20) are fungible tokens generated from cyberCERTs via `scripifyCert()` and convertible back via `convertScripToCert()`. They serve as the DeFi-composable layer — usable in AMMs, lending protocols, vesting contracts, and as collateral — while cyberCERTs remain the canonical ownership record. cyberSCRIPs are themselves securities in scrip form (grounded in DGCL §155), with an intrinsic, auditable, in-protocol tieback to definitive registered ownership positions on the stock ledger.

### Scripification Features

- **Partial scripification**: Scripify a subset of a cyberCERT's share units; the token remains active with reduced unit count
- **Configurable scrip ratios**: Numerator/denominator-based conversion between share units and scrip tokens
- **Scripify whitelist**: Optional per-token-ID gating of which cyberCERTs may be scripified
- **Conversion conditions**: Pluggable condition contracts for both scripification and de-scripification (KYC/AML, minimum amounts, accreditation)
- **Minimum presentment amount**: Configurable minimum scrip quantity for reconversion
- **Registration approval**: De-scripification by existing registered holders requires no additional approval; new holders must obtain registration approval (issuer-controlled)
- **Scripified Share Pool**: Virtual pool accounting tracks each registered holder's scripified units, with socialized withdrawal for reconversion by third parties
- **Irreversible admin renunciation**: Force transfer, force burn, freeze, and blocklist powers each have independent, permanent disable toggles

---

## Supported Security Types

The protocol natively supports issuance and lifecycle management for: SAFEs, SAFTs, SAFTEs, Token Purchase Agreements, Token Warrants, Convertible Notes, Common Stock, Preferred Stock, Stock Options, Restricted Stock Purchase Agreements, Restricted Stock Units, Restricted Token Purchase Agreements, and Restricted Token Units.

Series designations range from Pre-Seed through Series F.

---

## cyberRaise

The **RoundManager** powers cyberRaise — MetaLeX's onchain fundraising product. Issuers configure rounds with raise caps, ticket sizes, pricing, payment tokens (typically USDC), security types, and round modes (first-come-first-served or admission-based). Investors submit Expressions of Interest with EIP-712 signatures, funds are escrowed onchain, and closing mints the corresponding cyberCERTs with full metadata — all without MetaLeX ever taking custody of funds.

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/)
- A Base Sepolia RPC endpoint (for fork-dependent tests)

### Build

```sh
forge build --via-ir
```

### Test

Certain tests depend on external contracts deployed on Base Sepolia:

```sh
forge test --via-ir --fork-url <your-base-sepolia-rpc-endpoint> -vvvv
```

---

## Deployments

CyberCorps is live on Ethereum mainnet and L2s (Arbitrum, Base). MetaLeX Labs uses its own protocol — the [cyberRaise](https://metalex.substack.com/p/metalexs-cyberraise-v2-automate-your) SAFE certificates are visible onchain as cyberCERTs.

---

## Further Reading

- [MetaLeX Substack](https://metalex.substack.com/) — protocol design rationale, legal analysis, and product updates
- [5 Ways of Tokenizing Securities (& One Which is Best)](https://x.com/lex_node/status/2030322576208068616) — token ontology framework
- [SEC January 2026 Joint Staff Statement on Tokenized Securities](https://www.sec.gov/newsroom/speeches-statements/corp-fin-statement-tokenized-securities-012826) — regulatory context

---

## License

All software, documentation, and other files in this repository are copyright **MetaLeX Labs, Inc.**, a Delaware corporation. All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or mechanical, including photocopying, recording, or by any information storage and retrieval system, except with the express prior written permission of the copyright holder.
