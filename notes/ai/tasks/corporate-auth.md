# Corporate auth implementation

- Status: Locally implemented and validated; ready for independent review
- Updated: 2026-10-07, America/New_York
- Owner: Codex, this implementation chat
- Base: develop at d28a602d4afb01fbeacaafadc313a611d3473cf7; clean tracked tree before work
- Plan: notes/plans/corporate-auth-plan.md
- Scope: new deployments only; prior discarded changes are not reused. No legacy migration or last-officer guard.
- Remote freshness: previously unable to reach GitHub; remote freshness unverified.
- Acceptance: invariants and behavioral cases recorded in the plan before implementation.
- Gates: selected unit/integration suites and local transaction acceptance passed; required independent external-model review pending. No merge or production deployment performed or authorized.

## Implementation evidence

New BorgAuthV2 uses a company-specific UUPS proxy, independent memberships, fixed permission mappings, root administration and two-step root transfer. Numeric authority APIs cannot escalate V2 access. CyberCorp's roster owns the officer bit; root cannot edit that bit through generic membership administration. Root is an explicit override for officer management and the sole protocol configuration/upgrade authority. Approved-reference checks remain in consumer upgrades.

CyberCorpFactory has a reviewed-implementation setter and explicit deployCyberCorpWithGovernance entry point with root/board configuration committed into its salt. CorporateDeploymentLib keeps creation bytecode out of the factory. Legacy entry points remain numeric. Root, board executor and initial officer must be explicitly supplied; the board executor's internal quorum/voting implementation is external to this change. Existing global/platform authorities are separate.

Consumers updated: CyberCorp, IssuanceManager, DealManager, RoundManager, CyberScrip, LedgerEntryToken's storage-library admin gate, and company-scoped secondary/recertification/founder-override condition checks. No consumer role storage added. Factory consumes one gap slot. New authority storage is for new proxies only; no legacy migration was implemented.

## Validation

All tests cover the dirty implementation on base d28a602d4afb01fbeacaafadc313a611d3473cf7, with modified consumer/factory/auth source files and new BorgAuthV2, CorporateAuth, CorporateAuthCheck and CorporateDeploymentLib; test/script/plan files are also uncommitted. These results do not establish current remote freshness (ls-remote still fails).

- `forge test --offline --match-path 'test/{Corporate*,CyberCorpSingleFactoryTest,CyberScripTest,NonUSNationalityConditionTest,DealManagerSecondaryTradeTest,conditions/secondary/*}.t.sol'`: 513 passed, 0 failed/skipped across 20 suites. Includes 19 new tests and 256 fuzz runs for director-role separation. Relevant legacy business-flow and shared-condition regressions passed. Full repository/fork suites were not run.
- `forge build --offline --sizes --skip test --skip script`: passed. BorgAuthV2 5,625 bytes; CorporateDeploymentLib 4,820; factory 22,124; IssuanceManager 18,878; DealManager 22,883; RoundManager 21,157; LedgerEntryToken 24,307, leaving only 269 bytes under EIP-170.
- New Solidity files: `forge fmt --check` passed. `git diff --check` passed.
- Local script fixture and PowerShell runner on disposable loopback Anvil chain 31337: seven signed/simulated/submitted cases matched expected success/refusal. Root/role state survived an actual implementation-address change. Receipt evidence is in corporate-auth-local-acceptance.json. No real-network funds or transactions used; local node stopped afterward.

## Manager permission tests (2026-10-08, Claude Code)

`test/CorporateAuthManagerFlows.t.sol` runs deal, round and secondary-trade flows on a company from `deployCyberCorpWithGovernance`, plus a full permission matrix and refusals at real gates. Coverage map: `specs/analysis/auth-v2.md`. Result: 9 pass, 1 fails. `DealManager.proposeAndSignNewCertsDeal` reverts with `PermissionDenied(MANAGE_SECURITY_CLASSES, dealManager)` because the DealManager calls `IM.createCertPrinter`. The fix is an open decision for the user. Do not change the table or the test until the user chooses.

## Remaining gates and handoff

Independent external-model review is required, not performed, and not authorized to start by this request. No release clearance inferred from local tests. Platform release deployment/linking, merge, real deployment, client integration and any future legacy migration remain separate actions. Clients must stop numeric-role inference for new companies; legacy retrofit helpers and combined legacy deployment/offer/round entry points remain legacy-only.

Next action: obtain the required authorized independent review of this concrete patch and plan before release. Existing review/implementation ownership elsewhere is unchanged.
