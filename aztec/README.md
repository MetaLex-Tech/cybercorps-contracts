# Private Agreement Registry on Aztec (PoC)

A minimal port of `src/CyberAgreementRegistry.sol` to Aztec. It supports one flow:
`create_bound_contract_and_sign_for`. The creator makes an agreement and signs it in one private tx. The chain
keeps only nullifiers. The agreement data goes to each party as an encrypted private event, delivered offchain
through a MetaLeX mailbox.

- [ARCHITECTURE.md](ARCHITECTURE.md): components, data model, the MetaLeX data layer, privacy analysis.
- [USER-FLOWS.md](USER-FLOWS.md): onboarding, create and sign, receive, check, recovery.

## Layout

| Path | Content |
| --- | --- |
| `agreement_registry_contract/src/main.nr` | The `CyberAgreementRegistry` contract |
| `agreement_registry_contract/src/agreement.nr` | `Agreement` struct, id, validation, signature nullifier |
| `agreement_registry_test/src/lib.nr` | TXE tests |
| `scripts/e2e.ts` | Two-wallet flow on a local network, with an in-memory MetaLeX vault and mailbox |
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
| Compile | `aztec compile` | Pass. `create_bound_contract_and_sign_for` has 5,972 gates (`aztec profile gates target`). |
| Unit tests (TXE simulator) | `aztec test` | 14 of 14 pass |
| Local network flow | `node e2e.ts` on `aztec start --local-network` | 13 of 13 checks pass |
| Deploy script | `node deploy.ts` on the local network with test account 2 | Pass |
| Aztec mainnet | Not run | Not deployed |
| Independent review | Not run | None |

Notes on these results:

- The local node runs with `realProofs` set to false and accepts fake proofs. The run does not show that a real
  client proof verifies.
- TXE does not run the rollup check that drops an expired tx. The local network run shows that the PXE refuses an
  expiry at or before the anchor block. No test covers an expiry between the anchor and the inclusion block. The
  rollup circuit enforces that case (`private_tail_validator.nr`).
- The authwit test gives the delegate the signer scope. This is the same as a contract that runs in the signer's
  PXE.
