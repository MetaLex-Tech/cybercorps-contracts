# P1 Board authority — forward rollout runbook

**Status:** local target and webapp integration implemented; pinned fork
acceptance passes; no deployment broadcast. Target-block dry run, fresh-corp
route acceptance, policy approval, and authenticated hosted runtime remain.

## Release posture

Use a **forward cutover**. Almost all indexed corps are tests, and legacy
`BorgAuth` instances are immutable: upgrading a legacy `CyberCorp` proxy cannot
add the one-way `roleManager` lock to its already-deployed auth contract. Do not
pretend that upgrading only the corp proxy creates Board enforcement.

- Every newly deployed corp after cutover must use the dedicated v5
  `CyberCorpSingleFactory` and an upgraded top-level factory that completes the
  role-manager handoff and calls `activateBoardGovernance`.
- Existing corps remain explicitly legacy unless they are individually
  redeployed/migrated.
- The legacy single factory and its v4 reference remain unchanged. This keeps
  omitted/legacy top-level factories on the legacy path instead of letting them
  deploy a v5 corp without the P1 handoff.
- Reconcile only the named real-corp allowlist: the corps with off-chain
  records/non-draft positions, assets, known external recipients/signers, or a
  support/sales/legal designation. Test corps are not migration blockers.

## Preconditions

1. Record the chain, previous implementations, legacy
   `CyberCorpSingleFactory` address/reference, and every top-level factory proxy
   actually used by the product.
2. Confirm the broadcaster has `OWNER_ROLE` on the auth attached to the single
   factory and each supplied top-level factory.
3. Run the P1 focused suite and the relevant factory/fork suites.
4. Release the matching webapp ABI and boardRoom branch in the same window.
5. Do not configure a Board adapter until a concrete stockholder-governance
   contract, historical registered-owner voting checkpoints, canonical class
   voting terms, and the legal voting policy have separately passed review.

Current local evidence (2026-07-19):

- `CyberCorpBoardAuthorityTest`: 7/7;
- `CyberCorpForkTest`: 47/47;
- `PumpCorpFactoryForkTest`: 36/36;
- `DeployParentCoFactoryForkTest`: 25/25;
- PumpCorp and ParentCo fork fixtures point their exercised deployment route at
  v5 before exercising P1-aware factory code, proving the version-pairing
  invariant; and
- ParentCo bootstraps all configured officers before the one-way auth handoff,
  then asserts the founder is Board-authorized and additional officers retain
  the exact officer role.

## Environment

Required:

```text
PRIVATE_KEY_MAIN
CYBERCORP_SINGLE_FACTORY  # legacy factory; auth source/read-only invariant
```

Supply every top-level factory proxy that can deploy a corp on the target chain:

```text
CYBERCORP_FACTORY
PUMP_CORP_FACTORY
PARENT_CO_FACTORY
METADAO_FACTORY
```

An omitted optional factory is **not** upgraded and must be disabled in the app
until handled.

## Dry run

Never add `--broadcast` to the first run:

```sh
forge script --via-ir script/upgrade-board-authority-forward-path.s.sol:UpgradeBoardAuthorityForwardPathScript \
  --rpc-url "$RPC_URL" -vvvv
```

The script:

- checks authority before broadcasting;
- deploys a deterministic CyberCorp v5 reference;
- deploys a separate deterministic v5 `CyberCorpSingleFactory`, using the
  existing single-factory auth but leaving the legacy factory/reference
  unchanged;
- upgrades only the top-level factory proxies explicitly supplied and switches
  each proxy to the v5 single factory inside that proxy's same
  `upgradeToAndCall` transaction;
- asserts the v5 reference/deploy version, the unchanged legacy reference, and
  every supplied top-level factory pointer; and
- does **not** upgrade or activate any existing corp.

Review the simulation trace, target addresses, implementation bytecode, and gas
before an owner-authorized broadcast. This split-factory design is deliberate:
an upgraded route fails closed until its atomic pointer switch, while an omitted
legacy route continues to deploy v4 rather than silently creating an
unactivated v5 corp.

## Broadcast order

1. Pause/hide all corp-creation entry points.
2. Broadcast the forward-path script with the reviewed environment.
3. Read back the unchanged legacy reference, the new v5 single-factory
   reference, and every supplied proxy implementation/pointer.
4. Deploy one fresh internal test corp through each enabled factory route.
5. Release the matching webapp, including the new single-factory address used
   by deterministic-address and Pump signature helpers.
6. Re-enable creation only after the acceptance checks pass.

## Required acceptance checks

For every enabled deployment route:

- `CyberCorp.DEPLOY_VERSION()` is `"5"`;
- `boardGovernanceEnforced()` is `true`;
- `AUTH.roleManager()` equals the new corp;
- the founder is both a director and an officer;
- director and officer counts are both one;
- an officer added by the founder cannot call `AUTH.updateRole`;
- that officer cannot add/remove officers, change root corp configuration, or
  authorize a corp upgrade;
- the founder can add/remove officers and directors;
- neither the last officer nor last director can be removed;
- removing one capacity from a dual-role person preserves the other;
- boardRoom shows `Board enforced` / `Protocol roster`;
- officer controls appear only to a connected, authenticated director;
- seat/unseat uses `addDirector`/`removeDirector`;
- unanimous consent signers match the protocol Board roster; and
- the legacy officer-based “Transfer cyberCORP” action is absent.

Also open a known legacy corp and verify that it is labeled `Legacy authority` /
`Title-derived`, uses the old signer fallback, and is never described as
Board-enforced.

## Real legacy corps

For each allowlisted real corp, choose and document one disposition:

1. **Preserve as labeled legacy** temporarily, with no claim of Board
   enforcement.
2. **Redeploy and reconcile** its legal identity, authorized classes, positions,
   documents, and recipients into a fresh v5 corp after legal/operational
   approval.
3. **Custom migration** only if redeployment is unacceptable and the old auth
   can be safely replaced through an explicitly reviewed architecture.

Do not blanket-migrate the test inventory.

## Stop and rollback conditions

Stop before re-enabling creation if any fresh corp lacks the auth lock, Board
activation, founder memberships, or UI mode detection; if an officer can mutate
roles or root configuration; if a factory route still points at old code; or if
consent signers diverge from the displayed roster.

Because the rollout is forward-only, rollback consists of pausing creation,
restoring each switched top-level factory implementation/pointer, and reverting
the webapp release. The legacy single factory never changed. Keep the v5 single
factory available as the `upgradeFactory` for any fresh internal v5 corps
created during the window, even if those test corps are abandoned; no existing
corp was mutated by this script.
