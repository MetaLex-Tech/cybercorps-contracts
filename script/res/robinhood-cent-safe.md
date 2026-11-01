# On-chain 0.01 USDG SAFE rehearsal

Use [robinhood-cent-safe.ps1](../robinhood-cent-safe.ps1) from the repository root.
It wraps [RobinhoodCentSafeScript](../robinhood-cent-safe.s.sol), targeting
**Robinhood mainnet 4663** and the deployed CyberCorps factories/registry.

The principal is fixed at **10,000 USDG base units = 0.01 USDG**. The script:

1. Buys only the missing USDG using native ETH and a Uniswap v4 exact-output swap.
   An explicit maximum ETH input caps the trade; unused ETH returns to the investor.
   If the investor already has at least 0.01 USDG, it skips the swap.
2. Creates the CyberCorp owned by the configured officer through the live factory.
3. Creates a private founder-approved SeriesSeed SAFE round capped at 0.01 USDG.
4. Approves exactly 0.01 USDG, signs the investor agreement and deposits it.
5. Allocates the full deposit, finalizes the agreement and delivers the SAFE LET
   to the investor. At the observed 50-bps fee, the company receives **0.00995 USDG**
   and the platform **0.00005 USDG**. No approval allowance remains after payment.

**Gas is additional to the one-cent investment.** Each wallet must already hold
ETH for its transactions. The investor funds the swap and investment; the officer
pays for company/round creation and allocation. No ETH is automatically transferred
between the wallets. The script changes no templates, infrastructure, roles or fees.

## Wallet configuration

Configure these two variables yourself in your existing local environment or
ignored `.env`; no key values belong in this runbook or repository:

- `PRIVATE_KEY_MAIN`: officer/issuer wallet.
- `PRIVATE_KEY_INVESTOR`: **different**, plain EOA investor wallet.

The registry rejects duplicate agreement parties, so one key cannot serve both
roles. The script refuses same-address signers and code-bearing accounts. Keys
are read only by the operator's `run()` entrypoint. The wrapper does not read,
print or pass key values on the command line. No `--private-key` or `--account`
option is needed.

## Quote first

This entrypoint does not read either key:

```powershell
.\script\robinhood-cent-safe.ps1 -Mode Quote
```

It reports ETH input in **wei** for exactly 0.01 USDG at the current pool state.
For orientation only, the fork test spent about **0.000004463 ETH** for the swap;
this is not a fixed price or a gas estimate. Choose `SAFE_MAX_ETH_IN_WEI` yourself
after reviewing the fresh quote. If the quote exceeds that cap, the script refuses
before the first trade or company creation. The actual swap also enforces the cap.

## Set public run parameters once

The following are example public values. Replace identities, contacts, company
details, jurisdiction, valuation cap and template choice with your intended
values: they are signed agreement fields and are stored on-chain.

```powershell
$env:SAFE_REHEARSAL_SALT = (cast keccak 'my-robinhood-cent-safe-run-01').Trim()
$centRunTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$env:SAFE_ROUND_START = [string]($centRunTime - 3600)
$env:SAFE_ROUND_END = [string]($centRunTime + 3600)

# Example cap only: 0.000005 ETH. Review the fresh quote before choosing yours.
$env:SAFE_MAX_ETH_IN_WEI = '5000000000000'
$env:SAFE_VALUATION_CAP_USD = '10000000'  # whole-dollar SAFE cap, not payment amount
$env:SAFE_TEMPLATE_ID = '32'

$env:SAFE_COMPANY_NAME = 'My CyberCorp Rehearsal'
$env:SAFE_COMPANY_JURISDICTION = 'Delaware'
$env:SAFE_OFFICER_NAME = 'Your officer name'
$env:SAFE_OFFICER_CONTACT = 'your-officer-contact'
$env:SAFE_INVESTOR_NAME = 'Your investor name'
$env:SAFE_INVESTOR_CONTACT = 'your-investor-contact'
$env:SAFE_INVESTOR_TYPE = 'Individual'
$env:SAFE_INVESTOR_JURISDICTION = 'GB'
```

Supported templates are the existing standard SAFE IDs **30 (Reg D)** and **32
(Reg S)**. Select the intended agreement; the script does not evaluate investor
eligibility or choose a regulatory route. All five template global and signer
field names/order are checked before spending.

