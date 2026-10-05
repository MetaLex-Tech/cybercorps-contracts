# Task: ZKPassport identity-bound open slots in CyberAgreementRegistry

- **Status:** Active. The code and unit tests are done (uncommitted). The fork proof (F1/F2) and the external review are open.
- **Updated:** 2026-10-01.
- **Owner:** detoo, with Claude Code on this branch.
- **Collaborators / boundaries:** Do not change DealManager, RoundManager, SecondaryTradeStorage or the factories in v1.
- **Objective:** A creator can make an agreement in which an open slot is reserved for one ZKPassport `uniqueIdentifier`. The person with that passport signs from any wallet and sends a ZKPassport proof with the signature. On chain, observers see only the wallet and an opaque identifier. An auditor confirms the person by asking the user for a new proof that discloses the name, and compares its identifier with the on-chain record. A copy of the chip data is not enough.
- **Out of scope:** DealManager integration (follow-up task). Identity on the `signContractWithEscrow` path. Replacing a constraint after creation. Sybil resistance.
- **Canonical plan / sources:** App spec "Passport-bound agreements" (`zkpassport-hello-world/tmp/zkpassport-agreement-registry.md`, outside this repo). This record. `src/CyberAgreementRegistry.sol`, `src/interfaces/IZKPassportVerifier.sol`, `src/libs/conditions/NonUSNationalityCondition.sol` (reference for the proof checks).
- **Repository / branch:** MetaLex-Tech/cybercorps-contracts; base `develop`; working branch `feat/zkpassport-cyberagreement`.
- **Verified base / code head:** `d2e06908` (clean).
- **PR / artifact:** Not yet created.

## Decisions and evidence

All decisions are from the user, 2026-10-01.

1. SUPERSEDED 2026-10-05 by the app spec. The identifier is ZKPassport's SALTED identifier. ZKPassport's OPRF nodes supply the salt from one global key, so an app cannot choose a salt per agreement. With one domain and scope, the identifier is the same in all agreements, and observers can link one person's agreements (the spec lists this as an open point). The registry does not know or check the salt. It compares the identifier that the verifier returns with the stored constraint, and it checks the proof's `domain`/`scope`.
2. `domain` and `scope` are global admin config. Each agreement stores a copy (as a hash) at creation, so a later admin change does not affect it.
3. A renewed passport gives a new identifier, and the old constraint then cannot be met. This design does not resist sybil attacks. We accept both limits and state them in NatSpec.
4. v1 changes only the registry. The new sign path lets the finalizer submit with the same rule as `signContractFor`. DealManager integration is a later task. The escrow path has no open-slot caller, so it gets only the skip rule (invariant I1).
5. The verifier address is a `constant` (`0x1D000001000EFD9a6371f4d90bB8920D5431c0D8`, the same as `NonUSNationalityCondition`). We change it with a contract upgrade.
6. EIP-170 (user, 2026-10-01): the `getContractJson` body moved to the linked library `src/libs/CyberAgreementJsonLib.sol`. The output stays byte-identical to HEAD (one-off differential check against the `d2e06908` runtime code: escapes, Unicode, unfilled slot, void request, missing agreement). The proof check stays in the registry.
7. `ZKP_DEV_MODE` immutable, set in the constructor (user, 2026-10-01). True accepts dev-mode proofs. `upgrade-core` and `deploy-cyber-agreement-registry` set it from `DeploymentConstants.isTestnet`. Older one-off scripts and tests pass `false`.
8. Standalone variant `createStandaloneContractWithIdentitySlotsAndSign(For)` added (user, 2026-10-01). It changes no other contract.
9. Keep the I2 `customData` check for extra security (user, 2026-10-01). The app must bind `custom_data` = contractId as `0x` + 64 lowercase hex chars. Empty or other formats revert (tests). A Sepolia fork run showed the real verifier rejects a proof whose bound sender was changed (`Invalid commitment`); a change to `customData` itself was not tested, because the sample proof has empty `customData`.
10. Review against the app spec (2026-10-05): added I11–I13. `signContractWithEscrow`, `_recordSignature` and `getContractDetails` now read the template through a storage pointer, not a memory copy, to stay under EIP-170. Behavior does not change.

