# Robinhood: original addresses -> intermediate bootstrap -> v5

## Current split: colleague deploys secondary conditions and badge

The October 28 ownership change supersedes the badge instructions in the historical
October 23 plan below. **Our intermediate step is now 32 historical deployments
and 14 initial Safe calls** (13 on a rerun after the bridge upgrade). It performs
no badge deployment, upgrade, owner-role grant or issuer-key call and does not
require a badge to exist. The colleague owns the badge AUTH/proxy and the entire
secondary-condition group on **Robinhood mainnet, chain 4663**. These two deployment
tracks can proceed independently; final v5 acceptance depends on both.

The pasted `chainId: 84532` output is Base Sepolia reference material. Its shared
badge AUTH `0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d` and proxy
`0x114664773Ba721a6AA43890d5FDE7939aF37618F` are proposed reference addresses, not
verified Robinhood deployments. The current Robinhood badge constants still hold
the prior exception targets and **must be reconciled before final v5**. Secondary
condition fields remain zero until the colleague's actual handoff is verified.
The reference kill switch `0x4c3b9Ec3B6e416A64Fde4a17Ea856e1cf2fE0344` also differs
from the repository's existing production condition constant; do not copy either
as deployed Robinhood state or infer approval of its immutable admins.

Obtain the colleague's exact source revision, chain ID, deployed address inventory,
transaction hashes/receipts and Safe configuration batch. Verify badge AUTH pointer,
Safe owner role, removal of unintended deployer authority, and the LeXcheX minter's
issuer-key grant (accredited investor, investor type and investor jurisdiction).
Check condition AUTH/registry/badge references, exact immutable kill-switch admins
and the completed Safe-owned configuration calls. Update Robinhood constants only
from that verified handoff, then rehearse the combined final stage.

**The previously generated 15-call unsuffixed bootstrap JSON is stale for this
split. Leave it as historical evidence and regenerate it from the revised script
before any execution.** The 14-call `.simulation.json` remains review-only. Do not
run the full v5 runner until the external inventory and final-stage integration
have been completed; it currently includes the secondary-condition sub-script.

## October 28 intermediate setup on current develop

Use branch `codex/robinhood-intermediate-20261028`, based on develop
`0a598592e2b66a1754af81c3746e93b6c155e7c8`, for the intermediate step.
The pinned manifest is byte-identical to prepared commit `4537d18`. The bootstrap
now replays only its 32 historical entries; the four fresh badge entries remain
in the manifest as provenance and are excluded from execution.
This branch adds Robinhood constants, behavioral tests and a key-free
rehearsal launcher. It does not include the separate final-stage refresh's
`upgrade-robinhood.s.sol` wrapper or builder/JSON compatibility changes; use that
prepared branch and revalidate current source when taking up the final step.

The owner clarified on October 28 that matching is required for critical auths
and proxies, not every implementation/library/condition. The later owner
instruction assigns badge AUTH/proxy and secondary conditions on Robinhood
mainnet (4663) to a colleague. The earlier badge exception targets
remain provisional constants only until that external handoff is verified.
The later v5 proxy inventory still needs its own address review; this intermediate
setup does not approve every future CREATE3 proxy divergence.

From the repository root, run this rehearsal without a signing key:

```powershell
./script/prepare-robinhood-intermediate.ps1 -ExpectedChainId 4663
```

For a reproducible rehearsal of the October 28 snapshot, append
`-ForkBlockNumber 100370688`. For testnet, select `-ExpectedChainId 46630` and
configure its RPC/token. The launcher checks the actual chain ID, pins Solidity
0.8.28/Cancun and supplies the repository's explicit OpenZeppelin remappings.
It reads no signing key and exposes no broadcast switch. The Solidity entrypoint
is `PrepareRobinhoodIntermediateScript.prepare()`, which replays the deployments
and impersonates the Safe locally to check the entire 14-call batch.
Its output is `gnosis-batch-bootstrap-robinhood-4663.simulation.json` under
`script/res/`. **Do not import this simulation output into Safe.**

The local public settings are a six-decimal token at
`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`, the Safe as fee recipient,
50 bps primary fees, and the fresh-deployment assertion. A token's decimals and
code do not establish its suitability; keep the operator's token/fresh-state
checks. Rehearsal uses the historical sender
`0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B` without loading its key.

After independent review, real test-environment sign/simulate/submit acceptance
and explicit live deployment authorization, the deployment operator uses the
core-only signing entrypoint:

