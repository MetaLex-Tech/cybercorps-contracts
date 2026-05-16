# Sign a cyberAgreement

**cyberSign** is the protocol's agreement layer: the
`CyberAgreementRegistry` holds agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds reference it for their
underlying agreements.

## 1. Register a template

A template is a reusable legal document with a field schema.

```solidity
ICyberAgreementRegistry(registry).createTemplate(
    templateId,        // bytes32 — chosen id
    "Series A Stockholder Consent v1",  // title
    "ipfs://...",      // legalContractUri (canonical text)
    globalFields,      // string[] — fields common to the contract
    partyFields        // string[] — fields filled per signing party
);
```

## 2. Create a contract from the template

```solidity
bytes32 contractId = ICyberAgreementRegistry(registry).createContract(
    templateId,
    salt,           // uint256
    globalValues,   // string[]
    parties,        // address[]
    partyValues,    // string[][] — per-party values
    secretHash,     // bytes32
    finalizer,      // address allowed to finalise
    expiry          // uint256
);
```

## 3. Parties sign

Each party signs. Three entry points:

* `signContract(contractId, partyValues, fillUnallocated, secret)` — the
  caller signs for itself.
* `signContractFor(signer, contractId, partyValues, signature, fillUnallocated, secret)`
  — relayed, with the signer's EIP-712 signature.
* `signContractWithEscrow(escrowSigner, contractId, partyValues, signature, fillUnallocated, secret)`
  — using a pre-escrowed signature.

When every party has signed, the registry emits `ContractFullySigned`.

## 4. Finalise

```solidity
ICyberAgreementRegistry(registry).finalizeContract(contractId);
```

## Checking status

`hasSigned`, `allPartiesSigned`, `isFinalized`, `isVoided`,
`getContractDetails`, `getAgreementsForParty`.

## Related

* [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md),
  [Agreement templates](../reference/templates.md).
