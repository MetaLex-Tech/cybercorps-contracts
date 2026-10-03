---
description: Register templates and execute multi-party agreements in the CyberAgreementRegistry
---

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

`createContract` returns the id, and the registry emits it in
`ContractCreated`; an `eth_call` of the same `createContract` predicts it
before you send. When parties must sign before the agreement exists (the
proposer of a standalone agreement, for example), compute it as
`keccak256(abi.encode(templateId, salt, globalValues, parties, secretHash,
finalizer))`, and for a standalone agreement use `secretHash = 0`,
`finalizer = address(0)`, and the derived template id.

An older registry derives the id from four fields only:
`keccak256(abi.encode(templateId, salt, globalValues, parties))`. That is
the registry whose `SIGNATUREDATA_TYPEHASH()` returns `0x49ba7af1…0da4`,
such as the separate zkSync Era deployment (see step 3). Both registries
report `version()` `"1"`, so tell them apart by the typehash, not the
version.

## 3. Parties sign

Each party signs. Every entry point carries the signer's EIP-712 signature
over the agreement content. On the current registry the typed data is:

```ts
// viem signTypedData
const domain = {
  name: "CyberAgreementRegistry",
  version: "1",
  chainId,
  verifyingContract: registry,
};
const types = {
  SignatureData: [
    { name: "contractId", type: "bytes32" },
    { name: "signer", type: "address" },      // the party this signature counts for
    { name: "legalContractUri", type: "string" },
    { name: "globalFields", type: "string[]" },
    { name: "partyFields", type: "string[]" },
    { name: "globalValues", type: "string[]" },
    { name: "partyValues", type: "string[]" },
  ],
};
// message: the template's URI and fields, the agreement's global values,
// and this party's own partyValues, with signer = the party's address
```

Set `signer` to the party's address even when a delegate produces the
signature; the registry accepts it for that party only. Before signing,
read `SIGNATUREDATA_TYPEHASH()` on the registry: `0xe37d17c3…6f05` means
the type above, while an older registry (such as the separate zkSync Era
deployment) returns `0x49ba7af1…0da4` and expects the same struct without
`signer`. The entry points are:

* `signContract(contractId, partyValues, signature, fillUnallocated, secret)`
  — the caller signs for itself.
* `signContractFor(signer, contractId, partyValues, signature, fillUnallocated, secret)`
  — relayed, with the signer's EIP-712 signature.
* `signContractWithEscrow(escrowSigner, contractId, partyValues, signature, fillUnallocated, secret)`
  — using a pre-escrowed signature; only callable by the contract's
  finalizer, which must be a defined smart contract (e.g. a DealManager).

When every party has signed, the registry emits `ContractFullySigned`.

A party can also delegate signing authority with
`setDelegation(delegate, expiry)` / `revokeDelegation()` (`expiry == 0`
for no expiry). The delegate signs `SignatureData` with `signer` set to the
delegating party.

## 4. Finalise

If the contract was created with `finalizer == address(0)`, it finalizes
automatically when the last party signs. Otherwise the finalizer calls:

```solidity
ICyberAgreementRegistry(registry).finalizeContract(contractId);
```

## Voiding

`voidContractFor(contractId, party, signature)` records a party's void
request (an EIP-712 `VoidSignatureData(bytes32 contractId,address party)`
signature by the party or its delegate, or no signature when the finalizer
submits it). The contract voids
when every allocated party requests it (unfilled open slots don't count
toward unanimity), when its nonzero expiry has passed, or when the first
party requests it while only one signature has been collected.

{% hint style="info" %}
An agreement created with `expiry == 0` has **no deadline**: it never counts
as expired, so it voids only by unanimous request (or by the proposer while
it is the only signer). With a nonzero expiry, unanimous-void semantics hold
only **until that expiry passes** — an unfinalized agreement past its expiry
is voidable by a single party's request.
{% endhint %}

## Checking status

`hasSigned`, `allPartiesSigned`, `isFinalized`, `isVoided`,
`getContractDetails`, `getAgreementsForParty`.

## Related

* [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md),
  [Agreement templates](../reference/templates.md).
