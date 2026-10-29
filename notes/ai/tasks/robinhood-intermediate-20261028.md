# Task: Robinhood intermediate deployment setup

- **Status:** Operator deployed the 32 historical bootstrap targets; RPC receipts/payloads confirmed. Explorer source available on all 32 (22 Exact Match, 10 Similar Match). Safe execution, external badge/secondary handoff and release gates remain separate and unconfirmed. This task performed no signing or chain transactions.
- **Updated:** 2026-10-28 (America/New_York).
- **Owner:** Current Codex chat, intermediate setup only. Prior Robinhood and other rollout ownership remains unchanged.
- **Objective:** Make the prepared bridge available on current develop, rehearse it against fresh Robinhood state without a private key, and provide concrete deployment/Safe execution instructions.
- **Branch:** `codex/robinhood-intermediate-20261028`.
- **Base:** `0a598592e2b66a1754af81c3746e93b6c155e7c8` (refreshed `origin/develop`).
- **Sources:** [Prior task](robinhood-bootstrap.md), [canonical deployment runbook](../../../script/res/robinhood-bootstrap.md), prepared commit `4537d18`, broader [protocol plan](../../plans/protocol-improvement-plan.md).
- **Scope:** Restore bootstrap source, manifest, tests and Robinhood constants; add a key-free preparation entrypoint and intermediate operator instructions. No protocol source changes, final v5 deployment, merge, external review or real transactions.

## Invariants and acceptance criteria established before implementation

### Revised deployment split (October 28, before implementation)

The user assigned secondary conditions **and badge AUTH/proxy on Robinhood mainnet
(4663)** to a colleague. The pasted 84532 output is reference material, not Robinhood
deployment evidence. This supersedes our responsibility to deploy the four fresh
badge entries; whether the colleague reproduces the shared badge addresses must be
verified from their actual mainnet handoff, not inferred from those logs.

1. Intermediate bootstrap replays only the **32 historical** entries. Keep the
   frozen 36-entry manifest byte-identical as provenance, skipping its four
   zero-sourceTx badge entries. No duplicate badge deployment, upgrade, role or
   issuer-key transaction is permitted in this stage.
2. Bootstrap must succeed before the external badge exists and leave an already
   deployed external badge/auth untouched. The first Safe batch has 14 calls;
   reruns after the bridge Safe upgrade have 13. Core references, USDG, 50-bps
   primary fees, LeXcheX roles and original core address/state invariants remain.
3. Add behavioral coverage for absent external badge and an existing independently
   provisioned badge/auth. Preserve historical replay, rerun and refusal coverage.
4. Keep earlier badge address constants as prior targets pending verified external
   addresses; they are **not approved final-stage input** after this ownership
   change. Do not copy Base Sepolia's condition addresses, kill switch address or
   proposed admins into Robinhood as deployed/approved facts.
5. Regenerate the simulation-only batch and document that the user's pre-existing
   15-call unsuffixed batch belongs to the old combined scope and must be regenerated.
   Leave that user-owned file untouched.
6. Final v5 must wait for the colleague's chain/address/receipt, auth/issuer and
   immutable-admin handoff, verified constants and final-stage rehearsal. Existing
   independent review and test-environment sign/simulate/submit gates remain.

### Initial preparation criteria (historical where superseded above)

1. Preserve historical bootstrap Solidity and pinned manifest byte-for-byte from `4537d18`; retain original proxies and historical factory targets.
2. Preparation reads no private key, broadcasts nothing, simulates the complete Safe configuration and labels its JSON simulation-only.
3. Run the inherited behavioral acceptance/refusal tests on current develop. Include historical replay, wiring, fees, ownership, reruns and downgrade refusal.
4. Check fresh RPC chain/state and rehearse the bridge on that state when available. Treat Safe impersonation separately from real threshold signatures.
5. Keep simulated outputs separate from live deployment output. The live Safe batch may be used only after its referenced deployments have successful receipts, and must execute atomically before v5.
6. Keep independent review and real test-environment sign -> simulate -> submit success/refusal acceptance pending until evidence exists. Do not infer release approval from preparation or previous fork results.

## Current evidence

The user reports initial address-matching deployment complete. Local settings contain RPC, token, Safe fee recipient, primary fee 50 bps and fresh-deployment assertion. These are configuration evidence, not approval of token suitability, absence of existing corporations or live deployment.

Owner clarification, October 28: matching is required for critical auths/proxies; all contract addresses need not match. The owner explicitly retained the previous Robinhood-specific badge auth/proxy exception. Preserve original core and four shared intermediate factory proxies. Later v5 proxy address inventory remains a separate release decision.

