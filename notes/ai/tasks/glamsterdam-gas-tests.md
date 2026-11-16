# Task: Glamsterdam gas rules in the test suite

- **Status:** Ready for review
- **Updated:** 2026-11-16
- **Owner:** Claude Code session for detoo
- **Collaborators / boundaries:** None known. Test and config files only; no `src/` change.
- **Objective:** Tests run under Glamsterdam gas rules (EIP-8037, EIP-8038), and the gas guards check the
  limits that Glamsterdam enforces.
- **Out of scope:** Contract changes, deploy script changes, webapp gas settings.
- **Canonical plan / sources:** https://github.com/ethereum/glamsterdam-gas-invariants (README, AGENTS.md,
  INV-1 to INV-8); https://eips.ethereum.org/EIPS/eip-8037
- **Repository / branch:** cybercorps-contracts; base `develop` at `238237a6`, branch `test/glamsterdam-gas-limits`
- **Verified base / code head:** `af251895` (merge of `test/round-gas-layered`, which brings `develop` up to
  `32c59e33`) plus an uncommitted change to `test/RoundLifeCycleGasLimit.t.sol` (isolate setting and
  Glamsterdam numbers on the layered round guard)
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
- Chain limits, read 2026-11-09 through the project `RPC_URL_*` endpoints: Arbitrum and Robinhood 32M (ArbOS
  `maxTxGasLimit`), Base 40M, Ethereum 60M, Base Sepolia 120M, Sepolia 200M (block gas limit).
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