```powershell
forge script script/bootstrap-robinhood.s.sol:BootstrapRobinhoodScript --rpc-url $env:ROBINHOOD_RPC_URL --sender 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B --use 0.8.28 --evm-version cancun --via-ir --offline -R '@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/' -R '@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/' --broadcast --slow
```

This command requires `PRIVATE_KEY_MAIN` in the existing secret environment.
The RPC variable must be available in the operator's shell for this command;
the rehearsal launcher also supports reading that one public setting from `.env`.
Do not use `--skip-simulation`. Save/check all replay and LeXcheX role-grant
receipts. Only then import **that live run's**
`script/res/gnosis-batch-bootstrap-robinhood-4663.json` into Safe
`0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`, and execute all 14 calls atomically.
Verify factory implementation `0x424ab1B1DA8b7B2FE13cA0A7ABC346b22efa9191`,
the four factory references, stable whitelist, both 50-bps fees/recipients,
LeXcheX roles against the simulated batch. Badge issuer keys are a separate
external-deployment acceptance check before v5.
This setup grants no live deployment or signing approval.

### Reading the deployment logs

`[preserved]` identifies the original core AUTH and the three existing core proxies
whose addresses remain in place. `[pinned deployment]` identifies a frozen manifest
entry whose runtime was checked during this execution, either after replaying it
or reusing an occupied matching address. Each entry now includes its contract name
and role: proxy, implementation, library or AUTH. The shared factory, LeXcheX,
minter and four historical extension proxy targets match the production addresses
recorded for Ethereum/Base/Arbitrum in `DeploymentConstants`. The badge deployment
is now outside this bootstrap. Historical implementations
are bridge versions and need not equal the latest v5 implementations.
These logs appear during dry runs too; successful chain receipts establish actual
deployment. The Safe batch still must execute before the v5 step.

### Explorer verification with the installed Foundry build

Foundry v1.2.0-rc `0a7b3f0` can report `Chain 4663 not supported` despite the
chain-specific Etherscan table. Supply both flags explicitly with `--verify
--verifier etherscan`:

```powershell
--etherscan-api-version v2 --verifier-url https://api.etherscan.io/v2/api
```

The project also sets `etherscan_api_version = "v2"`. The key is loaded from the
ignored local environment, not committed to this repository. An explicit URL
without V2 mode gets past the local chain registry but omits Etherscan's required
chainid parameter. A read-only dummy `verify-check` with both options reached the
Etherscan V2 endpoint and returned the expected invalid-GUID response. This checks
routing only, not successful contract-source verification. No source upload or
deployment retry was performed while diagnosing it. Source verification and
successful deployment receipts remain separate evidence.

## October 23 refresh

Use branch `codex/robinhood-upgrade-refresh`, based on develop `d964679`.
The intermediate Solidity script and pinned JSON are unchanged from the prior
Robinhood preparation (`ff93f1c`). The final stage now uses the latest core and
rendering source, atomic URI/image-builder switching, ShareExtension, V3
extensions and secondary conditions. The primary rate supplied to the bootstrap
is retained; `50` is 0.5%. The current release sets secondary trades to **500 bps
(5%)**, replacing the prior runner's 600 bps.

The entrypoint for the final stage is now
`script/upgrade-robinhood.s.sol:UpgradeRobinhoodScript`. It checks the actual RPC
chain, Safe code and auth ownership, all bootstrap proxy auths, factory wiring,
badge issuer keys, payment-token code, historical V2 extensions and canonical
CreateX code before invoking the unchanged current `UpgradeV5Script`.
It also validates the two distinct nonzero kill-switch admins before deployment.
The common Safe JSON formatter uses standard cheatcodes and works with the
restored Foundry v1.2.0-rc; updating Foundry is not needed for JSON generation.
Always specify Solidity 0.8.28 and Cancun explicitly in the commands below.
The builder sub-script has one compatibility addition: a failed `imageBuilder()`
read means "unset" only for the pinned original Robinhood URI implementation
`0x3B93dBb163f9aCD500552FC22063744A27C5767b`. Other missing/malformed getter
results refuse. This permits the current atomic URI/image upgrade from the
actual original deployment without changing the bridge.

### Operator sequence (PowerShell)

