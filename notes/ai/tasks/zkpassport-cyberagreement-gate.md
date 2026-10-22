# Task: ZKPassport gate for CyberAgreement

- **Status:** Active
- **Updated:** 2026-10-18 PDT
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** metalex-webapp email signing (Privy) is the consumer; no webapp changes in this task
- **Objective:** `ZKPassportFinalizer` contract: creator gates each party (proof required or not, optional pin); each party signs in one transaction, a gated party records its ZKPassport proof in that transaction; agreement finalizes only with all signatures and all required proofs
- **Out of scope:** registry changes; adopting an agreement that already exists; webapp integration; deployment
- **Canonical plan / sources:** [specs/analysis/cyberagreement-zkpassport-gate.md](../../../specs/analysis/cyberagreement-zkpassport-gate.md)
- **Repository / branch:** cybercorps-contracts; base `develop` (e93f72cc), branch `feat/zkpassport-cyberagreement-closed-slots`
- **Verified base / code head:** tests ran on e41d4288 plus uncommitted per-party gate change in `src/ZKPassportFinalizer.sol`, `test/ZKPassportFinalizerTest.t.sol`, spec edits, this record
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Acceptance and current state

- Spec acceptance-test table: all rows covered by `test/ZKPassportFinalizerTest.t.sol` — verified (unit, mock verifier).
- Real-proof fork test: pending (needs a sample proof with `custom_data = contractId`).
- Independent external review, merge: not started.
- Deployment: proxy `0x83580c6c950802011C339b3adf13FB9e68B2f356` (salt `CyberCorpV5-ZKPassportFinalizerV1.0.1`) on Sepolia, Ethereum and Base, recorded in `DeploymentConstants` (2026-10-21). Evidence: `broadcast/deploy-zkpassport-finalizer.s.sol/{11155111,1,8453}/run-latest.json`, all receipts status 1.

## Decisions and evidence

- Finalizer contract, no registry change; pins bound into `contractId` through the salt (2026-10-15, chat).
- Per-party gate `(proofRequired, passportId)`, bound into `contractId`; ungated parties sign through `signWithoutProof`; `finalize` added as a backup for a last direct registry signature (2026-10-18, chat).
- Pins optional and only on gated parties; one passport fills one party per agreement; pinned passports reserved at create.
- No adopt of a pre-existing agreement; the webapp read-back handles the front-run case.
- Standalone path: `createStandaloneContractAndSignWithProof` and `createStandaloneContractAndSignWithoutProof` cover both registry standalone functions; registry unchanged; signer must be the first party, checked by `SignerNotFirstParty` (2026-10-17, split 2026-10-18, check added 2026-10-21 from PR #186 review).
- Refuses open slots and repeated party addresses (`DuplicateParty`, 2026-10-21, PR #186 review). Refuses `devMode` proofs unless initialized with `devMode`; the deploy script sets it on testnets only (2026-10-15).

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| New unit suite | `forge test ... --match-path test/ZKPassportFinalizerTest.t.sol`, e41d4288 + uncommitted per-party gate change | 43 passed |
| Deploy script fork test | Removed 2026-10-21 (PR #186 review). Each recorded deployment in `DeploymentConstants` breaks its fresh-deploy premise. | No test now proves the script's config or the testnet-only `devMode` flag |
| Full unit suite | `forge test ... --nmc '(ForkTest|AdhocTest)'`, same tree, Forge 1.7.1 | 1476 passed, 0 failed |
| Size | `forge build ... --sizes`, same tree | ZKPassportFinalizer 12,498 B |

## Review and blockers

- Unconfirmed: that the deployed verifier runs ZKPassport's current `SubVerifier` source (read 2026-10-15, commit 5edbf08), and that the SDK returns `uniqueIdentifier` from off-chain verification (needed for vetting).
- Open TODOs in the spec: proof scope, one person as two parties.

## Next action and handoff

Confirm the domain and scope TODOs in `script/deploy-zkpassport-finalizer.s.sol`; then decide on a real-proof fork test and the webapp integration. Base Sepolia has no ZKPassport verifier (checked 2026-10-15), so staging uses Sepolia.
