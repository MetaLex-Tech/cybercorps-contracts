# Deploy a PumpCorp for ACE

**ACE** (Asset Conversion to Equity) lets a token community convert into
equity stakeholders of an issuing corporation through a Reg S compliant
offering with zkPassport-based jurisdictional gating.

Under the hood, ACE is powered by `PumpCorpFactory` and the
`ACESAFEExtension`. The live consumer product is
[ace.metalex.tech](https://ace.metalex.tech), implemented in the
[`apps/cybercorps-web/src/app/ace`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/ace)
route of `metalex-webapp`.

## When to use this guide

You are an issuer who wants to run an ACE-style round: a structured Reg S
offering open to non-US persons, where investors arrive holding tokens and
leave holding ACE SAFEs (later convertible to equity).

## Steps

### 1. Configure the PumpCorp

```solidity
IPumpCorpFactory pf = IPumpCorpFactory(PUMP_FACTORY);

address pumpCorp = pf.createPumpCorp(PumpCorpParams({
    legalName: "Acme PumpCorp, Inc.",
    jurisdiction: "Delaware, USA",
    pricePerShare: 0.50e6,
    raiseCap: 5_000_000e6,
    perPartyAllocations: ...,           // optional per-investor allocations
    nationalityCondition: nonUsCond,    // zkPassport: non-US only by default
    agreementTemplate: "ipfs://ace-safe-regs-v1"
}));
```

The factory deploys a complete cyberCORP suite plus an ACE-configured
`RoundManager` and registers the `ACESAFEExtension` on the
`CyberCertPrinter`.

### 2. Open the round

The round is created automatically on PumpCorp deployment in Reg-S-default
mode. Open and close timestamps are part of `PumpCorpParams`.

### 3. Investors submit EOIs and fund

Identical to a standard cyberRAISE flow (see
[Tutorial 2](../tutorials/run-a-cyberraise-round.md)), with the additional
zkPassport check.

### 4. Close and mint ACE SAFEs

On close, each investor receives an ACE SAFE cyberCERT (an `ACESAFEExtension`
cert). These convert to equity in the next priced round via the same
[SAFE conversion flow](convert-safe-to-equity.md).

## Related

* Reference: [`PumpCorpFactory`](../reference/factories.md#pumpcorpfactory),
  [Extensions → `ACESAFEExtension`](../reference/extensions.md#acesafeextension).
* Explanation:
  [Application stack — ACE](../explanation/application-stack.md#ace).
