# Current project orientation

Snapshot: 2026-09-23, `develop` at `643540cf7d1c6d2dd5ea8c96a22502ead5458cd9`.
This is a navigation snapshot, not an audited portfolio or release status report.

## Canonical sources

- [Repository overview](../../README.md) and [protocol docs](../../docs/README.md).
- [Protocol improvement plan](../plans/protocol-improvement-plan.md).
- [Issuer award templates](../plans/issuer-award-templates-plan.md).
- [Control-agreement encumbrance specification](../plans/control-agreement-encumbrance-spec.md).
- [Additional specifications](../../specs/) and [tests](../../test/).

The three plan headers contain July 2026 status assertions. They were read for
orientation, not revalidated against September code or deployed contracts. Do not
repeat their shipped/proposed claims as current facts without checking evidence.
No `notes/plans/README.md` index exists at this base revision; another branch may
have one. Do not assume another checkout's files are present here.

## Shared tasks

- [Robinhood final v5 synchronization/preparation](tasks/robinhood-final-v5-20261030.md): October 30 merge of develop `7ce4e1c` into the Robinhood branch; user chose existing shared kill switch. 98 selected checks passed, including full final-stage fork rehearsal; live release/review/signing gates remain separate.

- [Robinhood intermediate deployment setup](tasks/robinhood-intermediate-20261028.md): October 28 operator deployment of 32 historical targets confirmed by RPC. Explorer source available: 22 Exact Match, 10 Similar Match. Separate 14-call Safe batch execution unconfirmed; colleague owns badge/secondary deployment on 4663; final-stage handoff/review/integration gates pending.

- [Protocol and webapp documentation refresh](tasks/docs-protocol-webapp-20261027.md): October 27 source comparison and GitBook guide/reference updates; documentation only, review pending.

- [PR #185 deployment scripts and Safe exports](tasks/pr185-deployment-scripts.md): linked registry deployment/export preparation, 2026-10-23; local tests and toy-key rehearsal passed, no live deployment.
- [Signer conditions on creator-bound agreements](tasks/creator-bound-signer-conditions.md): per-party conditions with evidence signed in the registry (ZKPassport first), 2026-10-27; unit and registry fork suites pass, uncommitted, no deployment.
- [SAFO Reg D/S rollout](tasks/safo-integration.md): October 18 owner-approved coordinated rollout; Claude review waived; Base Sepolia fork acceptance passed, live signer/quorum and remaining release checks pending.
- [Shared-state setup](tasks/shared-project-state.md): this documentation change.
- [GitBook register paragraph and LeXcheXBadge deployment claims](tasks/gitbook-register-and-badge-corrections.md): docs-only correction, 2026-10-04.
- [LET certificate footer names the issuing company](tasks/let-footer-issuer-name.md): renderer change, 2026-10-11.
- [LET footer all-chain upgrade scripts](tasks/let-footer-all-chain-upgrade.md): script preparation and validation, 2026-10-12; no live deployment.

This seed is not a complete inventory of ongoing tasks. Existing work, PR owners,
review monitors and audit ledgers retain ownership. No protocol task is reassigned
by this setup. Add verified pointers when resuming authorized work.
