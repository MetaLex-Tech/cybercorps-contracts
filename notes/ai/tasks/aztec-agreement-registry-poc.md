# Task: Aztec private agreement registry PoC

- **Status:** Ready for review (lifecycle redesign)
- **Updated:** 2026-11-04 (local time)
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
13. A holder of the invite can verify two proofs without MetaLeX: (path 1) the finalized nullifier of the recomputed
    agreement id exists; (path 2) each party's stored authwit is a valid Schnorr signature, by a key that the party
    address commits to, over the authwit message hash of the recomputed agreement. Any change to a party address,
    the expiry or one byte of the document makes both proofs fail.

## Invariants (BorgAuthV2 and upgrade, 2026-11-04)

BorgAuthV2 ports the minimal part of the EVM `BorgAuthV2` (branch `feat/borgauth-upgrade`): the root, the two-step
root transfer, the permission check and the upgrade. The roles and the other permissions come later by upgrade.

14. The `BorgAuthV2` initializer sets the root to its argument. A zero root fails. A second initialize fails.
15. `has_permission(APPROVE_UPGRADE, account)` is true only for the root. Each other permission is false for each
    account. `require_permission` fails when `has_permission` is false.
16. Root transfer has two steps. Only the root can propose a nominee, and the nominee cannot be the root. A new
    proposal replaces the old nominee, and a zero nominee cancels the proposal. Only the current nominee can
    accept. Accept makes the nominee the root and clears the nominee. After that, the old root has no permission.
17. `BorgAuthV2.update_to(new_class_id)` schedules its own upgrade only for an account with `APPROVE_UPGRADE`.
18. Review rule (no test): each new BorgAuthV2 class keeps the storage variables in the same order and adds new
    variables after them. It keeps `require_permission(Field, AztecAddress)` and the value of `APPROVE_UPGRADE`. A
    class with no `update_to` and no other call to `ContractInstanceRegistry` cannot be upgraded again.
19. The registry keeps the auth address in its immutables hash, `poseidon2([auth])`. It has no initializer.
20. Registry `update_to(auth, new_class_id)` schedules the upgrade only when `auth` matches the immutables hash and
    `auth` gives `APPROVE_UPGRADE` to the caller. Neither contract has a function that changes the upgrade delay.
21. `finalize` and `withdraw_consent` keep their behavior (invariants 1 to 12). They make no public calls.

## Acceptance tests (BorgAuthV2 and upgrade)

- TXE: the initial root has `APPROVE_UPGRADE`; another account has not; an unknown permission is false for the
  root; a zero root and a second initialize fail.
- TXE: a non-root cannot propose; the root cannot nominate itself; a non-nominee cannot accept; a replaced
  nominee and a cancelled nominee cannot accept; after accept, the new root has `APPROVE_UPGRADE` and the old root
  has not.
- TXE: the root calls `BorgAuthV2.update_to` and reaches `ContractInstanceRegistry.update`; a non-root and the old
  root after a transfer fail.
- TXE: the root calls the registry `update_to` and reaches `ContractInstanceRegistry.update`; a non-root, the old
  root after a transfer, and a call with another auth address fail. The TXE does not publish contract classes, so
  the protocol registry rejects the new class ("New contract class is not registered"). That message is the TXE
  evidence that the auth check passed.
- Local network: `deploy.ts` publishes a new class and schedules the upgrade of each contract. Not tested: the new
  class runs after the default delay.
- TXE: the 18 existing registry tests pass on a registry deployed with the auth immutables hash.

## Invariants (deploy script, 2026-11-04)

22. `deploy.ts` picks the deployment record by the L1 chain id of the node. A chain without a record fails before
    any tx.
23. The script computes each address from the recorded original artifact, the fixed salt, the deployer (the
    BorgAuthV2 root) and a universal deploy. A recorded address that differs from the computed address fails before any tx.
    A recorded artifact whose class id differs from its recorded class id fails before any tx.
24. The deployer is the BorgAuthV2 root on every network (user, 2026-11-04: no handoff). A recorded root that
    differs from the deployer fails before any tx.
25. The script sends a tx only when the chain needs it: BorgAuthV2 deploy when it has no instance; registry deploy
    when it has no instance; for each of the two contracts, class publish when the current class is not registered,
    and `update_to` when the contract class is not the current class and no upgrade to the current class is
    scheduled.
26. A second run on the same chain state sends no tx. Each item logs one status: deployed, unchanged, published,
    scheduled (with the time of change), pending (with the time of change) or up to date.
27. `--dry-run` sends no tx and logs what a real run would do.

## Acceptance tests (deploy script)

- Local network, fresh: the run deploys BorgAuth and the registry, and the registry is up to date. A second run
  sends no tx and logs all items as unchanged.
- Local network: a recorded address that differs from the computed one fails before any tx.
- Local network: with a changed registry build, the run publishes the class and schedules the upgrade. A second run
  sends no tx and logs the upgrade as pending.
