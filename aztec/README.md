# Private Agreement Registry on Aztec (PoC)

A minimal port of `src/CyberAgreementRegistry.sol` to Aztec. It supports the happy path of one agreement. Each party
signs offchain with a private authwit. MetaLeX collects the authwits and sends one private `finalize` tx when all
parties signed. The chain keeps only nullifiers. The parties, and an auditor that a party shares the invite with,
see the document and the status "finalized". The MetaLeX data key store keeps each salt for a retention period, so
a party can open the agreement again without the invite.

- [ARCHITECTURE.md](ARCHITECTURE.md): components, data model, the MetaLeX data layer, the EVM retrofit, privacy
  analysis and the comparison with today's webapp.
- [USER-FLOWS.md](USER-FLOWS.md): onboarding, draft and sign, review and sign, settle, view, recovery.
- [DEPLOYMENT.md](DEPLOYMENT.md): the steps for each deploy and each upgrade, and the log of each run.

## Layout

| Path                                           | Content                                                                                                                                 |
|------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `contracts/agreement_registry/src/main.nr`     | The `CyberAgreementRegistry` contract                                                                                                   |
| `contracts/agreement_registry/src/agreement.nr` | `Agreement` struct, id, validation, consent hash, nullifiers                                                                            |
| `contracts/agreement_registry/src/test/`       | TXE tests: finalize, withdraw, upgrade; `utils.nr` deploys BorgAuthV2 and the registry                                                  |
| `contracts/borg_auth_v2/src/main.nr`           | The `BorgAuthV2` contract: the root, who approves each upgrade. It can be upgraded                                                      |
| `contracts/borg_auth_v2/src/test.nr`           | TXE tests for the permission, the root transfer and the upgrade                                                                         |
| `scripts/poc.ts`                               | The parts that `e2e.ts` and the web app share: four wallets, the registry, and an in-memory MetaLeX vault, collector and data key store |
| `scripts/e2e.ts`                               | Lifecycle checks on a local network                                                                                                     |
| `webapp/` | The web app (TanStack Start, Postgres, Vercel) and its Playwright journey |
| `scripts/deploy.ts`                            | Idempotent deploy and upgrade of BorgAuthV2 and the registry. A second run sends no tx                                                  |
| `scripts/deployments.ts`                       | The recorded addresses of each network, the original artifacts and the salts                                                            |
| `scripts/res/`                                 | The original artifacts. Each network deploys them, so it gets the same addresses                                                        |
| `scripts/.env.example`                         | The env for a shared network: settler, Alice and Bob keys, registry address                                                             |

## Commands

Install the toolchain with `aztec-up` at version 6.0.0. Run these commands in this folder:

```shell
aztec compile
aztec test
aztec codegen target -o scripts/artifacts -f
```

Local network run, in two terminals:

```shell
aztec start --local-network --port 8090
cd scripts
npm install
DEPLOY_SALT_LABEL=MetaLex-v1.0.0-dev.0 AZTEC_NODE_URL=http://localhost:8090 node deploy.ts
DEPLOY_SALT_LABEL=MetaLex-v1.0.0-dev.0 AZTEC_NODE_URL=http://localhost:8090 node e2e.ts
```

Web app: see [webapp/README.md](webapp/README.md). It runs the wallets in the browser and MetaLeX on the server
with Postgres, and deploys to Vercel.

Testnet, or any shared network. Copy `scripts/.env.example` to `scripts/.env.testnet` (git ignores it) and fill
in the keys that `aztec-wallet create-account` prints. The deployer and the settler can be any account type. Use two
accounts: the deployer is the BorgAuthV2 root, and the settler key runs in the web app server. Alice and Bob must be
`schnorr_initializerless`, so that the settler can check their authwits. The SponsoredFPC pays each fee. Then run:

```shell
cd scripts && node --env-file=.env.testnet deploy.ts --dry-run
cd scripts && node --env-file=.env.testnet deploy.ts
```

`deploy.ts` finds the network by its L1 chain id in `deployments.ts`, and the environment by `DEPLOY_SALT_LABEL`
(`MetaLex-v1.0.0` for production, `MetaLex-v1.0.0-dev.0` for staging and development). Each label gives its own set
of contracts, so one network can hold staging and production. It deploys BorgAuthV2 and the registry if the environment does not have them. For each of the two contracts, it
publishes the current class if it is missing, and schedules the upgrade if the contract runs another class. It logs the
status of each item, and writes the deployment record into `deployments.ts` under its label. A shared network needs `DEPLOYER_SIGNING_KEY`. Only the local network can use the first test account as deployer.

Then run the lifecycle checks:

```shell
cd scripts && node --env-file=.env.testnet e2e.ts
```

The scripts use the registry that `deployments.ts` records for `DEPLOY_SALT_LABEL` on the network, so run
`deploy.ts` first. Without `SETTLER_SIGNING_KEY`, the scripts use the local network test accounts.

