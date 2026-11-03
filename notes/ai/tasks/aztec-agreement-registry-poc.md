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
8. The data key store keeps each salt encrypted, gives it only to a party of that agreement, and deletes it at the
   end of the retention period.
9. After a party withdraws its consent, `finalize` of that agreement fails.
10. A withdraw blocks only the consent of the caller to that one agreement id. A withdraw by a non-party does not
    block `finalize`.
11. A withdraw after `finalize` fails. A second withdraw of the same consent fails. A withdrawn consent cannot be
    given again for the same agreement id; the parties make a new agreement (new salt).
12. The withdraw tx holds no agreement data: one authwit nullifier besides the tx nullifier, no logs, no note
    hashes.

## Acceptance tests (lifecycle redesign)

- TXE: two parties give authwits, a third account finalizes, `is_finalized` goes from false to true.
- TXE: single party. Revert when one party has no authwit. Revert for an authwit of another agreement. Revert on a
  second finalize. Existing validation reverts.
- Local network: three separate wallets (Alice, Bob, MetaLeX settler) and one auditor wallet. Same nullifier count
  for one and two parties. Settler input has no salt. Auditor opens the document and reads "finalized".
- Local network: Bob opens the agreement without the invite, with the salt from the data key store. The store
  refuses a non-party and has no salt after the retention period. Its row holds no plaintext salt.
- TXE (withdraw): withdraw then finalize fails; withdraw after finalize fails; second withdraw fails; a withdraw
  for another agreement does not block finalize; a non-party withdraw does not block finalize.
- Local network (withdraw): Bob withdraws with his own tx (fee by the SponsoredFPC) before the settler sends
  finalize; the finalize is rejected; the withdraw tx has 2 nullifiers, no note hashes and no logs.
- Web app journey (Playwright): Alice drafts and signs; MetaLeX page shows no names and no salt; Bob opens the
  invite and signs; MetaLeX finalizes (node: 6 nullifiers, no note hashes, no logs, FPC pays); the auditor sees
  "finalized"; Bob on a new device opens it from the data key store; after the retention ends, his list is empty,
  the vault still has the blob, and Bob opens the agreement with the invite link that Alice sends again.
- Local network: after the retention period, the vault keeps the document and the invite opens it.

## Acceptance and current state

- Lifecycle redesign implemented: offchain authwit per party, one `finalize` tx by the MetaLeX settler.
- Contract compiles with Aztec 6.0.0: verified. `finalize` has 6,617 gates.
- TXE tests: verified (18 of 18). The settler call gets the party scopes, because TXE accounts keep the signing
  key in a note.
- Local network run with four separate wallets: verified (22 of 22 checks, 2026-11-02, three runs; also 22 of 22 with env accounts), fake proofs
  only. The data key store is in memory; its KMS key is a local random key and the login is the requester address.
- Docs (`README.md`, `ARCHITECTURE.md`, `USER-FLOWS.md`): rewritten for the lifecycle. All five Mermaid diagrams
  render with mermaid-cli 12.1.0.
- Web app (`aztec/scripts/app/`) and its Playwright journey: verified (1 of 1, three runs, 2026-11-02), fake proofs.
  The server runs each user's wallet and PXE in place of the browser. User flow canvas from the journey
  screenshots: https://claude.ai/artifact/J1aHLJzjShUcRE5HjikudE (private until shared).
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
- 2026-11-02 (user): Comparison diagrams show "MetaLeX smart contracts" (not only the registry), split into
  rule inputs (credential facts, amounts, parties, statuses; stay readable on EVM, reduced to minimum facts) and
  records (names, contacts, values; salted hashes on EVM). The indexer and credential issuers are part of
  "MetaLeX services", not separate boxes (user, 2026-11-02).
- 2026-11-02 (user): Aztec private notes use offchain delivery (`MessageDelivery::offchain`); the document vault
  keeps the encrypted note messages per recipient (owner, and `deliver_to` recipients) with retention. Onchain
  keeps note hashes and nullifiers only. Verified the API in aztec-nr v6.0.0 source (`note_message.nr`,
  `offchain_messages.nr`).
- 2026-11-02 (user): Added a local web app and a Playwright journey, like the metalex-webapp cyberSign journeys.
  The shared PoC code moved from `e2e.ts` to `scripts/poc.ts`. The app server, not the browser, runs the wallets:
  a browser PXE needs a wasm bundle, and the PoC tests the flow, not the bundle.