Optional parameters:

- `SAFE_COMPANY_PAYABLE`: company payout address; defaults to the officer wallet.
  It must differ from the investor and platform fee recipient.
- `SAFE_GAS_RESERVE_WEI`: minimum ETH balance reserve per signer; defaults to
  `100000000000000` wei (**0.0001 ETH**). Before a swap, the investor must hold
  that reserve **plus the full maximum ETH input**. This is a balance check,
  not a guarantee of gas cost or a transaction gas limit.

The start/end are absolute Unix seconds; the end is also the swap and offer
deadline. Keep the **same salt, times, identities, payout and other parameters**
when resuming a run. Do not regenerate this setup block between a failed partial
broadcast and its continuation. Choose a new salt deliberately for a new rehearsal.

## Simulate, then broadcast yourself

```powershell
.\script\robinhood-cent-safe.ps1 -Mode DryRun
```

Inspect the two signer addresses in Foundry's transactions, ETH maximum, 0.01 USDG
principal, company metadata, selected agreement, payout, fee and final LET owner.
Dry-run signs the agreement locally and simulates; it submits no live transaction.

When ready, use the same configuration:

```powershell
.\script\robinhood-cent-safe.ps1 -Mode Broadcast
```

Broadcast mode adds `--broadcast --slow`. Never use `--skip-simulation`. The
wrapper includes Solidity 0.8.28, Cancun, via-IR and the required remappings.
Final output labels the company, round manager, round ID, agreement ID and
SAFE LET address/token ID. Confirm the actual receipts in Foundry's broadcast
output and read the final ownership/agreement status from chain.

## Resume behavior

These are separate transactions, not one atomic transaction. If a later stage
fails, earlier confirmed actions remain on-chain. Rerun with the exact original
configuration rather than changing the salt or repeating raw transactions:

- Existing deterministic company/round: reuse after checking ownership/configuration.
- USDG already funded: skip the swap.
- Existing paid EOI: skip another swap/deposit and continue allocation while open.
- Finalized investment: return the existing LET without another swap or investment,
  even after the original end time. This is covered by the fork test.
- Different round parameters, voided EOI or another investor's already-filled
  round: refuse. No new swap is started for a filled round.

If a paid offer expires before allocation, the investor can recover its escrowed
USDG using the existing `RoundManager.recallEOI(bytes32)` method. Completed company
creation, swap and network fees cannot be undone by that refund.

## Route provenance and local validation

Addresses come from the [official Uniswap deployment feed](https://developers.uniswap.org/deployments.json)
and [Robinhood v4 deployment listing](https://developers.uniswap.org/docs/protocols/v4/deployments).
[Public route evidence](robinhood-cent-safe-route.json) records source revisions,
addresses and observed runtime hashes. Router source revision is `802fe4c`, with
v4-periphery dependency `545a5d2a87228167edde48f3b9eda122d1e3c4d6`; the exact-output
tuple includes `minHopPriceX36`. The route is ETH/USDG, fee 500, tick spacing 10,
no hook, pool ID `0x387bf619da4d3fb62bb276482693dba1b9b3520f573cabdfe033384a24125982`.
The script checks chain, router pool manager, nonzero liquidity and actual quote.

Local acceptance uses `python script/test-robinhood-cent-safe.py`. It invokes
`execute()` with generated public signers and local ETH funding only: USDG is
actually acquired from the deployed pool. It never reads the operator environment
keys or invokes the key-loading `run()` entrypoint. The successful scenario checks
the one-cent fee/payout, final agreement and investor LET, exact allowance cleanup,
JSON/SVG, completed rerun and recovery from an already-funded USDG balance.

The final selected suite passed **9 tests, 0 failed, 0 skipped**, on a Robinhood
fork at block **102212288**. The successful swap spent **4,462,287,569,119 wei ETH**
for exactly 0.01 USDG, excluding gas. It used the actual deployed pool and token;
only test ETH was locally funded. Refusal coverage includes a maximum below the
quote, expired configuration, wrong chain, same signer, unsupported template,
unfunded investor, platform/payout collision and an already-funded round.

No live transaction has been sent by this preparation task. Independent review,
real test-environment sign/simulate/submit acceptance and the operator's live
release remain separate from these local fork results.
