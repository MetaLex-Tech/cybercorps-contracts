# Task: protocol and webapp documentation refresh

- Status: Ready for review; source edits and local documentation checks complete.
- Updated: October 27, 2026 (America/Bogota).
- Owner: Codex, documentation-refresh chat.
- Objective: Compare the last GitBook updates with current contracts and webapp source, then conform the book to implemented behavior and explicit availability limits.
- Scope: `docs/`, this task record and its CURRENT-STATE pointer. No Solidity, application, template bytes, deployment, signing or hosted configuration changes.
- Branch: `codex/docs-protocol-webapp-20261027`, base contracts `develop` at `03651994c03bf2b2ff9f8af655caee51eed7de89`.
- Application evidence: fetched `develop` `3ad76d665b6df9fe084db8a883e135ad7cf4425b`; `production` `f5f620eee4d994372c4f7ecaaf52fa0b28f16a4a`.
- Canonical sources: [dated review](../../../docs/reference/documentation-status.md), exact source links there, webapp terminology guide and scoped task records read alongside current code.
- Ownership: existing implementation, release and audit owners remain unchanged. Unrelated dirty files in the original checkouts were left untouched; work uses isolated checkouts.
- PR: [#188](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/188),
  ready for review against `develop`. Content commit
  `c440d587717903a067c70849d61fc14d8ca30450`. No merge or auto-merge authorization.
- Monitor: `review-protocol-docs-pr-188`, this chat, five-minute heartbeat.
  Creation returned ACTIVE; app view and persisted TOML confirmed ACTIVE and
  the current thread binding. Event state: `pr188_seen.txt` in the task
  artifact directory. No other monitor ownership changed.

## Discovery and decisions

Last book-wide sweep/reorganization: October 2, PRs #163/#164. Last `docs/`
change: October 19, `a8bdbae`, SAFO enum/publication. Reviewed all intervening
contract source changes and webapp first-parent history; inspected current
callers and scoped records for material public features. The project uses
GitBook (`.gitbook.yaml`); no GitHub Pages workflow exists in the inspected
repository. Publishing the book is not established by editing its source.

The largest stale claims were cyberSign's onchain-only/no-email instructions,
disabled document preparation, formation's no-autosave/mandatory-cyberCORP
instructions, old LET UI labels, and missing creator-bound/passport APIs.
Preserved original agreement identities and supported legacy paths. Native
Membership Interest, CommonStock-based LLC compatibility and SAFO availability
are distinct. Advanced-raise development source is labeled separately from
production. Template specifications remain authoritative for approved paper.

## Runtime evidence

Read-only `cast` calls on October 27 returned the shared registry proxy's
implementation and bound-template/signature-type getters on Base (block
observed 53157679) and Arbitrum (518741765). Results are in the public
[deployment note](../../../docs/reference/deployments.md). Reads were latest
state calls, not pinned to one block. Ethereum failed via publicnode and
llamarpc with connection/TLS errors. Retained the app matrix as reported
historical evidence only. Other deployments were not re-probed.

## Acceptance and validation

- Updated relevant user guides and API references: implemented, review pending.
- Source/deployment/enablement distinction: implemented.
- Navigation, relative links and heading anchors: passed across 69 Markdown
  pages, with zero broken local targets or anchors. All three new pages are
  in SUMMARY. YAML frontmatter passed in 52 files; code fences and GitBook
  hint pairs passed throughout. `git diff --check` passed. Stale-claim search
  reviewed remaining no-email statements by their specific request family.
  New pages require explicit `git add -f` because the existing repository
  ignore rule ignores untracked `docs/` files.
- Independent external review: not performed; normal PR review pending.
- Contract/app tests and browser/live acceptance: not run, docs-only scope.
- GitBook preview checks: both SUCCESS on content commit `c440d58`, revision
  `kEcD84YEQHv2uOyIYrNO`; production publication and GAIBE import not performed.
- Initial full review sweep after baseline: no inline comments or review
  bodies; conversation contained only the automated review-running summary
  (comment 6442236792), with no actionable finding or audit attachment.
- Hosted CI at that sweep: Build sizes, Unit tests and Fork tests in progress.
  This record does not claim their success.

## Next action

The persisted heartbeat continues PR #188 review and scoped fixes. Inspect
conversation comments, complete review bodies, inline threads and any
applicable existing audit findings on each pass.
Do not start an audit or alter another task's ledger. After merge/closure,
perform the final sweep and retire the monitor; check publication/GAIBE
workflow evidence without merging or deploying the webapp on inference.


## CI diagnosis, October 27

At documentation head `80663877a4ec8d8e2c7ccd1ee89570957debec43`,
[CI run 40506700393](https://github.com/MetaLex-Tech/cybercorps-contracts/actions/runs/40506700393)
passed Build sizes and Fork tests; both GitBook preview contexts also passed.
Unit tests reported 1520 passing and five failures in
`DeployBoundAgreementRegistryScriptTest`. Each failure reaches
`vm.envUint("PRIVATE_KEY_MAIN")` in the existing deployment script without
that variable set. The exact base commit `03651994` has the same five
failures and totals in
[develop run 40257409633](https://github.com/MetaLex-Tech/cybercorps-contracts/actions/runs/40257409633).
The PR changes none of `src/`, `test/`, `script/`, `.github/` or
`foundry.toml` against that base.

This is a verified pre-existing unit-test failure, not a docs regression or
a passed check. No secrets were read or added. Script/test/CI changes remain
outside this documentation task. Do not repeat an unchanged failed job or
introduce a live deployment key as a workaround. Normal code review still
ran with no posted findings at this sweep. Keep the docs monitor active.
