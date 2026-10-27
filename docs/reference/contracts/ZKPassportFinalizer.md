# ZKPassportFinalizer

`ZKPassportFinalizer` adds per-party passport requirements to agreements in
`CyberAgreementRegistry`. It is a UUPS proxy controlled through BorgAuth.
The [source](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/ZKPassportFinalizer.sol)
was inspected on October 27, 2026. Application availability also requires a
reviewed deployment and an enabled signing flow.

## Set a requirement for each named party

```solidity
struct PartyGate {
    bool proofRequired;
    bytes32 passportId;
}
```

Pass one gate per party. A zero passport id allows any qualifying passport;
a nonzero id pins that party to a particular passport. A pin requires
`proofRequired = true`. Open slots, duplicate parties and duplicate pins
are refused. A pinned passport is reserved for its party when the agreement
is created; another party cannot use it.

`createContract(templateId, salt, globalValues, parties, partyValues,
expiry, gates)` creates through the registry with zero secret and this
contract as finalizer. The salt passed to the registry is
`uint256(keccak256(abi.encode(salt, gates)))`. Changing a gate therefore
changes the agreement id. This uses the registry's ordinary creation path,
not its creator-bound methods.

For creation and the first signature together, use
`createStandaloneContractAndSignWithProof` for a gated first party, or
`createStandaloneContractAndSignWithoutProof` for an ungated first party.
Both register the template if needed and use `parties[0]`. Their full
argument lists are in the source and the app's finalizer ABI.

## Submit signatures and passport evidence

| Method | Behavior |
| --- | --- |
| `signWithProof(contractId, params, partyValues, signature)` | Verifies and records the proof, then submits the bound party's signature to the registry. |
| `signWithoutProof(contractId, party, partyValues, signature)` | Signs for a party whose gate does not require a proof. |
| `attest(contractId, params)` | Records evidence for a gated party that already signed directly in the registry. |
| `finalize(contractId)` | Finalizes a registered agreement once all required signatures and evidence exist. |

The finalizer calls `signContractFor`, so the registry still verifies the
EIP-712 signature. Anyone can relay these methods, but cannot replace the
party's signature or proof. Proof verification checks the configured domain
and scope, the chain id, the exact agreement id in bound custom data, and
the bound sender's membership in the party list. It rejects a mismatched
pin, repeated evidence and a passport already used by another party in the
same agreement. Development proofs require a deployment initialized with
`devMode = true`.

A direct registry signature can exist before passport evidence. The
finalizer waits until every party has signed and every gated party has a
passport record before asking the registry to finalize. The registry's
expiry and void checks still apply. This passport gate is distinct from the
[NonUSNationalityCondition](../conditions.md) used in fundraising.

## Read configuration and status

Read `registry`, `verifier`, `expectedDomain`, `expectedScope`, `devMode`,
`isRegistered`, `gateOf` and `passportOf`. Events are `GatesSet`,
`PassportRecorded` and `VerifierUpdated`. An admin can update the verifier;
proxy upgrades require the owner. Verify the configured registry, verifier,
scope and development mode before using a deployment.
