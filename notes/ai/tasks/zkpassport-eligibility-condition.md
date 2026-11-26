# Task: Standalone ZKPassport nationality and age eligibility condition

- **Status:** Ready for review
- **Updated:** 2026-11-26 18:15 EST
- **Owner:** Antigravity session, for the owner
- **Collaborators / boundaries:** Standalone condition contracts and interfaces only (`src/interfaces/IZKPassportVerifier.sol`, `src/interfaces/IZKPassportEligibilityCondition.sol`, `src/libs/conditions/ZKPassportEligibilityCondition.sol`, `src/libs/conditions/ZKPassportEligibilityConditionFactory.sol`). `RoundManager`, `RoundManagerStorage`, `RoundManagerFactory`, `LexScrowStorage`, `NonUSNationalityCondition`, and `metalex-webapp` are untouched. No deployment, upgrade, or live transaction was executed.
- **Objective:** Provide a standalone `ICondition` and deterministic CREATE2 beacon-proxy factory that enforces zero-knowledge ZKPassport nationality allowlist or exclusion list, minimum age, optional sanctions screening, and non-salted one-passport-one-wallet binding on unmodified `RoundManager` (both `FCFS` and `FounderApproved` rounds) and `DealManager` contracts.
- **Out of scope:** `RoundManager` upgrades, onchain investor-count caps (`maxInvestors` / `maxPerNationality`), `ONCHAIN_ELIGIBILITY_VERSIONS` activation in `metalex-webapp`, deployment scripts/broadcasts, and live ZKPassport mobile-app proofs.
- **Canonical plan / sources:** `metalex-webapp` `notes/plans/cyberraise-minimum-close-and-investor-limits-20261113.md`, `notes/ai/tasks/round-investor-eligibility.md`, `notes/ai/tasks/zkpassport-granular-conditions-discovery.md`; owner decisions of 2026-11-26.
- **Repository / branch:** `MetaLex-Tech/cybercorps-contracts`; base `origin/develop` `04cc21b`, working branch `feat/zkpassport-eligibility-condition`
- **Verified base / code head:** Base `04cc21b`; tested code commit `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` (all 126 targeted Foundry tests passed on this exact commit).
- **Worktree locator:** Local worktree on branch `feat/zkpassport-eligibility-condition`
- **PR / artifact:** Opened from `feat/zkpassport-eligibility-condition` targeting `develop`

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Works on unmodified `RoundManager` (`FCFS` and `FounderApproved`) and `DealManager` without modifying `RoundManager` | Verified in unit and `RoundManager` integration tests (`011e7a93`) |
| Pure zero-knowledge nationality allowlist (`isNationalityIn`) or exclusion list (`isNationalityOut`) and minimum age (`isAgeAboveOrEqual`), with zero nationality or birthdate disclosure onchain | Verified against mock `IZKPassportEligibilityHelper` matching deployed ZKPassport `VerifierHelper` ABI (`011e7a93`) |
| Optional per-condition `enforceSanctions` flag (defaults to false when chosen by founder) | Verified (`011e7a93`) |
| Closes Hexens MTLX1-33: refuses caller-selected `devMode` unless `devModeAllowed` is true and enforces `NON_SALTED_NULLIFIER` (or `NON_SALTED_MOCK_NULLIFIER` in dev mode) | Verified (`011e7a93`) |
| Closes Hexens MTLX1-29: eligibility rules, domain, scope, and `devModeAllowed` are immutable after initialization; rule changes deploy a new deterministic proxy with a distinct scope | Verified (`011e7a93`) |
| Deterministic CREATE2 `BeaconProxy` factory with idempotent deploy, per-round salt support, and `BorgAuth` `OWNER_ROLE` beacon upgrades | Verified (`011e7a93`) |
| Independent external-model review, real ZKPassport proof fork test, deployment, and webapp integration | Pending (separate steps) |

## Decisions and evidence

