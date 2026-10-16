# CyberAgreement — ZKPassport Gate (Three-Party Workflow)

A new `PassportFinalizer` contract is the agreement's `finalizer`. The registry does not change.
Each party sends one transaction. It records the party's ZKPassport proof and the party's
signature together. The agreement finalizes only when all parties have a proof record and a
signature.

The creator can pin a passport to a party. The creator first checks that party's passport
off-chain (for example, the name on it). The pin is that passport's `uniqueIdentifier`. The party
can then sign only with that passport.

- `createContract(templateId, salt, globalValues, parties, partyValues, expiry, passportIds)`:
    1. Requires one `passportIds` entry for each party. `bytes32(0)` means "any passport". Two
       parties cannot have the same pin. Refuses an open slot (zero-address party), because pins
       and passport records belong to a party address.
    2. Calls `registry.createContract` with `finalizer = PassportFinalizer`, `secretHash = 0` and
       `salt = keccak256(abi.encode(salt, passportIds))`. Thus `contractId` binds the pins.
    3. Stores the pins and marks the agreement as registered here. A pinned passport is reserved
       for its party from the start.
- `signWithProof(contractId, proof, partyValues, signature)`:
    1. Verifies the proof. The party is the proof's bound sender. Requires that the agreement is
       registered here.
    2. If the party has a pin, requires `uniqueIdentifier == pin`.
    3. Requires that no other party of this agreement used the same `uniqueIdentifier`.
    4. Stores `passportOf[contractId][party] = uniqueIdentifier`.
    5. Forwards the signature to `registry.signContractFor(party, ...)`. The registry accepts a
       relayed signature only from the finalizer, because the finalizer is set.
    6. If all parties have signed and have a proof record, calls `registry.finalizeContract`.
- `attest(contractId, proof)` does steps 1–4 and 6 only. It is a backup for a party that signed
  directly on the registry. The normal flow does not use it.

The example has three parties. A is the creator. B and C are email parties with pregenerated
Privy wallets. A pins B's passport and leaves C unpinned. The webapp creates the agreement in its
own transaction, because it reads the agreement back before it offers any signature.

## Workflow

```mermaid
sequenceDiagram
    autonumber
    actor A as Party A (creator)
    actor B as Party B (pinned)
    actor P as Party P (A, B or C)
    participant App as Webapp + relayer
    participant Privy
    participant ZKP as ZKPassport app
    participant PF as PassportFinalizer
    participant Reg as CyberAgreementRegistry
    participant V as ZKPassport verifier
    Note over A, ZKP: Vet (off-chain, pinned parties only)
    A ->> App: Ask B to show a passport
    App ->> ZKP: Proof request, disclose name, same domain and scope as signing
    B ->> ZKP: Scan passport
    ZKP -->> App: Name, uniqueIdentifier U_B
    App -->> A: Name on B's passport
    A ->> App: Approve, pin U_B to B
    Note over A, Reg: Create (tx 1)
    A ->> App: Draft agreement, invite B and C by email
    App ->> Privy: Look up or pregenerate wallets for B and C
    Privy -->> App: walletB, walletC
    A ->> PF: createContract(parties = [A, walletB, walletC],<br/>passportIds = [0, U_B, 0])
    PF ->> Reg: createContract(salt = hash(salt, passportIds), finalizer = PF)
    PF ->> PF: Store pins
    Note right of Reg: contractId binds finalizer and pins
    App ->> App: Read back the agreement and the pins, then email B and C

    loop For each party P in A, B, C (any order), one tx each
        Note over P, ZKP: Off-chain: prove and sign
        P ->> App: Open the signing link, log in
        App ->> ZKP: Proof request, bind(user_address = wallet P, chain, custom_data = contractId)
        P ->> ZKP: Scan passport
        ZKP -->> App: Proof
        P ->> Privy: Sign the EIP-712 SignatureData
        Privy -->> App: Signature
        Note over App, V: On-chain: one tx
        App ->> PF: signWithProof(contractId, proof, partyValues, signature)
        PF ->> V: verify(proof)
        V -->> PF: verified, uniqueIdentifier U, helper
        PF ->> PF: Check scope, chainId, custom_data == contractId,<br/>agreement registered here, bound sender is a party
        PF ->> PF: Require U == pin of P (if pinned),<br/>U not used by another party
        PF ->> PF: passportOf[contractId][P] = U
        PF ->> Reg: signContractFor(P, contractId, partyValues, signature)
        Reg ->> Reg: Verify signature, record signedAt[P]
        opt P is the last party
            PF ->> PF: Require passportOf set for A, B and C
            PF ->> Reg: finalizeContract(contractId)
            Reg -->> App: ContractFinalized
        end
    end
```

