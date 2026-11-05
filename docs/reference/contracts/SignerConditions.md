---
description: Creator-bound agreements with per-party conditions and evidence-bound signatures
---

# Registry signer conditions

Current `CyberAgreementRegistry` source stores conditions for the named
parties of a creator-bound agreement. This replaces the separate
`ZKPassportFinalizer` for new integrations. Source was reviewed at
[`caa8364`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/caa83643b09806d5e0036e627e7cd14cd02a3b23)
on November 4, 2026. See [deployment evidence](../deployments.md#registry-checks-on-november-4-2026)
before choosing a runtime.

## Create the agreement with fixed conditions

```solidity
struct SignerCondition { bytes32 kind; bytes params; }

createBoundContract(template, salt, globalValues, parties, partyValues,
    expiry, conditions);
createBoundContractAndSignFor(template, salt, globalValues, parties,
    partyValues, expiry, conditions, creatorEvidence, creatorSignature);
boundIdsOf(creator, template, salt, globalValues, parties, partyValues,
    expiry, conditions);
```

These are overloads of the unconditioned methods. A nonempty outer
`conditions` array must have one list per party; each party's list can be
empty. The lists are fixed at creation. The current kind is
`keccak256("MetaLeX.SignerCondition.ZKPassport.v1")`; unknown kinds are
refused. Bound agreements have exact nonzero unique parties, no secret and
no external finalizer.

`boundIdsOf` returns the template and agreement ids without creating them.
An empty outer conditions array retains the original bound-id recipe.
A nonempty outer array, even if every inner list is empty, uses
`CONDITIONED_BOUND_AGREEMENT_DOMAIN` and commits
`keccak256(abi.encode(conditions))` alongside the original terms hash.
The domain is the hash of
`MetaLeX.CyberAgreementRegistry.ConditionedBoundAgreement.v1`.
Use the helper rather than treating both encodings as interchangeable.

## Sign with the evidence in the same call

```solidity
signContractWithEvidenceFor(signer, contractId, partyValues, evidence,
    signature);
```

A party with conditions signs the EIP-712 `SignatureWithEvidenceData` type.
It has the ordinary `SignatureData` fields plus `bytes[] evidence`. The
bytes-array hash is `keccak256` of the concatenated hashes of its elements.
Read `SIGNATUREWITHEVIDENCEDATA_TYPEHASH` on the reviewed registry. The
signature binds the exact evidence submitted, agreement, signer, URI,
field schemas and values. A valid unexpired delegate can supply it.

Supply one evidence item per condition, in the stored order. The registry
checks the exact initial party values and verifies all conditions before
recording the signature. The last party's signature automatically finalizes
the bound agreement. An ordinary `signContractFor` call from a conditioned
party reverts `EvidenceRequired`; a party with no conditions uses that
ordinary path and signature type instead. Expired, voided, finalized and
already-signed agreements retain their refusal checks.

## ZKPassport parameters and configuration

| Structure | Contents |
| --- | --- |
| `ZKPassportCondition` | `bytes32 uniqueIdentifier`; zero accepts any qualifying passport, otherwise it pins the party's passport. |
| `ZKPassportEvidence` | `ProofVerificationParams proof`. |
| `ZKPassportResult` | The verified `bytes32 uniqueIdentifier`. |
| `ZKPassportConfig` | `address verifier`, `string domain`, `string scope`, `bool devMode`. |

The proof must bind the exact chain, signer and agreement id. Verification
checks the configured scope/domain, rejects a mismatched pin, and refuses
one passport used by different parties in the same agreement. Production
configuration must refuse development-mode proofs.

An admin calls `setSignerConditionConfig(kind, config)`; read it through
`getSignerConditionConfig(kind)`. This configuration applies to agreements
using that kind, so it is an operational dependency even after creation.
There is no public conditions getter in this build. Read
`SignerConditionSet` events for the stored requirements and
`SignerConditionMet` for verification results. `SignerConditionConfigSet`
records configuration changes. Results are emitted, not exposed as a stored
result getter. The passport reuse map is scoped to the agreement.

These checks differ from fundraising's `NonUSNationalityCondition`:
a passport condition on an agreement does not by itself establish Reg S
eligibility or corporate signing authority.
