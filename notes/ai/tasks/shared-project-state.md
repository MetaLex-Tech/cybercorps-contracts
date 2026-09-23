# Shared project-state setup

- Status: Implementation complete; ready for review, pending merge.
- Updated: 2026-09-23.
- Owner: Codex task `01a0cd4d-53e5-7352-b278-45061e80e335`.
- Repository: MetaLex-Tech/cybercorps-contracts.
- Branch: `codex/shared-project-state`, targeting `develop`.
- Base: `643540cf7d1c6d2dd5ea8c96a22502ead5458cd9`.
- PR: [#160](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/160), ready for review against develop.
- Content commit: `d2c36f7`; later bookkeeping changes only documentation.
- Objective: Shared continuity for Codex, Claude Code and human handoffs.
- Scope: Root agent instructions and `notes/ai` only.
- Decision: [Portable project state](../DECISIONS.md).

## Acceptance and validation

Both agent entry points route to one shared procedure. Canonical plans remain
unchanged; dated plan claims are explicitly not current verification. Task records
capture scope, ownership, revisions, evidence, blockers and next action.

Verified 25 relative links, both entry-point routes, staged Git whitespace and
the actual documentation diff at content commit `d2c36f7`. No contract/runtime tests are applicable to this documentation
change. Live application startup has not been exercised. No external audit,
integration acceptance or deployment status is established by this setup.

## Activation and next action

Maintain the standard PR review loop; after authorized merge, incorporate the
change into other checkouts before their next substantive work.
The workflow applies on this branch; other checkouts must deliberately incorporate
it after merge. Existing sessions must read the entry point once. Git worktrees
and browser chat uploads do not automatically synchronize. No merge is authorized.
