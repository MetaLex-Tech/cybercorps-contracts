# Agent instructions

## Shared project state

Before substantive work, read [notes/ai/START-HERE.md](notes/ai/START-HERE.md),
the relevant task record and canonical plan. Maintain shared records at meaningful
milestones and handoffs so Codex, Claude Code and humans can resume from the same
evidence. Do not create records for trivial questions or unchanged polling passes.
Read applicable local instructions when present. Current explicit user instructions
and existing task ownership, review and authorization requirements remain in force.

## Contract work and evidence

For changes affecting protocol correctness, authorization, signing, payments or
funds, establish invariants and concrete acceptance tests before implementation.
Preserve required independent external-model review and integration gates; an
internal review or handoff summary does not satisfy them. For substantive bugs,
require a behavioral regression where feasible and document missing reproduction.
Keep unit tests, integration acceptance, independent review, merge and deployment
status distinct. For transaction flows, preserve required test-environment
sign -> simulate -> submit coverage with explicit success/refusal cases.
These instructions grant no authority to merge, deploy, sign real transactions,
send private code to another service or start external audits.

## Past audits and audit responses

Before evaluating an issue, review or audit finding, or proposed fix, and before
writing or approving a plan, specification, upgrade or task record, find the past
audits and recorded audit responses that cover the affected contracts, storage,
libraries and flows. Audit history is evidence to weigh; it does not replace
verification against the current source and deployed implementation. Sources in
this repository: the external reports in [audits/](audits/), with each finding's
status (for example Fixed or Acknowledged) and remediation commit; the AI review
report at the repository root; the audit scope in [specs/analysis/](specs/analysis/);
audit-driven design notes such as
[proportional-scrip-vault-notes.md](proportional-scrip-vault-notes.md); the
`test/Audit*.t.sol` regressions; and audit fix commits and PRs in git history.
For behavior the webapp consumes, also check the sibling `../metalex-webapp` audit
records that cite contract behavior or record a finding as needing a contract
change (`notes/verification/`, `notes/audits/`, V12 task records in
`notes/ai/tasks/` and contract-boundary plans in `notes/plans/`).

Cite each related finding by its report, original ID and severity (for example a
Hexens `MTLX1-` ID) and its recorded response. Check that the response still holds
at the current revision and at the deployed implementation: a fix can regress, and
an upgrade, refactor or new entry point can revive a finding. An acknowledged
finding is an accepted residual risk, not a resolved one. Do not silently reopen,
contradict or design around an acknowledged, won't-fix or owner-decided
disposition, and do not re-raise a known finding as new; cite it, state the new
evidence and obtain an explicit decision. Do not reintroduce a pattern that an
audit flagged and that was fixed unless the plan records why it is now safe.
Plans, task records and finding dispositions list the related findings with their
recorded responses, or state that none were found and which sources were
searched. This check is read-only: it grants no authority to start an audit,
change an audit report or recorded response, or send private code to another
service.
