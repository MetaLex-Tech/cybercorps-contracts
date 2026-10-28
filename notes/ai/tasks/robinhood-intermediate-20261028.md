# Task: Robinhood intermediate deployment setup

- **Status:** Core-only intermediate preparation complete, ready for review; external badge/secondary handoff and release gates pending. No live signing or submission authorized.
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
