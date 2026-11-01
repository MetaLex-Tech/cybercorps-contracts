# ETH to USDG and on-chain SAFE LET rehearsal script

- Owner: current Codex chat; prepare operator-run script, no live submission.
- Date: 2026-10-30. Branch: `codex/robinhood-intermediate-20261028`.
- Source base: `b59269beea86f7ccb14c516361140519c8da8f2c` plus existing local
  lifecycle acceptance additions. Preserve dirty operator files and prior work.
- Status: operator script and runbook prepared; generated-signer fork checks pass.
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
