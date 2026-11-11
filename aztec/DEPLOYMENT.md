# Deployment and upgrades

This document gives the steps for each deploy and each upgrade of the Aztec contracts. `deployments.ts` is the
record of what each network has. The chain is the record of each upgrade, and git is the record of each change to
`deployments.ts`.

The scripts are in `scripts/`:

- `deploy.ts` deploys, publishes and upgrades BorgAuthV2 and the registry. A run sends only the txs that the chain needs. A second run on the
  same chain state sends no tx. `--dry-run` sends no tx.
- `deployments.ts` records the contracts of each network and environment, the original artifacts and their class
  ids. `deploy.ts` writes the deployment records after a run that is not a dry run.
- `res/*.vN.json` are the original artifacts. They are frozen copies of the compiler output. See
  [New original artifacts](#new-original-artifacts).

## Concepts

- **Environment.** `DEPLOY_SALT_LABEL` selects the environment. All contracts of one environment use the salt of
  its label. Production uses `MetaLex-v1.0.0`. Staging and development use a semver pre-release, for example
  `MetaLex-v1.0.0-dev.0`. A new label gives a new set of contracts at new addresses.
- **Same addresses on each network.** An address depends on the class that the contract was first deployed with,
  the salt, the constructor arguments and the immutables hash. So each network deploys the original artifacts in
  `res/`, and then upgrades each contract to the current build.
- **Root.** The deployer is the BorgAuthV2 root on each network. Only the root holds `APPROVE_UPGRADE`, so only the
  root can upgrade the two contracts. The BorgAuthV2 address depends on the first root, and the registry address
  depends on the BorgAuthV2 address. Use the same deployer account for an environment on each network, or the
  addresses differ. A root transfer later does not change the addresses.
- **Upgrade delay.** `update_to` schedules the new class. The new class takes effect after the default delay of
  1 day (`DEFAULT_UPDATE_DELAY` = 86400 s). Until then, the contract runs its old class.
- **Upgradeable.** Both contracts can be upgraded. BorgAuthV2 ports part of the EVM `BorgAuthV2`: the root,
  `APPROVE_UPGRADE`, and the officer role. The testnet instance runs the v1 class (root only). The current build
  adds the officer role, so `deploy.ts` schedules a BorgAuthV2 upgrade (case L). Do not run it on a shared network
  before the independent review. See [BorgAuthV2 upgrade](#borgauthv2-upgrade).

## Before each run

1. Use Aztec 6.0.0 (`aztec-up`).
2. In `aztec/`, run `aztec compile` and `aztec test`. All tests must pass.
3. Fill the env file from `scripts/.env.example`: `AZTEC_NODE_URL`, `DEPLOY_SALT_LABEL` and the `DEPLOYER_*` keys.
   Use a deployer account that is not the settler. The settler key runs in the web app server.
4. In `scripts/`, run the dry run and read each step line:

   ```shell
   node --env-file=.env.testnet deploy.ts --dry-run
   ```

   Each step logs one line. A line that starts with 🟢 does work (or would, in a dry run). A line that starts with
   ⚫️ skips. These are the same markers as in the EVM `DeploymentScript`. `LOG_LEVEL=warn` in the env file hides the
   info logs of the wallet.

## New environment

Use this procedure for a new network, or a new label on a network.

1. If the network is new, add it to `NETWORKS` in `deployments.ts` with its L1 chain id and `deployments: {}`.
2. Do the steps in [Before each run](#before-each-run). The dry run shows `[config] record: none, a new
   environment`, and 🟢 `would deploy new` for BorgAuthV2 and the registry.
3. Run `node --env-file=.env.testnet deploy.ts`. It writes the record into `NETWORKS[chainId].deployments` in
   `deployments.ts` and logs 🟢 `[record] wrote ...`.
4. Run `deploy.ts` again. It must send no tx: each step line starts with ⚫️.
5. Set `REGISTRY_ADDRESS` of the web app to the new registry address. The scripts read the registry from
   `deployments.ts`.
6. Commit `deployments.ts`.

## Registry upgrade

Use this procedure when the registry code changes. The address does not change.

1. Make sure that the new code keeps the nullifier formulas (`contracts/agreement_registry/src/agreement.nr`):
   the agreement id, the consent hash, the finalized nullifier and the padding nullifiers. A change makes the
   finalized agreements and the withdrawn consents of the old class invalid.
2. Make sure that the new code keeps `update_to` and its auth check. Without it, the registry cannot be upgraded
   again.
3. Write the invariants and the TXE tests first. For a change to authorization, signing or funds, get an
   independent review before the deploy (see `AGENTS.md`).
4. Do the steps in [Before each run](#before-each-run). The dry run shows 🟢 `[publish class] would publish` and
   🟢 `[upgrade] would schedule ... <old class> -> <new class>`.
5. Run `node --env-file=.env.testnet deploy.ts`. The log shows 🟢 `[publish class] published` and 🟢 `[upgrade]
   scheduled ... takes effect at <time>`.
6. Run `deploy.ts` again. It must send no tx. The upgrade line is ⚫️ `upgrade already scheduled, takes effect at
   <time>`.
7. After the time of change, run `deploy.ts` again. The upgrade line must be ⚫️ `already runs the current build`.
8. Give each PXE the new artifact: in `webapp/`, run `bun run artifacts`, then deploy the web app. A PXE needs the
   artifact of the class that the registry runs, so do this after the time of change.
9. Run the web app journey against the network.

To cancel a scheduled upgrade, build the class that the registry runs now, and run `deploy.ts` again before the
time of change. It schedules the current class again.

## BorgAuthV2 upgrade

Use this procedure when the BorgAuthV2 code changes, for example to add the roles and permissions of the EVM
`BorgAuthV2`. The address does not change, so the registry address does not change.

1. Make sure that the new code keeps the storage variables `root_authority`, `pending_root_authority`,
   `initial_root`, `roles` and `initial_members` in this order, and adds new variables after them. A change of order
   makes the new class read the wrong values. An instance that upgrades from v1 has no `initial_root` and no
   `initial_members`, so it has no officer, and each private permission check fails. After the role delay, a root transfer gives the new root `APPROVE_UPGRADE` and `set_officer`
   gives the officer permissions.
2. Make sure that the new code keeps `require_permission(Field, AztecAddress)` and the value of `APPROVE_UPGRADE`.
   The registry calls it. Without it, the registry cannot be upgraded again.
3. Make sure that the new code keeps `update_to`, unless you want to stop all upgrades (see below).
4. Write the invariants and the TXE tests first, and get an independent review before the deploy (see
   `AGENTS.md`). This is a change to authorization.
5. Do steps 4 to 7 of [Registry upgrade](#registry-upgrade). The log lines name `BorgAuthV2` in place of the
   registry. One run can upgrade both contracts.

To stop all upgrades of BorgAuthV2, remove `update_to` from it and do the steps above. After the time of change, no
code can call `ContractInstanceRegistry.update` for BorgAuthV2, so nobody can change its code again. Until the time
of change, the root can schedule another class. This does not stop the registry upgrades: the registry still asks
BorgAuthV2 for `APPROVE_UPGRADE`. Read the new class and check that no function calls `ContractInstanceRegistry`
before the deploy.

## New original artifacts

Use this procedure only when an upgrade cannot do the change, for example a new set of contracts, or a change of
the BorgAuthV2 constructor or the registry immutables hash. It always gives new addresses, so it needs a new
`DEPLOY_SALT_LABEL`.

1. In `aztec/`, run `aztec compile`.
2. Copy the artifacts to the next version number. Never change a recorded artifact:

   ```shell
   cp target/borg_auth_v2_contract-BorgAuthV2.json scripts/res/BorgAuthV2.v2.json
   cp target/agreement_registry_contract-CyberAgreementRegistry.json scripts/res/CyberAgreementRegistry.v2.json
   ```

3. Get the class id of each new file. In `scripts/`, run this command once for each file:

   ```shell
   node --input-type=module -e "import { readFileSync } from 'node:fs'; import { loadContractArtifact } from '@aztec-labs/aztec.js/abi'; import { getContractClassFromArtifact } from '@aztec-labs/aztec.js/contracts'; const a = loadContractArtifact(JSON.parse(readFileSync(process.argv[1], 'utf8'))); console.log((await getContractClassFromArtifact(a)).id.toString());" res/BorgAuthV2.v2.json
   ```

4. Set the new paths and class ids in `ORIGINAL_ARTIFACTS` in `deployments.ts`.
5. Pick a new label, for example `MetaLex-v2.0.0`, and do the steps in [New environment](#new-environment) on each
   network.
6. Keep the old files in `res/`. They are the record of the old environments.

## Scenarios

What `deploy.ts` does in each chain state. "Run" is a real run, "Dry" is `--dry-run`. In the Run column, 🟢 means
that the step sent a tx or wrote `deployments.ts`.

### Checks before any tx

Each check fails the run before it sends a tx.

| Condition                                                                 | Error                                    |
|---------------------------------------------------------------------------|------------------------------------------|
| `AZTEC_NODE_URL` or `DEPLOY_SALT_LABEL` is not set                        | `... is not set`                         |
| The L1 chain id is not in `NETWORKS`                                      | `deployments.ts has no network for ...`  |
| `DEPLOYER_SIGNING_KEY` is not set, and the network is not the local one  | `DEPLOYER_SIGNING_KEY is not set ...`    |
| A file in `res/` does not give its class id in `ORIGINAL_ARTIFACTS`       | `... has class id ..., but ... records`  |
| `target/` has no registry build (`aztec compile` did not run)             | File not found                           |
| A recorded `root`, `auth` or `registry` differs from the computed value   | `deployments.ts records ..., but ...`    |

### Steps

`[publish class]` and `[upgrade]` run once for each contract: first BorgAuthV2, then the registry.

| Step              | Chain state                                                   | Run                                                          | Dry                                |
|-------------------|---------------------------------------------------------------|--------------------------------------------------------------|------------------------------------|
| `[deploy]`        | The instance exists                                           | ⚫️ already exists                                            | ⚫️ already exists                  |
| BorgAuthV2        | The instance is missing                                       | 🟢 deployed new from v1 (the tx also publishes the v1 class) | 🟢 would deploy new                |
| `[deploy]`        | The instance exists                                           | ⚫️ already exists                                            | ⚫️ already exists                  |
| registry          | The instance is missing                                       | 🟢 deployed new from v1 (the tx also publishes the v1 class) | 🟢 would deploy new                |
| `[publish class]` | The current build is published                                | ⚫️ already published                                         | ⚫️ already published               |
|                   | Missing, the contract is missing, the build is v1             | ⚫️ already published (by the deploy)                         | ⚫️ published by the deploy          |
|                   | Missing in any other case                                     | 🟢 published                                                 | 🟢 would publish                   |
| `[upgrade]`       | The contract runs the build, no upgrade is scheduled          | ⚫️ already runs the current build                            | ⚫️ already runs the current build  |
|                   | An upgrade to the build is scheduled                          | ⚫️ already scheduled, takes effect at T                      | ⚫️ already scheduled               |
|                   | The contract runs another class, no upgrade is scheduled      | 🟢 scheduled old -> build, takes effect at T                 | 🟢 would schedule                  |
|                   | An upgrade to another class is scheduled                      | 🟢 scheduled again, the build replaces the pending class     | 🟢 would schedule                  |
|                   | The contract is missing, the build is v1                      | Not reached: the deploy step deploys it                      | ⚫️ the deploy runs the build       |
|                   | The contract is missing, the build is not v1                  | Not reached: the deploy step deploys it                      | 🟢 would schedule v1 -> build      |
|                   | The deployer is not the root (after a root transfer)          | Error `BorgAuthV2: permission denied`, no tx                 | 🟢 would schedule (no root check)  |
| `[record]`        | The record is the same                                        | ⚫️ unchanged                                                 | ⚫️ unchanged                       |
|                   | The record is missing or has missing fields                  | 🟢 wrote                                                     | 🟢 would write                     |

### End to end

| #  | Scenario                                                          | Run                                                                                   | Tested on the local network |
|----|-------------------------------------------------------------------|---------------------------------------------------------------------------------------|-----------------------------|
| A  | New environment, the build is v1                                  | 🟢 deploy x2, ⚫️ publish, ⚫️ upgrade, 🟢 record                                     | Yes                         |
| B  | New environment, the build is not v1 (after a registry upgrade)   | 🟢 deploy x2, 🟢 publish, 🟢 schedule, 🟢 record. The registry runs v1 until T        | Dry run only                |
| C  | Run again, no change                                              | ⚫️ on each step, no tx                                                               | Yes                         |
| D  | The registry code changed                                         | ⚫️ deploy x2, 🟢 publish, 🟢 schedule, ⚫️ record                                     | Yes                         |
| L  | The BorgAuthV2 code changed                                       | ⚫️ deploy x2, 🟢 publish, 🟢 schedule BorgAuthV2, ⚫️ registry, ⚫️ record              | Yes                         |
| E  | Run again during the delay                                        | ⚫️ on each step, the upgrade line shows T                                            | Yes                         |
| F  | Run after T                                                       | ⚫️ on each step, "already runs the current build"                                    | No                          |
| G  | Cancel: build the class that the contract runs, during the delay | ⚫️ publish, 🟢 schedule the running class again                                      | Yes                         |
| H  | A second change during the delay (v2 scheduled, the build is v3)  | 🟢 publish v3, 🟢 schedule v3. v2 never takes effect                                  | No                          |
| I  | An earlier run stopped after the BorgAuthV2 deploy                | ⚫️ BorgAuthV2, 🟢 registry, then as A or B                                            | No                          |
| J  | A tx fails during the run                                         | Error. `[record]` does not run. The next run continues from the chain state          | No                          |
| K  | Another account deployed BorgAuthV2 or the registry first         | ⚫️ already exists. A universal deploy with the same salt and arguments gives the same contract, with our deployer as root | No |
