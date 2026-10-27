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
- PR: not yet created. No merge or auto-merge authorization.

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
- Publication, GAIBE import and deployment: not performed.

## Next action

Finish documentation validation, open a ready PR against contracts `develop`,
and start a persisted review-and-fix heartbeat under the owner's standing
instructions. Initial full sweep must include conversation comments, complete
review bodies, inline threads and any applicable existing audit findings.
Do not start an audit or alter another task's ledger. After merge/closure,
perform the final sweep and retire the monitor; check publication/GAIBE
workflow evidence without merging or deploying the webapp on inference.
