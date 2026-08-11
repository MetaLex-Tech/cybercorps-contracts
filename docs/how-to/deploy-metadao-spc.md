# Deploy a MetaDAO SPC

A **MetaDAO** is a futarchy-governed entity, structured as a Cayman
Segregated Portfolio Company. It is deployed by the **`MetaDAOFactory`**
([`src/MetaDAOFactory.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/MetaDAOFactory.sol)).

## Prerequisites

* Legal counsel familiar with Cayman SPCs and futarchy governance.
* The MetaDAO Futarchy Governance templates from
  [`/templates`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/templates)
  (search for `MetaDAO Futarchy Governance SPC`).

## Approach

`MetaDAOFactory` deploys a cyberCORP suite configured as an SPC-style
entity. Its entry points are:

* `createParentCorp(...)` — admin-only, one-time creation of the MetaDAO
  parent corp.
* `deployMetaCorp(...)` — deploys a suite (BorgAuth, CyberCorp,
  IssuanceManager, DealManager) with the same parameter shape as
  `CyberCorpFactory.deployCyberCorp`.
* `deployMetaDAOContractFor(...)` — deploys a SegCo suite and executes the
  SegCo and board-consent agreements in one transaction, taking a
  `_segCoTemplateId` and `_boardConsentTempateId` plus the deployer
  officer's values and EIP-712 signature.

New segregated portfolios ("SegCos") are approved by board-consent
agreements recorded through the
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).
The deploy script
([`script/deploy-metadao-factory.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-metadao-factory.s.sol))
seeds the registry with the SegCo and Board Consent templates.

> The factory's full parameter lists are not reproduced here — consult the
> contract source, which is authoritative for the current MetaDAO
> deployment shape.

## Related

* [Factories](../reference/factories.md),
  [Agreement templates](../reference/templates.md).
* Explanation: [Legal mappings](../explanation/legal-mappings.md).
