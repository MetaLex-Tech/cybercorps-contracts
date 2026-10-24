# PR #185 deployment script and direct Safe batch

- Status: Ready for review; local validation complete, uncommitted.
- Updated: 2026-10-23 America/New_York.
- Owner: Codex, PR #185 review/deployment-preparation chat.
- Base: `feat/registry-creator-bound-agreements` at `68c8e7548179f744c53342cfdae771e35a6d50d9`.
- Scope: Deployment script and Safe Transaction Builder JSON generation. No live broadcasts, Safe proposals/signatures, protocol-source changes, merge, push or external audit.
- Sources: PR #185; `script/libs/DeploymentUtils.sol`; `script/deploy-parentco-factory.s.sol`; `script/libs/DeploymentScript.sol`; `DeploymentConstants.coreV2`; canonical issuer-award-templates plan section 0. Existing implementation/release ownership remains unchanged.

## User-directed simplification

The user requested that the deployment script generate Safe JSON directly using
past repository examples. This supersedes the earlier manifest plus separate
Python exporter workflow. Removed `script/export-bound-agreement-batch.py` and
its tests, custom JSON serialization, manifests and the extra verification/export
step. The Solidity script now calls the existing
`DeploymentUtils.formatSafeTxJson`, prints the JSON and writes
`script/res/gnosis-batch-bound-registry-<chain-id>.json` directly. The README and
local rehearsal reflect this single-step workflow.

The previous workflow's 15 Solidity/13 Python tests and local rehearsal were
historical validation only; the exporter tests no longer apply. No mandatory
external-review or release acceptance gate was waived by this simplification.

## Current invariants and implementation

1. Forge deploys/links CyberAgreementJson; the script broadcasts only the registry
   implementation CREATE. It never broadcasts a proxy upgrade, even for an owner
   deployer. Uses standard Forge wallet/sender options.
2. Refuse wrong chain, missing proxy/implementation/AUTH, and unauthorized upgrade
   authority. Defaults require deployed code at the configured Safe; explicit
   testnet/custom arguments remain available.
3. Exactly one zero-value Safe call: `upgradeToAndCall(candidate, 0x)`, no initializer
   or unrelated calls. Uses the shared repository formatter unchanged.
4. Simulate the upgrade as the authority, check implementation, AUTH, domain,
   signature schema, version and linked JSON rendering, then restore proxy state.
5. JSON is generated during simulation, as in existing scripts. Only import the
   output after successful deployment receipts; dry-run or failed-broadcast files
   are previews. There is no separate post-deployment verifier. Repeated runs can
   use fresh nonces/library addresses and overwrite the chain's output.
6. Keep unit tests, local rehearsal, live-fork/testnet application acceptance,
   independent review, deployment and real Safe execution distinct.

## Final validation of the simplified workflow

All checks cover the dirty tree on the named base: the deployment script,
README, tests/fixture/rehearsal, scoped .gitignore entry and shared task records.
No protocol source was edited.

- `forge test --use 0.8.28 --match-contract DeployBoundAgreementRegistryScriptTest -vv`: **7 passed, 0 failed**. Exact shared-formatter JSON/calldata, all five default targets using local fixtures, unchanged proxy before execution, populated agreement and pending-signature preservation, wrong-chain/missing-target/unauthorized refusals. Test-only output prefixes protect operator release files.
- `python test/rehearse_bound_registry_upgrade.py`: **passed**, final local evidence `script/res/bound-registry-rehearsal/290059e6b5a7/`. Actual localhost library/implementation deployments, dry-run nonce/proxy preservation, direct generated JSON consumption, candidate code check and independently encoded calldata comparison, unauthorized refusal, toy-key sign -> simulate -> submit through an owner-gated contract stand-in, successful receipt and implementation/linked-JSON readback.
- Solidity formatting and whitespace checks passed. Local Foundry 1.2.0-rc / Solidity 0.8.28; CI pins Foundry 1.7.1. Existing compiler warnings and nonfatal sandbox signature-cache warning remain.

## Next action and handoff

Review `script/deploy-bound-agreement-registry.s.sol` and follow
`script/README-bound-agreement-upgrade.md` for the selected chain/wallet. Local
fixture tests do not prove compatibility with every historical live implementation.
Actual Safe threshold/guard/UI acceptance, remote fork/testnet application
acceptance and required independent external-model review remain pending.
No live deployment or real Safe execution occurred.
