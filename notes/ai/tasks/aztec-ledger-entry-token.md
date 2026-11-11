# Task: Aztec private LedgerEntryToken (LET) PoC

- **Status:** Ready for review (e2e blocked by the local network)
- **Updated:** 2026-11-10 (local time)
- **Owner:** Claude Code session for the user (detoo)
- **Collaborators / boundaries:** The webapp half is `metalex-webapp` task `cyberraise-aztec-let-testnet` (branch
  `feat/aztec-let-testnet`, another session). This task changes `aztec/` only. It does not edit the webapp. No change
  to `src/`, `test/` or `script/`.
- **Objective:** A private LET class on Aztec that follows the EVM authority model (one company BorgAuthV2 per
  company), commits its security type and series, and has holder-side possession transfer next to the issuer-side
  register.
- **Out of scope:** Partial-note (commitment) transfers, transfer restrictions, a DEX, an approved-class allowlist for
  upgrades, deployment, mainnet.
- **Canonical plan / sources:** this record; `aztec/README.md`; `aztec/contracts/ledger_entry_token/src/`;
  `aztec/contracts/borg_auth_v2/src/main.nr`; EVM `BorgAuthV2` permission table (branch `feat/borgauth-upgrade`,
  `src/BorgAuthV2.sol`).
- **Repository / branch:** cybercorps-contracts, `feat/aztec`
- **Verified base / code head:** base `5330592f`; all LET files and this change are uncommitted
- **Worktree locator:** `cc-aztec` worktree
- **PR / artifact:** not yet created

## Decisions (user, 2026-11-10)

1. One company BorgAuthV2 per LET. The company owner is its root. MetaLeX is not in it. `Config` holds one auth.
2. `Config = { auth, security_type, security_series, blinding }`. The type and series use the EVM `SecurityClass` and
   `SecuritySeries` numbers. They are committed in the immutables hash, so other contracts can check them privately.
3. A secret `blinding` field keeps the type and series hidden when the instance is published.
4. The LET `update_to` is private. It enqueues only `ContractInstanceRegistry.update(new_class_id)`. The registry keeps
   its public `update_to`.
5. BorgAuthV2 roles move to `DelayedPublicMutable` so that private functions can check them. The root keeps
   `PublicMutable` for the public path (rule 18: new variables come after the old ones).
6. The LET follows the AIP-721 shape for possession: a `CertNote { token_id }` in the possessor's private set, and
   `transfer(from, to, token_id, authwit_nonce)` with `#[authorize_once]`.
7. **Open item (accepted for the PoC):** nothing limits which class the company root can upgrade a LET to. The EVM
   limits upgrades to the MetaLeX reference implementation.
8. **Open item (test later):** `require_permission_private` reads `initial_root` and `initial_members` with no
   `is_initialized` check. The public path has one. An instance of the old BorgAuthV2 class has neither. aztec-nr
   v6.0.0 fails a private read of an uninitialized `PublicImmutable` (`public_immutable.nr:361-369`, its test
   `read_uninitialized_private_fails`), so each private check on an upgraded old instance should fail. Test with an
   instance of the old class before a LET uses an upgraded auth.
9. Privacy rule of thumb: keep frequent user actions in private notes and nullifiers. A mutable value that a private
   function reads must be `DelayedPublicMutable`. Use `PublicMutable` only for values that public code alone reads.
   Rare admin acts (officer grants, root transfer, upgrades) can be public. Use private role notes only when the
   member list itself is confidential.

## Defaults chosen by the implementer (2026-11-10, "dew it")

- Role delay = `MAX_TX_LIFETIME` (1 day). aztec-nr names this the privacy-optimal delay. A revoked officer keeps its
  private power for up to 1 day.
- Decision (user, 2026-11-10): the root is not an officer by default. `constructor(root, members)` takes up to
  `MAX_INITIAL_MEMBERS` (4) `Member { account, roles }` entries. A new role adds a bit to `MEMBER_ROLES`, so the
  constructor signature stays the same. Each member holds its roles with no delay until a role change for it takes
  effect. This lets a new company issue at once. The deploy script sets up the company auth. EVM: `completeSetup`
  grants `OFFICER` to a separate address.
- Decision (user, 2026-11-11): roles are `u32`. Bits 0-5 are all six EVM `CorporateAuth` role bits (`DIRECTOR` to
  `ROUND_MANAGER`), pinned by the test `role_bits_match_the_evm`. `ROOT = 1 << 30` and the internal `SET = 1 << 31`
  take the high bits. Only `OFFICER` grants permissions and can be an initial member role. Permission values stay small numbers, because
  a bytes32 keccak256 does not fit in a Field.
- Permissions follow the EVM table: `APPROVE_UPGRADE` (root), `ISSUE_SECURITIES` and `ADMINISTER_CERTIFICATES`
  (officer). Root alone is not an officer.
- `Cert.holder` is an `AztecAddress`, because a note owner must be an Aztec account. EVM-only holders need a derived
  Aztec account (as cyberSign does).
- The settler has no role. The officer authwit carries the authority.
- `assign` (registration) needs an endorsement authwit from the legal owner of record. A possession transfer does not
  change the register.
- Txs now have note hashes and encrypted logs. The claim "each action emits the same side effects" is dropped.

## Invariants

BorgAuthV2:

1. `has_permission(APPROVE_UPGRADE, a)` (public) is true only for the current `root_authority`, at once.
2. Each initial member with `OFFICER` holds `ISSUE_SECURITIES` and `ADMINISTER_CERTIFICATES` at once, publicly and
   privately, until a role change for it takes effect. The root holds no officer permission unless it is also a
   member or `set_officer` grants it. The constructor refuses a member role outside `MEMBER_ROLES`.