## Design

**Storage** (append after `delegations`, `__gap` 40 → 36):

- `string identityDomain`, `string identityScope`: global, `onlyAdmin` setter, event.
- `mapping(bytes32 => bytes32) identityScopeHash`: per agreement, `keccak256(abi.encode(domain, scope))` copied at creation.
- `mapping(bytes32 => mapping(uint256 => bytes32)) slotIdentityConstraints`: contractId → slot index → required identifier. 0 means no constraint.

**Create:** `createContractWithIdentitySlots(<createContract params>, uint256[] slotIndexes, bytes32[] uniqueIdentifiers)`.

- It shares one internal body with `createContract`. The `createContract` id formula does not change.
- The id also binds `slotIndexes`, `uniqueIdentifiers` and the scope hash.
- The event gives contractId, slot, identifier, domain and scope, so auditors can read the strings.

**Sign:** `signContractWithIdentityFor(signer, contractId, slotIndex, partyValues, signature, secret, ProofVerificationParams proof)`.

- It shares the agreement checks and the bookkeeping with `signContractFor`.
- The caller names the slot. This path does not use first-fit.

## Invariants

- **I1:** Only `signContractWithIdentityFor`, with a valid proof, can fill a constrained slot. `getFirstOpenPartyIndex` skips constrained slots, so `signContractFor` and `signContractWithEscrow` with `fillUnallocated` cannot fill one.
- **I2:** The proof is valid for one agreement and one wallet only. Bound `senderAddress == signer`, bound `chainId == block.chainid`, and bound `customData` == contractId as a `0x` lowercase hex string.
- **I3:** The proof's `keccak256(domain, scope)` equals the agreement's stored copy. `helper.verifyScopes` passes with those strings.
- **I4:** The verifier's returned identifier equals `slotIdentityConstraints[contractId][slotIndex]`.
- **I5:** A registry with `ZKP_DEV_MODE == false` rejects a proof with `serviceConfig.devMode == true`. A dev-mode proof can come from a mock passport. A mock passport with Alice's data could give her identifier.
- **I6:** The proof has not expired. ZKPassport's verifier enforces this ("The proof was generated outside the validity period"). The registry does not check it again (user, 2026-10-05).
- **I7:** A front-runner cannot take the id with other constraints. The constraints and the scope hash are in `contractId`.
- **I8:** Agreements with no constraints keep the same ids and the same behavior, and all existing tests pass unchanged.
- **I9:** The upgrade keeps the storage layout. Only appended slots change, and the gap shrinks by the same count.
- **I10:** After the slot is filled, the wallet is a normal party for void, finalize and the views.
- **I11:** The proof's nullifier type is SALTED (`helper.enforceNullifierType`). A SALTED mock type passes only in dev mode, which the verifier and `ZKP_DEV_MODE` gate.
- **I12:** The proof has a strict face match (`helper.isFaceMatchVerified(STRICT, ANY)`).
- **I13:** The proof's sanctions root is valid at signing time (`helper.enforceSanctionsRoot(block.timestamp, true)`).

## Test matrix

Unit tests go in a new contract in `test/CyberAgreementRegistryIdentityTest.t.sol`. The mock verifier goes at the constant address with `vm.etch`, and it reuses the mock shape from `NonUSNationalityConditionTest`. Fork tests go in `CyberAgreementRegistryIdentityForkTest`.

