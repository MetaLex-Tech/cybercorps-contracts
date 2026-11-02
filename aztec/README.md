# Private Agreement Registry on Aztec (PoC)

A minimal port of `src/CyberAgreementRegistry.sol` to Aztec. It supports the happy path of one agreement. Each party
signs offchain with a private authwit. MetaLeX collects the authwits and sends one private `finalize` tx when all
parties signed. The chain keeps only nullifiers. The parties, and an auditor that a party shares the invite with,
see the document and the status "finalized".

- [ARCHITECTURE.md](ARCHITECTURE.md): components, data model, the MetaLeX data layer, privacy analysis.
- [USER-FLOWS.md](USER-FLOWS.md): onboarding, draft and sign, review and sign, settle, view, recovery.

## Layout

| Path | Content |
| --- | --- |
| `agreement_registry_contract/src/main.nr` | The `CyberAgreementRegistry` contract |
| `agreement_registry_contract/src/agreement.nr` | `Agreement` struct, id, validation, consent hash, nullifiers |
| `agreement_registry_test/src/lib.nr` | TXE tests |
| `scripts/e2e.ts` | Lifecycle on a local network with four wallets, an in-memory MetaLeX vault and collector |
| `scripts/deploy.ts` | Deploy script with a fixed salt (same address on every network) |

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

Deploy:

```shell
cd scripts && AZTEC_NODE_URL=<node> DEPLOYER_SECRET_KEY=<fr> DEPLOYER_SIGNING_KEY=<fq> DEPLOYER_SALT=<fr> node deploy.ts
```

The deployer is an initializerless Schnorr account. It must hold fee juice at its address.

## Verification

Status on 2026-11-01, uncommitted, branch `feat/aztec`:

| Check | Command | Result |
| --- | --- | --- |
| Compile | `aztec compile` | Pass. `finalize` has 6,617 gates (`aztec profile gates target`). |
| Unit tests (TXE simulator) | `aztec test` | 13 of 13 pass |
| Local network flow | `node e2e.ts` on `aztec start --local-network` | 15 of 15 checks pass |
| Deploy script | `node deploy.ts` on the local network with test account 2 | Pass |
| Aztec mainnet | Not run | Not deployed |
| Independent review | Not run | None |

Notes on these results:

- The local node runs with `realProofs` set to false and accepts fake proofs. The run does not show that a real
  client proof verifies.
- A TXE contract account keeps its signing key in a private note. So the TXE tests give the settler the scopes of
  the parties. The local network run uses initializerless accounts and a settler PXE that has no party keys.
- TXE does not run the rollup check that drops an expired tx. The local network run shows that the PXE refuses an
  expiry at or before the anchor block. No test covers an expiry between the anchor and the inclusion block. The
  rollup circuit enforces that case (`private_tail_validator.nr`).
