# Task: Standalone ZKPassport nationality and age eligibility condition

- **Status:** Ready for review
- **Updated:** 2026-11-26 18:38 EST
- **Owner:** Antigravity session, for the owner
- **Collaborators / boundaries:** Standalone condition contracts, interfaces, deterministic deploy script, and tests (`src/interfaces/IZKPassportVerifier.sol`, `src/interfaces/IZKPassportEligibilityCondition.sol`, `src/libs/conditions/ZKPassportEligibilityCondition.sol`, `src/libs/conditions/ZKPassportEligibilityConditionFactory.sol`, `script/deploy-zkpassport-eligibility-condition.s.sol`, `script/README-zkpassport-eligibility-condition.md`). `RoundManager`, `RoundManagerStorage`, `RoundManagerFactory`, `LexScrowStorage`, `NonUSNationalityCondition`, and `metalex-webapp` are untouched. No live deployment, upgrade, or broadcast transaction was executed.
- **Objective:** Provide a standalone `ICondition`, deterministic CREATE2 beacon-proxy factory, and rehearsed deployment script that enforces zero-knowledge ZKPassport nationality allowlist or exclusion list, minimum age, optional sanctions screening, and non-salted one-passport-one-wallet binding on unmodified `RoundManager` (both `FCFS` and `FounderApproved` rounds) and `DealManager` contracts.
- **Out of scope:** `RoundManager` upgrades, onchain investor-count caps (`maxInvestors` / `maxPerNationality`), `ONCHAIN_ELIGIBILITY_VERSIONS` activation in `metalex-webapp`, live deployment broadcasts, and live ZKPassport mobile-app proofs.
- **Canonical plan / sources:** `metalex-webapp` `notes/plans/cyberraise-minimum-close-and-investor-limits-20261113.md`, `notes/ai/tasks/round-investor-eligibility.md`, `notes/ai/tasks/zkpassport-granular-conditions-discovery.md`; owner decisions of 2026-11-26.
- **Repository / branch:** `MetaLex-Tech/cybercorps-contracts`; base `origin/develop` `04cc21b`, working branch `feat/zkpassport-eligibility-condition`
- **Verified base / code head:** Base `04cc21b`; tested code commits `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` (unit/integration suite) and `63ad1c15aabbab9f4ed2091b72dc6bf7221b6f27` (deploy script and live Base/Ethereum/Sepolia fork rehearsal suite).
- **Worktree locator:** Local worktree on branch `feat/zkpassport-eligibility-condition`
- **PR / artifact:** https://github.com/MetaLex-Tech/cybercorps-contracts/pull/222

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Works on unmodified `RoundManager` (`FCFS` and `FounderApproved`) and `DealManager` without modifying `RoundManager` | Verified in unit and `RoundManager` integration tests (`011e7a93`) |
| Pure zero-knowledge nationality allowlist (`isNationalityIn`) or exclusion list (`isNationalityOut`) and minimum age (`isAgeAboveOrEqual`), with zero nationality or birthdate disclosure onchain | Verified in unit tests (`011e7a93`) and verified against live Ethereum/Base/Sepolia `v0.21.0` `VerifierHelper` bytecode selectors (`63ad1c15`) |
| Optional per-condition `enforceSanctions` flag (defaults to false when chosen by founder) | Verified (`011e7a93`) |
| Closes Hexens MTLX1-33: refuses caller-selected `devMode` unless `devModeAllowed` is true and enforces `NON_SALTED_NULLIFIER` (or `NON_SALTED_MOCK_NULLIFIER` in dev mode) | Verified in unit tests (`011e7a93`) and live Base/Sepolia fork tests (`63ad1c15`) |
| Closes Hexens MTLX1-29: eligibility rules, domain, scope, and `devModeAllowed` are immutable after initialization; rule changes deploy a new deterministic proxy with a distinct scope | Verified (`011e7a93`) |
| Deterministic CREATE2 `BeaconProxy` factory with idempotent deploy, per-round salt support, and `BorgAuth` `OWNER_ROLE` beacon upgrades | Verified in unit tests (`011e7a93`) and live Base/Ethereum/Sepolia fork tests (`63ad1c15`) |
| Deployment script simulates cleanly on Sepolia, Base, and Ethereum with zero deployer role and identical Ethereum/Base factory addresses | Verified via `forge script` dry-runs and `DeployZKPassportEligibilityConditionForkTest` (`63ad1c15`); simulation only, not deployed |
| Live Sepolia broadcast + real/mock ZKPassport mobile proof test, production broadcast, and `metalex-webapp` integration | Pending owner broadcast and separate webapp task |

## Decisions and evidence

