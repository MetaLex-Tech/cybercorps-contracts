# SAFE LET image upgrade

Deployment signing uses `PRIVATE_KEY_MAIN`, matching the other upgrade scripts.
Set `--sender` to that key's address so Forge links the content library with the
same signer. Wallet options in the examples apply to Forge's library setup;
the upgrade script signs its deployments with `PRIVATE_KEY_MAIN`. No env file
needs to be opened or inspected.

`upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript` deploys the current
`CertificateImageContentBuilder` linked library and `CertificateImageBuilderContract`
wrapper. SAFE / ACE images retain **Consideration**, but show current
`unitsRepresented`, including secondary lots with zero `investmentAmountUSD`.

If the URI implementation differs from current source, the script also deploys
`CertificateUriBuilder` and exports one atomic
`upgradeToAndCall(newImplementation, setImageBuilder(newImage))`. Otherwise it
exports only `setImageBuilder(newImage)`. Same-linked-code reruns produce an empty
batch. AUTH is checked before deployment and preserved during simulated execution.
No LET, extension, factory, balance, legal template or token data is changed.

All owner calls are queued for Gnosis Safe, even if the deployment wallet is also
an owner. `--broadcast` sends contract deployments only. Safe execution is separate.

## All four chains

From the repository root, using Python 3.10+ and Foundry:

```sh
python script/upgrade-safe-let-image.py --sender 0xYOUR_DEPLOYER --account YOUR_KEYSTORE_ACCOUNT
```

This **simulates only**, on all four chains. The defaults use the Forge RPC
aliases already configured in `foundry.toml`:

- `eth`: Ethereum, chain 1, RPC alias `ethereum`.
- `base`: Base, chain 8453, RPC alias `base`.
- `arb`: Arbitrum, chain 42161, RPC alias `arbitrum`.
- `rhc`: Robinhood, chain 4663, RPC alias `robinhood`.

The proxy and owner Safe come from `DeploymentConstants.coreV2`: currently
`0x5500c095ea7dE6F8a5E15949e24B80604cc670A3` and
`0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C` on each chain. Each RPC is checked
against its expected chain. These constants identify targets; local unit fixtures
do not establish current live code or ownership.

To select chains or override an RPC:

```sh
python script/upgrade-safe-let-image.py --chains base rhc --rpc rhc=YOUR_RPC_OR_ALIAS --sender 0xYOUR_DEPLOYER --ledger
```

After release checks, adding `--broadcast` first simulates **every** selected
chain, then deploys sequentially with `--slow`. A failure stops the run; earlier
deployments may already have mined. The runner does not sign or submit Safe calls.

Every run has an isolated directory:

```text
script/res/safe-let-image/<UTC-time>-<run-id>/
  manifest.json
  eth-1-simulation.json
  base-8453-simulation.json
  arb-42161-simulation.json
  rhc-4663-simulation.json
  eth-1-unverified.json          # only with --broadcast
  base-8453-unverified.json
  arb-42161-unverified.json
  rhc-4663-unverified.json
  <chain>-<phase>.log
```

The JSON files use Safe Transaction Builder format. **Never execute a simulation
batch.** Broadcast files remain `.unverified.json`: a successful Forge exit does
not independently verify receipts or linked runtime code. Before Safe import,
verify the successful deployment receipts, the new implementation/image/library
code, chain, destination, zero value and exact calldata. Preserve the previous
implementation and image addresses from the log for rollback. Import each batch
into its own chain's configured Safe, then verify decoded `tokenURI` images.
An empty `transactions` array means there is no owner action to execute.

Fresh Forge invocations can deploy a fresh linked content library, causing a new
image wrapper even when source is unchanged. Do not use an earlier run's JSON
after retrying with different deployment nonces or library addresses.

## Direct Forge usage

```sh
forge script script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript --rpc-url ethereum --sender 0xYOUR_DEPLOYER --account YOUR_KEYSTORE_ACCOUNT
forge script script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript --rpc-url base --sender 0xYOUR_DEPLOYER --account YOUR_KEYSTORE_ACCOUNT
forge script script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript --rpc-url arbitrum --sender 0xYOUR_DEPLOYER --account YOUR_KEYSTORE_ACCOUNT
forge script script/upgrade-safe-let-image.s.sol:UpgradeSafeLetImageScript --rpc-url robinhood --sender 0xYOUR_DEPLOYER --account YOUR_KEYSTORE_ACCOUNT
```

These infer the chain from the RPC and write
`script/res/gnosis-batch-safe-let-image-<chain-id>.unverified.json`.
Without `--broadcast`, they simulate only. Direct runs overwrite that file, so
prefer the runner's isolated outputs. For older Foundry releases that need
explicit OpenZeppelin remappings, append:

```text
-R @openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/
-R @openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/
```

The runner uses `runForChain(uint256,string)` to pin the expected chain and output
path. `runWithArgs(uint256,address,address,string)` takes an expected chain,
URI proxy, owner Safe and output path for separately verified custom targets or
local rehearsals. Historical separate Pump URI proxies are not in the current
default inventory; verify their addresses and ownership before using that entrypoint.

## Validation

```sh
forge test --use 0.8.28 --match-contract UpgradeSafeLetImageScriptTest
python -m unittest discover -s test -p test_safe_let_image_runner.py
python test/rehearse_safe_let_image.py
```

Add the remappings above if required by your Foundry version. The localhost
rehearsal accepts no external RPC or wallet and uses public toy keys. It checks
deployment-only broadcast, wrong-chain/wrong-owner refusal, exact batch calldata,
unauthorized execution refusal, signed simulation/submission, unchanged AUTH and
SAFE SVG readback. Its contract authority stands in for a Safe; real Safe
thresholds, signatures, guards, UI import, pinned live-chain fork acceptance and
independent review remain separate release gates.
