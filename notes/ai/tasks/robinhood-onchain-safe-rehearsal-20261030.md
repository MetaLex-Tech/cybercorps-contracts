# ETH to USDG and on-chain SAFE LET rehearsal script

- Owner: current Codex chat; prepare operator-run script, no live submission.
- Date: 2026-10-30. Branch: `codex/robinhood-intermediate-20261028`.
- Source base: `b59269beea86f7ccb14c516361140519c8da8f2c` plus existing local
  lifecycle acceptance additions. Preserve dirty operator files and prior work.
- Status (November 1): all `SAFE_*` settings optional; default-only generated-signer
  fork lifecycle passes. Existing RPC/officer key plus distinct investor key suffice.
- User request: script to convert some ETH to USDG, create a round and invest
  in a SAFE LET, which the user will run on-chain.
- Prior evidence: [strict live-template acceptance](robinhood-live-template-acceptance-20261030.md).

## Invariants and acceptance criteria before implementation

1. Chain 4663 and existing canonical core/registry/USDG/SAFE V3 only. No upgrades,
   no template fixtures or alternate payment tokens. Discover and verify a real
   native ETH/USDG swap pool/router from primary deployment sources and RPC.
2. Require explicit ETH input, USDG minimum output, investment amount, expiry and
   operator metadata; enforce bounded amounts, balance checks, deadline and
   minimum output. Never infer a spending budget from a wallet balance.
3. Officer and investor must be different signer addresses (registry rejects
   duplicate parties). Script reads user-managed environment keys only when run
   by the operator; no real key lookup, insertion, signing or live broadcasting
   by this task. Local checks use generated test signers through explicit inputs.
4. Swap proceeds must actually fund the USDG investment; no mock/deal minting of
   USDG in fork acceptance. Use exact approvals and clear remaining allowance.
5. Form company through live factories, sign and create SAFE round, investor
   signs/escrows USDG, officer allocates and finalizes, investor receives SAFE LET.
   Assert fee/payout/balances, signatures, finalization, owner/type and metadata.
6. No silent duplicate live investments or repeated swaps on rerun. Explicit
   salts and deterministic outputs/checkpoints; reject incompatible prior state
   or expose safe staged continuation. Document that separate broadcast calls
   are not atomic and how to resume after failure without repeating the swap.
7. Validate available-route quoting/swap, full local fork lifecycle and material
   refusals (slippage, expired config, wrong chain, same signer, insufficient
   proceeds). Keep independent review, actual test-environment sign/simulate/submit
   and operator release gates distinct. No live transaction is authorized here.

## Progress

### November 1 implementation and validation

Implemented against `f90978dbf333abb19a20696fd879cb8aad55bdc4` plus uncommitted
changes to the rehearsal script/test/runner/runbook, `.gitignore` and shared
records. Protocol `src/` is unchanged. Earlier explicit-public-configuration
requirements below are superseded by the user's test-only instruction above.
Every `SAFE_*` value now has a default; only the existing RPC/key setup and
distinct `PRIVATE_KEY_INVESTOR` are required. Test labels/reserved contacts,
template 32, $10m valuation, deterministic officer salt, saved 24-hour dates
and live quote +5% default ETH cap (ceiling 0.00001 ETH) are implemented.
The local ignored file stores only salt/dates/budget/valuation and must be
retained for retries. Existing optional env overrides remain supported.

**16 passed, 0 failed, 0 skipped** on fresh Robinhood fork **103742143**:
5 config regressions and 11 real-route lifecycle/refusal checks. Both the actual
default loader with public settings empty and the live-quoted budget complete
formation, signing, USDG investment and investor SAFE LET delivery. Full existing
fee/allowance/metadata/retry checks still pass. Quote was **4,434,813,571,845 wei**;
saved default cap **4,656,554,250,438 wei**, gas additional. Evidence:
[November 1 verification](robinhood-cent-safe-verification-20261101.json).
The first unit pass caught old-Foundry `writeJson(key)` not inserting missing
fields; full-object serialization fixes it, covered by the budget retry check.
Unit test expectation ordering was also corrected before the final full pass.
Solidity formatting, Python compilation and whitespace checks pass. No operator
key was read/set/inserted, `.env` was unchanged, and `run()`/live broadcast were
not invoked. Independent external review, actual test-environment submission,
merge and live deployment remain separate/unperformed gates.

### November 1 configuration correction: acceptance before implementation

Current checkout is `f90978dbf333abb19a20696fd879cb8aad55bdc4`; current remote
branch fetched successfully. Owner remains this Codex chat. The operator reported
missing `SAFE_ROUND_START`. Make salt/start/end optional with a saved, public-only
run identity per officer/salt. First use defaults to an already-open 24-hour
window; later runs must retain the original dates, including after expiry.
Explicit date overrides conflicting with saved dates must refuse rather than
create a second round. Keep the explicit ETH budget, valuation and signed legal
metadata; do not invent identities or financial terms. Do not read operator keys
or invoke `run()` during validation. Regression checks must cover initial defaults,
stable retry dates, deliberate distinct salts, expiry without automatic renewal,
and refusal of changed dates. User then requested reasonable defaults at the
current price: extend this to a live exact-output quote plus 5% rounded-up
headroom, with an absolute default ceiling of 0.00001 ETH, and a $10 million
rehearsal valuation cap. Persist both with the dates; retries cannot silently
increase spending or change signed valuation terms. Explicit environment values
remain supported for initial configuration. Test quote rounding/ceiling,
persisted budget/valuation and conflicting overrides, plus the real pool path.
The user then clarified this is a test and requires **no new mandatory env vars
except the investor key**. This supersedes the earlier explicit-budget/metadata
requirement for this rehearsal. All `SAFE_*` inputs must be optional; default
metadata must clearly say test/rehearsal and use reserved `.invalid` contacts,
without inventing real identities or claiming investor jurisdiction/eligibility.
Keep the two distinct environment keys and existing RPC config. Test `loadConfig`
itself with all public SAFE variables absent, using generated signers only.
Existing full-lifecycle acceptance remains distinct
from these configuration regressions and from live submission/review gates.

