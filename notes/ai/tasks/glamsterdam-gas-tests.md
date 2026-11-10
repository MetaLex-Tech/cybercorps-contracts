# Task: Glamsterdam gas rules in the test suite

- **Status:** Ready for review
- **Updated:** 2026-11-09
- **Owner:** Claude Code session for detoo
- **Collaborators / boundaries:** None known. Test and config files only; no `src/` change.
- **Objective:** Tests run under Glamsterdam gas rules (EIP-8037, EIP-8038), and the gas guards check the
  limits that Glamsterdam enforces.
- **Out of scope:** Contract changes, deploy script changes, webapp gas settings.
- **Canonical plan / sources:** https://github.com/ethereum/glamsterdam-gas-invariants (README, AGENTS.md,
  INV-1 to INV-8); https://eips.ethereum.org/EIPS/eip-8037
- **Repository / branch:** cybercorps-contracts; base `develop` at `238237a6`, branch `test/glamsterdam-gas-limits`
- **Verified base / code head:** base `238237a6`; `a4b08951` (WIP commit) plus uncommitted changes to
  `test/libs/GasBudget.sol` and the three guard suite headers (200M budget)
- **Worktree locator:** main checkout
- **PR / artifact:** not yet created

## Acceptance and current state

- Tests and script simulations use Glamsterdam gas (`evm_version = "amsterdam"`). Verified.
- Gas guards check execution gas <= 90% of 2^24 and total gas <= 90% of 200M. Verified.
- The Osaka check (total <= 90% of 2^24) is removed. Owner decision, 2026-11-09.
- Guards measure each step as its own transaction (`isolate = true`). Verified.
- Unit suite passes. Verified.
- Arbitrum and Robinhood (32M per transaction) and Base (40M per block) are not covered by the budget.
  Open (TODO in `test/libs/GasBudget.sol`).

## Decisions and evidence

- Owner decisions, 2026-11-09: global `amsterdam`; Amsterdam only. Total budget: first the smallest chain
  limit (32M), then replaced by the owner: assume the Ethereum gas limit matches Sepolia (200M).
- The fork does not set the gas limit; validators raise it. If Ethereum forks while the limit is still 60M,
  a 65M transaction cannot go in a block (EIP-8037: `tx.gas <= state_gas_available`).
- Chain limits, read 2026-11-09 through the project `RPC_URL_*` endpoints: Arbitrum and Robinhood 32M
  (ArbOS `maxTxGasLimit`), Base 40M, Ethereum 60M, Base Sepolia 120M, Sepolia 200M (block gas limit).
  The owner states that only Sepolia runs Glamsterdam today.
- `--evm-version amsterdam` does not change bytecode: solc 0.8.28 caps the target at `prague`. Checked on
  `CyberCorp` and `LedgerEntryToken`.
- Forge 1.8.5 under `amsterdam` charges state gas from `gasleft()` (no reservoir, no 2^24 execution cap).
  `lastFrameGas` reports execution gas only. `test/GasBudget.t.sol` fails if either reading changes.
- Cross-check against Sepolia: `CyberCorp` creation is 26,406,431 gas in Forge (in-EVM) and
  25,821,867 from Sepolia `eth_estimateGas` (whole transaction).
- With `isolate = false`, slots that setup creates and the measured call clears give their state gas back
  inside the same transaction. The `gasleft()` difference then reads low or underflows. The guards and the two
  vault-epoch cost tests now run isolated.
- Related audit findings: Pashov AI report 2026-07-23, finding 2 (confidence 80), unbounded
  `_zeroAllVaultNominals` loop. Recorded response: fixed by the proportional scrip-vault patch (`APPLY.md`);
  the loop is not in `src/` at `238237a6`. The Hexens and Zellic PDFs have no matches for gas-limit terms.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --nmc '(ForkTest\|AdhocTest)'`; `a4b08951` + 200M changes | 1528 passed, 0 failed |
| Fork tests | `forge test ... --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`; `238237a6` + 32M changes (the budget is not in fork tests) | 217 passed, 0 failed, 1 skipped |
| Build | `forge build ... --sizes`; same | passed |

## Review and blockers

Legacy ~13 KB per-cert payload operations need ~65M: `createRound` 64.9M, `allocate` 65.1M, legacy equity
`finalize` 64.6M to 65.4M. They fit the 180M budget, but not Arbitrum, Robinhood or Base. They also do not fit
Ethereum until its limit goes above ~65M.

## Next action and handoff

Owner reviews and commits. Owner decides if Arbitrum, Robinhood and Base need their own budget.