Read-only snapshot [robinhood-readiness-20261028.json](robinhood-readiness-20261028.json), block **100370688**, chain **4663**: Safe has code and threshold 2, holds core AUTH role 200; factory implementation is the pinned original `0xa150525deD1aA387E160FDF4b45e975acD02E156`; all 36 replay targets have no code. Configured token has code and decimals 6. Historical sender balance is 4,111,247,866,410,888 wei at this block. No real signer control, gas sufficiency, token suitability or absence of existing corps is inferred.

## Validation

Validated dirty code based on `0a598592e2b66a1754af81c3746e93b6c155e7c8`: restored unchanged bootstrap source/manifest, Robinhood constants, inherited tests plus preparation-entrypoint test, new Solidity rehearsal entrypoint and PowerShell launcher. No production contract source changed.

- `forge test --match-path test/BootstrapRobinhoodTest.t.sol --offline --use 0.8.28 --evm-version cancun --threads 1` with explicit OpenZeppelin remappings: **17 passed, 0 failed, 0 skipped**. Includes inherited historical-bytecode, state/role/fee/wiring, rerun, v5-core compatibility and refusal cases; added preparation simulation/export check.
- `./script/prepare-robinhood-intermediate.ps1 -ExpectedChainId 4663 -ForkBlockNumber 100370688`: **passed**. All 36 replay deployments and historical LeXcheX Safe-role grant simulated; all 15 Safe-owned calls locally executed and postconditions checked. Real Safe signatures/submission were not exercised.
- Deployment estimate at this block: **86,733,583 gas**, **0.003574811443661583 ETH** at **0.041216001 gwei**; separate Safe execution is excluded. This is a historical estimate, not a funding guarantee.
- Generated mainnet review batch: `script/res/gnosis-batch-bootstrap-robinhood-4663.simulation.json`. Checked chain/Safe, 15 zero-value calls and expected destination inventory. Simulation only; not an execution artifact. Testnet fixture export was archived under ignored `out/robinhood-rehearsal/`.
- `forge fmt --check`, PowerShell syntax parse and `git diff --check`: passed. Bootstrap source and manifest byte-for-byte equal `4537d18`; manifest SHA-256 `0e08923887062963553ad3d8a36e911c0e68cb05c46de075bbf304856d24f82a`.
- Existing compiler warnings, stale historical artifact warnings and sandbox signature-cache warnings occurred; tests and rehearsal succeeded. No toolchain or dependency update was needed. Remote `develop` was fetched and matches the stated base.

## Review and release gates

Independent external-model review, source-chain provenance review and real test-environment sign -> simulate -> submit success/refusal acceptance remain pending. Earlier October 23 full-v5 rehearsal remains evidence of its exact prior code, not current branch release approval. No merge, deployment, Safe signature/execution or external audit occurred.

## Next action and handoff

Review the [updated operator runbook](../../../script/res/robinhood-bootstrap.md) and simulation-only batch. After the existing release gates and explicit live authorization, the operator may broadcast the revised core-only bootstrap entrypoint, confirm receipts, then sign and execute that live run's complete 14-call Safe batch atomically. The old 15-call JSON must be regenerated. Verify the listed core postconditions and the colleague's independent badge/secondary handoff before proceeding to v5. This chat owns only the intermediate setup; the colleague owns the user-assigned badge/secondary deployment, while other prior rollout ownership is unchanged.

## October 28 follow-up: labeled deployment logs

At the user's request, the bootstrap now names every replay target and distinguishes
proxies, implementations, libraries and LeXcheX AUTH. It separately prints the
preserved original core AUTH/factory/registry/URI proxy addresses. This supersedes
the source-byte-identity criterion above only for console labeling; the frozen
manifest, payloads, salts, addresses, authority checks and Safe calls are unchanged.
The source-byte-identity validation above applies to preparation commit `2ab7563`.

All ten shared replay proxy addresses were compared with the checked-in production
core/extension records (including grouped ETH/Arbitrum extension constants); all
match. This is a repository-address comparison, not a new remote-chain inspection.
The approved badge exception is retained. A locally generated unsuffixed Safe
batch was present before this change and was left untouched; its presence and the
pasted logs do not establish that any deployment or Safe execution occurred.

