---
description: Deploy a cyberCORP and its ACE round in one transaction through PumpCorpFactory
---

# Deploy a PumpCorp for ACE

**ACE** (Asset Conversion to Equity) is a structured offering, typically
under Regulation S and open to non-US persons, in which investors arrive
holding a community's tokens and leave holding ACE SAFEs in the issuing
corporation. The **`PumpCorpFactory`**
([`src/PumpCorpFactory.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/PumpCorpFactory.sol))
and an ACE-configured SAFE extension run it. The live product is
[ace.metalex.tech](https://ace.metalex.tech).

## How PumpCorpFactory deploys an offering

`PumpCorpFactory` uses the same primitives as `CyberCorpFactory`. It
deploys a cyberCORP suite configured for an ACE offering and creates the
round. `deployCyberCorp` deploys the suite only, and
`deployCyberCorpAndCreateRoundFor` deploys the suite and creates the round
in one transaction. The source also contains
`deployCyberCorpAndCreateOffer`, which is marked work in progress and is not
in use.

`deployCyberCorpAndCreateRoundFor` checks that the round's first two party
values are the officer's name and address, and verifies two officer
signatures:

* the escrowed EIP-712 signature over the round economics (domain
  `"RoundManager"`), which the new RoundManager checks, and
* `metadataSignature`, an EIP-712 signature under the domain
  `"PumpCorpFactory"` over the deployment details the escrowed signature
  does not cover: the corp salt, payout address, round flags, officer,
  company details, extension data, round party values, legal details,
  the `CyberCertData` entries and condition addresses
  (`InvalidMetadataSignature` otherwise).

Deployment addresses are bound to the configuration. The factory hashes the
caller's salt with the company details, payout address and officer
(`computeDeploymentSalt`) before deploying, and each component factory
namespaces the salt by its caller, so another deployer cannot take the
predicted addresses with different terms.

## Run the offering

The flow follows a standard cyberRAISE round:

1. Deploy the PumpCorp through `PumpCorpFactory` with the offering
   parameters: pricing, cap, the agreement template, and a zkPassport-based
   non-US `ICondition` for Regulation S gating.
2. Investors submit EOIs and are allocated as in [Run a cyberRAISE
   round](run-a-cyberraise-round.md).
3. On allocation, each investor receives an ACE SAFE as a Ledger Entry
   Token (LET) whose security series is `SecuritySeries.ACE`.

The `deploy*` parameter lists are long and are not reproduced here. The
contract source and the deploy scripts
([`script/deploy-pump-factory.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-pump-factory.s.sol),
[`script/deploy-pump-factory-full-lifecycle.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-pump-factory-full-lifecycle.s.sol))
are the authoritative reference for the ACE deployment shape.

See also [Factories](../reference/factories.md), [Security
types](../reference/security-types.md), and [ACE](../webapp/ace.md) for the
investor app.
