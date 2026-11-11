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

- [Robinhood four-chain address parity](tasks/robinhood-address-parity-20261101.md): November 1 live snapshots confirm all 13 critical auth/proxy addresses, 16 shared extension addresses and 19 current secondary-condition addresses match on Robinhood, Base, Ethereum and Arbitrum; 68/68 sampled wiring checks pass. Implementation addresses/payment settings differ; checklist historical/Base-only exceptions documented. Read-only checker, public evidence and interactive canvas prepared; no transactions.

- [Robinhood LET verification](tasks/robinhood-let-verification-20261101.md): November 1 shared LET implementation `0x487Ed0…7920` and storage library exactly match freshly recompiled checkout code, including metadata; factory reference confirmed. User explicitly approved source publication; both Etherscan submissions passed and follow-up lookup confirms exact verified source. No blockchain transactions sent.

- [One-cent on-chain SAFE rehearsal preparation](tasks/robinhood-onchain-safe-rehearsal-20261030.md): November 1 simplification makes all `SAFE_*` settings optional, with saved dates/budget, live quote +5% cap and clear test metadata. Existing RPC/officer key plus distinct investor key suffice. 16 configuration/real-route fork checks pass, including default-only company/SAFE round/investor LET delivery. No live transactions or operator-key use by this task.

- [Robinhood live-template acceptance](tasks/robinhood-live-template-acceptance-20261030.md): fresh block 102202000 confirms 86/86 exact deployed templates and unchanged legacy ID 1. All 3 fixture-free lifecycle checks pass: company/SAFE round, signed USDG investment, allocation/finalized investor SAFE LET, rendering and refusal/refund paths. No live submissions or deployment-key use.

- [Base-to-Robinhood template synchronization](tasks/robinhood-base-template-sync-20261030.md): October 30 complete Base snapshot contains 87 definitions; deployment plan selects 86 missing IDs and preserves Robinhood's conflicting immutable legacy SAFE ID 1. 17 checks pass, including full fork import, exact matching/rerun and signed USDG SAFE LET issuance. Script/runbook ready; no live registrations.

- [Robinhood post-v5 acceptance](tasks/robinhood-post-v5-acceptance-20261030.md): October 30 user-reported final Safe execution; 23 resulting state checks pass against the 22-call operator batch. Critical addresses match Base. Deployed-code fork formation/SAFE issuance succeeds with a local copy of Base template 32, which is absent on Robinhood; production template registration remains. Robinhood 3 tests pass; Base control 2 pass, 1 expected skip. Local working-tree evidence; no live transactions.

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
