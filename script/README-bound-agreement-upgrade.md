# Deploy creator-bound agreements and generate the Safe batch

`DeployBoundAgreementRegistryScript` deploys the linked `CyberAgreementJson`
library and a new registry implementation, simulates the proxy upgrade, and
writes Safe Transaction Builder JSON directly. It uses the existing
`DeploymentUtils.formatSafeTxJson` helper, as `deploy-parentco-factory.s.sol`
and `DeploymentScript.finish` do. No separate exporter or manifest is needed.

The script broadcasts only deployments. The proxy upgrade is left for the Safe,
even when the deployment wallet also holds an owner role.

## Run

Example for Base:

```sh
forge script script/deploy-bound-agreement-registry.s.sol:DeployBoundAgreementRegistryScript --sig "runForChain(uint256)" 8453 --rpc-url base --sender YOUR_DEPLOYER_ADDRESS --account YOUR_KEYSTORE_ACCOUNT --use 0.8.28 --broadcast --slow
```

Omit `--broadcast --slow` for a dry run. Standard Forge wallet options such as
`--ledger` can replace `--account`. The sender must match the selected wallet.
Forge deploys and links the library automatically. Use repository optimizer/via-IR
settings; CI pins Foundry 1.7.1. No script-specific private-key environment variable
is required.

| Chain | Expected chain argument | RPC argument | Output |
| --- | --- | --- | --- |
| Ethereum | 1 | `ethereum` | `script/res/gnosis-batch-bound-registry-1.json` |
| Base | 8453 | `base` | `script/res/gnosis-batch-bound-registry-8453.json` |
| Arbitrum | 42161 | your URL or configured alias | `script/res/gnosis-batch-bound-registry-42161.json` |

Targets come from `DeploymentConstants.coreV2`: registry
`0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`, Safe
`0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`. The expected chain must match the RPC.

## Import into Safe

After the deployment broadcast succeeds, import the generated JSON into the
matching chain's Safe Transaction Builder. It contains exactly one zero-value
`upgradeToAndCall(newImplementation, 0x)` call to the existing registry, with
no initializer. The script prints the library, implementation, proxy and authority
addresses along with the JSON.

Forge writes files during simulation, before broadcast receipts exist. A dry-run
or failed-broadcast JSON is only a preview: confirm successful library and
implementation deployment before importing it. Each run overwrites the chain's
file and may use new nonces/addresses; use the output from the successful run.
No automatic post-deployment exporter checks are performed.

The script checks proxy/implementation code and AUTH ownership, simulates the
upgrade as the Safe, checks the implementation, AUTH, signing domain/schema,
version and linked JSON rendering, then restores the simulated proxy state.
A live chain with a different signing schema refuses and needs separate review.
Safe signatures, guards and UI import remain separate acceptance steps. After
Safe execution, check the receipt, implementation slot and representative old/new
agreement flows. Existing independent-review and release gates remain in force.

## Testnets and custom targets

For a testnet where the default Safe is absent or not an owner, supply the
inventoried upgrade authority explicitly. The last argument is an output prefix;
the script appends `.json`:

```sh
forge script script/deploy-bound-agreement-registry.s.sol:DeployBoundAgreementRegistryScript --sig "runWithArgs(uint256,address,address,string)" 84532 REGISTRY_PROXY TEST_AUTHORITY script/res/gnosis-batch-bound-registry-84532 --rpc-url base_sepolia --sender YOUR_DEPLOYER_ADDRESS --account YOUR_KEYSTORE_ACCOUNT --use 0.8.28
```

## Validation

```sh
forge test --use 0.8.28 --match-contract DeployBoundAgreementRegistryScriptTest -vv
python test/rehearse_bound_registry_upgrade.py
```

Seven script tests cover the five configured chains using local fixtures,
exact batch calldata, unchanged proxy before Safe execution, populated agreement
and pending-signature preservation, and wrong-chain/unauthorized refusals.
The Anvil rehearsal uses public toy keys and consumes the script-generated JSON
directly: deploy, check the unchanged proxy, reject unauthorized execution,
then sign, simulate and submit the upgrade through an owner-gated contract
stand-in. It verifies the implementation and linked JSON readback. The stand-in
does not model real Safe thresholds or guards. Python is only needed for this
local test, not deployment or batch generation. Local evidence is retained in
ignored `script/res/bound-registry-rehearsal/<run-id>/`.
