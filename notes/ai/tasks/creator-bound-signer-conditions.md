# Task: Signer conditions on creator-bound agreements

- **Status:** Ready for review (uncommitted)
- **Updated:** 2026-10-27 PDT
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** PR #185 (creator-bound registry, not deployed); `ZKPassportFinalizer` stays unchanged and deployed
- **Objective:** A creator can attach a third-party check to each party of a creator-bound agreement. The registry records a party's signature only when that party's check passes. `ZKPassportSignerCondition` is the first check.
- **Out of scope:** conditions on `createContract` and standalone agreements; changes to `ZKPassportFinalizer`; deployment; webapp integration
- **Canonical plan / sources:** this record; `src/CyberAgreementRegistry.sol`; `src/interfaces/ISignerCondition.sol`; lessons from `ICondition` and `ISecondaryTradingCondition`
- **Repository / branch:** cybercorps-contracts; base `develop` (0a598592), branch `feat/creator-bound-zkpassport-condition`
- **Verified base / code head:** base 0a598592 plus uncommitted changes: `src/CyberAgreementRegistry.sol`, `src/ZKPassportSignerCondition.sol`, `src/interfaces/ISignerCondition.sol`, `test/CyberAgreementRegistryBoundTest.t.sol`, `test/ZKPassportSignerConditionTest.t.sol`, `script/deploy-bound-agreement-registry.s.sol`, `script/README-bound-agreement-upgrade.md`, this record
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Design

- Per-party `SignerCondition { condition, data }`. The creator sets it at creation. It goes into the `contractId`, so each signature covers it.
- `signContractFor` calls `ISignerCondition.checkSigner(registry, contractId, party, data)` (view) before it records the signature. A false result reverts with `SignerConditionNotMet`.
- New ABI is additive only: overloads of `createBoundContract` and `createBoundContractAndSignFor` with a `conditions` argument, `getSignerCondition`, `boundIdsOf`, `CONDITIONED_BOUND_AGREEMENT_DOMAIN`, event `SignerConditionSet`, three errors.
- The bound creation code moves to the linked `CyberAgreementBound` library, because the registry had 238 B of EIP-170 margin.
- `ZKPassportSignerCondition.submitProof` records a passport for the proof's bound sender and the `contractId` in the proof's custom data. Anyone can relay it, also before the agreement exists. `checkSigner` passes when the party has a record and the record matches the optional pin in `data`.

## Invariants

1. Existing selectors, parameters and returns do not change. The existing bound functions keep their ID formula.
2. Only the new bound overloads can store a condition. No function changes a stored condition.
3. A party with a condition cannot get a signature recorded unless `checkSigner` returns true at that time. This applies to every caller of `signContractFor`, including relayers and the create-and-sign overload.
4. An agreement with conditions has a different `contractId` from the same agreement without conditions, and the ID changes with any condition or its data.
5. A condition contract must report `ISignerCondition` through ERC-165 at creation.
6. One passport fills at most one party in one agreement. A pinned party passes only with its pinned passport.

## Acceptance tests

| # | Case | Expected |
| --- | --- | --- |
| R1 | `boundIdsOf` with no conditions | Equals the PR #185 formula and the ID from the existing functions |
| R2 | Conditioned create | Stores conditions, emits `SignerConditionSet` for each nonzero condition, ID from `boundIdsOf` |
| R3 | ID depends on condition address and data | Different IDs |
| R4 | Conditions length differs from parties | `SignerConditionsLengthMismatch` |
| R5 | Condition is an EOA or does not support the interface | `InvalidSignerCondition` |
| R6 | Party's check returns false | `signContractFor` reverts `SignerConditionNotMet` (direct and relayed) |
| R7 | Creator's check returns false in create-and-sign | Whole call reverts, no agreement |
| R8 | Check passes | Signature recorded; last signature finalizes |
| R9 | Party with zero-address condition | Signs with no check |
| R10 | Original `createContract` agreement | Signs as before; `getSignerCondition` empty |
| Z1 | `submitProof` then create-and-sign in one flow | Creator's passport recorded; signature recorded |
| Z2 | No proof | `SignerConditionNotMet` |
| Z3 | Pin mismatch | `checkSigner` false |
| Z4 | Same passport for a second party | `PassportAlreadyUsed` |
| Z5 | Proof for another contractId, chain, scope, or dev mode | Refused |
| Z6 | Second record for the same party | `AlreadyRecorded` |
| Z7 | `checkSigner` from another registry | false |
| Z8 | Relayer settles in one transaction: one `aggregate3` call with both proofs, create-and-sign for Alice, and the signatures of Bob and Chad | Agreement finalized; passports recorded |
| Z9 | Same batch without one gated party's proof | Whole batch reverts; no agreement and no passport record stay |

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Acceptance R1-R10 | `forge test ... --match-path test/CyberAgreementRegistryBoundTest.t.sol`, Forge 1.8.5, real registry, allow-list test condition | 20 passed (8 existing bound tests unchanged) |
| Acceptance Z1-Z9 | `forge test ... --match-path test/ZKPassportSignerConditionTest.t.sol`, real registry, mock ZKPassport verifier, test copy of Multicall3 `aggregate3` | 22 passed |
| Full unit suite | `forge test ... --nmc '(ForkTest\|AdhocTest)'`, Forge 1.8.5 | 1544 passed, 13 failed. All 13 also fail on base 0a598592 with Forge 1.8.5 (5 secondary gas guards, 6 footer/rendering script nonces, 2 bound deploy-script nonce checks). CI pins 1.7.1; not run on 1.7.1 |
| Registry fork suites | `forge test ... --match-contract '(CreditFacilityFactoryForkTest\|RoundManagerForkTest\|CyberCorpUpgradeabilityForkTest\|ShareExtensionForkTest\|SAFORolloutForkTest)' --threads 1 --cups 10` | 17 passed, 1 skipped (skip pre-existing) |
| ABI diff vs base | `forge inspect` methodIdentifiers, events, errors | Only additions; no selector, event or error removed or changed |
| Storage layout vs base | `forge inspect storageLayout` | `signerConditions` at slot 10; `__gap` 40 -> 39; total unchanged |
| Size | `forge build ... --sizes` | Registry 23,770 B (806 B margin, was 238 B); CyberAgreementBound 7,064 B; ZKPassportSignerCondition 7,089 B |

## Review and blockers

- Independent external-model review: not started.
- A condition contract's owner can change its code if it is upgradeable. The ID binds the address, not the code.
- Template squatting can still block a bound creation (existing PR #185 behavior).

## Next action and handoff

User review of the uncommitted change; then commit, PR, and the required independent external-model review. The PR #185 Safe batches in `script/res/gnosis-batch-bound-registry-*.json` are now stale, because the registry implementation changed; regenerate them at deployment time.
