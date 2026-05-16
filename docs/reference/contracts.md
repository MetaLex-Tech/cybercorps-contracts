# Core contracts

Contract roles, as implemented in
[`cybercorps-contracts`](https://github.com/MetaLex-Tech/cybercorps-contracts)
(`develop`, `DEPLOY_VERSION "4"`).

| Contract | Role |
|---|---|
| [**CyberCorp**](contracts/CyberCorp.md) | The onchain entity. Stores the company name, type, jurisdiction, contact details, dispute-resolution default, officers, escrowed officer signatures, and the addresses of the IssuanceManager / DealManager / RoundManager. UUPS-upgradeable. |
| [**CyberCorpFactory**](factories.md) | Deploys a cyberCORP and its full suite (BorgAuth, IssuanceManager, DealManager, RoundManager) in one call. |
| [**IssuanceManager**](contracts/IssuanceManager.md) | Issuance authority. Creates CyberCertPrinters, mints/assigns/voids cyberCERTs, deploys CyberScrip, runs scripification and de-scripification, manages recertification approvals. |
| [**CyberCertPrinter**](contracts/CyberCertPrinter.md) | ERC-721 of cyberCERTs (Ledger Entry Tokens). One printer per security class. Mutated only by its IssuanceManager. |
| [**CyberScrip**](contracts/CyberScrip.md) | ERC-20 fungible form of a security, deployed per CyberCertPrinter. USDC-style compliance powers (force transfer, force burn, freeze) with one-way disable toggles. |
| [**CyberShares**](contracts/CyberShares.md) | An ERC-20 share token with certificate-formation logic. Partly in-progress — see the page. |
| [**DealManager**](contracts/DealManager.md) | Deal lifecycle: propose, sign, finalise, void/revoke. Built on the agreement registry. |
| [**RoundManager**](contracts/RoundManager.md) | Multi-investor fundraising rounds: create, submit EOIs, allocate, close. |
| [**LeXscroWLite**](contracts/LeXscroWLite.md) | The escrow concept used at deal/round close. **Not a contract in this repository's `src/`** — see the page. |
| [**CyberAgreementRegistry**](contracts/CyberAgreementRegistry.md) | Onchain registry of agreement templates and executed, multi-party-signed contracts. |
| [**SafeCertificateConverter**](contracts/SafeCertificateConverter.md) | Computes a SAFE→equity conversion plan from round data. **Currently a stub.** |
| [**LexChex / LexChexMinter**](contracts/LexChex.md) | ERC-5484 soulbound accreditation credentials. |
| [**CertificateUriBuilder**](contracts/CertificateUriBuilder.md) | Builds the onchain JSON + SVG token URI for cyberCERTs. |

See [Factories](factories.md) for the specialised factories (PumpCorp,
MetaDAO, ParentCo).
