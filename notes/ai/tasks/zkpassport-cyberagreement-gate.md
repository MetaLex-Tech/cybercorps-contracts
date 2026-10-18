# Task: ZKPassport gate for CyberAgreement

- **Status:** Active
- **Updated:** 2026-10-17 PDT
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** metalex-webapp email signing (Privy) is the consumer; no webapp changes in this task
- **Objective:** `ZKPassportFinalizer` contract: each party records a ZKPassport proof and signs in one transaction; optional creator pins; agreement finalizes only with all proofs
- **Out of scope:** registry changes; adopting an agreement that already exists; webapp integration; deployment
- **Canonical plan / sources:** [specs/analysis/cyberagreement-zkpassport-gate.md](../../../specs/analysis/cyberagreement-zkpassport-gate.md)
- **Repository / branch:** cybercorps-contracts; base `develop` (e93f72cc), branch `feat/zkpassport-cyberagreement-closed-slots`
- **Verified base / code head:** tests ran on d0031cc3 plus uncommitted standalone change in `src/ZKPassportFinalizer.sol`, `test/ZKPassportFinalizerTest.t.sol`, spec edits, this record
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Acceptance and current state

- Spec acceptance-test table: all rows covered by `test/ZKPassportFinalizerTest.t.sol` — verified (unit, mock verifier).
- Real-proof fork test: pending (needs a sample proof with `custom_data = contractId`).
- Independent external review, merge, deployment: not started.

## Decisions and evidence

- Finalizer contract, no registry change; pins bound into `contractId` through the salt (2026-10-15, chat).
- Pins optional; one passport fills one party per agreement; pinned passports reserved at create.
- No adopt of a pre-existing agreement; the webapp read-back handles the front-run case.
- Standalone path: `ZKPassportFinalizer.createStandaloneContractAndSignWithProof` covers both registry standalone functions; registry unchanged; signer must be the first party (2026-10-17).
- Refuses open slots. Refuses `devMode` proofs unless initialized with `devMode`; the deploy script sets it on testnets only (2026-10-15).

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| New unit suite | `forge test ... --match-path test/ZKPassportFinalizerTest.t.sol`, d0031cc3 + uncommitted standalone change | 29 passed |
| Deploy script fork test | `test/createx/DeployZKPassportFinalizerScriptForkTest.t.sol`, same tree; Base, Sepolia and Base Sepolia pinned | 3 passed; no real-proof sample yet |
| Full unit suite | `forge test ... --nmc '(ForkTest|AdhocTest)'`, same tree, Forge 1.7.1 | 1462 passed, 0 failed |
| Size | `forge build ... --sizes`, same tree | ZKPassportFinalizer 11,252 B |

## Review and blockers

- Unconfirmed: that the deployed verifier runs ZKPassport's current `SubVerifier` source (read 2026-10-15, commit 5edbf08), and that the SDK returns `uniqueIdentifier` from off-chain verification (needed for vetting).
- Open TODOs in the spec: proof scope, which parties need a proof, one person as two parties.

## Next action and handoff

Confirm the domain and scope TODOs in `script/deploy-zkpassport-finalizer.s.sol`; then decide on a real-proof fork test and the webapp integration. Base Sepolia has no ZKPassport verifier (checked 2026-10-15), so staging uses Sepolia.
