# Task: Robinhood intermediate deployment setup

- **Status:** Preparation complete, ready for review; no live signing or submission authorized.
- **Updated:** 2026-10-28 (America/New_York).
- **Owner:** Current Codex chat, intermediate setup only. Prior Robinhood and other rollout ownership remains unchanged.
- **Objective:** Make the prepared bridge available on current develop, rehearse it against fresh Robinhood state without a private key, and provide concrete deployment/Safe execution instructions.
- **Branch:** `codex/robinhood-intermediate-20261028`.
- **Base:** `0a598592e2b66a1754af81c3746e93b6c155e7c8` (refreshed `origin/develop`).
- **Sources:** [Prior task](robinhood-bootstrap.md), [canonical deployment runbook](../../../script/res/robinhood-bootstrap.md), prepared commit `4537d18`, broader [protocol plan](../../plans/protocol-improvement-plan.md).
- **Scope:** Restore bootstrap source, manifest, tests and Robinhood constants; add a key-free preparation entrypoint and intermediate operator instructions. No protocol source changes, final v5 deployment, merge, external review or real transactions.

## Invariants and acceptance criteria established before implementation

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

Review the [updated operator runbook](../../../script/res/robinhood-bootstrap.md) and simulation-only batch. After the existing release gates and explicit live authorization, the operator may broadcast the unchanged bootstrap entrypoint, confirm receipts, then sign and execute that live run's complete Safe batch atomically. Verify the listed on-chain postconditions before proceeding to v5. This chat owns only the intermediate setup; prior task and optional rollout ownership is unchanged.
