---
description: Register a template, create a multi-party agreement, collect EIP-712 signatures and finalize or void it in the CyberAgreementRegistry
---

# Sign a cyberAgreement

cyberSign runs on the `CyberAgreementRegistry`, which holds agreement
templates and the executed contracts made from them. Deals and rounds create
their agreements in the same registry.

## 1. Register a template

A template is a reusable legal document with a field schema. Anyone can
register one. Ids are first-come, and a collision reverts
`TemplateAlreadyExists`.

```solidity
ICyberAgreementRegistry(registry).createTemplate(
    templateId,        // bytes32, the id you choose
    "Series A Stockholder Consent v1",  // title
    "ipfs://...",      // legalContractUri (canonical text)
    globalFields,      // string[], fields common to the contract
    partyFields        // string[], fields filled per signing party
);
```

A one-off agreement can skip this step.
`createStandaloneContractAndSign(title, legalContractUri, globalFields,
partyFields, salt, globalValues, parties, partyValues, expiry, signature)`
derives a template id from the content, creates the template if it does not
exist, creates the contract and records the proposer's signature, all in one
transaction.

## 2. Create a contract from the template

```solidity
bytes32 contractId = ICyberAgreementRegistry(registry).createContract(
    templateId,
    salt,           // uint256
    globalValues,   // string[]
    parties,        // address[]
    partyValues,    // string[][], per-party values
    secretHash,     // bytes32
    finalizer,      // address allowed to finalize
    expiry          // uint256
);
```

`createContract` returns the id, and the registry emits it in
`ContractCreated`. An `eth_call` of the same `createContract` predicts it
before you send. When a party must sign before the agreement exists (the
proposer of a standalone agreement, for example), compute the id as
`keccak256(abi.encode(templateId, salt, globalValues, parties, secretHash,
finalizer))`. For a standalone agreement, use `secretHash = 0`,
`finalizer = address(0)` and the derived template id.

A registry with the older signature type, whose
`SIGNATUREDATA_TYPEHASH()` returns `0x49ba7af1…0da4`, derives the id from
four fields only: `keccak256(abi.encode(templateId, salt, globalValues,
parties))`. The separate zkSync Era deployment is one. Both registry types
report `version()` `"1"`, so only the typehash tells them apart.

## 3. Collect each party's signature

Every signing entry point carries the signer's EIP-712 signature over the
agreement content. On a registry with the current type, the typed data is:

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
signature; the registry accepts the signature for that party only. Read
`SIGNATUREDATA_TYPEHASH()` on the registry before signing. `0xe37d17c3…6f05`
means the type above. `0x49ba7af1…0da4`, the older type used by the zkSync
Era deployment, expects the same struct without `signer`.

The registry has three signing entry points:

* `signContract(contractId, partyValues, signature, fillUnallocated, secret)`
  records the caller's own signature.
* `signContractFor(signer, contractId, partyValues, signature, fillUnallocated, secret)`
  relays another party's EIP-712 signature.
* `signContractWithEscrow(escrowSigner, contractId, partyValues, signature, fillUnallocated, secret)`
  applies a pre-escrowed signature. Only the contract's finalizer can call
  it, so the agreement must name a nonzero finalizer, such as a DealManager
  or RoundManager (`FinalizerNotDefined` otherwise).

When every party has signed, the registry emits `ContractFullySigned`.

A party can delegate signing authority with `setDelegation(delegate,
expiry)` (`expiry == 0` means no expiry) and withdraw it with
`revokeDelegation()`. The delegate signs `SignatureData` with `signer` set
to the delegating party.

## 4. Finalize the contract

A contract created with `finalizer == address(0)` finalizes automatically
when the last party signs. Otherwise the finalizer calls:

```solidity
ICyberAgreementRegistry(registry).finalizeContract(contractId);
```

## Void an agreement

`voidContractFor(contractId, party, signature)` records a party's void
request. The signature is an EIP-712
`VoidSignatureData(bytes32 contractId,address party)` signature by the party
or its delegate, and the finalizer can submit a request with no signature.
The contract voids when every allocated party requests it (unfilled open
slots don't count toward unanimity), when its nonzero expiry has passed, or
when the first party requests it while only one signature has been
collected.

{% hint style="info" %}
An agreement created with `expiry == 0` has **no deadline**. It never counts
as expired, so it voids only by unanimous request, or by the proposer while
it is the only signer. With a nonzero expiry, the unanimity requirement
holds only **until that expiry passes**; after that, a single party's
request voids an unfinalized agreement.
{% endhint %}

## Check an agreement's status

Read status with `hasSigned`, `allPartiesSigned`, `isFinalized`, `isVoided`,
`getContractDetails` and `getAgreementsForParty`.

Function-level detail is in
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md),
and MetaLeX's template library is in [Agreement
templates](../reference/templates.md).