The user specified enough ETH for **0.01 dollars**; principal is therefore fixed
at **0.01 USDG / 10,000 base units**, with gas additional. The script buys only the
missing balance to reach that amount and requires an explicit ETH maximum. A
second signer is required by the registry's DuplicateParty rule. The operator
must provide `PRIVATE_KEY_MAIN` (officer) and `PRIVATE_KEY_INVESTOR` (investor),
without embedding or transmitting actual keys during preparation.

## Route and implementation

- Verified official [Uniswap deployment feed](https://developers.uniswap.org/deployments.json)
  (source contracts commit `cd2e8a869498e9cd6e821ad518d91f6c7a3d8d72`), router
  revision `802fe4c`, and its exact v4-periphery submodule revision
  `545a5d2a87228167edde48f3b9eda122d1e3c4d6`. The deployed 2.1.2 router's ABI
  includes `minHopPriceX36`; no older-router ABI was assumed.
- Verified live router `poolManager()`, active liquidity and an exact-output
  quote for 10,000 USDG units. The ETH/USDG pool uses currency0 zero, fee 500,
  spacing 10, no hook; pool ID
  `0x387bf619da4d3fb62bb276482693dba1b9b3520f573cabdfe033384a24125982`.
  [Route evidence](../../../script/res/robinhood-cent-safe-route.json) includes
  canonical addresses and runtime hashes. No third-party calldata or token approval
  is accepted; the ETH-funded router command returns unspent native ETH.
- [Solidity entrypoint](../../../script/robinhood-cent-safe.s.sol): quote-only mode
  requires no keys. Operator `run()` reads environment keys and configuration;
  tests invoke `execute()` directly using generated test signers. Chain, plain
  distinct EOAs, explicit ETH max, reserves, dates, SAFE 30/32 field shape, USDG,
  payout and existing state are checked. No operator key lookup/insertion or
  environment edit was performed by the task.
- The swap runs before first company creation, enforces exact USDG delivery and
  maximum ETH spend, and refunds change. Already-funded USDG skips a repeated
  swap. Company, round and agreement IDs are deterministic for unchanged public
  inputs. Matching company/round and paid/finalized agreement state is reused.
  A completed rerun does not trade or reinvest, even after expiry; incompatible,
  voided and already-raised round state refuses. Changed inputs intentionally
  constitute a different run; the runbook instructs keeping original inputs.
- Actual deployed factory formation, officer escrowed EIP-712 signature, investor
  registry EIP-712 signature, exact USDG allowance, EOI escrow, officer allocation,
  agreement finalization and investor SAFE V3 LET readback are implemented.
  Round cap/min/max all equal the one-cent principal; price is 1 USD per 18-decimal
  fractional unit. The operator supplies the legal metadata and valuation cap.
- [PowerShell wrapper](../../../script/robinhood-cent-safe.ps1) exposes Quote,
  DryRun (default), and explicit Broadcast with `--slow`. It never reads or passes
  a key value. [Runbook](../../../script/res/robinhood-cent-safe.md) documents both
  wallet roles, public configuration, quote/max input, gas, execution, receipts
  and partial-run continuation/expiry recall.

## Validation and limits

**9 passed, 0 failed, 0 skipped** at Robinhood fork block **102212288**.
[Verification evidence](robinhood-cent-safe-verification-20261030.json) records
exact code/test/runner/log hashes, source revision, fork hash and commands.
The selected production source is base `b59269b`; new script/test/wrapper and
documentation are local working-tree additions. Protocol `src/` was not changed.

The actual pool swap consumed **4,462,287,569,119 wei ETH** for **0.01 USDG**,
excluding gas. Only native ETH was funded locally; no USDG was minted or injected,
and no code/calls were mocked. Company receives **9,950** USDG units (0.00995),
platform receives **50** (0.00005), allowance and escrow end at zero. Both agreement
signatures/finalization, investor delivery/legal LET ownership, SAFE/SeriesSeed,
extension, 0.01 investment and JSON/SVG are verified.

Material checks cover too-small ETH budget before spending, expired config,
same signer, wrong chain, unfunded investor, unsupported template, platform/payout
collision, changed investor on an already-filled round, completed idempotent rerun
after expiry, and continuation from a real already-executed swap. Existing compiler
warnings were nonfatal. Python compilation, Solidity formatting, PowerShell parser
and whitespace checks pass. Local sanitized logs/metadata/SVG are under ignored
`out/robinhood-cent-safe/`.

The key-loading `run()` entrypoint was not executed by the agent. No real key was
read, set or inserted. No live swap, formation, approval, signature submission or
investment was sent. The operator will fund/select wallets and run on-chain.
No arbitrary default budget was derived from wallet balances. The ETH maximum
does not include gas and no ETH is automatically transferred between wallets.

Separate transactions are not atomic; failed live stages can leave earlier
confirmed stages in place. Resume logic is prepared and partly exercised, but no
real test-environment signer/quorum control or sign/simulate/submit acceptance,
external-model review, frontend acceptance or release approval is established.
No public-round LeXcheX/passport/compliance condition flow was tested. Nothing
was merged/pushed and existing operator files were preserved.
