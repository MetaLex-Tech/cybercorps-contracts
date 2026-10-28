# Task: Robinhood pre-v5 bootstrap

## October 28 intermediate handoff

Current intermediate-only preparation on develop `0a59859` is recorded in
[robinhood-intermediate-20261028.md](robinhood-intermediate-20261028.md).
That record owns the current rehearsal and operator handoff; the October 23
full-v5 refresh below remains historical evidence of its exact source.
The owner explicitly retained the prior badge auth/proxy address exception
on October 28 and requires matching for critical auths/proxies, not every contract.

## Refresh prepared and locally validated — 2026-10-23

Owner: this Codex task. Preparation only; no live signing, deployment, Safe execution or external audit.
Worktree branch: `codex/robinhood-upgrade-refresh`, based on refreshed `origin/develop`
`d964679` (2026-10-21). Historical bootstrap restored from `codex/robinhood-bootstrap`
`ff93f1c`. The preceding September validation below is historical evidence only.

Acceptance criteria established before implementation:

1. Preserve the bootstrap source and pinned historical manifest byte-for-byte, including
   original core addresses, replay salts and init code. Re-run its behavioral tests.
2. Carry Robinhood configuration into the latest constants without inheriting Ethereum's
   ZKPassport verifier/finalizer. Keep original factories separate from V2 targets.
3. Exercise original -> bootstrap -> current core, atomic URI/image upgrade, ShareExtension,
   V3 extensions and secondary conditions. Preserve primary fees (50 bps in the rehearsal),
   use the current release secondary default (500 bps), preserve registry state and Safe authority.
4. Provide a Robinhood final-stage preflight that rejects missing Safe/code/authority,
   incomplete bootstrap wiring and wrong network before deployments. Never downgrade through
   the intermediate step after v5. Test successful and refused paths.
5. Keep the final Safe JSON compatible with the installed historical Foundry. Check JSON
   destinations/calldata and local Safe-call simulation. Distinguish simulation from real
   Safe signatures and chain receipts. Real target-chain acceptance and independent review remain pending.
6. Document remaining address-matching limitations and optional ZKPassport/SAFO/factory work;
   do not represent absent optional dependencies as deployed.

### Read-only chain evidence

`robinhood-readiness-20261023.json` records block 95918728 on Robinhood mainnet
(4663), queried through the locally configured RPC without signing or submission.
The configured Safe now has code, reports five owners and threshold two, and
holds core AUTH role 200. Its signing keys/control were not verified. The core
factory still uses original implementation `0xa150525deD1aA387E160FDF4b45e975acD02E156`
and the three logged original nonproxy factories. The target V2 issuance factory
and pinned badge proxy have no code. CreateX has the canonical expected runtime
hash. Thus the previous missing-Safe-code blocker is resolved at this block, but
the intermediate deployment/Safe batch remains necessary before the final step.

Local fixture tests verified all 16 prior intermediate cases on the refreshed
source. The complete final-stage and pinned live-state fork rehearsals passed,
as detailed below.
The CreateX fixture is public deployed runtime at this same block and asserts
the upstream expected hash before installing it locally. No credentials or RPC
URLs are stored in the evidence or fixture. The three historical replay sources
remain saved broadcast evidence; this refresh did not independently re-fetch all
historical Ethereum receipts.

### Compatibility finding and address scope

The full original -> bridge -> final regression reproduced an empty revert in
`DeployBuildersScript`: original URI implementation `0x3B93dBb163f9aCD500552FC22063744A27C5767b`
has no `imageBuilder()` getter. The updated script treats a missing getter as an
unset image builder only for that pinned implementation on 4663/46630. Unknown
implementations and other chains still refuse. Both complete local release paths
pass after this fix, including the observed-state fork. The upstream final
runner and all other upstream sub-scripts remain unchanged. No protocol source
contract was modified.

