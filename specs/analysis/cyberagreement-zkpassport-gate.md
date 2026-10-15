# CyberAgreement — ZKPassport Gate (Three-Party Workflow)

A new `PassportFinalizer` contract is the agreement's `finalizer`. The registry does not change.
Each party sends one transaction. It records the party's ZKPassport proof and the party's
signature together. The agreement finalizes only when all parties have a proof record and a
signature.

- `signWithProof(contractId, proof, partyValues, signature)`:
  1. Verifies the proof and stores `passportOf[contractId][party] = uniqueIdentifier`. The party is
     the proof's bound sender.
  2. Forwards the signature to `registry.signContractFor(party, ...)`. The registry accepts a
     relayed signature only from the finalizer, because the finalizer is set.
  3. If all parties have signed and have a proof record, calls `registry.finalizeContract`.
- `attest(contractId, proof)` does steps 1 and 3 only. It is a backup for a party that signed
  directly on the registry. The normal flow does not use it.

The example has three parties. A is the creator. B and C are email parties with pregenerated
Privy wallets. The webapp creates the agreement in its own transaction, because it reads the
agreement back before it offers any signature.

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

    Note over A,Reg: Create (tx 1)
    A->>App: Draft agreement, invite B and C by email
    App->>Privy: Look up or pregenerate wallets for B and C
    Privy-->>App: walletB, walletC
    A->>Reg: createContract(parties = [A, walletB, walletC], finalizer = PF)
    Note right of Reg: contractId binds finalizer = PF
    App->>App: Read back the agreement, then email B and C

    loop For each party P in A, B, C (any order), one tx each
        Note over P,ZKP: Off-chain: prove and sign
        P->>App: Open the signing link, log in
        App->>ZKP: Proof request, bind(user_address = wallet P, chain, custom_data = contractId)
        P->>ZKP: Scan passport
        ZKP-->>App: Proof
        P->>Privy: Sign the EIP-712 SignatureData
        Privy-->>App: Signature

        Note over App,V: On-chain: one tx
        App->>PF: signWithProof(contractId, proof, partyValues, signature)
        PF->>V: verify(proof)
        V-->>PF: verified, uniqueIdentifier, helper
        PF->>PF: Check scope, chainId, custom_data == contractId,<br/>registry.isParty(contractId, bound sender)
        PF->>PF: passportOf[contractId][P] = uniqueIdentifier
        PF->>Reg: signContractFor(P, contractId, partyValues, signature)
        Reg->>Reg: Verify signature, record signedAt[P]
        opt P is the last party
            PF->>PF: Require passportOf set for A, B and C
            PF->>Reg: finalizeContract(contractId)
            Reg-->>App: ContractFinalized
        end
    end
```

Total: four transactions. One creates the agreement. Each party sends one.

## Notes

- **Order.** The parties can act in any order and at different times. The last
  `signWithProof` finalizes the agreement.
- **Relaying.** `signWithProof` takes the party from the proof's bound sender, not from
  `msg.sender`. Anyone can submit it. The registry still checks the party's own signature.
  `custom_data = contractId` ties the proof to this agreement.
- **Self-submission.** A party can call `registry.signContractFor` from its own wallet and skip
  the proof. That party then has no proof record, so the agreement does not finalize. The party
  sends `attest` to record the proof. If that is the last missing proof, `attest` finalizes the
  agreement. The webapp must treat `finalized` as the effective state.
- TODO: Decide the proof scope. One app-wide scope makes `uniqueIdentifier` the same in every
  agreement, so it links all agreements of one passport on-chain. A per-agreement scope
  (`scope = contractId`) prevents that link.
- TODO: Decide if every party needs a proof, or only some parties.
- TODO: Support the standalone path (`createStandaloneContractAndSign`,
  `createStandaloneContractAndSignFor`). It fixes `finalizer = address(0)`, so the gate does not
  apply. The webapp email flow does not use it now.
