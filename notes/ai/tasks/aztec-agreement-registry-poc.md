# Task: Aztec private agreement registry PoC

- **Status:** Ready for review
- **Updated:** 2026-11-01 (local time)
- **Owner:** Claude Code session for the user (detoo)
- **Collaborators / boundaries:** New files under `aztec/` only. No change to `src/`, `test/` or `script/`.
- **Objective:** A minimal Aztec port of `CyberAgreementRegistry.createBoundContractAndSignFor`, privacy first,
  with architecture and user-flow docs.
- **Out of scope:** Counterparty signature, void, finalize, open slots, finalizer, signer conditions. Mainnet
  deployment.
- **Canonical plan / sources:** `aztec/README.md`, `aztec/ARCHITECTURE.md`, `aztec/USER-FLOWS.md`
- **Repository / branch:** cybercorps-contracts, `feat/aztec`
- **Verified base / code head:** base `fd9a1e65`; `aztec/` is uncommitted
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Acceptance and current state

- Contract compiles with Aztec 6.0.0: verified.
- TXE tests pass: verified (14 of 14).
- Two-wallet flow on a local network with offchain delivery: verified (13 of 13 checks), fake proofs only.
- Docs for architecture and user flows: written.
- Mainnet deployment: not done, no authority.

## Decisions and evidence

- Agreement data stays offchain. The chain keeps a signature nullifier and one event commitment (3 nullifiers per
  tx, measured on the local network).
- Private event with `MessageDelivery::offchain()`, not per-party notes. One commitment for all parties hides the
  party count.
- `#[authorize_once]` replaces EIP-712 signatures and the `delegations` map. A private authwit runs in the signer
  PXE, so a remote relayer cannot use it. A MetaLeX FPC pays fees instead.
- `MAX_PARTIES` is 4, from the 11-field event limit.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Compile | `aztec compile` in `aztec/`, uncommitted on `fd9a1e65` | Passed |
| TXE tests | `aztec test` | 14 passed; TXE cannot test rollup expiry rejection |
| Local network | `aztec start --local-network --port 8090`, then `node e2e.ts` | 13 checks passed; node had `realProofs=false` |
| Deploy script | `node deploy.ts` on the local network, test account 2 | Passed |

## Review and blockers

No independent review. Real-proof run and mainnet deploy need a funded deployer and user authorization.

## Next action and handoff

User reviews the PoC and docs. Next code step: a counterparty `sign_for` function.