`script/res/robinhood-create3-predictions.json` records all 27 new CREATE3 targets
for historical sender `0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B`. All differ from
the Base production targets currently in constants. This is an offline source
comparison, not verification of live Base code. The script's fresh CREATE3 policy
is unchanged from the earlier plan; exact matching would require historical
deployment recovery for these too. The four badge CREATE2 entries also retain
their disclosed Robinhood-specific addresses. Do not describe this branch as
achieving complete address parity, and do not replace zero fields with absent
Base addresses. Intermediate source/manifest remain byte-identical to `ff93f1c`.

### Final validation and handoff

Validated the dirty tree based on `d964679a6a1dd16b88022865b71214102e6839fa`:
restored historical bootstrap/manifest/test; Robinhood constants; common JSON
formatter; builder getter fallback; new final wrapper, regression tests,
hash-checked CreateX runtime fixture and CREATE3 prediction manifest. The task
record, runbook and readiness evidence describe this same prepared code.

- `forge test --match-path 'test/*Robinhood*Test.t.sol' --offline --use 0.8.28
  --evm-version cancun --threads 1`, with the two explicit `@openzeppelin`
  remappings: **48 passed, 0 failed, 0 skipped** across three suites. This count
  includes 16 inherited bootstrap cases repeated in the final-stage suite.
- The opt-in fork test was enabled using only RPC and token-address settings.
  It selected Robinhood mainnet block **95918728**, replayed the intermediate
  step, simulated its Safe calls, and ran the complete current final runner.
  The deployer key used by the final rehearsal was public toy key `0xA11CE`;
  no real signing key was used. Gas funding and Safe execution were simulated.
- Both mainnet/testnet local full-release paths passed. They preserve registry
  domain/template state, core AUTH and Safe ownership, retain 50 bps primary fees,
  set 500 bps secondary fees, install an image builder atomically, and deploy
  ShareExtension, V3 extensions and conditions with their expected auths.
- Refusal coverage includes missing Safe/authority, incomplete bootstrap batch,
  wrong chain/CreateX, invalid kill admins, unknown legacy URI implementation
  and legacy fallback on another chain. JSON checks cover chain, destination,
  calldata, empty data, value and timestamp on the installed old Foundry.
- The 27 offline CREATE3 predictions were independently checked against the
  Solidity utility. A complete simulation used real canonical CreateX runtime.
- Foundry v1.2.0-rc `0a7b3f02b559fcb884f9886274f04a89dec15f9c`, Solidity 0.8.28,
  Cancun, optimizer 15, via IR. Installed dependency commits match develop pins:
  forge-std `8ba9031`, OpenZeppelin `fda6b85`, upgradeable `36ec707`.

The initial full-release regression failed at the absent legacy URI getter;
the narrow script compatibility fix is covered by that same previously failing
full path and four focused getter success/refusal cases. A preliminary invalid-admin
test mutated shared process environment; it was replaced with isolated validation
tests before the final passing run. The upstream uninitialized CreateX artifact
failed the runtime hash assertion, so the fixture uses the exact deployed runtime
with the canonical pinned hash instead.

No live deployments, real Safe signatures/execution, independent external review,
merge or release approval occurred. The fork uses Safe impersonation, not real
2-of-5 authorization. Real test-environment sign -> simulate -> submit success
and refusal cases, fresh-state confirmation, full address-parity decisions,
templates/app inventory and independent review remain release gates.

Next operator action: review the prepared branch and address inventory; simulate
the unchanged intermediate script, then execute its separately approved deployment
and atomic Safe batch before using `UpgradeRobinhoodScript`. Two approved kill-switch
admins are required for the final step. Optional ZKPassport, SAFO activation and
credit-facility factories retain their own owners/gates. This task owns only the
Robinhood upgrade preparation and has not assumed those other rollouts.

## Historical preparation record (superseded by the refresh above)

