# Deploy a PumpCorp for ACE

**ACE** (Asset Conversion to Equity) lets a token community convert into
equity. It is powered by the **`PumpCorpFactory`**
([`src/PumpCorpFactory.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/PumpCorpFactory.sol))
and an ACE-configured SAFE extension. The live product is
[ace.metalex.tech](https://ace.metalex.tech).

## When to use this guide

You are an issuer running an ACE-style offering: a structured, typically
Regulation S offering open to non-US persons, where investors arrive holding
tokens and leave holding ACE SAFEs.

## Approach

`PumpCorpFactory` builds on the same primitives as `CyberCorpFactory`:
it deploys a cyberCORP suite configured for an ACE offering and creates the
round. Its entry points are `deployCyberCorp` (suite only) and
`deployCyberCorpAndCreateRoundFor`, which deploys the suite **and** creates
the round in one transaction. (`deployCyberCorpAndCreateOffer` is also in
the source but is marked work in progress and not in use.)
`deployCyberCorpAndCreateRoundFor` checks that the round's first two party
values are the officer's name and address, and verifies two officer
signatures:

* the escrowed EIP-712 signature over the round economics (domain
  `"RoundManager"`, checked by the new RoundManager), and
* `metadataSignature`, an EIP-712 signature under the domain
  `"PumpCorpFactory"` over the deployment details the escrowed signature
  does not cover: the corp salt, payout address, round flags, officer,
  company details, extension data, round party values, legal details,
  certificate data, and condition addresses (`InvalidMetadataSignature`
  otherwise).

Deployment addresses are bound to the configuration: the factory hashes the
caller's salt with the company details, payout address, and officer
(`computeDeploymentSalt`) before deploying, and each component factory
namespaces the salt by its caller, so another deployer cannot occupy the
predicted addresses with different terms.

The flow then mirrors a standard cyberRAISE round:

1. Deploy the PumpCorp through `PumpCorpFactory`, supplying the offering
   parameters (pricing, cap, the agreement template, and a non-US /
   zkPassport `ICondition` for Regulation S gating).
2. Investors submit EOIs and are allocated, exactly as in
   [Run a cyberRAISE round](../tutorials/run-a-cyberraise-round.md).
3. On allocation, each investor receives an ACE SAFE cyberCERT (its security
   series is `SecuritySeries.ACE`).

> The `deploy*` parameter lists are long and not reproduced here — consult
> the contract source and the deploy scripts
> ([`script/deploy-pump-factory.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-pump-factory.s.sol),
> [`script/deploy-pump-factory-full-lifecycle.s.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/deploy-pump-factory-full-lifecycle.s.sol)),
> which are the authoritative reference for the current ACE deployment
> shape.

## Related

* [Factories](../reference/factories.md),
  [Security types](../reference/security-types.md).
* Explanation: [Application stack — ACE](../explanation/application-stack.md#ace-asset-conversion-to-equity).
