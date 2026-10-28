# Task: Signer conditions on creator-bound agreements

- **Status:** Ready for review (uncommitted on top of wip commit 4d4ef689)
- **Updated:** 2026-10-27 PDT
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** PR #185 (creator-bound registry, not deployed); `ZKPassportFinalizer` stays unchanged and deployed
- **Objective:** A creator can attach conditions to each party of a creator-bound agreement. A party with conditions signs together with its evidence (for example a ZKPassport proof), and its signature covers the evidence. A relayer can settle the whole agreement in one transaction.
- **Out of scope:** conditions on legacy (`createContract`, standalone) agreements; changes to `ZKPassportFinalizer`; deployment; webapp integration
- **Canonical plan / sources:** this record; `src/CyberAgreementRegistry.sol`; `src/interfaces/ISignerConditions.sol`; `src/libs/SignerConditionLib.sol`; `src/libs/ZKPassportConditionLib.sol`
- **Repository / branch:** cybercorps-contracts; base `develop` (0a598592), branch `feat/creator-bound-zkpassport-condition`
- **Verified base / code head:** 4d4ef689 plus uncommitted changes: `src/CyberAgreementRegistry.sol` (conditions getters removed), `test/libs/CyberAgreementUtils.sol`, `test/CyberAgreementRegistrySignerConditionsTest.t.sol` (new), `notes/ai/CURRENT-STATE.md`, this record
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Design

- `SignerCondition { bytes32 kind; bytes params; }`. `conditions[i]` lists the conditions of `parties[i]`; all must pass. The conditions are part of the `contractId` (domain `ConditionedBoundAgreement.v1`). An empty outer list gives the PR #185 id.
- Each kind defines the structs inside `params`, evidence, the `SignerConditionMet` result and the config. ZKPassport (`keccak256("MetaLeX.SignerCondition.ZKPassport.v1")`): `ZKPassportCondition { uniqueIdentifier }` (zero = any passport), `ZKPassportEvidence { proof }`, `ZKPassportResult { uniqueIdentifier }`, `ZKPassportConfig { verifier, domain, scope, devMode }`. A changed struct means a new kind.
- A party with conditions signs with `signContractWithEvidenceFor` and the new EIP-712 type `SignatureWithEvidenceData` (`SignatureData` fields plus `bytes[] evidence`). All other signers keep `signContractFor` and `SignatureData`. `signContractFor` reverts `EvidenceRequired` for a party with conditions (one extra cold storage read on every legacy signature).
- The logic and state are in linked libraries that run in the registry: `CyberAgreementBound` (creation, signing with evidence, config) with `SignerConditionLib` and `ZKPassportConditionLib` inlined. Their state is in namespaced slots, so the registry storage layout does not change.
- Config per kind is set by `ADMIN_ROLE`. No duplicate-kind check. No stored result; the ZKPassport library keeps the reverse map `contractId => uniqueIdentifier => party` so one passport fills one party per agreement.
- No conditions getter, to keep EIP-170 margin. Readers use `SignerConditionSet` events.

## Invariants

1. Legacy selectors, events, errors, signature type and behavior do not change. Storage layout does not change.
2. Only bound creation can store conditions; nothing changes them later.
3. A party with conditions gets a signature recorded only through the evidence path, after every condition passes in that call.
4. The signature of a party with conditions covers each evidence item.
5. One passport fills at most one party in an agreement; a pinned condition accepts only its passport.

## Acceptance and current state

`test/CyberAgreementRegistrySignerConditionsTest.t.sol` (42 tests) covers: config (admin only, unknown kind, zero verifier); creation (events, id depends on conditions, same kind twice, length mismatch, unknown kind, bad params, kind not configured); signing (all parties then finalize, create-and-sign with and without creator evidence, `EvidenceRequired`, `NoSignerConditions` on a party without conditions and on a legacy agreement, evidence length, signature must cover the submitted evidence, legacy-type signature refused, delegate, party values mismatch, already signed, no agreement); ZKPassport checks (other agreement, chain, scope, dev mode both ways, not verified, zero helper, bound to another wallet, pin mismatch, passport used by another party); lifecycle (sign after expiry, void after expiry, void by proposer then sign refused, unanimous void, void after finalize refused); relayer settlement in one `aggregate3` transaction, and the whole batch reverts when one proof is invalid.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| New and related suites | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --match-path 'test/{CyberAgreementRegistrySignerConditionsTest,CyberAgreementRegistryBoundTest,ZKPassportFinalizerTest}.t.sol'`, Forge 1.8.5; real registry, mock ZKPassport verifier, test copy of Multicall3 `aggregate3` | 97 passed |
| Mutation checks | Removed the `EvidenceRequired` guard; removed the evidence from the digest | Both detected (2 and 12 failures) |
| Full unit suite | `forge test ... --nmc '(ForkTest\|AdhocTest)'`, Forge 1.8.5 | 1556 passed, 13 failed; the same 13 fail on base 0a598592 with Forge 1.8.5. CI pins 1.7.1; not run on 1.7.1 |
| Registry fork suites | `forge test ... --match-contract '(CreditFacilityFactoryForkTest\|RoundManagerForkTest\|CyberCorpUpgradeabilityForkTest\|ShareExtensionForkTest\|SAFORolloutForkTest)' --threads 1 --cups 10` | 17 passed, 1 skipped (pre-existing skip) |
| ABI diff vs base | `forge inspect` methodIdentifiers, events, errors | Only additions |
| Storage layout vs base | `forge inspect storageLayout` | Identical |
| Size | `forge build ... --sizes` | Registry 22,942 B (1,634 B margin); CyberAgreementBound 13,187 B |

## Review and blockers

- Independent external-model review: not started. No real ZKPassport proof has been used; no fork test against the canonical Multicall3.
- The PR #185 Safe batches in `script/res/gnosis-batch-bound-registry-*.json` are stale; regenerate them at deployment time. The ZKPassport config must be set (`setSignerConditionConfig`) on each chain before conditioned agreements can be created.
- Template squatting can still block a bound creation (existing PR #185 behavior).

## Next action and handoff

User review, then commit and PR. If a later registry change does not fit under EIP-170, move the bound and condition functions to an extension contract that the registry reaches through `fallback()`; keep new registry state in namespaced storage so the move needs no extra layout coupling.
