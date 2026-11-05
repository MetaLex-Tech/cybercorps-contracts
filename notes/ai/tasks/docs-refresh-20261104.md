# Task: November 4 GitBook and public documentation refresh

- Status: Drafted; validation, independent review and publication pending.
- Updated: November 4, 2026 (America/Bogota).
- Owner: Codex, current documentation survey chat.
- Scope: Public docs and this shared task record only. No contract, app,
  template bytes, deployment configuration or live signing changes.
- Branch: `codex/docs-refresh-20261104`; contracts base
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

Pending documentation checks and independent review. Read-only RPC calls
returned the evidence type/domain on Base, Arbitrum and Robinhood; Ethereum
publicnode failed. Public deployment note lists exact observed blocks and
implementations and distinguishes latest-state reads from pinned acceptance.
No contract tests, app typechecks or user transactions are necessary for
this prose-only patch; none are claimed.

## Next action

Validate local links and source claims, obtain independent review, open a
ready documentation PR and establish its recurring review/fix monitor.
After checks/review, publish the docs and verify the public pages contain
the new date and substantive sections. Track GAIBE refresh separately.
