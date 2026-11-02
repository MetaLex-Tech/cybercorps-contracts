# Task: Aztec private agreement registry PoC

- **Status:** Ready for review (lifecycle redesign)
- **Updated:** 2026-11-02 (local time)
- **Owner:** Claude Code session for the user (detoo)
- **Collaborators / boundaries:** New files under `aztec/` only. No change to `src/`, `test/` or `script/`.
- **Objective:** A minimal Aztec port of `CyberAgreementRegistry.createBoundContractAndSignFor`, privacy first,
  with architecture and user-flow docs.
- **Scope update (2026-11-01):** The full happy path. Every party signs offchain. MetaLeX collects the signatures
  and settles them in one tx. At the end, all parties and an auditor that a party shares with see the details and
  the status "finalized".
- **Out of scope:** Void, open slots, finalizer, signer conditions, escrow. Mainnet deployment.
- **Canonical plan / sources:** `aztec/README.md`, `aztec/ARCHITECTURE.md`, `aztec/USER-FLOWS.md`
- **Repository / branch:** cybercorps-contracts, `feat/aztec`
- **Verified base / code head:** base `fd9a1e65`; `aztec/` is uncommitted
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Invariants (lifecycle redesign)

1. `finalize` succeeds only when each address in `parties[0..party_count]` gave a private authwit for the consent
   hash of this agreement id, to this registry, on this chain.
2. A consent for one agreement cannot finalize another agreement.
3. One agreement finalizes once.
4. `finalize` fails after the expiry.
5. The finalize tx has the same number of nullifiers for 1 to `MAX_PARTIES` parties. It has no logs and no note
   hashes.
6. The MetaLeX settler never receives the salt or `terms_hash`.
7. A holder of the invite (salt, expiry, parties) can open the document and read the finalized status.

## Acceptance tests (lifecycle redesign)

- TXE: two parties give authwits, a third account finalizes, `is_finalized` goes from false to true.
- TXE: single party. Revert when one party has no authwit. Revert for an authwit of another agreement. Revert on a
  second finalize. Existing validation reverts.
- Local network: three separate wallets (Alice, Bob, MetaLeX settler) and one auditor wallet. Same nullifier count
  for one and two parties. Settler input has no salt. Auditor opens the document and reads "finalized".

## Acceptance and current state

- Lifecycle redesign implemented: offchain authwit per party, one `finalize` tx by the MetaLeX settler.
- Contract compiles with Aztec 6.0.0: verified. `finalize` has 6,617 gates.
- TXE tests: verified (13 of 13). The settler call gets the party scopes, because TXE accounts keep the signing
  key in a note.
- Local network run with four separate wallets: verified (15 of 15 checks, two runs), fake proofs only.
- Docs (`README.md`, `ARCHITECTURE.md`, `USER-FLOWS.md`): rewritten for the lifecycle. All five Mermaid diagrams
  render with mermaid-cli 12.1.0.
- Mainnet deployment: not done, no authority.

## Decisions and evidence

- 2026-11-01: Replaced `create_bound_contract_and_sign_for`, the signature nullifier, the `AgreementSigned` event and
  the mailbox with offchain authwits and one `finalize`. Supersedes the earlier event and mailbox decisions.
- `Agreement` holds `terms_commitment = poseidon2(terms_hash, salt)`, not the salt. The settler finalizes without
  the terms (invariant 6, checked in the local network run).
- The consent hash holds the signer. Without it, two parties sign the same message hash, and the PXE keeps only
  one witness for that hash. TXE showed this: each party alone passed, two parties failed.
- Unused party slots get padding nullifiers: 6 nullifiers for one and for two parties (measured).
- The invite (salt, expiry, parties) is shared out of band in the URL fragment. No events go to the parties.
- The settler needs accounts whose authwit check reads no owner private state (initializerless Schnorr works).
- 2026-11-02 (user): MetaLeX may cache each invite (salt) for a retention period to improve UX. MetaLeX can then
  read the agreement during that period; users accept this trust. The collector and the settler still never get
  the salt. Docs only; the cache is not in the PoC.
- 2026-11-02: Added the PII matrix and the comparison with `metalex-webapp` `a5d47d9b4` to `ARCHITECTURE.md`.
- 2026-11-02: The invite cache encrypts each invite with AES-256-GCM under a KMS key (application-level
  encryption; database storage encryption does not stop a credentialed copy). Added side-by-side Today/Proposed
  component and secret diagrams with migration tags (keep, change, replace, new) and a migration table.
- 2026-11-02 (user): The EVM system stays in use and gets a privacy retrofit: salted hashes onchain instead of
  encrypted values. Design only, in `ARCHITECTURE.md` "EVM retrofit: hashes onchain": EIP-712 nested `Terms` /
  `PartyTerms` structs with a salt, so wallets show readable terms and the registry checks signatures from stored
  hashes. Onchain-logic readers assessed (CertificateUriBuilder, DealManagerStorage counterparty check,
  Section4a7DisclosureCondition, SecondaryTradeStorage, RoundManagerStorage, factories, LeXcheXMinter).
  Three-way diagrams (Today, EVM retrofit, Aztec) replace the two-way ones.
- 2026-11-02 (user): "Invite cache" renamed to "data key store". The unit of access can later be a cyberCorp or a
  group, under an ACL. Its KMS key is `ENCRYPTION_KEY` ("decrypts all data keys"), so it maps to today's
  `ENCRYPTION_KEY` and `keys` table. Supersedes the "invite cache" wording above.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Compile | `aztec compile` in `aztec/`, uncommitted on `fd9a1e65` | Passed |
| TXE tests | `aztec test` | 13 passed; TXE cannot test rollup expiry rejection |
| Local network | `aztec start --local-network --port 8090`, then `node e2e.ts` | 15 checks passed, two runs; `realProofs=false` |
| Deploy script | `node deploy.ts` on the local network, test account 2 | Passed |

## Review and blockers

No independent review. Real-proof run and mainnet deploy need a funded deployer and user authorization.

## Next action and handoff

User reviews the lifecycle design and docs. Open items are listed in `aztec/ARCHITECTURE.md` (consent withdrawal
before finalize, data key store with ACL and retention periods, FPC use limits, value arrays).