- 2026-11-02 (user): The document holds the full legal text of the template (no IPFS link), so the vault blob is
  the whole agreement. The end of the retention period deletes only the data key; the vault keeps the encrypted
  document for the parties. Invite links stay in the browser of each party (`localStorage`); an agreement opened
  with a stored salt does not save a link on the device.
- 2026-11-02: Cross-checked the PoC with the Aztec developer docs (networks, testnet guide, privacy
  considerations, limitations, authwits, testing, readiness states, deployment, fees, offchain messages). The PoC
  follows them: separate test crate on the same v6.0.0 tag, `aztec test`, `should_fail_with`, universal deploy with
  a fixed salt, the testnet SponsoredFPC address equals the computed one (`0x2d8f…69d3`), no public calls, domain
  separated hashes. Documented deviations and gaps in `aztec/ARCHITECTURE.md`: consent hash without caller and
  selector (by design), withdraw pattern from the docs not built, "no real secrets" warning, protocol padding vs.
  our padding nullifiers (untested), settler checks authwits of other accounts (not in the docs). Testnet endpoint
  from the docs: `https://aztec-testnet.drpc.org` (6.0.0); not called by the agent.
- 2026-11-02 (user): Padding test: a no-padding copy of `finalize` gave 3 nullifiers for one party and 4 for two
  on the 6.0.0 local node. The padding nullifiers stay.
- 2026-11-02 (user): Added `withdraw_consent(agreement)` (docs cancel pattern: the authwit nullifier of the caller).
  Invariants 9 to 12 and the acceptance tests were written first. TXE 18 of 18; e2e step 10 shows the withdraw tx
  (2 nullifiers, no notes, no logs) and a rejected finalize. No independent review.
- 2026-11-02 (user): Scripts load the settler, Alice and Bob from an untracked env file (`scripts/.env.testnet`,
  template `.env.example`), with the keys from `aztec-wallet create-account`; the registry comes from
  `REGISTRY_ADDRESS`. Parties must be `schnorr_initializerless`. All fees use the SponsoredFPC (same address on the
  local network and the testnet). `deploy.ts` uses the settler and the FPC. Verified on the local network only;
  derived addresses equal the `aztec-wallet` addresses.
- 2026-11-02 (user approved): Deployed the registry on the Aztec testnet (node `https://aztec-testnet.drpc.org`,
  6.0.0, Sepolia L1) with the user's `detoo` schnorr account as settler and the SponsoredFPC as fee payer. Registry
  `0x18b41975b6265c16f1debf308070c866fad699802392c4e14f4a4597cc05ba38` (same as the local universal deploy), tx
  `0x08d31f3b3608e54533746345030fe350d6ab638fb54dc478cfa1903068198d41`, block 16480, status proposed, instance
  published, real ClientIVC proof (4.7 s). The free dRPC plan refuses JSON-RPC batches above 3, so the scripts take
  `AZTEC_NODE_MAX_BATCH_SIZE`. The deploy tx later showed `checkpointed`.
- 2026-11-02 (user approved): Testnet e2e `node --env-file=.env.testnet e2e.ts`: 22 of 22 checks, one run, about
  1.5 minutes, real ClientIVC proofs (2.3 to 2.8 s). Finalize tx
  `0x240dd2db03e8521b18ef00d527564c3aa80590e733f7e68ad1146479ae18f17f` in block 16488 (6 nullifiers, no note
  hashes, no logs, FPC fee payer). Second finalize and finalize after withdraw rejected by the node ("Existing
  nullifier"). No independent review.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Compile | `aztec compile` in `aztec/`, uncommitted on `fd9a1e65` | Passed |
| TXE tests | `aztec test` | 18 passed (5 for withdraw); TXE cannot test rollup expiry rejection |
| Local network | `aztec start --local-network --port 8090`, then `node e2e.ts` | 22 checks passed, three runs on 2026-11-02, with test accounts and with env accounts; `realProofs=false` |
| Web app journey | `npm run journey` in `aztec/scripts` (Playwright 1.61.0, Chromium) on the same local network | 1 passed, three runs on 2026-11-02; wallets run in the app server, not the browser |
| Deploy script | `node deploy.ts` on the local network, test account 2 | Passed |

## Review and blockers

No independent review. Real-proof run and mainnet deploy need a funded deployer and user authorization.

## Next action and handoff

User reviews the lifecycle design and docs. Open items are listed in `aztec/ARCHITECTURE.md` (consent withdrawal
before finalize, data key store with ACL and retention periods, FPC use limits, value arrays).