- Local network: `--dry-run` on a fresh network sends no tx.
- Result 2026-11-04 (local network 6.0.0, port 8090, first test account): all five passed. BorgAuth
  `0x0502…b939`, registry `0x25be…9b29`, recorded in `deployments.ts`. With a temporary `version()` utility in the
  registry, the run published class `0x2b98…f9a3` and scheduled `update_to`; the next run logged "pending". After
  the source was restored, the run scheduled the original class `0x2c61…0d73` again. Not tested: the new class
  after the delay. Not run on the testnet (needs authorization).
- 2026-11-04 (user): One salt for all contracts of a release, like the EVM scripts (`UPGRADE_SALT`,
  `"CyberCorpV5-SecondaryConditionsV1.0.0"`): `DEPLOY_SALT_LABEL = 'MetaLexAztecV1.0.0'` (semver, user), salt =
  sha256(label) reduced into the field. Local network addresses after the change: BorgAuth `0x1593…d0a9`, registry
  `0x045b…76bd` (deploy, then a second run with no tx). Earlier local deploys with other salts are not recorded.
- 2026-11-04 (user): The salt label comes from the env (`DEPLOY_SALT_LABEL`, required), so that one network can
  hold more than one environment. `deployments.ts` keys each network by L1 chain id and each deployment by its
  label (`NETWORKS[chainId].deployments[label]`). The user set the label format to `MetaLex-v1.0.0`. Local network:
  `MetaLex-v1.0.0` deployed BorgAuth `0x2d61…8c28` and the registry `0x1043…432a`, a second run sent no tx, a run
  without the label fails, and a dry run of `MetaLex-staging-v1.0.0` computes other addresses. Supersedes the local
  addresses above.
- 2026-11-04 (user): Label convention: `MetaLex-v1.0.0` for production, a semver pre-release `MetaLex-v1.0.0-dev.N`
  for staging and development. The local record moved to `MetaLex-v1.0.0-dev.0`: BorgAuth `0x1673…b9d4`, registry
  `0x11a5…7f95` (deploy, then a second run with no tx). Supersedes the `MetaLex-v1.0.0` local record.
- 2026-11-04 (user): `deploy.ts` writes the deployment record into `deployments.ts` after a run that is not a dry
  run. It regenerates the `NETWORKS` block at the end of the file, and writes nothing when the record is the same.
  `DEPLOYMENT.md` keeps no log (user: one source of truth). Local network: a recorded label leaves the file
  byte-identical; a dry run writes nothing; a new label `MetaLex-v1.0.0-dev.1` wrote only its record (diff = the 5
  added lines), and the next run read it back as unchanged. The test record was then removed by hand.
- 2026-11-04 (user): `deploy.ts` logs one line for each step with the EVM `DeploymentScript` markers (🟢 work,
  ⚫️ skip). Two gaps fixed: (1) a shared network needs `DEPLOYER_SIGNING_KEY`; only chain 31337 may use the public
  test account (checked with a dry run against `https://aztec-testnet.drpc.org`, no keys: the run stops before the
  wallet); (2) the dry run reports exactly whether the registry deploy publishes the class and whether a new
  environment needs an upgrade (checked on the local network with a temporary registry build). The scenario matrix
  is in `aztec/DEPLOYMENT.md`.
- 2026-11-04 (user): The scripts read the registry from `deployments.ts` (`NETWORKS[l1ChainId].deployments[label]`
  with `DEPLOY_SALT_LABEL`). `REGISTRY_ADDRESS` is removed from `scripts/.env.example`. `poc.ts` no longer deploys a
  registry without BorgAuth on the local network: `deploy.ts` must run first. Local e2e: 24 of 24 checks against the
  recorded `MetaLex-v1.0.0-dev.0` registry `0x11a5…7f95`; without the label, the run stops with
  `DEPLOY_SALT_LABEL is not set`. The web app still reads its own `REGISTRY_ADDRESS`.

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
- Local network (auditor proofs): both paths pass for the original agreement; both fail for a changed clause.
- Web app journey (auditor): both paths pass; a changed clause, expiry or party address fails both; reset passes.
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
- BorgAuthV2 and the upgrades (2026-11-04): `contracts/borg_auth_v2/src/main.nr` and `update_to` in the registry.
  TXE 39 of 39 (21 for BorgAuthV2 and the upgrades). Local network: both contracts deploy, publish and schedule an
  upgrade through `deploy.ts`. The webapp still uses the old testnet registry with immutables hash 0. No independent
  review.
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
- 2026-11-02 (user): Auditor proofs, both paths (invariant 13). Each party's device stores its evidence (authwit,
  signing public key, account preimage) in the vault, encrypted with the document key. `verifyAgreement` checks the
  finalized nullifier (path 1) and each Schnorr signature over the recomputed authwit message hash, with the key bound
  to the address through the account preimage and `immutablesHash` (path 2). The auditor page lets the user change
  parties, expiry and document and shows both results live. Local e2e 24 of 24 (test and env accounts, two runs
  each); journey 3 of 3 with change/reset checks; TXE 18 of 18. Not run on the testnet yet. Per-deal accounts added
  as an open item.
