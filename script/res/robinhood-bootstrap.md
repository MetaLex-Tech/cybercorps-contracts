# Robinhood: original addresses -> intermediate bootstrap -> v5

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

The committed manifest replaces those ignored/local dependencies. Its exact SHA-256
is pinned in Solidity; `.gitattributes` preserves its LF line endings. Changing a
payload requires a reviewed manifest/hash update, not an environment override.
Each address is recomputed from the canonical `0x4e59...` deployer, salt and init
code before any broadcast is recorded. Saved receipts and offline reproduction
are not independent verification of the source-chain transactions; verify source
provenance and target-chain code during release review.

V3 extensions, badge and secondary conditions are **new CREATE3 deployments** on
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
     explicit zero if desired. v5 separately sets the secondary rate to 600 bps.
   - `ROBINHOOD_FRESH_DEPLOYMENT=true`: operator assertion of the fresh-state prerequisite.
3. Simulate, without broadcasting:

   ```sh
   forge script script/bootstrap-robinhood.s.sol:BootstrapRobinhoodScript --rpc-url "$ROBINHOOD_RPC_URL"
   ```

   This simulates deployments and Safe calls and writes
   `script/res/gnosis-batch-bootstrap-robinhood-<chainId>.json`. The bridge uses
   standard Foundry JSON/string cheatcodes; v5's formatter needs a newer toolchain.
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
   rerun. The original URI builder has no image builder: separately deploy/configure
   the approved image builder after the URI upgrade if certificate SVGs are required.
   Templates and application signing configuration also require a release inventory.

## Required acceptance before deployment

Local tests exercise historical bytecode, address/state preservation, reruns,
authority and mismatch refusal. They do not establish target-chain Safe ownership,
source-chain provenance, payment-token suitability, or an absence of existing corps.
Independent external-model review remains pending. Before deploying, run the full
sequence on a Robinhood fork and in the test environment with real test Safe signing,
simulation and submission. Include successful formation/issuance, wrong-chain and
altered-signature refusal, unauthorized upgrades, factory-reference/fee checks,
certificate metadata and the complete v5 configuration. No release approval or
production deployment is implied by these files.