| # | Case | Expect | Invariant |
|---|---|---|---|
| A1 | Admin sets domain/scope | config stored, event | — |
| A2 | Non-admin sets domain/scope | revert | — |
| C1 | Create with one constrained open slot | slot constraint + scope hash stored, event | — |
| C2 | Create when domain/scope not set | revert | I3 |
| C3 | Constraint on slot 0, on a named slot, or out of range | revert | I1 |
| C4 | Duplicate slot index | revert | — |
| C5 | Zero identifier | revert | I4 |
| C6 | Length mismatch between slots and identifiers | revert | — |
| C7 | Same params, different identifier → different contractId | ids differ | I7 |
| C8 | `createContract` id unchanged for the same params | id equals the old formula | I8 |
| C9 | Admin changes scope after create | agreement keeps the old hash and signs with the old scope; a new-scope proof reverts | Decision 2 |
| S1 | Valid proof, signer signs directly | slot filled, `AgreementSigned`, finalizes when complete | I2–I4 |
| S2 | Valid proof, delegate signs for the bound wallet | success | I2 |
| S3 | Finalizer submits for the signer | success | Decision 4 |
| S4 | Third party (not signer, not finalizer) submits, finalizer set | revert `NotFinalizer` | Decision 4 |
| R1 | Verifier returns `verified == false` / zero helper | revert | — |
| R2 | Wrong identifier | revert | I4 |
| R3 | Wrong domain or scope | revert | I3 |
| R4 | `verifyScopes` returns false | revert | I3 |
| R5 | Bound sender is not the signer | revert | I2 |
| R6 | Wrong bound chainId | revert | I2 |
| R7 | Bound customData for another contractId | revert | I2 |
| R8 | `devMode == true` | revert | I5 |
| R9 | Expired proof | revert in the ZKPassport verifier (fork test only; the unit mock does not check) | I6 |
| R10 | Slot has no constraint / slot already filled / named slot | revert | I1 |
| R11 | Wrong EIP-712 signature with a valid proof | revert `SignatureVerificationFailed` | — |
| R12 | Secret set and wrong | revert `InvalidSecret` | — |
| R13 | Expired, voided or finalized agreement | revert | — |
| E1 | `signContractFor(fillUnallocated=true)` with only constrained open slots | revert `NotAParty` | I1 |
| E2 | Mixed agreement: `signContractFor` fills the unconstrained slot, not the constrained one | correct slot | I1 |
| E3 | `signContractWithEscrow(fillUnallocated=true)` with only constrained slots | revert `NotAParty` | I1 |
| P1 | Filled wallet can void and is in `getParties`, `getAgreementsForParty`, JSON | normal party | I10 |
| L1 | Storage layout diff before and after | only appended slots | I9 |
| F1 | Fork: real verifier, real proof with `customData = contractId`, signs via delegate of the bound wallet | success | I2–I6 |
| F2 | Fork: same real proof against another contractId | revert | I2 |

F1 and F2 need a new sample proof whose `customData` is a known contractId, and whose `domain`/`scope` match the test config. The bound wallet in the proof has no known key. The test calls `vm.prank(boundWallet)` and `setDelegation` to a `makeAddrAndKey` delegate, and the delegate makes the signature.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | full unit suite on `60fa3e88` + uncommitted changes | 1,463 passed |
| Fork tests | full fork suite, same tree | 202 passed. F1/F2 not written: they need a SALTED proof with `custom_data` = a contractId |
| Size (`forge build --sizes`) | same tree | registry 24,203 B (373 B margin) |
| Storage layout | `forge inspect storageLayout` before/after | slots 0–9 unchanged; new slots 10–13; gap 36; storage still ends at slot 50 |
| JSON parity | one-off test against base runtime code (deleted after the run) | byte-identical |

## Review and blockers

- An independent external review is required before merge (signing/authorization change). Not started.
- F1/F2 need a real ZKPassport proof that binds a known contractId. Who makes it: unknown.

## Next action and handoff

Make a real ZKPassport proof that binds `custom_data` = a known contractId (Sepolia or Base Sepolia), then write fork tests F1/F2 with it. Upgrade scripts must deploy the linked `CyberAgreementJsonLib` (`new CyberAgreementRegistry` in forge scripts links it automatically; Safe batches need a check). Then the external review.