- 2026-11-03 (user): Rewrote the web app on the cyberSign stack in `aztec/webapp/` (TanStack Start, Vite 8, Nitro
  Vercel preset, Tailwind, Drizzle on Postgres; `pg` driver so Neon and local Postgres both work). The wallets and
  PXEs run in the browser (keys in `localStorage`, restore by signing key). MetaLeX services persist in Postgres.
  The settler runs in the server function (option 1): `waitUntil` + `NO_WAIT`, the browser polls; claims are a
  single insert/update so one request wins; a `settling` row older than 5 min retries. bb.js, noir wasm and pino stay
  external (they read files next to their own code); bb.js keeps only the build platform's binary. Linux function
  116 MB. Journey: local network 1 of 1; Aztec testnet 1 of 1, two runs (54 s), finalize txs `0x0786d013…e3e3`
  (block 16576, 6 nullifiers) and `0x2a1cd3a7…cc3c`. Old `scripts/app` and `scripts/journey` removed. Not deployed
  to Vercel (needs the user's account); `waitUntil` on Vercel not yet observed.

- 2026-11-04 (user): Implemented the BorgAuth design from the 2026-11-03 open item. `BorgAuth` keeps roles 99, 98
  and 97 in public state, with `constructor(owner)`, owner-only `update_role`, and `only_role` / `user_role` views.
  Owner swap is grant and revoke. Role adapters and the two-step transfer are not ported. The registry gets
  `update_to(auth, new_class_id)`; the auth address is in the registry `immutables_hash` as `poseidon2([auth])`, so
  the caller passes `auth` and the registry checks it. No `set_update_delay`. The auth package is `aztec/auth`
  (Nargo package `borg_auth_contract`).
- 2026-11-04 (user): Folder layout follows the Aztec monorepo (`aztec-labs-eng/aztec-node` v6.0.0,
  `noir-contracts/contracts/app/*`): one crate for each contract under `aztec/contracts/` (`agreement_registry`,
  `borg_auth`), TXE tests inside each crate (`mod test;`), cross-contract tests in the dependent crate (the
  registry crate, like AMM with Token). The separate `aztec/test` crate (the `aztec new` scaffold shape) is removed.
  Supersedes the "separate test crate" item of the 2026-11-02 docs cross-check. Package names are unchanged.

- 2026-11-04 (user): Port the EVM `BorgAuthV2` model (branch `feat/borgauth-upgrade`, not merged) and rename the
  Aztec contract to `BorgAuthV2`. Only the minimal part for today: the root, the two-step root transfer
  (`propose_root_transfer`, `accept_root_transfer`), `has_permission` / `require_permission` with one permission,
  `APPROVE_UPGRADE` (value 1, root only), and `update_to` for BorgAuthV2 itself. Root alone approves an upgrade (no
  approved-class check like the EVM factory). The user needs two properties: a later upgrade can match the EVM
  features, and a later upgrade can stop all upgrades (a class without `update_to`). Storage order and
  `require_permission` stay fixed for each later class. The numeric roles (99, 98, 97) are gone. The crate is
  `contracts/borg_auth_v2` (package `borg_auth_v2_contract`). The v1 artifacts in `scripts/res/` were replaced, not
  versioned, because no shared network had a v1 deployment. The record key `owner` is now `root`. The local record
  `MetaLex-v1.0.0-dev.0` was redeployed: BorgAuthV2 `0x168a…2fe2`, registry `0x0d8a…5218`.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Compile | `aztec compile` in `aztec/`, uncommitted on `fd9a1e65` | Passed |
| TXE tests | `aztec test`, uncommitted on `e9602d19`, 2026-11-04, BorgAuthV2 | 39 passed (24 registry, 15 BorgAuthV2) (6 registry upgrade); TXE cannot test rollup expiry rejection or a real class upgrade |
| Local network | `aztec start --local-network --port 8090`, then `node e2e.ts` | 22 checks passed, three runs on 2026-11-02, with test accounts and with env accounts; `realProofs=false` |
| Web app journey | `npm run journey` in `aztec/scripts` (Playwright 1.61.0, Chromium) on the same local network | 1 passed, three runs on 2026-11-02; wallets run in the app server, not the browser |
| Deploy script | `node deploy.ts` on the local network, test account 2 | Passed |
| Deploy script, BorgAuthV2 | `LOG_LEVEL=warn DEPLOY_SALT_LABEL=MetaLex-v1.0.0-dev.0 AZTEC_NODE_URL=http://localhost:8090 node deploy.ts` (and `--dry-run`), uncommitted on `e9602d19` | Fresh deploy, rerun with no tx, a temporary BorgAuthV2 build published and scheduled then pending, a temporary registry build published and scheduled through `require_permission`, both scheduled back after restore. Then `node e2e.ts`: 24 of 24, `all checks passed`. Not tested: a new class after the delay |

## Review and blockers

No independent review. Real-proof run and mainnet deploy need a funded deployer and user authorization.

## Next action and handoff

User reviews the lifecycle design and docs. Open items are listed in `aztec/ARCHITECTURE.md` (admin-gated
upgrades with a BorgAuth-style auth contract, decided 2026-11-03 for later; consent withdrawal
before finalize, data key store with ACL and retention periods, FPC use limits, value arrays).