Total: four transactions. One creates the agreement. Each party sends one. The vetting step is
off-chain.

## Notes

- **Order.** The parties can act in any order and at different times. The last
  `signWithProof` finalizes the agreement.
- **Relaying.** `signWithProof` takes the party from the proof's bound sender, not from
  `msg.sender`. Anyone can submit it. The registry still checks the party's own signature.
  `custom_data = contractId` ties the proof to this agreement.
- **One passport, one party.** Within one agreement, each `uniqueIdentifier` can fill one party
  only. A pin stops a party from using another person's passport. An unpinned party can use any
  passport that no other party of the agreement used.
- **Pins and scope.** `uniqueIdentifier` depends on the passport, the domain and the scope. The
  vetting proof and the signing proof must use the same domain and scope, or the pin never
  matches. The scope cannot be `contractId`, because `contractId` depends on the pins.
- **Pinned party visits twice.** A pinned party opens the app once for vetting and once to sign.
  An unpinned party opens it once.
- **Create front-run.** Anyone can call `registry.createContract` with the same arguments and the
  derived salt before the creator. The registry then refuses the creator's call, and
  `PassportFinalizer` has no record of that agreement, so it refuses every signature. The attacker
  gains nothing. The creator must create again with a new salt.
- **Self-submission.** A party can call `registry.signContractFor` from its own wallet and skip
  the proof. That party then has no proof record, so the agreement does not finalize. The party
  sends `attest` to record the proof. If that is the last missing proof, `attest` finalizes the
  agreement. The webapp must treat `finalized` as the effective state.
- **Proof format.** The proof binds `custom_data` to `contractId` as a lowercase `0x` hex string
  of 32 bytes. `PassportFinalizer` refuses a proof with `devMode = true`.
- TODO: Decide the proof scope. It must be the same for vetting and signing. One app-wide scope
  makes `uniqueIdentifier` the same in every agreement, so it links all agreements of one passport
  on-chain.
- TODO: Decide if every party needs a proof, or only some parties.
- TODO: Decide if one person can fill two parties (for example, as an individual and as an officer
  of a company). The one-passport-one-party rule refuses this now.
- TODO: Support the standalone path (`createStandaloneContractAndSign`,
  `createStandaloneContractAndSignFor`). It fixes `finalizer = address(0)`, so the gate does not
  apply. The webapp email flow does not use it now.

## Invariants

1. An agreement with `finalizer = PassportFinalizer` finalizes only when every party has signed
   and has a passport record.
2. A passport record comes only from a proof that verifies, has the expected domain and scope,
   is bound to this chain and to this `contractId`, and is not in dev mode.
3. The record goes to the proof's bound sender. That address must be a party of the agreement.
4. A pinned party's record equals its pin.
5. Within one agreement, a passport fills one party only, and each party has one record.
6. Only `PassportFinalizer.createContract` registers an agreement and its pins. `contractId`
   binds the pins through the salt.

## Acceptance tests

| Case                                                                              | Expected                                         |
|-----------------------------------------------------------------------------------|--------------------------------------------------|
| Three parties, each `signWithProof`, any order                                    | Last call finalizes; each record stored          |
| Pinned party proves with its pinned passport                                      | Signs                                            |
| Pinned party proves with another passport                                         | `PassportPinMismatch`                            |
| Two parties prove with the same passport                                          | Second call `PassportAlreadyUsed`                |
| Unpinned party proves with another party's pinned passport                        | `PassportAlreadyUsed`                            |
| Two parties with the same non-zero pin at create                                  | `DuplicatePin`                                   |
| `passportIds` length differs from `parties`                                       | `PassportIdsLengthMismatch`                      |
| Zero-address party at create                                                      | `OpenSlotNotSupported`                           |
| Different pins, same other arguments                                              | Different `contractId`                           |
| Agreement created on the registry directly                                        | `signWithProof` reverts `AgreementNotRegistered` |
| Proof fails, zero helper, wrong scope, wrong chain, wrong `custom_data`, dev mode | Reverts with the matching error                  |
| Bound sender is not a party                                                       | `NotAParty`                                      |
| Valid proof, bad signature                                                        | Registry reverts; no record stays                |
| Party signs on the registry directly, then `attest`                               | Last `attest` finalizes                          |
| `attest` before the party signs                                                   | `NotSigned`                                      |
| Same party proves twice                                                           | `AlreadyRecorded`                                |
| Non-last party signs                                                              | Not finalized                                    |
