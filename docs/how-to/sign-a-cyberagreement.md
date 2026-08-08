# Sign a cyberAgreement

**cyberSign** is the protocol's agreement layer: the
`CyberAgreementRegistry` holds agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds reference it for their
underlying agreements.

## 1. Register a template

A template is a reusable legal document with a field schema. Template
creation is **permissionless** — anyone can register one; ids are
first-come (`TemplateAlreadyExists` on a collision).

```solidity
ICyberAgreementRegistry(registry).createTemplate(
    templateId,        // bytes32 — chosen id
    "Series A Stockholder Consent v1",  // title
    "ipfs://...",      // legalContractUri (canonical text)
    globalFields,      // string[] — fields common to the contract
    partyFields        // string[] — fields filled per signing party
);
```

For one-off agreements you can skip the separate template step:
`createStandaloneContractAndSign(title, legalContractUri, globalFields,
partyFields, salt, globalValues, parties, partyValues, expiry, signature)`
derives a template id from the content, creates the template just-in-time
if needed, creates the contract, and records the proposer's signature — all
in one transaction.

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

Each party signs. Every entry point carries the signer's EIP-712 signature
over the agreement content (contract id, canonical text URI, fields and
values):

* `signContract(contractId, partyValues, signature, fillUnallocated, secret)`
  — the caller signs for itself.
* `signContractFor(signer, contractId, partyValues, signature, fillUnallocated, secret)`
  — relayed, with the signer's EIP-712 signature.
* `signContractWithEscrow(escrowSigner, contractId, partyValues, signature, fillUnallocated, secret)`
  — using a pre-escrowed signature; only callable by the contract's
  finalizer, which must be a defined smart contract (e.g. a DealManager).

When every party has signed, the registry emits `ContractFullySigned`.

A party can also delegate signing authority with
`setDelegation(delegate, expiry)` / `revokeDelegation()`.

## 4. Finalise

If the contract was created with `finalizer == address(0)`, it finalizes
automatically when the last party signs. Otherwise the finalizer calls:

```solidity
ICyberAgreementRegistry(registry).finalizeContract(contractId);
```

## Voiding

`voidContractFor(contractId, party, signature)` records a party's void
request (EIP-712-signed, or submitted by the finalizer). The contract voids
when all parties request it, when it has expired, or when the first party
requests it while only one signature has been collected.

## Checking status

`hasSigned`, `allPartiesSigned`, `isFinalized`, `isVoided`,
`getContractDetails`, `getAgreementsForParty`.

## Related

* [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md),
  [Agreement templates](../reference/templates.md).
