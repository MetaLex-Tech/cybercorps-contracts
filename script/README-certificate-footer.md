# Upgrade the LET certificate renderers

The script installs the current URI implementation and image builder on the
shared URI proxy, and upgrades the `ShareExtension` and `ShareExtensionV3`
proxies from `DeploymentConstants.extensions`. It first shipped the issuer
footer.

The Forge script uses the connected RPC's chain ID and Forge's configured
sender/wallet. It reads no script-specific environment variables or private keys.
All five chains in `DeploymentConstants.coreV2` are supported: Ethereum (1), Base
(8453), Arbitrum (42161), Sepolia (11155111), and Base Sepolia (84532).

## Run with Forge

```sh
forge script script/upgrade-certificate-footer.s.sol:UpgradeCertificateFooterScript
```

Supply your usual Forge `--rpc-url`, `--sender`, and wallet options such as
`--account` or `--ledger`, or their standard Forge configuration. For example:

```sh
forge script script/upgrade-certificate-footer.s.sol:UpgradeCertificateFooterScript --rpc-url base --sender 0xYOUR_DEPLOYER_ADDRESS --account YOUR_KEYSTORE_ACCOUNT
```

Without `--broadcast` this only simulates. After release approval, add
`--broadcast --slow` to deploy the linked content library, the image builder
and the URI implementation, when their code changed. The script always queues
the owner call for the configured Safe, even when the deployment wallet is also
an owner. It never broadcasts the owner call itself. AUTH stays the same.

The URI builder calls the image builder through one entry point, and that entry
point can change between releases. So when the URI implementation changed, the
Safe gets one `upgradeToAndCall(implementation, setImageBuilder(image))` call,
which switches both parts in one transaction. When the URI implementation
already has the current code, the Safe gets `setImageBuilder` only.

The image shows the series name that a Share extension gives through
`seriesNameOf`. So the same batch also upgrades each Share extension proxy
whose implementation differs from the current source, with
`upgradeToAndCall(implementation, "")`. The Safe must own each proxy. The Safe
runs the batch as one transaction.

The output path is derived automatically:

`script/res/gnosis-batch-certificate-footer-<chain-id>-<proxy>.unverified.json`

This is Safe Transaction Builder JSON. The `.unverified` name reminds you that
Forge writes it during simulation, before any broadcast completes. After a
successful broadcast, verify the receipts and deployed image/library code, then
import the JSON into the matching Safe. A simulation-only or failed-broadcast
file must not be executed. Direct runs overwrite that chain/proxy file; use the
latest successfully deployed version. An empty transactions array is a no-op.

The script updates the configured shared URI proxy, not arbitrary custom URI
builders. Existing tokens using that proxy pick up the new renderers after the
Safe executes the batch. Verify the decoded live `tokenURI` after execution.

## Optional all-chain runner

The Python runner accepts RPC URLs or Forge RPC aliases on the command line.
It passes the sender and keystore account through to Forge. It adds no environment
variables. Use Python 3.10+ and Foundry (CI pins v1.7.1).

```sh
python script/upgrade-certificate-footer.py --sender 0xYOUR_DEPLOYER_ADDRESS --account YOUR_KEYSTORE_ACCOUNT --rpc ethereum=ethereum --rpc base=base --rpc arbitrum=ARBITRUM_RPC_URL --rpc sepolia=sepolia --rpc base-sepolia=base_sepolia
```

Replace `ARBITRUM_RPC_URL` with your endpoint or a configured Forge alias.
To select a subset, add `--chains sepolia base-sepolia` and provide those RPCs.
Use Forge directly for other wallet options, such as a hardware wallet.

The runner defaults to simulation. Adding `--broadcast` first simulates every
selected chain, then broadcasts deployments sequentially with `--slow` receipt
waiting. Its `runForChain(uint256,string)` entrypoint checks the expected chain
against the RPC and accepts the per-run output path as ordinary `--sig` arguments.
Broadcast is not atomic across chains. The deployment wallet needs gas on each.

Artifacts are grouped under `script/res/certificate-footer/<UTC-time>-<run-id>/`.
`manifest.json` records each phase. `*-simulation.json` references simulated
addresses and must not be executed. A successful broadcast promotes the matching
batch to `*-deployment.json`; verify its receipts before Safe import. A failed
step stops the run and retains `*.unverified.json` for investigation. Some
deployments may already have mined before a failure. Inspect receipts and state
before retrying; a new run can use different nonces and linked-library addresses.

Same-linked-code reruns are no-ops. A fresh Forge invocation may deploy a fresh
content library and therefore a different image builder even with unchanged
source. Neither entrypoint signs or submits Safe transactions.

For custom proxies, `runWithArgs(uint256,address,address,address,address,string)`
accepts an expected chain ID, the URI proxy, the `ShareExtension` and
`ShareExtensionV3` proxies (zero leaves one out), the Safe and the output path;
wallet selection stays with Forge.
The separate `upgrade-certificate-rendering.s.sol` makes the same atomic switch
of the renderers. It does not upgrade the Share extensions.
It signs with `PRIVATE_KEY_MAIN` and sends the owner call directly when that key
is an owner.

## Validation

```sh
python -m unittest discover -s test -p test_certificate_footer_runner.py
forge test --use 0.8.28 --match-contract UpgradeCertificateFooterScriptTest
python test/rehearse_certificate_footer.py
```

On older Forge versions, add the two OpenZeppelin remappings used by the Python
runner if auto-remapping fails. Tests cover all five default chain targets,
Safe-only updates, the atomic implementation/image switch, the image-only case,
Share extension upgrades in the same batch, AUTH preservation, no-op reruns,
and refusals.

The Anvil rehearsal uses public toy keys and Forge wallet flags. It deploys the
renderer on an isolated localhost chain, verifies the pointer is unchanged,
then signs, simulates and submits the exported setter and checks the result.
The owner is an EOA stand-in: actual Safe thresholds, signatures, guards, UI
import and live-chain state remain separate release acceptance gates.