Validation on dirty base `2ab7563761fc21d13e3048cc8d91af5dae26c1be`: the existing
original-to-bridge state/configuration regression passed for the initial named-log
change; final display-role refinements passed `forge build` for the bootstrap and
`forge fmt --check`. Manifest SHA-256 remains
`0e08923887062963553ad3d8a36e911c0e68cb05c46de075bbf304856d24f82a`.
No new test was added for this display-only change, and no transaction was submitted.

## Validated colleague deployment split

Validated dirty code based on `9cef8f3`: the bootstrap filters its hash-pinned
manifest to the 32 historical entries, omits the badge Safe-role requirement and
issuer-key call/check, and remains independent of the external deployment. The
36-entry manifest is unchanged; no protocol contract source changed. Robinhood
badge address constants are explicitly marked prior targets awaiting the colleague's
verified handoff, not approved final-v5 configuration.

- **19 tests passed, 0 failed, 0 skipped** with the same pinned compiler/EVM and
  explicit remappings as above. New regressions prove that no badge/auth/render/
  implementation is deployed when absent, no badge transaction is queued, and an
  independently provisioned badge's implementation, auth authority and issuer keys
  remain untouched. Existing v5-core formation, refusal, rerun and separately
  provisioned badge-upgrade/handoff cases pass.
- Key-free core-only rehearsal at Robinhood **block 100370688 passed**. It replayed
  32 deployments and simulated **14** Safe calls. The regenerated committed
  `.simulation.json` has no old or shared badge destination. Estimated deployment
  gas: **76,310,400**, **0.0032135836411104 ETH** at **0.042112001 gwei**; Safe
  execution is separate. The source-state block is pinned; the fee quote came from
  the RPC during rehearsal.
- `forge fmt --check` and `git diff --check` passed. Frozen manifest SHA-256 remains
  `0e08923887062963553ad3d8a36e911c0e68cb05c46de075bbf304856d24f82a`.
- Initial allocating manifest filtering hit a compiler IR stack limit; stable
  in-place compaction resolved compilation. A preliminary external-badge fixture
  consumed its one-shot Safe prank on an intervening constant getter; reading the
  constant before the prank corrected the fixture. These were local preparation
  issues; no live contract was changed or transaction submitted.

The pre-existing user-owned unsuffixed JSON still contains 15 calls and is left
untouched as historical output. It must not be executed for the new split.
External-model review, real test-environment sign/simulate/submit acceptance,
colleague receipts/configuration verification, final-stage integration and explicit
live authorization remain pending.

## Foundry verification configuration follow-up

The user reported missing Etherscan key and then `Chain 4663 not supported` while
running the bootstrap with explicit `--verifier etherscan --verify`. Added the
chain-specific key reference (actual key kept only in ignored `.env`), chain 4663
V2 endpoint table and project V2 API default in `foundry.toml`.

Read-only `forge verify-check` with a dummy GUID reproduced the unsupported-chain
error on installed Foundry v1.2.0-rc `0a7b3f0`. Explicit verifier URL alone reached
the endpoint but omitted chainid; explicit URL **and** `--etherscan-api-version v2`
returned the expected invalid-GUID response. Both flags are documented in the
runbook. Config parsing and `git diff --check` passed. This is routing validation,
not full source verification; no private source was uploaded and no broadcast,
signing or deployment retry was performed by this task.

A local non-dry-run bootstrap artifact now contains 33 transactions and zero
saved receipts. This does not establish that all transactions were or were not
submitted; deployment status remains unconfirmed without RPC/receipt readback.

## Post-deployment source verification (October 28)

The user explicitly requested a PowerShell script and execution of explorer source
verification after deployment. This authorizes publishing verification packages
for this deployed bootstrap scope; it does not authorize signing, deployment,
upgrades, Safe execution, private-source uploads outside that scope or external audits.
The latest local bootstrap artifact now has 33 saved successful receipts; RPC
confirmation is still required before explorer submission. The user's subsequent
removal of the Etherscan table from `foundry.toml` is preserved.

Acceptance criteria established before implementation:

1. Select only the 32 historical entries from the unchanged hash-pinned manifest;
   exclude the colleague's badge/secondary scope and original prerequisite stack.
2. Read RPC chain 4663, confirm each actual deployment transaction targets the
   deterministic factory with its exact manifest payload and a successful receipt,
   and require code at the corresponding target before submission.
3. Reuse already-public Ethereum explorer source/settings for those same CREATE2
   addresses. Do not verify old bytecode using current checkout source. Recover
   constructor arguments from the saved matching historical transactions and pin
   a portable recipe inventory; similar-match source records can omit arguments.