| Check      | Evidence and exact revision                                                                                                                | Result / remaining limitation   |
|------------|--------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------|
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --nmc '(ForkTest\|AdhocTest)'`; `af251895` + round guard change | 1536 passed, 0 failed           |
| Fork tests | `forge test ... --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`; `238237a6` + 32M changes (the budget is not in fork tests)           | 217 passed, 0 failed, 1 skipped |
| Build      | `forge build ... --sizes`; same                                                                                                            | passed                          |

## Review and blockers

Legacy ~13 KB per-cert payload operations need ~65M: `createRound` 64.9M, `allocate` 65.1M, legacy equity
`finalize` 64.6M to 65.4M. They fit the 180M budget, but not Arbitrum, Robinhood or Base. They also do not fit
Ethereum until its limit goes above ~65M.

2026-11-16: `RoundLifeCycleLayeredGasLimitTest` measures the round with the layered payload (`ShareExtensionV3`).
`allocate` is 21,214,866 (−67.4%), so it fits 32M. `createRound` is 67,057,241 (+3.3%), so the layered format does not
make round creation fit 32M, 40M or 60M.

2026-11-16: the fixture matches no live cert. Read through `RPC_URL_ETHEREUM`: the live Series Seed 2
and Series Seed printers are layered (`ShareExtensionV3`; series data 9,504 B and 9,728 B; cert layer
896 B and 800 B). The Common Stock certs are legacy (7,904 B to 12,864 B, no legends).
`RoundLifeCycleMainnetSeed2GasLimitTest` uses `test/libs/MainnetSeed2ShareCert.sol`, copied from printer
`0xe48F7f3DE3F68E7C53Deaf6D092C0eC6Af459e0A` cert #1 at block 26429373. `createRound` is 51,337,723 and
`allocate` is 21,318,089. Round creation with live data fits 60M, but not 32M or 40M.

2026-11-16: replay of the 30 mainnet transactions that touched the three MetaLeX Labs printers, plus the May
round and the Common Stock `acceptOffer` (`test/GlamsterdamReplayAdhocTest.t.sol`). Each test forks at its
transaction hash and sends the same calldata from the same sender. Run with `--evm-version prague` and with
`amsterdam`, both with `--disable-block-gas-limit` (without it, the fork uses the block's 60M limit and the
May `allocate` runs out of gas). The `prague` replay is within 2.5% of each receipt. The numbers do not include
intrinsic or calldata gas, and use the contract code at each block.

| Operation (real transaction) | Receipt | Glamsterdam total | Execution | Guarded? |
|---|---:|---:|---:|---|
| May `createRound` (legacy) | 13.0M | **62.0M** | 7.4M | yes (fixture 64.9M) |
| May `allocate` (legacy) | 13.9M | **61.3M** | 8.5M | yes (fixture 65.1M) |
| Common `finalize` (real sale) | 10.6M | **45.3M** | 6.8M | yes (fixture ~65M) |
| `createCertAndAssignWithName`, legacy 13.9 KB | 9.5-9.6M | **44.6-44.8M** | 5.6M | **no** |
| `createCertPrinter` (Seed, Seed 2) | 9.2M | **44.4-44.5M** | 5.2M | **no** |
| `createCertAndAssignWithName`, legacy 8.9 KB | 6.0-6.1M | **27.6-28.4M** | 3.6M | **no** |
| `createCertAndAssignWithName`, layered | 4.4-4.5M | 19.9-20.2M | 2.7M | **no** |
| `submitEOI` | 1.5M | 6.0M | 1.0M | yes |
| `acceptOffer` | 2.3M | 5.8M | 1.9M | yes |
| `postOffer` | 0.6-1.6M | 2.3-3.2M | 0.4-1.4M | yes |
| Common printer creation (older version) | 0.5M | 2.3M | 0.3M | no |
| `scripifyCert` | 1.0M | 1.8M | 0.9M | no |
| `addCertLegend` | 0.24-0.26M | 0.9-1.1M | 0.2M | no |
| `voidEmptyCerts`, flags, timestamps, holder count | <0.31M | <0.41M | <0.31M | no |

- Execution gas never binds (highest 8.5M against a 15.1M budget). Total gas is the only limit that binds.
- Calls that write new storage cost 4.2-4.8x more. Calls that only update storage cost 1.07-2x more.
- Against 90% budgets: Arbitrum and Robinhood (28.8M) cannot run the 44M operations, and legacy 8.9 KB
  issuance is at 98.6%. Base (36M) cannot run the 44M operations or `finalize`. Ethereum at 60M (54M)
  cannot run the May `createRound` or `allocate`. Everything fits 180M.
- The legacy round fixture reads 3-4M above the real May transactions.

### Why the ~60M operations cost so much

State diffs of the replays under `amsterdam` (each new storage slot costs 97,920 state gas). New slots explain
more than 99% of the state gas in each transaction.

| Transaction | Total | New slots | Main writes |
|---|---:|---:|---|
| May `createRound` | 62.0M | 551 | RoundManager keeps the round's copy of the cert payload (422 slots, 41.3M). The new printer stores its 6 default legends (113 slots, 11.1M). Execution 7.4M. |
| May `allocate` | 61.3M | 539 | The new cert gets the payload copied from the round (416 slots, 40.7M) and a copy of the 6 legends (113 slots, 11.1M). Execution 8.5M. |
| `createCertPrinter` (Seed 2) | 44.4M | 394 | Series data (279 slots, 27.3M). Default legends (113 slots, 11.1M). |
| Legacy `createCertAndAssignWithName` | 44.8M | 400 | The cert's 13.9 KB payload (400 slots). This printer has no legends. |
| Common `finalize` | 45.3M | 393 | The buyer's new cert gets a copy of the seller's payload (390 slots). |

- A legacy round writes the payload two times. `createRound` keeps each cert's payload in RoundManager storage
  (`round.extensionData`), and `allocate` copies it onto the cert. Together they write about 82M of state gas.
- Each mint copies the printer's default legends onto the cert (`s.certLegend[tokenId] = s.defaultLegend` in
  `recordMint`, `recordMintAndAssign` and `recordMintFromAndAssign`). On the Seed printers this costs about 11.1M
  for each cert, at issuance and at each secondary mint.
- The share data's transfer restrictions repeat the legend text. The same text is therefore stored as the
  printer's default legends, as each cert's legend copy, and inside the payload.

### Can a separate transaction avoid it

A split moves gas to another transaction. It does not lower the total, because state gas is a fixed price for
each new slot. A split helps only to fit a per-transaction cap, such as 32M on Arbitrum and Robinhood.
The figures below are estimates (slot counts x 97,920); the split sequences were not run.

| Change | Possible without a contract change? | Effect |
|---|---|---|
| Create the printer with no legends, then call `addDefaultLegend` x6 | Yes (`onlyIssuanceManagerOrAdmin`) | Takes about 11M out of `createRound` or `createCertPrinter`. The legends must be in place before the first mint, because a mint copies only the legends that exist then. A cert minted earlier needs `addCertLegend` for each legend, at the same cost. |
| Create with empty series data, then call `setSeriesData` | Yes | For live Seed 2, `createRound` drops from 51.3M to about 22M. `setSeriesData` needs about 30M, which is above the 28.8M L2 budget. It writes the whole value in one call, so it cannot be split further. |
| Mint the cert empty, then call `updateCertificateDetails` with the payload | Technically yes | Moves about 41M into a second transaction, still too large for L2s. The cert exists without its terms until then. Not recommended. |
| The legend copy at mint (11.1M per cert) | No | The mint always copies. Only a printer with no default legends avoids it. |

What lowers the cost:
1. The layered format, which exists today. The cert payload drops from about 438 slots to 28, and `allocate`
   goes from 61.3M to 21.3M. The round's copy becomes small. The series data is written one time for each printer.
2. Contract change (open decision): certs read the printer's legends instead of copying them. Estimated saving
   about 11.1M for each mint on printers with legends, including secondary mints. A cert's legends would then
   follow later edits to the printer's defaults, so this needs an owner decision and an audit-history check.
3. Data change: do not repeat the legend text inside the transfer restrictions. No code change. The saving is
   not measured. This is a legal choice about the documents.

## Next action and handoff

Owner reviews and commits. Owner decides if Arbitrum, Robinhood and Base need their own budget.
