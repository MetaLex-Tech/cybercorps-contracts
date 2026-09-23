# Shared project-state setup

- Status: Implementation prepared; review and merge pending.
- Updated: 2026-09-23.
- Owner: Codex task `01a0cd4d-53e5-7352-b278-45061e80e335`.
- Repository: MetaLex-Tech/cybercorps-contracts.
- Branch: `codex/shared-project-state`, targeting `develop`.
- Base: `643540cf7d1c6d2dd5ea8c96a22502ead5458cd9`.
- Objective: Shared continuity for Codex, Claude Code and human handoffs.
- Scope: Root agent instructions and `notes/ai` only.
- Decision: [Portable project state](../DECISIONS.md).

## Acceptance and validation

Both agent entry points route to one shared procedure. Canonical plans remain
unchanged; dated plan claims are explicitly not current verification. Task records
capture scope, ownership, revisions, evidence, blockers and next action.

Check relative links, entry-point routing, Git whitespace and the actual diff
before publishing. No contract/runtime tests are applicable to this documentation
change. Live application startup has not been exercised. No external audit,
integration acceptance or deployment status is established by this setup.

## Activation and next action

Open the scoped PR, maintain its standard review loop and record the PR link here.
The workflow applies on this branch; other checkouts must deliberately incorporate
it after merge. Existing sessions must read the entry point once. Git worktrees
and browser chat uploads do not automatically synchronize. No merge is authorized.
