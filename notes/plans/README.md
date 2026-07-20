# Protocol plans

Status index audited against `develop` on 2026-07-19.

| Document | Status | What remains |
| --- | --- | --- |
| [protocol-improvement-plan.md](protocol-improvement-plan.md) | Active roadmap | P1's forward-deployment Board/officer authority target, root action matrix, and matching boardRoom integration; external-controller P2 canonical terms/cap enforcement; and P3 registry hardening are implemented locally and unreleased. P2 replaced an undeployable in-printer prototype and now passes the production size gate. All 25 non-fork Foundry test files pass individually, and P1 pinned fork acceptance passes (47 CyberCorp + 36 PumpCorp + 25 ParentCo tests); policy approval, target-block dry run, fresh-corp route acceptance, and authenticated hosted acceptance remain. P2/P3 need coordinated demo/pilot rollout. A stockholder-voting adapter is pilot-conditional. P4 CAL is proposed. |
| [p1-board-authority-rollout-runbook.md](p1-board-authority-rollout-runbook.md) | Ready; execution open | Forward-only cutover through a separate v5 single factory, per-route atomic implementation/pointer pairing, selective real-corp disposition, contract/webapp acceptance, stop conditions, and rollback. The legacy single factory/reference and every existing corp remain unchanged. |
| [issuer-award-templates-plan.md](issuer-award-templates-plan.md) | Target implemented locally; rollout open | The live proxy still has the interim permissionless caller-chosen path. Local contracts restore the owner-only curated path, add idempotent content-addressed `createTemplatePublic`, reject empty legal URIs, and pass the focused 18-test suite including proxy state preservation; the webapp call site and ABI are updated locally. Deploy/upgrade and runtime verification remain. |
| [p2-p3-rollout-runbook.md](p2-p3-rollout-runbook.md) | Ready; execution open | Renderer/controller/registry deployment, IssuanceManager reference, atomic per-corp manager upgrade plus printer migration, webapp release, acceptance, and rollback. No CyberCertPrinter beacon upgrade; test-corp migration is not a release gate. |
| [control-agreement-encumbrance-spec.md](control-agreement-encumbrance-spec.md) | Proposed / unbuilt (P4) | Implement lien storage/lifecycle, collateral guards, foreclosure, agreement/condition checks, upgrade/deploy path, indexer/web surface, and adversarial Foundry tests. |

Cross-repo app status lives in
`metalex-webapp/notes/plans/README.md`. In particular, webapp #815’s
director/board-consent UI now consumes the local P1 target when enforcement is
detected and retains the title-derived model only as a labeled legacy fallback.
Neither the contracts nor that app branch are deployed yet.
