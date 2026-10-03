---
description: Deploy a futarchy-governed Cayman segregated portfolio company and its SegCos through MetaDAOFactory
---

# Deploy a MetaDAO SPC

A **MetaDAO** is a futarchy-governed entity structured as a Cayman
Segregated Portfolio Company (SPC), and each of its portfolios (SegCos) has
its own futarchy oracle. The **`MetaDAOFactory`**
([`src/MetaDAOFactory.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/MetaDAOFactory.sol))
deploys it.

You need legal counsel familiar with Cayman SPCs and futarchy governance,
and the MetaDAO Futarchy Governance templates from
[`/templates`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/templates)
(search for `MetaDAO Futarchy Governance SPC`).

## How MetaDAOFactory deploys the SPC

`MetaDAOFactory` deploys cyberCORP suites configured as an SPC-style
entity through three entry points:

* `createParentCorp(...)` creates the MetaDAO parent corp. Only the
  factory's owner can call it, and a second call reverts
  `ParentCorpAlreadyCreated`.
* `deployMetaCorp(...)` deploys a suite (BorgAuth, CyberCorp,
  IssuanceManager, DealManager) with the same parameter shape as
  `CyberCorpFactory.deployCyberCorp`.
* `deployMetaDAOContractFor(...)` deploys a SegCo suite and executes the
  SegCo and board-consent agreements in one transaction. It takes a
  `_segCoTemplateId` and `_boardConsentTempateId` (spelled that way in the
  source) plus the deployer officer's values and EIP-712 signature.

Board-consent agreements recorded through the
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md)
approve each new SegCo. The deploy script
([`script/deploy-metadao-factory.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-metadao-factory.s.sol))
seeds the registry with the SegCo and Board Consent templates.

The factory's full parameter lists are not reproduced here. The contract
source is the authoritative reference for the MetaDAO deployment shape.

See also [Factories](../reference/factories.md), [Agreement
templates](../reference/templates.md), [Legal
mappings](../explanation/legal-mappings.md), and
[Launchpads](../webapp/launchpads.md) for the MetaDAO formation pages in
the app.
