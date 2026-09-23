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