- **2026-11-26 (owner):** Do not modify `RoundManager`; build a standalone `ICondition` for nationality + age only (no onchain investor caps), pure zero-knowledge `isNationalityIn`/`isNationalityOut` + `isAgeAboveOrEqual`, optional `enforceSanctions` defaulting to `false`, then add the deploy script and fork rehearsals (step 2).
- **Live onchain verification (2026-11-26, `cast`):**
  - `ZKPassportRootVerifier` (`0x1D000001000EFD9a6371f4d90bB8920D5431c0D8`, 4,951 bytes) is live on Ethereum (`1`), Base (`8453`), and Sepolia (`11155111`); NOT deployed on Arbitrum (`42161`, 0 bytes) or Base Sepolia (`84532`, 0 bytes).
  - Live `v0.21.0` (`0x00000015...`) `VerifierHelper` (11,079 bytes on all three chains: Ethereum `0x1E878E61D565F4c40FC40235D4c4A5FC66Afab2D`, Base `0xCFC06f8447C4acaB2c855Cf3b73873c5e029921B`, Sepolia `0xe8AE97eF2fFF59597D1B6882286754FEC200F3a9`) exposes all 8 selectors (`isNationalityIn`, `isNationalityOut`, `isAgeAboveOrEqual`, `getNullifierType`, `enforceSanctionsRoot`, `verifyScopes`, `getBoundData`, `getProofTimestamp`). Older `v0.16.0`–`v0.20.0` helpers omit `getNullifierType` and revert cleanly.
  - Core `BorgAuth` (`0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01`, 2,188 bytes) grants MetaLeX Safe (`0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`) role `200` (`>= OWNER_ROLE`) on Ethereum, Base, and Sepolia.
- **Simulated deterministic CREATE2 addresses (simulation only — NOT deployed):**
  - `ZKPassportEligibilityCondition` impl (Ethereum, Base, Sepolia): `0x5bF1ad7463e5461201b59ff94Fb96D321217e4EC`
  - `ZKPassportEligibilityConditionFactory` impl (Ethereum, Base, Sepolia): `0xB648cFf98f3e351541D50E4EC5DF37e8c88B53D0`
  - `ZKPassportEligibilityConditionFactory` proxy (Ethereum & Base, `devModeAllowed = false`, `cyberraise.metalex.tech`): `0x21Cc247B450e315d8399044Fce2218DA278e25FD`
  - `ZKPassportEligibilityConditionFactory` proxy (Sepolia, `devModeAllowed = true`, `staging.cyberraise.metalex.tech`): `0x79422cdACcb294F5d05D71207a1F16EEc9D07D8c`
  - Sample Sepolia condition (`GBR`/`USA`, `18+`, `sanctions = false`): `0x83C6688ac48F4c4B48BfEa43463f7977be728a14`
- **Related past audit findings:**
  - **Hexens MTLX1-33 (Medium, Acknowledged on `NonUSNationalityCondition`):** Closed by gating `serviceConfig.devMode` on immutable `devModeAllowed` and enforcing `NON_SALTED_NULLIFIER` (plus `NON_SALTED_MOCK_NULLIFIER` only when `devModeAllowed == true`).
  - **Hexens MTLX1-29 (Low, Acknowledged on `NonUSNationalityCondition`):** Closed by making rules, domain, scope, and `devModeAllowed` immutable per condition proxy.
  - **V12 F-10 (Medium, fixed in metalex-webapp #1611):** `expectedDomain` and rule-bound `expectedScope` are immutable per proxy and verified via `helper.verifyScopes`.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Targeted Foundry unit and integration suite (`ZKPassportEligibilityConditionTest`, `ZKPassportEligibilityRoundIntegrationTest`, `NonUSNationalityConditionTest`, `CyberAgreementRegistrySignerConditionsTest`, `RoundManagerFCFSTest`) | `forge test --match-contract "..." --summary` on commit `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` (also passed full CI `Unit tests` job on PR #222) | Passed: 126 passed, 0 failed, 0 skipped. Uses mock ZKPassport verifier/helper. |
| Live fork deployment rehearsal suite (`DeployZKPassportEligibilityConditionForkTest`) | `forge test --match-contract DeployZKPassportEligibilityConditionForkTest --threads 1 -vv` against live Base, Ethereum, and Sepolia RPCs on commit `63ad1c15aabbab9f4ed2091b72dc6bf7221b6f27` | Passed: 4 passed, 0 failed, 0 skipped. Proves live `v0.21.0` helper ABI, MetaLeX Safe beacon upgrade, idempotent deploy, identical Eth/Base factory addresses, and refusal of Arbitrum/Base Sepolia and legacy `v0.16.0` proofs. |
| Dry-run `forge script` simulations (Sepolia and Base) | `forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url ...` (no `--broadcast`) on commit `63ad1c15aabbab9f4ed2091b72dc6bf7221b6f27` | Passed: Sepolia ~6.46M gas, Base ~6.43M gas. Simulation only; no live broadcast executed. |
| Contract bytecode sizes | `forge build --sizes` on commit `011e7a93bb8ef114a992d391de18a3b5bbd8c8d5` (also passed CI `Build sizes`) | Passed: `ZKPassportEligibilityCondition` 11,200 B, `ZKPassportEligibilityConditionFactory` 8,320 B, `RoundManager` unchanged at 24,010 B. |

## Review and blockers

- **Codex Code Review (PR #222):** Completed on `9a97bec` with 0 findings; will re-run after pushing `63ad1c15` + this record. Security review (`@codex security review`) can be triggered on PR #222 if desired.
- **Live ZKPassport mobile-app proof:** Requires broadcasting the Sepolia factory with the owner's signer and submitting one `v0.21.0` mock-passport proof from the ZKPassport app against the sample condition.
- **Deployment / webapp integration:** Not executed by this session.

## Next action and handoff

Review and merge PR #222 (`feat/zkpassport-eligibility-condition` -> `develop`), broadcast `script/deploy-zkpassport-eligibility-condition.s.sol` on Sepolia with your signer, run one live mock-passport proof against the sample condition, then broadcast on Base and Ethereum and wire `metalex-webapp` to the deployed factory addresses.
