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

`MetaDAOFactory` deploys a cyberCORP suite configured as an SPC-style entity
and seeds the agreement registry with the MetaDAO Futarchy templates. New
segregated portfolios ("SegCos") are approved by board-consent agreements
recorded through the [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).

> The factory's exact constructor and deployment parameters are not
> reproduced here — consult the contract source, which is authoritative for
> the current MetaDAO deployment shape.

## Related

* [Factories](../reference/factories.md),
  [Agreement templates](../reference/templates.md).
* Explanation: [Legal mappings](../explanation/legal-mappings.md).
