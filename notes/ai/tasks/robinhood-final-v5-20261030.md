# Task: synchronize and prepare the final Robinhood v5 step

- **Owner:** Current Codex chat; final-step preparation only. Colleague badge/secondary ownership is retained.
- **Status:** Local merge and final-stage preparation complete. Live signing, deployment and Safe execution remain outside this request.
- **Date:** 2026-10-30 (America/New_York).
- **Branch:** `codex/robinhood-intermediate-20261028`.
- **Base:** `3b0f1e749a4bba0de2382eab3e3481d5562229ac`.
- **Fetched upstream:** `origin/develop` at `7ce4e1c825998de5cf309e620d1e9d8e0d1b543d` (10 upstream-only commits). There is no `main` branch.
- **User direction:** Merge latest develop into this Robinhood branch. Reuse existing shared kill switch `0x456EDAfB7283dB8FDa2A5b3ecE576d9292512435`.
- **Sources:** [Prior intermediate task](robinhood-intermediate-20261028.md), [release runbook](../../../script/res/robinhood-bootstrap.md), broader [protocol plan](../../plans/protocol-improvement-plan.md), exact upstream v5 runner/recorded CREATE2 inventory and fresh RPC snapshot.

## Acceptance criteria before merging/implementation

1. Merge the fetched upstream into this branch without pushing or modifying develop.
   Preserve the user's existing `foundry.toml` edit (removal of the Etherscan table)
   and untracked mainnet bootstrap Safe JSON. Keep a recoverable copy of local edits.
2. Retain the historical bootstrap/verification manifests and recipes byte-identically.
   Resolve Robinhood constants in favor of upstream's now-deployed shared mainnet
   auth/proxy targets; preserve separate historical testnet fixture support.
3. Reuse the existing kill switch, as explicitly selected by the user. Do not
   nominate different admins or deploy a second one. Record its observed admins/state.
4. Keep upstream's new CREATE2 address replay and registry signer-condition changes;
   do not replace them with the older October 23 runner. Check old-Foundry Safe JSON
   compatibility and apply only any necessary tooling correction with a regression.
5. Compile/run relevant behavioral tests, distinguish unit checks from fresh-state
   fork rehearsal, and use only a public toy key for any local final-stage simulation.
   Preserve any tracked operator Safe output that a rehearsal would overwrite.
6. Walk through dry-run -> reviewed operator broadcast -> actual Safe batch ->
   receipt/state verification -> ownership handoff. The walkthrough does not grant
   release approval or replace external-model review or real test-environment
   sign/simulate/submit success/refusal acceptance.

## Read-only current chain evidence

At Robinhood block **101730171**, all **99** addresses in upstream's recorded
CREATE2 inventory have code. Core factory is still the intermediate implementation
`0x424ab1B1DA8b7B2FE13cA0A7ABC346b22efa9191`, with the four expected factory proxy
references, USDG stable and LeXcheX auth. Both primary fees read **50 bps**.
The Safe holds core role 200 and LeXcheX/badge role 99. Shared badge proxy
`0x114664773Ba721a6AA43890d5FDE7939aF37618F` points to auth
`0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d` and reports minter issuer keys **65539**.
The old Robinhood-specific badge/auth have no code and must not remain mainnet targets.

The shared kill switch exists at the user-selected address. Its observed MetaLeX
admin is Safe `0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`, Legion admin is
`0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf`, and `killed` is false. These differ
from the earlier pasted Base Sepolia example. The user's reuse decision applies
to this actual observed instance. No role/admin rotation or transaction was sent.

## Merge resolution and validation

Validated the dirty merge of parents `3b0f1e7` and `7ce4e1c`: merged upstream
protocol/deployment sources, constants conflict resolution retaining historical
testnet/original-deployment helpers, user-approved reuse of the existing mainnet
kill switch, explicit fixture-core input in the old badge test harness, and new
`test/RobinhoodFinalPreparationTest.t.sol`. Mainnet targets follow upstream's
shared badge/extension/condition inventory. `src/` and the v5 runner are unchanged
from the fetched upstream. No older refresh runner/helper was copied over them.

- **22 Robinhood tests passed, 0 failed/skipped**, including the complete latest
  v5 runner on a fork of **block 101730171** using public toy key `0xA11CE`, local
  gas funding and Safe impersonation. It preserved core/auth/proxy references and
  USDG, retained 50-bps primary fees, set 500-bps secondary fees, installed an image
  builder, retained the existing kill code/admins/state and Safe authority, and set
  production registry ZKPassport config with dev mode false. The resulting local
  Safe batch contains **23** calls. Its toy-key addresses/output are simulation only.
- **76 registry tests passed, 0 failed/skipped**, covering existing agreements,
  creator-bound creation and new signer-condition/ZKPassport success/refusal paths.
  Total selected suite executions: **98 passed**. The new Safe JSON compatibility
  test also passed separately before the full run, so no formatter patch was needed.
- Commands used offline Solidity **0.8.28**, Cancun, one thread and explicit
  OpenZeppelin remappings. Installed Foundry remains v1.2.0-rc `0a7b3f0`.
  Existing compiler warnings and nonfatal signature/RPC-cache permission warnings
  occurred; they did not prevent the tests or fork execution.
- The bootstrap user batch is byte-identical to its pre-merge backup; its SHA-256
  is `b9c45e70a5febae59df7c06e1776b3fc57dbb870ec74737724858d7057d1e0a9`.
  The fork wrapper restored the upstream mainnet v5 JSON after archiving test
  output under ignored `out/robinhood-final-sync/`. Both frozen bootstrap/verification
  manifests retain their recorded hashes. No generated testnet JSON remains in
  `script/res/` from this run.
- User removal of the Foundry Etherscan table was stashed by exact path, then
  restored successfully as an unstaged edit over the merged config. A recoverable
  task stash is `99030eafde08b13ae36ce29644cd5cb3611aebe2`; local-only file backups
  are under ignored `out/robinhood-final-sync/`. The new upstream RPC alias was
  configured in ignored `.env` from the existing endpoint without changing the
  signing key or exposing credentials.
- Sanitized fork test log SHA-256:
  `336d2f11ae6c49595993c5f3f021e4e396f04b9b87e6d6b62ab5801a2a3c7a7b`.
  [Readiness snapshot](robinhood-readiness-20261030.json) records only public
  chain addresses/state and the exact fetched upstream revision.

## Operator handoff

Validated code is saved in merge commit
`13ea54eaf1ae9d40931a290503702dcc14744353`, with parents `3b0f1e7` and `7ce4e1c`.
The fetched upstream is an ancestor of that commit. This final status update is
documentation only; the tests cover that merge's code. Nothing was pushed.

Follow the October 30 section at the top of the [runbook](../../../script/res/robinhood-bootstrap.md):
operator-specific full dry run, release acceptance, operator broadcast, confirmation
of receipts, atomic execution of that run's final Safe batch, on-chain postconditions
and conditional ownership handoff, then application acceptance. The existing kill
switch needs no new admin environment variables. Archive any historical/simulation
batch separately; the batch to execute must come from the actual successful run.

External-model review, actual signer/quorum control and real test-environment
sign/simulate/submit acceptance remain distinct, pending gates. No real key was
used for this rehearsal, no live transaction was signed/submitted, no Safe was
executed, and no audit or default-branch push was started. The target merge is
local to this Robinhood branch; develop itself is not modified.
