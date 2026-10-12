# Task: Prepare LET footer upgrades on all supported chains

- **Status:** Ready for review; scripts tested locally, no live deployment authorized
- **Updated:** 2026-10-12 America/New_York
- **Owner:** Codex current chat
- **Scope:** Footer-specific upgrade script, all-chain runner, tests and usage instructions.
- **Canonical sources:** [Footer implementation](let-footer-issuer-name.md),
  `script/libs/DeploymentConstants.sol`, `script/libs/DeploymentScript.sol`.
- **Branch / base:** `claude/keen-benz-55739a`, code base
  `a098d2f50e610c25a935bd772d717edd855cd032`; existing uncommitted footer-review
  record is preserved. `origin/develop` refreshed before implementation.
- **Boundary:** Ownership of the footer implementation and PR monitor stays with
  its existing owner. No source-contract changes, merge, live deployment or Safe signing.

## Invariants and acceptance tests established before implementation

Follow-up requested by the user: remove all script-specific environment inputs,
including key/deployer/chain/output settings. Direct Forge runs must use the RPC
chain and Forge wallet/sender options, derive a chain/proxy output filename, and
still queue the setter exclusively for the Safe. The optional all-chain runner
must pass explicit function arguments and standard Forge flags, not custom envs.
Revalidate default entrypoints, mismatch refusal and local signed deployment.

1. Cover all five chain defaults (1, 8453, 42161, 11155111, 84532), and reject a
   selected chain that differs from the RPC chain before deployment.
   Direct Forge runs infer the chain from the RPC; an explicit runner-supplied
   `runForChain` argument mismatch still refuses.
2. Change only the image builder; keep the URI implementation and AUTH unchanged,
   even when the existing URI implementation differs from current source.
3. Require configured Safe ownership before deployments. Per the user's multisig
   clarification, always queue the setter, even if the deployer is also an owner.
   Test Safe batch success, missing Safe ownership, missing proxy, wrong chain.
4. Safe batches contain only `setImageBuilder`, with correct chain, destination,
   zero value and exact calldata. Render the issuer footer after simulation.
5. A same-code rerun does not redeploy the image builder or retain stale calls.
6. Runner defaults to dry run, validates every selected chain before broadcasting,
   stops on failure, and separates simulation batches from completed deployment batches.
7. Keep unit tests, local sign/simulate/submit rehearsal, remote fork acceptance,
   independent review, deployment and Safe execution as separate evidence.

## Validation and handoff

Validated the dirty tree based on `a098d2f50e610c25a935bd772d717edd855cd032`:
new `script/upgrade-certificate-footer.s.sol`, Python all-chain runner, script
README, `test/UpgradeCertificateFooterScript.t.sol`, Python runner tests and
local Anvil rehearsal/fixture. Also updated `.gitignore` for Python caches and
shared task pointers. No production contract source changed. All changes remain
uncommitted, alongside the preceding branch-review record.

- **47 Solidity tests passed:** six new upgrade tests plus all 41 previously
  passing non-fork certificate tests. Command:
  `forge test --use 0.8.28 --match-path 'test/*Certificate*' --no-match-contract CertificateUriBuilderLegacyForkTest -R '@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/' -R '@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/'`.
- **6 Python runner tests passed:** all five chains simulate by default, all
  preflights precede broadcast, missing RPC configuration refuses before work,
  failed preflight blocks every broadcast, and failed/wrong-chain output stays
  unverified. `python -m unittest discover -s test -p test_certificate_footer_runner.py`.
- **Local sign -> simulate -> submit rehearsal passed:**
  `python test/rehearse_certificate_footer.py`, localhost Anvil, public toy keys.
  Real local deployment receipts verified; even a deployer-owner did not update
  the proxy. The JSON setter was then signed, simulated and submitted by the
  authorized owner, preserving URI implementation and AUTH. Wrong chain and
  missing Safe ownership refused before deployment, and an unauthorized setter
  simulation refused. The owner is an EOA stand-in, not an actual Safe: threshold
  signatures, guards and Safe UI import remain acceptance gates.
- **Static checks:** Python CLI help and `git diff --check` passed.
- **Superseded RPC-chain inference follow-up (2026-10-12):** `run()` initially defaulted the
  optional `FOOTER_CHAIN_ID` to `block.chainid`. The same six upgrade tests pass
  after extending the five-chain test to exercise an empty expected-chain value
  and explicit mismatch refusal on every supported chain. The runner continues
  supplying its expected chain. Replaced by the environment-free entrypoints below.
- **Forge-native configuration follow-up (2026-10-12):** removed all environment
  reads from the new Solidity script, including private key, deployer, chain ID
  and output path. `run()` uses `block.chainid` and a chain/proxy-derived filename;
  `vm.broadcast(msg.sender)` uses Forge's configured sender and signer. The
  all-chain runner takes RPCs as CLI options, forwards Forge `--sender`/`--account`,
  and uses `runForChain(uint256,string)` arguments for expected chain and output.
  No custom environment variables are injected. `runWithArgs` no longer takes a key.
  Revalidated **47 Solidity tests, 6 Python tests, and the local Anvil
  sign/simulate/submit rehearsal**, now using Forge wallet flags for deployment.
  All five default entrypoints and wrapper mismatch refusals passed. No live
  deployment or real Safe acceptance occurred.

The new script always requires configured Safe ownership and queues only
`setImageBuilder`; only deployments can be broadcast. Generated artifacts are
unique per run and chain through the Python runner, with simulation/deployment
phases distinguished and failed output left `.unverified.json`. Direct Forge
runs write `script/res/gnosis-batch-certificate-footer-<chain>-<proxy>.unverified.json`;
deployment receipts must be verified before importing that output to Safe.
Same-link reruns are no-ops; a fresh Forge
invocation may deploy a fresh linked library and therefore a new image builder.

The five-chain unit test installs local proxy fixtures at the configured
addresses. It is not evidence of current live deployments or ownership.
Remote fork acceptance for these new scripts, independent external review,
live deployment, real Safe execution and decoded live-token acceptance are
pending. Earlier green CI for the footer branch does not cover these uncommitted
scripts. No real credentials were used and no live transactions were submitted.

Next action: review the scripts and `script/README-certificate-footer.md`, then
perform configured-chain dry runs and the required real-Safe test-environment
acceptance before release authorization. The existing footer/PR owner retains
their review and deployment gates. This record remains local until shared.
