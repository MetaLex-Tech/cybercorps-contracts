# Task: November 4 GitBook and public documentation refresh

- Status: Complete. Documentation merged and public publication verified.
- Updated: November 4, 2026 (America/Bogota).
- Owner: Codex, current documentation survey chat.
- Scope: Public docs and this shared task record only. No contract, app,
  template bytes, deployment configuration or live signing changes.
- Implementation branch: `codex/docs-refresh-20261104`; final publication
  evidence branch: `codex/docs-refresh-20261104-publication-evidence`. Contracts base
  `caa83643b09806d5e0036e627e7cd14cd02a3b23`.
- Evidence: webapp production `4ef010e5c58cc10eae16cdf395a0134a3b9ba84d`,
  develop `f441c30de6324ee57586279563f0c55ac97bdc77`; prior review
  `3ad76d665b6df9fe084db8a883e135ad7cf4425b`.
- Canonical survey: [Documentation status](../../../docs/reference/documentation-status.md).
- Existing implementation/release/audit owners retained. Isolated worktrees
  preserve unrelated local changes.

## Acceptance and decisions

The public welcome page still showed October 27; #188 / `0a598592` was the
last docs change. Read all subsequent contract source changes and the
application commit survey, then inspected affected current callers and task
records. Updated user guides and references; kept old finalizer identity as
a historical page, source-only round reuse and hosted enablement unknowns.
User request includes updating the public docs and verifying publication;
no application promotion or contract merge/deployment is inferred.

Related audit history checked read-only: Hexens July–August 2026 final
report, original MTLX1-39 **Medium**, Acknowledged (standalone expiry);
MTLX1-30 **Low**, Acknowledged (permissionless agreement creation);
MTLX1-33 **Medium**, Acknowledged (fundraising passport dev mode);
MTLX1-26 **Low**, Fixed (round authorization through weaker factories);
MTLX1-41 **High**, Fixed (CREATE2 deployment authorization).
Also read creator-bound signer-condition and #185 deployment-script records,
current creation/signature/round validation source, and webapp release/V12
records for touched user flows. This is documentation reconciliation, not a
new vulnerability assessment or revalidation of every audit fix onchain.
No audit disposition was reopened, changed or declared newly resolved.

## Validation and review

PR [#195](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/195)
is ready against develop. First content checkpoint `dd103acade81f3df50067d39273ba36a7f4d5f0c`.
Documentation checks passed: 71 Markdown pages, 665 local targets/anchors,
54 YAML frontmatter blocks, code fences and GitBook hint pairs; zero errors.
`git diff --check` passed. A dry run of the current production GAIBE
importer wrote all five sections, imported 70 content pages (SUMMARY is
navigation), and emitted no warning or skipped section. Output stayed in a
task artifact directory; no app knowledge or configuration was changed.
Both GitBook preview contexts passed with revision `UjPtiQsh9GhcVazUzQXG`.
GitHub Codex review of `dd103ac` completed with no findings. Separate Claude
CLI read-only review found three material docs corrections: current public
open slots retain standalone creation; an unchanged creation paragraph
contradicted that routing; the current app refuses retired-finalizer
requests and requires a new request. All were verified against the current
create form and email-signing loader and corrected. Other scoped API, ENS,
network, membership, agentic and welcome-link claims passed that review.
A separate focused follow-up review verified all corrections and the two
UI/namespace clarifications, with no remaining material findings. Final
content `451519127a1d1323bd75bbba70608dff3764dcce` passed both GitBook
checks, Build sizes, Unit tests and Fork tests in run
[41964064936](https://github.com/MetaLex-Tech/cybercorps-contracts/actions/runs/41964064936).
Current-head GitHub Codex review completed without findings.

The full initial review sweep read conversation comments, complete review
bodies and inline threads; no findings or V12 activity were present.
Heartbeat `review-public-docs-pr-195` was created, rendered and its saved
configuration verified ACTIVE every two minutes in this chat. Its
append-only baseline and V12/finding state live under the persistent
`pr-monitor-state/cybercorps-contracts-195` task directory. Reuse that state.

Read-only RPC calls
returned the evidence type/domain on Base, Arbitrum and Robinhood; Ethereum
publicnode failed. Public deployment note lists exact observed blocks and
implementations and distinguishes latest-state reads from pinned acceptance.
No contract tests, app typechecks or user transactions are necessary for
this prose-only patch; none are claimed.

## Publication and closeout

PR #195 squash-merged to develop as
`8789081be696cc334f9b7b193b3c3eba17c8122b` on November 4, 2026,
23:00 America/Bogota. The public homepage initially retained October 27,
then updated after GitBook synchronization. Browser checks used normal
public URLs, with no `/~/revisions/` preview path:

- Homepage: November 4 review date and Robinhood/network wording.
- [Survey](https://docs.metalex.tech/building-on-the-protocol/reference/documentation-status):
  new date, source revisions and changes since October 27.
- [Agentic guide](https://docs.metalex.tech/using-the-apps/agentic-transactions):
  new page, human authorization, scopes and enablement limit.
- [Signer conditions](https://docs.metalex.tech/building-on-the-protocol/reference/contracts/signerconditions):
  conditioned creation and evidence-signature APIs.
- [cyberSign](https://docs.metalex.tech/using-the-apps/cybersign):
  open-slot routing and retired-finalizer refusal corrections.

Saved public-page text and a survey screenshot in the task artifact directory.
Final post-merge full review sweep succeeded: no inline threads, complete
review-body findings, V12 runs or outstanding dispositions. The heartbeat
was deleted through the app after this terminal sweep; event/V12 state is
retained. No recurring review loop remains necessary for this closed PR.

The docs notification workflow succeeded and created webapp
[GAIBE refresh #2283](https://github.com/MetaLex-Tech/metalex-webapp/pull/2283).
That application PR and its deployment are separate; this docs task did not
take its ownership, merge it or release the webapp.

## Next action

No documentation task remains. The publication evidence is on this record's
named evidence branch and on PR #195. Future source changes need their own
fresh comparison; this dated review does not claim ongoing product coverage.
