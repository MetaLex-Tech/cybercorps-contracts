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
round. The flow then mirrors a standard cyberRAISE round:

1. Deploy the PumpCorp through `PumpCorpFactory`, supplying the offering
   parameters (pricing, cap, the agreement template, and a non-US /
   zkPassport `ICondition` for Regulation S gating).
2. Investors submit EOIs and are allocated, exactly as in
   [Run a cyberRAISE round](../tutorials/run-a-cyberraise-round.md).
3. On allocation, each investor receives an ACE SAFE cyberCERT (its security
   series is `SecuritySeries.ACE`).

> `PumpCorpFactory`'s exact constructor and `deploy*` parameters are not
> reproduced here — consult the contract source, which is the authoritative
> reference for the current ACE deployment shape.

## Related

* [Factories](../reference/factories.md),
  [Security types](../reference/security-types.md).
* Explanation: [Application stack — ACE](../explanation/application-stack.md#ace).