4. Use direct Etherscan V2 requests with explicit chainid to avoid the installed
   Foundry chain-registry failure. Keep keys/RPC secrets out of output, tracked
   files and saved state. Never request or use a transaction signing key.
5. Provide prepare-only operation, resumable submission/status state and per-contract
   outcomes. Do not label a queued request, similar source or a failed/pending
   explorer response as fully verified. Preserve receipts and verification as
   separate evidence. Check both success and refusal/error behavior locally.

### Results and handoff

[Per-contract verification report](robinhood-verification-20261028.json) records
addresses, deployment transaction hashes, source-package hashes, compiler names,
explorer outcomes and links. **All 32 actual replay transactions/receipts/payloads
and target code were confirmed through Robinhood RPC.** The operator's broadcast
artifact contains 33 successful saved receipts including its separate role-grant
call. The regenerated unsuffixed Safe JSON now contains 14 calls; this verification
did not execute or confirm execution of that batch.

Ran `script/verify-robinhood-bootstrap.ps1` in prepare-only mode for all 32,
submitted one public historical library package successfully, then submitted the
remaining packages. A final `-StatusOnly` run confirmed **22 Exact Match source
records and 10 Similar Match source records**; there are no remaining unverified,
failed or pending entries in this scope. The ten are nine ERC1967 proxies and
LeXcheX BorgAuth. Etherscan's verification queue replied `Already Verified` for
them, and source readback confirmed the similar-match distinction. Do not describe
them as exact constructor-argument verification. Etherscan restricts Similar Match
reverification to whitelisted authors; upgrading those ten requires that external
account/support step. No support message or ownership signature was sent.

The script defaults to preparation, supports `-Submit` and `-StatusOnly`, reports
exact/similar matches separately, and offers `-RequireExactMatch` to make similarity
an incomplete result. After the owner's account gets Etherscan access,
`-Submit -RetrySimilarMatch -RequireExactMatch` retries those entries. It excludes
the colleague scope and original prerequisite deployment and does not load a
signing key. Public source packages and resumable state stay under ignored
`out/robinhood-verification/`; portable constructor recipes are committed with
LF/hash protection. Existing user edits to `foundry.toml` and the generated Safe
batch were preserved.

Validation on dirty base `521e695c6390452d7134a681a051e181e03b729f`: PowerShell syntax
and offline fixture checks passed for source/settings preservation, constructor
arguments, credential exclusion, missing/URL-only source refusal, chain/routing
override refusal, successful/reverted receipts, wrong payload, missing code,
V2 POST query routing and exact/similar classification. The first POST exposed
Etherscan's requirement that routing/auth stay in the query string; corrected and
covered by a fixture. `Already Verified` with status zero is classified from actual
source readback, rather than mislabeled as failed or exact. `git diff --check` and
checks for configured secrets in new deliverables passed. No Solidity or deployment
logic changed; no unrelated Solidity test suites were rerun.

Next: the operator handles the separate Safe configuration and the colleague's
badge/secondary handoff. Full source/ABI availability is established for these 32;
exact upgrades for ten, external-model review, integration acceptance and final-v5
readiness are not established by explorer verification.

## October 28 default-branch contract synchronization check

At the user's request before v5 upgrades, fetched the remote default branch.
The remote has no `main`; its default is `develop`. Fresh `origin/develop` is
`0a598592e2b66a1754af81c3746e93b6c155e7c8`, already an ancestor of this branch's
`521e695c6390452d7134a681a051e181e03b729f` (four branch-only commits, zero missing
default-branch commits). The complete `src/` tree and the v5/core/builders/V2/V3/
secondary-condition entrypoints are identical to that default-branch revision.
No merge or contract edit was necessary.

Re-ran `test/BootstrapRobinhoodTest.t.sol` with offline Solidity 0.8.28, Cancun,
one thread and the explicit OpenZeppelin remappings: **19 passed, 0 failed,
0 skipped**, including v5 core formation, external-badge preservation/handoff,
rerun and refusal cases. Tested code head is `521e695`; the pre-existing local
`foundry.toml` deletion of the Robinhood Etherscan table was retained, and the
user-owned unsuffixed mainnet batch was untouched. Removed only the new testnet
simulation JSON generated by this test run. A nonfatal signature-cache permission
warning occurred. This record update is local and uncommitted.

This establishes source synchronization and local compatibility only. The
colleague's verified badge/secondary handoff, final-stage rehearsal, independent
review and test-environment sign/simulate/submit gates remain as recorded above;
no release approval, signing or deployment was performed.
