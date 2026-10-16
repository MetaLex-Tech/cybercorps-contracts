# Task: ZKPassport gate for CyberAgreement

- **Status:** Active
- **Updated:** 2026-10-15 17:29 PDT
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** metalex-webapp email signing (Privy) is the consumer; no webapp changes in this task
- **Objective:** `PassportFinalizer` contract: each party records a ZKPassport proof and signs in one transaction; optional creator pins; agreement finalizes only with all proofs
- **Out of scope:** registry changes; standalone create-and-sign path (TODO in spec); adopting an agreement that already exists; webapp integration; deployment
- **Canonical plan / sources:** [specs/analysis/cyberagreement-zkpassport-gate.md](../../../specs/analysis/cyberagreement-zkpassport-gate.md)
- **Repository / branch:** cybercorps-contracts; base `develop` (e93f72cc), branch `feat/zkpassport-cyberagreement-closed-slots`
- **Verified base / code head:** tests ran on 9499ae47 plus uncommitted `src/PassportFinalizer.sol`, `test/PassportFinalizerTest.t.sol`, spec edits, this record
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Acceptance and current state

- Spec acceptance-test table: all rows covered by `test/PassportFinalizerTest.t.sol` — verified (unit, mock verifier).
- Real-proof fork test: pending (needs a sample proof with `custom_data = contractId`).
- Independent external review, merge, deployment: not started.

## Decisions and evidence

- Finalizer contract, no registry change; pins bound into `contractId` through the salt (2026-10-15, chat).
- Pins optional; one passport fills one party per agreement; pinned passports reserved at create.
- No adopt of a pre-existing agreement; the webapp read-back handles the front-run case.
- Refuses `devMode` proofs and open slots.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| New unit suite | `forge test ... --match-path test/PassportFinalizerTest.t.sol`, 9499ae47 + uncommitted files | 22 passed |
| Full unit suite | `forge test ... --nmc '(ForkTest|AdhocTest)'`, same tree, Forge 1.7.1 | 1455 passed, 0 failed |
| Size | `forge build ... --sizes` | PassportFinalizer 9,884 B |
| Fork tests | not run | no real-proof sample yet |

## Review and blockers

- Unconfirmed: the real ZKPassport verifier's `devMode` semantics, and that the SDK returns `uniqueIdentifier` from off-chain verification (needed for vetting).
- Open TODOs in the spec: proof scope, which parties need a proof, one person as two parties, standalone path.

## Next action and handoff

Review the contract and tests; then decide on a real-proof fork test and the webapp integration.
