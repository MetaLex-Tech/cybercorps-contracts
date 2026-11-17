# Task: SAFE LET image upgrade scripts

- **Status:** Ready for review; locally validated, uncommitted, no live deployment
- **Updated:** 2026-11-11 America/New_York
- **Owner:** Codex, current chat
- **Objective:** Prepare renderer deployments and chain-specific Gnosis Transaction
  Builder batches for Ethereum (1), Base (8453), Arbitrum (42161), Robinhood (4663).
- **Branch / verified base:** `feat/let-safe-update`,
  `0840563798421134235fb79f32e5b940b537e214`; initially clean. `origin/develop`
  fetched before implementation. Changes must remain uncommitted.
- **Scope / boundaries:** New upgrade script, all-chain runner, usage instructions
  and tests. No live deployment, Safe signing, merge, legal-template changes or
  token/accounting migration. Existing tasks retain their owners.
- **Canonical sources:** `script/upgrade-certificate-footer.s.sol`,
  `script/deploy-builders.s.sol`, `script/libs/DeploymentConstants.sol`,
  `specs/analysis/pr-116-merge-plan.md`, and the SAFE renderer fix at the base.

## Invariants and acceptance criteria established before implementation

1. Default targets come from `DeploymentConstants.coreV2` on the four requested
   chains. RPC/expected-chain mismatch and missing proxy/implementation/Safe
   ownership refuse before script deployments.
2. Deploy the linked content library/image wrapper; deploy the URI implementation
   only if its runtime differs. Use one atomic `upgradeToAndCall` with the image
   setter when both sides must switch; otherwise queue just the setter.
3. Always export owner actions for the configured Safe, even if the deployment
   wallet also has owner access. Broadcast may deploy contracts only.
4. Simulated execution preserves AUTH and roles. Assert the implementation/image
   pointers and SAFE SVG behavior: Consideration uses remaining units, including
   zero historical consideration; other security types retain their semantics.
5. Each chain gets correctly addressed, zero-value, exact-calldata Safe JSON.
   Same-linked-code reruns clear stale transactions. Simulation output and
   deployment output are separate, and neither is automatically approved.
6. The runner defaults to simulation, preflights every selected chain before any
   deployment broadcast, stops on failure and isolates run artifacts.
7. Local public-toy-key sign -> simulate -> submit success and unauthorized
   refusal remain distinct from real-Safe and live-fork acceptance.

## Audit and compatibility evidence

Reviewed the existing renderer upgrade plan and historical task evidence, the
root Pashov AI report (metadata injection and BorgAuth role observations), audit
scope v2, and sibling webapp audit/verification/task records. Related Hexens
report `audits/hexens-metalex-jul-aug26(Final).pdf` findings reviewed in the
preceding renderer work: MTLX1-15 (Low, Fixed; metadata injection), MTLX1-10
(Informational, Fixed; dates), MTLX1-28 (Low, Acknowledged; partly-paid shares),
MTLX1-8/9 (Medium, Acknowledged; holding periods). This task preserves those
implementations and dispositions; it changes no accounting, dates, escaping,
roles or storage layout. Live implementation equivalence is not established.
No additional script-specific finding was identified in the searched records.

The current inventory configures the shared core URI proxy on all four chains.
Older plans mention a separate Base Pump URI proxy, absent from current constants;
do not silently upgrade a historical address. Custom targets require a separately
verified inventory and use the explicit script entrypoint.

## Validation / release gates

Validated the uncommitted tree based on the exact base above. Task-owned changes:
new `script/upgrade-safe-let-image.s.sol`, `.py` runner, README, Solidity tests,
Python runner tests and localhost rehearsal/fixture; artifact ignore rules and
shared task pointers. No production source or existing upgrade script changed.

- **10 Solidity upgrade tests passed:** four default targets, wrong-chain and
  wrong-owner refusals, missing proxy/implementation, zero Safe, exact Safe JSON,
  atomic switch, current-image retention, legacy URI without the image getter,
  deployer-owner Safe queueing, AUTH/roles, SAFE SVG values and no-op cleanup.
  `forge test --use 0.8.28 --match-contract UpgradeSafeLetImageScriptTest` with
  the README's explicit OpenZeppelin remappings.
- **60 existing renderer/script tests passed:**
  `forge test --use 0.8.28 --match-path 'test/*Certificate*' --no-match-contract CertificateUriBuilderLegacyForkTest`
  with the same remappings; six suites, zero failures/skips.
- **8 Python runner tests passed:**
  `python -m unittest discover -s test -p test_safe_let_image_runner.py`.
  Tests cover four-chain default simulation, all preflights before broadcast,
  failure stopping, wrong-chain/invalid batch refusal, RPC overrides and wallets.
- **Local sign -> simulate -> submit rehearsal passed:**
  `python test/rehearse_safe_let_image.py`, localhost Anvil chain 31337 with public
  toy keys and a contract owner stand-in. Wrong chain and missing Safe ownership
  with `--broadcast` refused without deployment nonce changes. Successful
  deployment broadcast left URI implementation/image unchanged despite the
  deployer owning the proxy. The exported exact atomic call refused an
  unauthorized authority caller, then succeeded through signed simulation and
  raw transaction submission. AUTH was preserved; SVG readback showed
  Consideration 40,000 without historical consideration. Ignored local evidence:
  `script/res/safe-let-image-rehearsal/cfe68ae9ada6/`.
- CLI help and `git diff --check` passed. Windows sandbox blocks localhost RPC;
  rehearsal passed with an approved localhost-only sandbox override. Native Forge
  signature-cache permission warnings do not affect the passing assertions.

Independent external-model review, pinned live-chain forks, actual Safe threshold /
guard / import acceptance, deployment and Safe execution are separate pending
release gates. No authority to perform those external actions is inferred.

## Next action

Follow-up: user requested the standard `PRIVATE_KEY_MAIN` signing variable and
asked not to inspect env files. The Solidity script now initializes the existing
DeploymentScript signing helpers from that variable; owner calls still only go
into the Safe batch. Tests inject a public toy key, and the local rehearsal
explicitly supplies that toy key through its child process environment. No env
files were opened. Prior Forge-wallet signing guidance is superseded for the
upgrade deployments; `--sender` must still match for linked-library setup.
Revalidated all 10 Solidity upgrade tests with the injected toy key and checks
against its deployment address. The updated localhost signed rehearsal passed;
evidence is `script/res/safe-let-image-rehearsal/f0aa1106481f/`. No env files
were inspected, no live transactions sent, and no changes committed.

Review `script/README-safe-let-image.md` and the new scripts. Then run configured
chain simulations and the pending release acceptance checks before authorizing
deployment. The runner defaults to simulation and leaves broadcast batches
`.unverified.json` pending receipt/code verification; it never submits owner calls.
Changes and this record remain local and uncommitted; no PR was created.