- **2026-11-26 (owner):** Do not modify `RoundManager`; build a standalone `ICondition` for nationality + age only (no onchain investor caps).
- **2026-11-26 (owner):** Use pure zero-knowledge `isNationalityIn` / `isNationalityOut` + `isAgeAboveOrEqual` with no nationality disclosure onchain (since per-nationality caps are not onchain).
- **2026-11-26 (owner):** Make sanctions screening an optional flag (`enforceSanctions`), defaulting to `false` so founders control sanctions independently of `NonUSNationalityCondition` presets.
- **Deployed runtime read (2026-11-26, `cast`):** `RoundManagerFactory` `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9` references `RoundManager` `5.1` on Base (`0x2d282dB929bf095B1F9a97469b090f7A4f92Bd1a`, 24,010 bytes), Ethereum (`0x288E4789D0bFf776bB0c670790F5B801Ff0198A8`), and Arbitrum (`0x7dD0F65F3D3FB598950FAF4F680993FA115f42b3`). `ZKPassportRootVerifier` `0x1D000001000EFD9a6371f4d90bB8920D5431c0D8` verified on Base (4,951 bytes); official `VerifierHelper` exposes `isNationalityIn`, `isNationalityOut`, `isAgeAboveOrEqual`, `getNullifierType`, `enforceSanctionsRoot`, `verifyScopes`, `getBoundData`, and `getProofTimestamp`.
- **Related past audit findings:**
  - **Hexens MTLX1-33 (Medium, Acknowledged on `NonUSNationalityCondition`):** Closed in `ZKPassportEligibilityCondition` by gating `params.serviceConfig.devMode` on immutable `devModeAllowed` and enforcing `NullifierType.NON_SALTED_NULLIFIER` (plus `NON_SALTED_MOCK_NULLIFIER` only when `devModeAllowed == true`). Existing `NonUSNationalityCondition` is untouched.
  - **Hexens MTLX1-29 (Low, Acknowledged on `NonUSNationalityCondition`):** Closed by making `allowedNationalities`, `excludedNationalities`, `minimumAge`, `enforceSanctions`, `expectedDomain`, `expectedScope`, and `devModeAllowed` immutable per condition proxy.
  - **V12 F-10 (Medium, fixed in metalex-webapp #1611):** `expectedDomain` and rule-bound `expectedScope` are immutable per proxy and verified via `helper.verifyScopes`.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Targeted Foundry unit and integration suite (`ZKPassportEligibilityConditionTest`, `ZKPassportEligibilityRoundIntegrationTest`, `NonUSNationalityConditionTest`, `CyberAgreementRegistrySignerConditionsTest`, `RoundManagerFCFSTest`) | `forge test --match-contract "ZKPassportEligibilityConditionTest|ZKPassportEligibilityRoundIntegrationTest|NonUSNationalityConditionTest|CyberAgreementRegistrySignerConditionsTest|RoundManagerFCFSTest" --summary` on commit `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` | Passed: 126 passed, 0 failed, 0 skipped (24 new unit tests, 4 new FCFS/FounderApproved integration tests, 98 existing regression tests). Uses mock ZKPassport verifier/helper; no live real-passport proof test was run. |
| Contract bytecode size check | `forge build --sizes` on commit `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` | Passed: `ZKPassportEligibilityCondition` 11,200 B (13,376 B margin), `ZKPassportEligibilityConditionFactory` 8,320 B (16,256 B margin), `RoundManager` unchanged at 24,010 B. |

## Review and blockers

- **Independent external-model review:** Pending on the opened PR.
- **Real ZKPassport proof verification:** Not run (no mobile passport fixture in repo for `isNationalityIn` / `isAgeAboveOrEqual` + `getNullifierType`). Recommend one Sepolia fork/testnet mock-passport proof check before production deployment.
- **Deployment / webapp integration:** Not authorized in this task; `ONCHAIN_ELIGIBILITY_VERSIONS` in `metalex-webapp` remains empty until a contract release covers investor caps or webapp adopts factory-deployed conditions separately.

## Next action and handoff

Complete PR review and independent external review on `feat/zkpassport-eligibility-condition` targeting `develop`, verify one real/mock ZKPassport proof against the live Sepolia `ZKPassportRootVerifier`, and only then plan deployment scripts and `metalex-webapp` integration.
