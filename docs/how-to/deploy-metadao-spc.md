# Deploy a MetaDAO SPC

A **MetaDAO** is a futarchy-governed corporation structured as a Cayman
Segregated Portfolio Company (SPC) where each portfolio is independently
governed by onchain prediction-market governance.

The live UI lives at the
[`apps/cybercorps-web/src/app/(frame-layout)/metadao`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/metadao)
route of `metalex-webapp`.

## Prerequisites

* You have legal counsel familiar with Cayman SPCs and futarchy governance
  on hand. The corresponding agreement templates are in the contracts
  repository under `templates/` (search for `MetaDAO Futarchy Governance SPC`).
* You are ready to designate a futarchy market venue.

## Steps

### 1. Use `MetaDAOFactory.createMetaDAO`

```solidity
IMetaDAOFactory f = IMetaDAOFactory(METADAO_FACTORY);

address metaDao = f.createMetaDAO(MetaDAOParams({
    legalName: "Acme MetaDAO SPC",
    jurisdiction: "Cayman Islands",
    futarchyOracle: ORACLE,        // prediction-market oracle
    boardConsentTemplate: "ipfs://metadao-board-consent-v1",
    segCoCombinedTemplate: "ipfs://metadao-segco-combined-v1"
}));
```

The factory deploys an SPC-style cyberCORP and configures the agreement
registry with the MetaDAO Futarchy templates.

### 2. Approve segregated portfolios ("SegCos")

New SegCos are approved by a board consent recorded in
`CyberAgreementRegistry`. The factory pre-registers the `MetaDAO Futarchy
Governance SPC - Board Consent - Approval of SegCo v 1.0` template; instances
are countersigned onchain.

### 3. Wire futarchy market outcomes to authority

Each SegCo's governance authority is bound to the futarchy oracle's decision
for that portfolio. Implementation detail varies by oracle; see the
`MetaDAOFactory` source.

## Related

* Reference: [`MetaDAOFactory`](../reference/factories.md#metadaofactory),
  [Agreement templates](../reference/templates.md).
* Explanation:
  [Legal mappings across jurisdictions](../explanation/legal-mappings.md).
