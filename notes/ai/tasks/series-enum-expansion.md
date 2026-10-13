# Task: expanded series catalog for MetaLeX's cap table

- **Status:** Source PR open; deployment and live acceptance pending.
- **Updated:** 2026-10-13.
- **Owner:** Codex, overall series naming implementation and PR review task.
- **Objective:** Represent Series Seed 2 Preferred Stock as PreferredStock (8) / SeriesSeed2 (19), preserving all existing enum identities.
- **Repository / branch:** `MetaLex-Tech/cybercorps-contracts`, `codex/series-enum-expansion`, targeting `develop`.
- **Verified base / code head:** Base `a57b99b3102b65fae8da8c8b3f969b66a5a2e18b`; tested implementation `28d78a67b7fd64132fea6fd97f51cf3a1b641ed1`. This handoff adds documentation only.
- **Worktree locator:** Isolated checkout of the pushed branch; do not switch another task's checkout.
- **PR:** [Contracts #176](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/176).
- **Canonical release scope:** [Direct issuance release](../../../docs/series-enum-release.md); [exact catalog](../../../test/res/series-catalog.json).
- **App integration and overall plan:** [Webapp #1666](https://github.com/MetaLex-Tech/metalex-webapp/pull/1666), branch `codex/series-naming-comparison`, `notes/ai/tasks/series-naming-plan.md` and `notes/plans/series-naming-decision-20261011.md`.

## Acceptance and current state

The source adds 74 values after the unchanged values 0–9. It implements all 84 JSON identifiers and the added human-readable SVG names. Direct creation and assignment tests cover Seed 2 and representative family boundaries. No storage fields, signature schemas or authorization rules change.

Implementation and PRs were approved on 2026-10-13. Merge, deployment, company upgrades, live issuance and voiding are not authorized by that approval. The deployment plan identifies issuance/LET dependencies, compatible renderers, factory references and separate company acceptance. Source/runtime equivalence and the actual deployment manifest remain unverified.

The app PR prepares readers and exports; it does not complete Release 1. Direct-write enablement, restrictions on deferred workflows and actual cap table integration remain open. New-code writes must stay closed until their deployed dependencies are verified. Existing preferred LET replacements require a reconciled holding list and separate live-operation approval; existing common/scrip holdings remain outside that replacement scope.

## Validation

All results below cover implementation `28d78a67b7fd64132fea6fd97f51cf3a1b641ed1`.

| Check | Result and limitation |
| --- | --- |
| `forge test --match-path test/SeriesEnumExpansion.t.sol -vv` | 35 pass, including inherited regression cases; catalog, renderer, direct assignment and unauthorized creation covered. |
| Selected existing URI/JSON/issuance/metadata/scrip-void suites | 31 pass; some issuance cases overlap the preceding suite. |
| `forge build --sizes --skip test script` | Pass; LET 24,288 bytes, leaving 288 bytes of EIP-170 headroom. |
| [GitHub CI run 38451107624](https://github.com/MetaLex-Tech/cybercorps-contracts/actions/runs/38451107624) | Build sizes, unit tests and existing fork tests passed, observed 2026-10-13. |
| Deployed runtime, company acceptance and app results | Pending; source tests and CI do not establish live support. |

## Review and boundaries

Codex owns review and resolution for contracts #176 and webapp #1666. The existing current-chat monitor is `review-series-enum-prs`; reuse its event and finding state rather than creating another owner or baseline. The PR threads are the shared review evidence. Automated Codex review of `28d78a6` completed with one finding: add this missing task record and its CURRENT-STATE pointer. This documentation change addresses that finding; the reply and resolution follow the pushed commit.

Webapp #1662 and `claude/series-name-labels` remain separately owned and must not be modified. MetaLeX's Series Seed 2 cyberRaise is Phase 2. Formation, secondary sales, scrip/conversion, general imports and other-issuer enablement remain later work. Arbitrary designation records and class-registry redesign are outside this approved implementation.

## Next action and handoff

Continue the existing review loop, then complete the scoped webapp direct-write path and deferred-workflow restrictions. Before any separately authorized deployment, identify the matching release source and actual dependency addresses. Report implementation, independent review, merge, deployment and live acceptance separately. Ownership remains with the current Codex task.
