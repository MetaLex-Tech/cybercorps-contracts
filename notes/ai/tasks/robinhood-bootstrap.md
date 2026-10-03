# Task: Robinhood pre-v5 bootstrap

- **Status:** Implemented and locally tested; ready for review, not approved for deployment
- **Updated:** 2026-09-25 UTC
- **Owner:** Codex, current Robinhood bootstrap task
- **Scope:** Add the step between `feat/new-chain-deploy` and the develop v5 runner, preserving historical core and V2 extension addresses.
- **Out of scope:** Broadcasting, merging, external audits, existing-corp migration, and replaying every optional historical extension.
- **Base:** develop `1dca3007937008e8a527be34abfca2d4370e1d22`; original branch `d548b3095aeb64110c92dc8e75447b9af4062c1c`.
- **Working branch:** `codex/robinhood-bootstrap`, uncommitted changes on the named base.
- **Sources:** `script/upgrade-public-rounds.s.sol`, `script/upgrade-v5.s.sol`, `script/libs/DeploymentConstants.sol`, local historical Ethereum broadcast receipts. Broader design: `notes/plans/protocol-improvement-plan.md`.
- **Collaborators:** None assigned. No ownership transfer of other tasks.

## Invariants and acceptance tests (established before implementation)

1. Preserve the original core AUTH, CyberCorpFactory, registry and URI builder addresses/state. Deploy the four newer factory proxies at the common production addresses using frozen CREATE2 payloads, not recompiled historical source.
2. Refuse unsupported chain IDs, absent/mismatched original contracts, an uncontrolled Safe, an invalid payment token, a modified manifest and incompatible occupied deployment addresses.
3. Refuse to downgrade a top-level factory that has moved beyond the original or pinned intermediate implementation.
4. Replay only curated CREATE2 deployments; never historical payments, role removal, legacy beacon upgrades or template calls. Verify payload/address correspondence and deployed code. Re-runs before v5 must reuse the deployments.
5. Explicitly configure factory references, stable whitelist, fee policy/recipient and LeXcheX roles. Produce and simulate the Safe batch; the batch must execute before v5.
6. Add Robinhood mainnet/testnet selection for v5. Preserve the recoverable historical core/V2 addresses; clearly distinguish fresh CREATE3 V3/secondary addresses from existing cross-chain addresses.
7. Local tests must cover the original -> bootstrap state, storage preservation, reruns and negative cases, and exercise the v5 core upgrade after bootstrap where the available toolchain permits.
8. Production acceptance remains separate: independent external-model review, storage/layout evidence, Robinhood fork and test-environment sign -> simulate -> submit with success/refusal cases. No production signing or external review is authorized by this task.

## Evidence / current state

The previous read-only comparison found that the old three component factories are not UUPS proxies and that RoundManager/LeXcheX do not exist in the original deployment. Nine CREATE2 address calculations matched saved historical deployment calldata. The working tree was clean before implementation.

## Validation and handoff

Implemented `script/bootstrap-robinhood.s.sol`, its pinned 32-entry replay manifest,
`script/res/robinhood-bootstrap.md`, and `test/BootstrapRobinhoodTest.t.sol` with an
original-deployment bytecode fixture. Added Robinhood constants and the v5 guard
for a badge auth created by the secondary-condition sub-script. The original
fixture is extracted from `broadcast/warrant-deploy.s.sol/1/run-latest.json`.
The production source contract files are unchanged.

Validated on the dirty working tree based on the exact base above:

- `forge test --match-path test/BootstrapRobinhoodTest.t.sol --offline`: **15 passed**.
  Includes actual historical CREATE2 deployment replay, expected factory addresses,
  Safe-batch JSON decoding and simulated execution, fee/whitelist/role wiring,
  reruns, wrong-chain/authority/code/implementation/payload refusal, and prevention
  of a downgrade after the current `UpgradeCoreScript` succeeds. The integration
  case deploys a new corporation with current v5 core implementations and preserves
  the original registry template and EIP-712 domain across the upgrade.
- `forge fmt --check script/bootstrap-robinhood.s.sol test/BootstrapRobinhoodTest.t.sol`: passed.
- `git diff --check`: passed.
- Compiler: Solidity 0.8.28; local Foundry 1.2.0. Existing repository warnings remain.

The local tests use simulated Safe authority, not a signed Safe transaction.
They do not run the complete v5 extension/secondary-condition rollout or verify
live Robinhood prerequisites. The v5 JSON formatter uses a newer cheatcode than
the installed Foundry; the bootstrap uses standard string/JSON cheatcodes instead.

No PR, merge, chain deployment, target-chain sign/simulate/submit acceptance or
independent external review has occurred. The required independent external-model
review and Robinhood release rehearsal remain pending and must not be inferred
from these local results. No external audit was started. These changes and this
record are local-only until deliberately shared.

## Remaining release decisions

- Select mainnet/testnet and verify the actual payment token, primary fee and recipient.
- Confirm fresh chain state and the controlled Safe; verify canonical CREATE2 and
  CreateX runtime code and the source deployment provenance.
- Use the historical AUTH owner for the first LeXcheX bootstrap or arrange its
  Safe-role grant. No alternate owner is substituted in init code.
- V3 extensions, badge and secondary conditions use fresh CREATE3 addresses, not
  replayed historical addresses. Record them in constants after the first v5
  broadcast before any rerun. Legacy credential condition/ZKPassport and optional
  factories are not provisioned. URI image-builder configuration and templates
  remain part of release acceptance, as documented in the runbook.

Next action: review this local branch and its runbook, then obtain the required
independent review and execute the separately authorized target-chain rehearsal.
Ownership stays with this task until explicitly transferred.