3. Only the root can call `set_officer`. A grant or revoke takes effect after the role delay, publicly and privately.
4. After a root transfer, the new root holds `APPROVE_UPGRADE` privately after the role delay. The old root loses it
   privately after the same delay.
5. An unknown permission is false for each account.

LET:

6. Each action fails when `Config` does not match the immutables hash (any field: auth, type, series, blinding).
7. `mint` needs a signer with `ISSUE_SECURITIES` in `config.auth` and the signer's authwit for this version.
   `update_details`, `void`, `unvoid` and `assign` need `ADMINISTER_CERTIFICATES` and the signer's authwit.
8. The version and register rules of the earlier LET stay: one mint per token id, a version changes once, a new version
   is new, the field rules of each action.
9. `mint` gives the holder a `CertNote` for the token id.
10. Only the possessor, or an account with the possessor's authwit for this exact call, can `transfer` a `CertNote`.
    The authwit works once. A transfer of a note the sender does not hold fails.
11. A possession transfer does not change the register (`is_current` stays the same).
12. `assign` fails without the endorsement of the old legal owner for this old version and this new holder.
13. `class_of(config)` returns the committed type and series, and fails for a wrong `Config`.
14. Private `update_to` needs `APPROVE_UPGRADE` in `config.auth` (private check) and reaches
    `ContractInstanceRegistry.update`. An officer that is not root, and the root of another auth, fail.
15. Review rule (no test): `update_to` enqueues only `ContractInstanceRegistry.update(new_class_id)`. No public
    function receives `Config`.

## Acceptance

| Criterion | State |
| --- | --- |
| TXE tests for invariants 1-14 | Verified 2026-11-10: BorgAuthV2 35, LET 42 (lifecycle 30, possession 6, upgrade 6) |
| Workspace `aztec test` passes (registry test helper passes the new constructor argument) | Verified 2026-11-11: 101 of 101 |
| `let-e2e.ts` on a local network | Verified 2026-11-11: 24 of 24 checks, `LOG_LEVEL=warn AZTEC_NODE_URL=http://localhost:8090 node let-e2e.ts`, on the local network on port 8090 |
| Webapp follows the new formulas and the frozen artifact | Not in this task: handoff to the webapp task |
| Independent review | Not started. The Aztec PoC has no independent review |
| Deployment | Not in scope |

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Baseline `aztec test` before this change | base `5330592f` + uncommitted LET v1 | 62 of 62 (registry 24, BorgAuthV2 15, LET 23) |
| `aztec test` after this change | base `5330592f` + uncommitted `aztec/` (BorgAuthV2 roles, LET v2, tests) | 93 of 93 (registry 24, BorgAuthV2 27, LET 42). TXE simulator, no real proofs |
| `node let-e2e.ts` on the local network | same tree | Not run to the end: first tx (company auth deploy) rejected, "Invalid expiration timestamp"; cause: stale local network (newest block 190 h old) |
| `aztec test` after the initial members | same tree + `constructor(root, members)` | 101 of 101 (registry 24, BorgAuthV2 35, LET 42). TXE simulator, no real proofs. `let-e2e.ts` not run: no local network on port 8090 |
| Registry class id | `getContractClassFromArtifact` on HEAD build vs current build | HEAD `0x028c…481f` = recorded v1. Current `0x2c44…9e14`. Function bytecode is the same; only `outputs.globals.storage` differs, because the registry artifact embeds the BorgAuthV2 storage layout |

## Findings

- A dependency on the BorgAuthV2 contract crate puts its storage layout into the artifact of each dependent. So a
  BorgAuthV2 storage change moves the class id of the registry and of the LET with no code change. `deploy.ts` would
  then schedule a registry upgrade with the same code. A small interface-only crate (as aztec-nr does for
  `ContractInstanceRegistry`) would remove this coupling. Not done: needs a decision.
- Decision (user, 2026-11-11): the `MetaLex-v1.0.0` environment and the v1 artifacts are deprecated and removed.
  The next environment is `MetaLex-v1.1.0`, deployed from `res/BorgAuthV2.v1.1.0.json` and
  `res/CyberAgreementRegistry.v1.1.0.json` (new auth, new registry, no data migration: all old data is test data).
  On a testnet, `deploy.ts` also runs the sub-script `deploy-test-corp-auth.ts`: a company BorgAuthV2 with the
  deployer as root and an initial officer, with the accounts in `TEST_CORP_OFFICERS` (env), recorded as
  `testCorpAuth`. Local run of `MetaLex-v1.1.0-dev.0` passed
  on 2026-11-11. Testnet `MetaLex-v1.1.0` deployed on 2026-11-11 at the user's request (before the independent
  review): auth `0x2f46…17be`, registry `0x0bc3…1339`. Test corp auth redeployed with the web app officer
  `0x1f6432…5bee24` (wallet `0x5ff4…9abf`) as a second initial member: `0x1114…bc2a` (the first, `0x22ab…5e47`, is
  unused). See the README validation table.

## Webapp handoff (not done here)

The webapp task `cyberraise-aztec-let-testnet` must follow the new contract: `Config` (company auth, type, series,
blinding), the `signer` argument, `Cert.holder` as an Aztec account, the endorsement for `assign`, a company
BorgAuthV2 deploy per company, and a new frozen artifact `LedgerEntryToken.v1.json`.

## Next action and handoff

Set the web app `REGISTRY_ADDRESS` to the `MetaLex-v1.1.0` testnet registry, use `testCorpAuth` as the auth of the
test LET class, and run `bun run artifacts` in `webapp/`. The independent review is still open. The user decides on the commit, the
BorgAuthV2 interface crate, and the webapp handoff. Later: test open item 8 (old-class BorgAuthV2 `initial_root`).