Networks for this PoC (Aztec docs, networks page): the testnet runs 6.0.0 at `https://aztec-testnet.drpc.org`, with
the SponsoredFPC at `0x2d8fff82a3b0c15d0a89169e7d8d043e079ab94d52031f1de1e4972ebad169d3`. The testnet needs real
proofs, so each tx takes longer than on the local network. Mainnet has no SponsoredFPC. The Aztec docs say not to put
real secrets on an Aztec network yet, so the PoC uses test data only.

## Verification

Status on 2026-11-02, uncommitted, branch `feat/aztec`:

| Check                             | Command                                                                                                              | Result                                                                                                                                                                                                                                                         |
|-----------------------------------|----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Compile                           | `aztec compile`                                                                                                      | Pass. `finalize` has 6,617 gates, `withdraw_consent` 5,245 (`aztec profile gates target`).                                                                                                                                                                     |
| Unit tests (TXE simulator)        | `aztec test`                                                                                                         | 39 of 39 pass on 2026-11-04 (21 for `BorgAuthV2` and the upgrades)                                                                                                                                                                                                  |
| Local network flow, test accounts | `node e2e.ts` on `aztec start --local-network`                                                                       | 24 of 24 checks pass, two runs                                                                                                                                                                                                                               |
| Local network flow, env accounts  | `node --env-file=<env> e2e.ts`, keys from `aztec-wallet create-account`, registry from `deploy.ts`                   | 24 of 24 checks pass, two runs                                                                                                                                                                                                                               |
| Web app journey, local network | `APP_URL=http://localhost:3001 bun run journey` in `webapp/`, app built with `bun run build` and run with `.env.local` | 1 of 1 passes on 2026-11-03 (33 s) |
| Web app journey, Aztec testnet | `APP_URL=http://localhost:3002 bun run journey` in `webapp/`, app run with `.env.testnet` (local Postgres, testnet node, settler `detoo`) | 1 of 1 passes, two runs on 2026-11-03 (54 s each). Finalize txs `0x0786d013834dfd0815422b3858fe7b16c52ebc2c8095347f2346fa70ae04e3e3` (block 16576, 6 nullifiers, no note hashes) and `0x2a1cd3a7d6ad18fc1378f4f4edb90eab1051c46afcce25afccc61697ed0bcc3c` |
| Vercel build | `VERCEL=1 bun run build` in a Linux x64 container (`node:24-bookworm`) | Server function 116 MB with the Linux prover (limit 250 MB). Not deployed. |
| Deploy script                     | `AZTEC_NODE_URL=http://localhost:8090 node deploy.ts` on the local network, first test account                       | Pass on 2026-11-04: deploy, a second run with no tx, a recorded-address mismatch fails, `--dry-run`, and with a changed registry build: class publish, `update_to` scheduled, a second run logs it as pending. The upgrade after the delay is not tested |
| Aztec testnet deploy              | `node --env-file=.env.testnet deploy.ts`, node `https://aztec-testnet.drpc.org` 6.0.0, `DEPLOY_SALT_LABEL=MetaLex-v1.0.0` | Pass on 2026-11-04: BorgAuthV2 `0x0970f8e12c8b3ff5dab4bb049b9802b85d313bf70f1cb8fcdef2ddb87eee0a9f` (tx `0x2c8cb1c7f60fc9b6e139635a8e8707ea99e17afec744ad6555a52d614abad23f`), registry `0x14958bb6e18e19e04358b855e4c36805814b28a86a773625fdc645b30c060380` (tx `0x017888d0dd3f2bfd39068cc21e35874c535c2dc6667f0ee5109f595abb0c32c6`), root `0x0e39…0c70`. A second run sends no tx |
| Aztec testnet e2e                 | `node --env-file=.env.testnet e2e.ts`                                                                                | 24 of 24 checks pass on 2026-11-04, one run, real client proofs. Finalize tx `0x186ccd3aacccb392361c1a435d3eeeb61096631a046ac6351173fe61e21169c9`, block 18758 |
| Aztec mainnet                     | Not run                                                                                                              | Not deployed                                                                                                                                                                                                                                                   |
| Independent review                | Not run                                                                                                              | None                                                                                                                                                                                                                                                           |

Notes on these results:

- The local node runs with `realProofs` set to false and accepts fake proofs. The run does not show that a real
  client proof verifies.
- A TXE contract account keeps its signing key in a private note. So the TXE tests give the settler the scopes of
  the parties. The local network run uses initializerless accounts and a settler PXE that has no party keys.
- TXE does not run the rollup check that drops an expired tx. The local network run shows that the PXE refuses an
  expiry at or before the anchor block. No test covers an expiry between the anchor and the inclusion block. The
  rollup circuit enforces that case (`private_tail_validator.nr`).
