# CyberAgreement — ZKPassport Gate (Three-Party Workflow)

A new `PassportFinalizer` contract is the agreement's `finalizer`. The registry does not change.
Each party records a ZKPassport proof for the agreement. The agreement finalizes only when all
parties have a proof record and a signature.

- `attest(contractId, proof)` stores `passportOf[contractId][party] = uniqueIdentifier`.
- `signFor(...)` forwards a signature to `registry.signContractFor`. The registry accepts a relayed
  signature only from the finalizer, because the finalizer is set.
- `finalize(contractId)` checks a record for every party, then calls `registry.finalizeContract`.

The example has three parties. A is the creator. B and C are email parties with pregenerated
Privy wallets.

## Workflow

```mermaid
sequenceDiagram
    autonumber
    actor A as Party A (creator)
    actor P as Party P (A, B or C)
    participant App as Webapp + relayer
    participant Privy
    participant ZKP as ZKPassport app
    participant PF as PassportFinalizer
    participant Reg as CyberAgreementRegistry
    participant V as ZKPassport verifier

    Note over A,Reg: Create
    A->>App: Draft agreement, invite B and C by email
    App->>Privy: Look up or pregenerate wallets for B and C
    Privy-->>App: walletB, walletC
    A->>Reg: createContract(parties = [A, walletB, walletC], finalizer = PF)
    Note right of Reg: contractId binds finalizer = PF
    App->>App: Read back the agreement, then email B and C

    loop For each party P in A, B, C (any order)
        Note over P,V: Prove
        P->>App: Open the signing link, log in
        App->>ZKP: Proof request, bind(user_address = wallet P, chain, custom_data = contractId)
        P->>ZKP: Scan passport
        ZKP-->>App: Proof
        App->>PF: attest(contractId, proof)
        PF->>V: verify(proof)
        V-->>PF: verified, uniqueIdentifier, helper
        PF->>PF: Check scope, chainId, custom_data == contractId,<br/>registry.isParty(contractId, bound sender)
        PF->>PF: passportOf[contractId][P] = uniqueIdentifier

        Note over P,Reg: Sign
        P->>Privy: Sign the EIP-712 SignatureData
        Privy-->>App: Signature
        App->>PF: signFor(P, contractId, partyValues, signature)
        PF->>PF: Require passportOf[contractId][P] is set
        PF->>Reg: signContractFor(P, ...)
        Reg->>Reg: Verify signature, record signedAt[P]
    end

    Note over App,Reg: Finalize
    Reg-->>App: ContractFullySigned (no auto-finalize, finalizer is set)
    App->>PF: finalize(contractId)
    PF->>PF: Require passportOf set for A, B and C
    PF->>Reg: finalizeContract(contractId)
    Reg-->>App: ContractFinalized
```

## Notes

- **Order.** Each party proves before it signs through `signFor`. The parties can act in any
  order and at different times.
- **Relaying.** `attest` takes the party from the proof's bound sender, not from `msg.sender`.
  Anyone can submit it. `custom_data = contractId` ties the proof to this agreement.
- **Self-submission.** A party can call `registry.signContractFor` from its own wallet and skip
  `signFor`. The agreement then becomes fully signed but not finalized. `finalize` still requires
  all three proof records. The webapp must treat `finalized` as the effective state.
- **Finalize caller.** `finalize` has no access control. It can only finalize an agreement that has
  all signatures and all proof records.
- TODO: Decide the proof scope. One app-wide scope makes `uniqueIdentifier` the same in every
  agreement, so it links all agreements of one passport on-chain. A per-agreement scope
  (`scope = contractId`) prevents that link.
- TODO: Decide if every party needs a proof, or only some parties.