- **Status:** Implemented and locally tested; ready for review, not approved for deployment
- **Updated:** 2026-09-25 UTC
- **Owner:** Codex, current Robinhood bootstrap task
- **Scope:** Add the step between `feat/new-chain-deploy` and the develop v5 runner, preserving historical core and V2 extension addresses.
- **Out of scope:** Broadcasting, merging, external audits, existing-corp migration, and replaying every optional historical extension.
- **Base:** develop `1dca3007937008e8a527be34abfca2d4370e1d22`; original branch `d548b3095aeb64110c92dc8e75447b9af4062c1c`.
- **Working branch:** `codex/robinhood-bootstrap`; user checkpoint `d0ae01dc81a1708b28784223eaa3ced2abf7c72f` (Robinhood Upgrade Prep), with follow-up changes uncommitted.
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
9. Preserve the user's reverted v5-runner edit and deleted standalone test fixture.
   Supply an existing Safe-owned badge/auth to the unchanged v5 runner. Verify
   its badge helper and mainnet ownership handoff preserve the proxy, Safe role
   and minter issuer keys. Keep the original-bytecode test setup in the pinned
   bootstrap manifest instead of recreating the deleted file.

## Evidence / current state

The previous read-only comparison found that the old three component factories are not UUPS proxies and that RoundManager/LeXcheX do not exist in the original deployment. Nine CREATE2 address calculations matched saved historical deployment calldata. The working tree was clean before implementation.

## Validation and handoff

Implemented `script/bootstrap-robinhood.s.sol`, its pinned replay manifest,
`script/res/robinhood-bootstrap.md`, and `test/BootstrapRobinhoodTest.t.sol`.
Added Robinhood constants. After the user confirmed intentional edits, preserved
the unchanged v5 runner and deletion of the standalone original-deployment fixture.
The manifest now includes 32 historical deployments, four new deterministic
badge deployments, and a separate 13-entry original deployment array for tests.
The new badge auth is owned directly by the Safe; its proxy and auth are populated
in constants before v5, avoiding the zero-auth handoff and new-badge setup path.
Original payloads come from `broadcast/warrant-deploy.s.sol/1/run-latest.json`.
The production source contract files and `script/upgrade-v5.s.sol` are unchanged.

Validated the uncommitted follow-up to the exact checkpoint above: bootstrap
script, deployment constants, pinned manifest, tests, runbook and this record.

- `forge test --match-path test/BootstrapRobinhoodTest.t.sol --offline`: **16 passed**.
  Includes actual historical CREATE2 deployment replay, expected factory addresses,
  Safe-batch JSON decoding and simulated execution, fee/whitelist/role wiring,
  reruns, wrong-chain/authority/code/implementation/payload refusal, and prevention
  of a downgrade after the current `UpgradeCoreScript` succeeds. The integration
  case deploys a new corporation with current v5 core implementations and preserves
  the original registry template and EIP-712 domain across the upgrade.
  The additional badge test invokes the current secondary-condition script's
  badge helper and production ownership-handoff helper, executes their Safe
  calls, and verifies retained Safe authority, proxy auth and minter issuer keys.
- `forge fmt --check script/bootstrap-robinhood.s.sol test/BootstrapRobinhoodTest.t.sol`: passed.
- `forge build script/upgrade-v5.s.sol --offline`: passed with existing compiler warnings.
- `git diff --check`: passed.
- Compiler: Solidity 0.8.28; local Foundry 1.2.0. Existing repository warnings remain.
- Verified `upgrade-v5.s.sol` has no diff from develop `1dca300` and the deleted
  `test/res/robinhood-original-deployment.json` remains absent.

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
- V3 extensions and secondary conditions use fresh CREATE3 addresses, not
  replayed historical addresses. Record them in constants after the first v5
  broadcast before any rerun. Legacy credential condition/ZKPassport and optional
  factories are not provisioned. URI image-builder configuration and templates
  remain part of release acceptance, as documented in the runbook.
- Badge auth/proxy have new pinned Robinhood CREATE2 addresses, not the historical
  cross-chain addresses. This explicit divergence keeps the unchanged v5 runner
  compatible. Their build provenance is recorded separately in the manifest.

Next action: review this local branch and its runbook, then obtain the required
independent review and execute the separately authorized target-chain rehearsal.
Ownership stays with this task until explicitly transferred.