Keep formation/issuance disabled until acceptance of the complete release.
The original deployment is already a prerequisite; do not rerun it as an upgrade.
Use the historical deployer as `--sender` so newly linked libraries and script
deployments use the intended account. Set the existing bootstrap environment:
`PRIVATE_KEY_MAIN`, `ROBINHOOD_RPC_URL`, `ROBINHOOD_STABLE`,
`ROBINHOOD_FEE_RECIPIENT`, `ROBINHOOD_PRIMARY_FEE_BPS=50` and
`ROBINHOOD_FRESH_DEPLOYMENT=true` (only for genuinely unused original deployments).

1. Simulate the intermediate stage:

   ```powershell
   forge script script/bootstrap-robinhood.s.sol:BootstrapRobinhoodScript --rpc-url $env:ROBINHOOD_RPC_URL --sender 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B --use 0.8.28 --evm-version cancun --via-ir -vvvv
   ```

   After review and release acceptance, the operator may use the same command
   with `--broadcast --slow`. Check all deployment receipts, then import the
   resulting `script/res/gnosis-batch-bootstrap-robinhood-4663.json` into the
   configured Safe and execute the complete batch atomically. Use 46630 for testnet.
   A simulated batch must not be executed before its referenced deployments exist.

2. Add `KILL_SWITCH_METALEX_ADMIN` and `KILL_SWITCH_LEGION_ADMIN`. These must be
   approved, different, nonzero addresses. They govern an immutable two-admin
   kill-switch contract; the fee recipient is not a substitute for this decision.

3. Check the final-stage prerequisites after the intermediate Safe transaction:

   ```powershell
   forge script script/upgrade-robinhood.s.sol:UpgradeRobinhoodScript --sig "preflight()" --rpc-url $env:ROBINHOOD_RPC_URL --sender 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B --use 0.8.28 --evm-version cancun --via-ir -vvvv
   ```

4. Simulate the complete current final stage:

   ```powershell
   forge script script/upgrade-robinhood.s.sol:UpgradeRobinhoodScript --rpc-url $env:ROBINHOOD_RPC_URL --sender 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B --use 0.8.28 --evm-version cancun --via-ir -vvvv
   ```

   After acceptance, add `--broadcast --slow`. Check receipts, record all newly
   logged CREATE3 proxy/singleton addresses in the Robinhood fields of
   `DeploymentConstants` **before another run**, then import the actual run's
   `script/res/gnosis-batch-upgrade-v5-4663.json` and execute it atomically.
   Dry runs and tests overwrite their local JSON; never import test output.
   Complete the auth ownership handoff. The historical LeXcheX owner can drop
   its role once the Safe role is established; the script preserves Safe ownership.
   Never rerun the intermediate stage after the final upgrade.

### Address scope and optional recent deployments

The original core proxies and 32 historical CREATE2 entries retain their prior
targets. The four badge entries still have the documented Robinhood-specific
addresses. Full parity with another chain still needs historical badge deployment
provenance; this refresh does not silently change that manifest.
New ShareExtension, V3 extensions and conditions use the current runner's same
CREATE3 salts. Their addresses depend on the actual sender. Compare predictions
with the chosen canonical chain before asserting exact matching. Implementations
and linked libraries deployed with CREATE depend on the sender's nonce.
`robinhood-create3-predictions.json` contains all 27 new targets for the historical
deployer. **All 27 differ from the Base reference addresses currently recorded in
DeploymentConstants.** The reference comparison is source evidence, not fresh Base
RPC readback. The predictions are independently checked against the Solidity utility.
Exact matching for these proxies would require their historical deployment
inputs/provenance too; simply inserting the Base addresses into Robinhood constants
would point at absent contracts. This preparation retains the prior fresh-CREATE3
policy rather than silently claiming full cross-chain parity.

Robinhood's ZKPassport verifier/finalizer fields are explicitly zero; Ethereum's
recent finalizer address is not evidence of a Robinhood deployment. The separate
`deploy-zkpassport-finalizer.s.sol` requires a verified supported verifier, explicit
domain/scope and chain selection before use. Do not run its hardcoded default
entrypoint against Robinhood. The latest registry implementation is included,
but passport signing is not enabled by this preparation.

The current source includes SAFO labels/rendering, but the main v5 runner does
not deploy the dedicated SAFO extension or register its templates. Those retain
the separate [SAFO rollout gates](../../notes/ai/tasks/safo-integration.md).
The optional MetaDAO credit-facility, Pump and ParentCo factories are not part
of this fresh-chain core upgrade. Templates and app configuration still need a
Robinhood release inventory.

