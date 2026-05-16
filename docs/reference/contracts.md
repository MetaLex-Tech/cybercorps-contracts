# Core contracts

| Contract | Role |
|---|---|
| [**CyberCorp**](contracts/CyberCorp.md) | Onchain legal entity. Stores legal name, entity type, jurisdiction, governance, escrowed signatures, dispute resolution, and references to all subsidiary contracts. Root of the knowledge graph. |
| **CyberCorpFactory / CyberCorpSingleFactory** | Deploys new cyberCORPs and their full contract suite. See [Factories](factories.md). |
| [**IssuanceManager**](contracts/IssuanceManager.md) | Issuance authority. Mints and revokes securities; manages scripification and de-scripification; deploys CyberScrip; enforces conversion conditions; gates registration approval. |
| [**CyberCertPrinter**](contracts/CyberCertPrinter.md) | ERC-721 minting engine. Each token is a *Ledger Entry Token* (cyberCERT). Uses pluggable extensions for instrument-specific metadata. |
| [**CyberScrip**](contracts/CyberScrip.md) | ERC-20 fungible token generated from cyberCERTs via scripification. USDC-style compliance powers with independent, irreversible disable toggles. |
| [**CyberShares**](contracts/CyberShares.md) | Share tracking and accounting (outstanding, authorized, reservation). |
| [**DealManager**](contracts/DealManager.md) | Deal lifecycle with integrated escrow. Proposes deals, manages counterparty signing, escrows assets, releases on condition satisfaction. |
| [**RoundManager**](contracts/RoundManager.md) | Multi-investor fundraising rounds. First-come and admission modes, ticket sizing, raise caps, timed offers, EIP-712 EOIs. |
| [**LeXscroWLite**](contracts/LeXscroWLite.md) | Atomic deal-closing escrow. Holds ERC-20 and ERC-721 against `ICondition`s and releases when satisfied. |
| [**SafeCertificateConverter**](contracts/SafeCertificateConverter.md) | Computes SAFE→equity conversion plans using round pricing and cap-table snapshots. |
| [**CyberAgreementRegistry**](contracts/CyberAgreementRegistry.md) | Onchain anchor for cybernetic legal agreements: templates, executed agreements, party signatures, escrow linkage. |
| [**LexChex / LexChexMinter**](contracts/LexChex.md) | Compliance gating. Manages KYC/AML and accreditation credentials. |
| [**CertificateUriBuilder / CertificateImageBuilder**](contracts/CertificateUriBuilder.md) | Constructs fully onchain token URI metadata (JSON + SVG). |

For specialised factories see [Factories](factories.md). For extensions, hooks
and conditions, see the dedicated reference pages.
