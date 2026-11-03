# Private Agreement Registry on Aztec (PoC)

A minimal port of `src/CyberAgreementRegistry.sol` to Aztec. It supports the happy path of one agreement. Each party
signs offchain with a private authwit. MetaLeX collects the authwits and sends one private `finalize` tx when all
parties signed. The chain keeps only nullifiers. The parties, and an auditor that a party shares the invite with,
see the document and the status "finalized". The MetaLeX data key store keeps each salt for a retention period, so
a party can open the agreement again without the invite.

- [ARCHITECTURE.md](ARCHITECTURE.md): components, data model, the MetaLeX data layer, the EVM retrofit, privacy
  analysis and the comparison with today's webapp.
- [USER-FLOWS.md](USER-FLOWS.md): onboarding, draft and sign, review and sign, settle, view, recovery.

## Layout

| Path                                           | Content                                                                                                                                 |
|------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `agreement_registry_contract/src/main.nr`      | The `CyberAgreementRegistry` contract                                                                                                   |
| `agreement_registry_contract/src/agreement.nr` | `Agreement` struct, id, validation, consent hash, nullifiers                                                                            |
| `agreement_registry_test/src/lib.nr`           | TXE tests                                                                                                                               |
| `scripts/poc.ts`                               | The parts that `e2e.ts` and the web app share: four wallets, the registry, and an in-memory MetaLeX vault, collector and data key store |
| `scripts/e2e.ts`                               | Lifecycle checks on a local network                                                                                                     |
| `scripts/app/`                                 | A local web app with one page for each role: Alice, Bob, auditor and MetaLeX                                                            |
| `scripts/journey/`                             | Playwright journey that drives the web app and saves a screenshot for each step                                                         |
| `scripts/deploy.ts`                            | Deploy script with a fixed salt (same address on every network)                                                                         |
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
cd scripts && npm install && AZTEC_NODE_URL=http://localhost:8090 node e2e.ts
```

Web app, with the local network running:

```shell
cd scripts && AZTEC_NODE_URL=http://localhost:8090 npm run app
```

Open http://localhost:8091/alice. The server runs the wallet and PXE of each user in place of the user's browser.
Each role page is one user, because the PoC has no login.

Web app journey, with the local network running. It starts the app on port 8091, or uses one that runs:

```shell
cd scripts && npx playwright install chromium && npm run journey
```

The screenshots go to `scripts/journey/test-results/`. To keep the journey off an app that already runs on 8091, set
`JOURNEY_PORT` (for example `JOURNEY_PORT=8093 npm run journey`).

Testnet, or any shared network. Copy `scripts/.env.example` to `scripts/.env.testnet` (git ignores it) and fill
in the keys that `aztec-wallet create-account` prints. The settler can be any account type. Alice and Bob must be
`schnorr_initializerless`, so that the settler can check their authwits. The SponsoredFPC pays each fee. Then run:

```shell
cd scripts && node --env-file=.env.testnet deploy.ts
```

Put the printed `REGISTRY_ADDRESS` into `.env.testnet`, then:

```shell
cd scripts && node --env-file=.env.testnet e2e.ts
```

Without `SETTLER_SIGNING_KEY`, the scripts use the local network test accounts and deploy a new registry.

Networks for this PoC (Aztec docs, networks page): the testnet runs 6.0.0 at `https://aztec-testnet.drpc.org`, with
the SponsoredFPC at `0x2d8fff82a3b0c15d0a89169e7d8d043e079ab94d52031f1de1e4972ebad169d3`. The testnet needs real
proofs, so each tx takes longer than on the local network. Mainnet has no SponsoredFPC. The Aztec docs say not to put
real secrets on an Aztec network yet, so the PoC uses test data only.

## Verification

Status on 2026-11-02, uncommitted, branch `feat/aztec`:

| Check                             | Command                                                                                                              | Result                                                                                                                                                                                                                                                         |
|-----------------------------------|----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Compile                           | `aztec compile`                                                                                                      | Pass. `finalize` has 6,617 gates, `withdraw_consent` 5,245 (`aztec profile gates target`).                                                                                                                                                                     |
| Unit tests (TXE simulator)        | `aztec test`                                                                                                         | 18 of 18 pass                                                                                                                                                                                                                                                  |
| Local network flow, test accounts | `node e2e.ts` on `aztec start --local-network`                                                                       | 24 of 24 checks pass, two runs                                                                                                                                                                                                                               |
| Local network flow, env accounts  | `node --env-file=<env> e2e.ts`, keys from `aztec-wallet create-account`, registry from `deploy.ts`                   | 24 of 24 checks pass, two runs                                                                                                                                                                                                                               |
| Web app journey                   | `npm run journey` (Playwright, Chromium) on `aztec start --local-network`                                            | 1 of 1 passes, three runs, with the auditor verify steps                                                                                                                                                                                                  |
| Deploy script                     | `node --env-file=<env> deploy.ts` on the local network, settler from `aztec-wallet`                                  | Pass; the deployer address equals the `aztec-wallet` address                                                                                                                                                                                                   |
| Aztec testnet deploy              | `node --env-file=.env.testnet deploy.ts`, node `https://aztec-testnet.drpc.org` 6.0.0, `AZTEC_NODE_MAX_BATCH_SIZE=3` | Pass on 2026-11-02, real client proof. Registry `0x18b41975b6265c16f1debf308070c866fad699802392c4e14f4a4597cc05ba38`, tx `0x08d31f3b3608e54533746345030fe350d6ab638fb54dc478cfa1903068198d41`, block 16480, mined (`checkpointed` at the second check)         |
| Aztec testnet e2e                 | `node --env-file=.env.testnet e2e.ts`                                                                                | 22 of 22 checks pass on 2026-11-02, one run, about 1.5 minutes, real client proofs (2.3 to 2.8 s each). Finalize tx `0x240dd2db03e8521b18ef00d527564c3aa80590e733f7e68ad1146479ae18f17f`, block 16488: 6 nullifiers, no note hashes, no logs, FPC as fee payer |
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