The local full-release rehearsal uses CreateX runtime read at Robinhood block
95918728 and checked against the
[upstream v1.0.0 documented runtime hash](https://github.com/pcaversaccio/createx/tree/v1.0.0).
It impersonates the Safe locally; real threshold signing, target-chain submission
and independent external review remain separate acceptance gates.

The historical detail below explains the unchanged bridge. This refresh replaces
its old final-step toolchain, secondary-rate and separate-image-builder guidance.

This is the **fresh-chain** step after `feat/new-chain-deploy` (`d548b30`) and before
`script/upgrade-v5.s.sol`. It supports Robinhood mainnet (4663) and testnet (46630).
It is not an existing-corporation migration. Keep formation, signing and issuance
clients disabled until the complete v5 rollout has been accepted.

## What the bridge does

- Keeps core AUTH `0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01`,
  CyberCorpFactory `0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2`,
  registry `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` and
  URI builder `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3`.
- Replays the historical production factory deployment payloads to produce
  CyberCorpSingleFactory `0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4`,
  IssuanceManagerFactory `0xD353972D7955F421d94d0eA8c42c88c417F7155A`,
  DealManagerFactory `0x3982b078f2ac306219c9540Ebc908360a960C251` and
  RoundManagerFactory `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9`.
  These are the common Ethereum/Base/Arbitrum addresses, not the exceptional
  Base Sepolia issuance/round factory addresses.
- Replays LeXcheX AUTH, NFT and minter, and the four V1/V2 extension proxies used
  by the current v5 runner (SAFE, SAFT V2, SAFTE V2 and TokenWarrant V2).
- Provisions a fresh deterministic badge proxy at
  `0xe1B94940a1926D3A836820F054b071815Aae964f`, with a separate auth at
  `0x8e50f5409f1DF3af22C68A1c63927a5585005DB7` owned by the Safe from construction.
  These two addresses differ from the other chains. The bootstrap grants the
  minter its three credential issuer keys in the Safe batch. This supplies the
  nonzero badge/auth addresses expected by the unchanged v5 runner, whose badge
  helper keeps this proxy and may upgrade its implementation.
- Prepares an atomic Safe batch to upgrade CyberCorpFactory to the historical
  intermediate implementation `0x424ab1B1DA8b7B2FE13cA0A7ABC346b22efa9191`,
  wire all four factories and LeXcheX auth, whitelist the explicitly supplied
  stable, configure primary fees and their recipient, and grant credential roles.
  The bridge leaves registry/URI implementations and legacy component beacons alone.
- Gives the Safe ownership of the historical LeXcheX auth if necessary. It does
  not revoke the original owner; v5 performs its documented ownership handoff.

The script compares occupied deployment addresses against the frozen runtime,
checks proxy implementation slots and auths, rejects an unexpected top-level
implementation, and verifies the wiring after simulating the Safe batch. Reruns
are supported **before v5**, including after a partially broadcast deployment.
After v5 it deliberately refuses to downgrade either the corporate factory or
the replayed component/extension proxies.

## Address provenance

`robinhood-bootstrap.json` contains 32 CREATE2 deployments extracted from local
historical Ethereum broadcasts, with the source transaction hashes and source
paths recorded in the file. Only entries with successful saved receipts were
selected. No historical CALL, payment, template creation or role removal is replayed.
The three source broadcasts are:

- `broadcast/upgrade-public-rounds.s.sol/1/run-latest.json`
- `broadcast/deploy-lexchex.s.sol/1/run-latest.json`
- `broadcast/deploy-extensions-v2.s.sol/1/run-latest.json`

Four additional CREATE2 payloads freeze the new badge auth, renderer library,
implementation and initialized proxy. Their `sourceTx` is zero: they are new,
not historical deployments. The `badgeBuild` record captures source revision,
compiler/settings and salt. The badge implementation is linked to the frozen
renderer address; the auth uses the historical BorgAuth creation code with its
owner constructor argument replaced by the Safe. All 36 deployment payloads are
checked and replayed in order. No public proxy is left uninitialized.

The separate `originals` array contains the 13 original CREATE2 payloads from
`broadcast/warrant-deploy.s.sol/1/run-latest.json`, for reproducing the actual
old deployment in tests. The bootstrap does **not** deploy those entries; it
requires the original deployment to have completed first. Tests read this same
pinned manifest and do not depend on a separate original-deployment fixture.

The committed manifest replaces those ignored/local dependencies. Its exact SHA-256
is pinned in Solidity; `.gitattributes` preserves its LF line endings. Changing a
payload requires a reviewed manifest/hash update, not an environment override.
Each address is recomputed from the canonical `0x4e59...` deployer, salt and init
code before any broadcast is recorded. Saved receipts and offline reproduction
are not independent verification of the source-chain transactions; verify source
provenance and target-chain code during release review.

V3 extensions and secondary conditions are **new CREATE3 deployments** on
Robinhood in v5. No matching historical replay payloads are included for them.
Their configuration fields start at zero. Record the addresses logged by v5 in
`DeploymentConstants` after the first broadcast, **before rerunning v5**, including
the ownership-handoff rerun. The current helpers deliberately reject zero config
at an already occupied CREATE3 address. CREATE3 requires canonical CreateX code at
`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`; verify that prerequisite separately.
No legacy LeXcheX condition, ZKPassport verifier, Pump, ParentCo or MetaDAO factory
is provisioned or represented as deployed by this bridge.

## Runbook

1. Verify Robinhood chain ID, RPC and gas funding. Verify the canonical CREATE2
   deployer runtime and a working, controlled MetaLeX Safe at
   `0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`. The original deploy step must have
   completed with that Safe holding the core AUTH owner role. Independently
   establish that no corporations, certificates, rounds or agreements requiring
   migration have been created. The script cannot enumerate all legacy instances.
2. Supply these environment variables using the normal local secrets mechanism:
   - `PRIVATE_KEY_MAIN`: first LeXcheX deployment needs the historical owner key
     for `0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B`, because that address is embedded
     in the AUTH constructor. A different sender is accepted once the auth exists
     and is under the Safe's control.
   - `ROBINHOOD_STABLE`: the verified token contract on the selected Robinhood
     network; no Ethereum/Base token address is inferred or copied.
   - `ROBINHOOD_FEE_RECIPIENT`: approved primary-fee recipient.
   - `ROBINHOOD_PRIMARY_FEE_BPS`: approved primary fee in basis points, including
     explicit zero if desired. v5 separately sets the secondary rate to 500 bps.
   - `ROBINHOOD_FRESH_DEPLOYMENT=true`: operator assertion of the fresh-state prerequisite.
3. Simulate, without broadcasting:

   ```sh
   forge script script/bootstrap-robinhood.s.sol:BootstrapRobinhoodScript --rpc-url "$ROBINHOOD_RPC_URL"
   ```

   This simulates deployments and Safe calls and writes
   `script/res/gnosis-batch-bootstrap-robinhood-<chainId>.json`. Both stages now use
   standard Foundry JSON/string cheatcodes.
   Do not pass `--skip-simulation`. Gas estimation/simulation does not replace a
   testnet broadcast rehearsal or an actual Safe signature check.
4. After independent review and test-environment acceptance, the approved deployment
   operator can run the same command with `--broadcast`. This broadcasts only the
   CREATE2 deployments and, if needed, the LeXcheX Safe-role grant. The core upgrade
   and configuration still require the generated Safe batch to be signed and
   executed **atomically**. Do not run v5 until that transaction has succeeded and
   its postconditions have been read from the chain.
5. Run `script/upgrade-v5.s.sol:UpgradeV5Script` on the same RPC, first as a dry run.
   Its Robinhood configuration uses the bootstrapped core/V2 addresses. Complete
   its own Safe batch and ownership handoff; save new CREATE3 addresses before a
   rerun. The refreshed final runner installs the current URI and image builders
   together in one owner call, including an originally unset image builder.
   Templates and application signing configuration also require a release inventory.

## Required acceptance before deployment

Local tests exercise historical bytecode, address/state preservation, reruns,
authority and mismatch refusal, v5 core formation, and v5 badge upgrade/handoff
while retaining the Safe's authority and the minter's issuer grant.
They do not establish target-chain Safe ownership,
source-chain provenance, payment-token suitability, or an absence of existing corps.
Independent external-model review remains pending. Before deploying, run the full
sequence on a Robinhood fork and in the test environment with real test Safe signing,
simulation and submission. Include successful formation/issuance, wrong-chain and
altered-signature refusal, unauthorized upgrades, factory-reference/fee checks,
certificate metadata and the complete v5 configuration. No release approval or
production deployment is implied by these files.
