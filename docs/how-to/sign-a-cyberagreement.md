# Sign a cyberAgreement

**cyberSign** is the protocol's cybernetic legal-agreement execution layer.
Templates are registered in `CyberAgreementRegistry`, parties countersign
onchain via EIP-712, and execution is anchored to the resulting cyberCERTs
and deal records.

cyberSign is unbundled from cyberRAISE: you can use it as a standalone
signing layer for any legal instrument that should run on the same chain as
the assets it governs.

## When to use this guide

You need to record a signed legal agreement (a SAFE, a side letter, a board
consent, a stockholder consent, an investor representation letter, etc.)
onchain such that it is bound to a specific cyberCORP, party, and (optionally)
deal or cyberCERT.

## Steps

### 1. Register the template

If the template is not already in `CyberAgreementRegistry`, an admin uploads
it:

```solidity
uint256 templateId = registry.registerTemplate(TemplateData({
    name: "Series A Stockholder Consent v1",
    contentUri: "ipfs://...",      // canonical text
    contentHash: keccak256(text),
    schema: "..."                  // optional EIP-712 schema for typed params
}));
```

Most commonly used templates (see
[Agreement templates](../reference/templates.md)) are pre-registered.

### 2. Instantiate an executed agreement

```solidity
uint256 agreementId = registry.proposeAgreement(AgreementProposal({
    templateId: templateId,
    parties: [acme, alice],
    params: abi.encode(...),       // values for the typed parameters
    boundCertIds: [42],            // optional: bind to specific certs
    boundDealId: 0                 // optional: bind to a deal
}));
```

### 3. Countersign

Each party signs an EIP-712 payload covering the template id, params, and
their party identity, and submits the signature:

```solidity
registry.signAgreement(agreementId, aliceSig);
```

When all parties have signed, the registry emits `AgreementExecuted` and the
agreement is permanently anchored — addressable by `agreementId` from any cert
or deal that bound to it.

### 4. (Optional) Use as a precondition

A `RequireAgreementExecutedCondition` (custom) can be attached to any
state transition to require that a specific agreement is fully executed first
— e.g., "this round cannot close until the side letter is signed."

## Related

* Reference:
  [`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md),
  [Agreement templates](../reference/templates.md).
* Explanation: [Application stack — cyberSign](../explanation/application-stack.md#cybersign).
