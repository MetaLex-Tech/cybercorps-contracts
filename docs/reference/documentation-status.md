---
description: Dated source revisions, prior documentation updates, changes covered and verification limits
---

# Documentation status and source review

Reviewed on **October 27, 2026**. This book is maintained in `docs/`, with
GitBook navigation and redirects in `.gitbook.yaml`. The repository has no
GitHub Pages build workflow. Publication of this update must be checked
separately after its documentation PR merges.

## When the documentation last changed

The last book-wide review and reorganization merged on **October 2, 2026**:
[PR #163](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/163) and
[PR #164](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/164).
The last commit touching `docs/` before this update was **October 19, 2026**,
[`a8bdbae`](https://github.com/MetaLex-Tech/cybercorps-contracts/commit/a8bdbae),
covering the SAFO enum and v1.1 publication status.

Intervening focused updates covered v4 scrip and v3 ticket compatibility,
officer management and upgrade guards, Reg D/S selection, register wording,
cap table menus, certificate rendering, Tokenization Hub navigation and
published legal templates. They did not refresh the complete app guides.
This review compares the October 2 baseline with the inspected revisions,
including changes already covered by those smaller updates.

## Inspected revisions

| Source | Revision | What it establishes |
| --- | --- | --- |
| Contracts `develop` | [`03651994c03bf2b2ff9f8af655caee51eed7de89`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/03651994c03bf2b2ff9f8af655caee51eed7de89) | Current source, tests, templates and deployment records at fetch time. |
| Webapp `develop` | [`3ad76d665b6df9fe084db8a883e135ad7cf4425b`](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b) | Current application behavior in source, including the advanced-raise follow-up. |
| Webapp `production` | [`f5f620eee4d994372c4f7ecaaf52fa0b28f16a4a`](https://github.com/MetaLex-Tech/metalex-webapp/tree/f5f620eee4d994372c4f7ecaaf52fa0b28f16a4a) | Production-branch comparison; this review did not independently verify its deployed build or aliases. |

A merge, deployment, enabled feature and successful user transaction are
separate facts. The guides describe implemented workflows and name known
availability limits. They do not certify every issuer, network or hosted
configuration.

## Changes covered by this review

| Area | Changes since the broad October 2 review | Source evidence |
| --- | --- | --- |
| Registry | Creator-bound template/agreement ids, unsigned and create-and-sign methods, unchanged direct signing and ordinary ids, JSON rendering moved into `CyberAgreementJson`. | [Registry source](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/CyberAgreementRegistry.sol), contract PR #185. |
| Passport finalization | Exact-party gates, optional passport pins, proof binding, relay methods and finalization after signatures and evidence. | [Finalizer source](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/ZKPassportFinalizer.sol), contract PR #186. |
| Instruments and rendering | Membership Interest 13, SAFO 14 and extension schema; expanded image tuple, issuer footer and series names. | [Constants](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/CyberCorpConstants.sol), [URI builder](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/CertificateUriBuilder.sol), [SAFO extension](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/03651994c03bf2b2ff9f8af655caee51eed7de89/src/storage/extensions/SAFOExtension.sol). |
| cyberSign | Managed private/public requests, email signing and delivery, offchain and mixed execution, company ownership, delegation guards and completion evidence. | [Creation UI](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/web/src/app/%28frame-layout%29/cybersign/create/_components), [shared signing package](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/packages/document-signing/src), app PRs #1847, #1852, #2007 and #2010. |
| Formation | Browser draft autosave, optional offchain company records, packet preparation, grouped invitations, signed revisions and issuance links. | [Formation source](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/cybercorps-web/src/features/entityFormation), [packet source](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/cybercorps-web/src/features/postFormation), app PRs #1961, #1966, #1969, #1973 and #1975. |
| Cap table and LETs | Current labels, legal-identity setup, signing-officer attribution, historical contract associations, packet approval and issue-date checks. | [Cap table UI](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/cybercorps-web/src/app/%28frame-layout%29/cybercorps/captable/_components), app PRs #1918, #1925, #1986 and #2009. |
| Fundraising | Native membership templates and separate economic Units preparation; current development-only advanced document workflow; SAFO launch pause. | [Membership source](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/cybercorps-web/src/features/membershipUnits), [advanced setup](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b/apps/cybercorps-web/src/features/advancedRaise), app PRs #1833, #2020, #2044 and #2052. |

The source diff also covered the company, issuance, deal, round, escrow,
authorization, factories and upgrade components. Their unchanged protocol
implementations retain the existing references. A new company can use newer
factory references while an older company retains its own component versions;
applications must select behavior from the targeted instance.

## Availability and verification limits

- **Advanced-raise preparation:** present in the inspected development source;
  absent from the inspected production tree. Its guide section is labeled
  accordingly.
- **SAFO:** source and published legal packets exist; new app launches remain
  paused and preview-only. Partial deployment evidence does not establish
  an enabled issuer configuration.
- **Email delivery and sponsorship:** implemented, but enabled separately by
  request family and environment. This pass sent no invitations and changed
  no configuration.
- **Registry runtime:** Base and Arbitrum implementation slots and public
  getters were read successfully. Ethereum RPC reads failed. Exact results
  and limits are in [Deployments](deployments.md#registry-checks-on-october-27-2026).
- **Other deployments:** existing address tables remain a dated record. This
  pass did not revalidate every factory, extension, condition or issuer.
- **Validation:** source/API comparison, navigation, local link targets and
  Markdown checks apply to this documentation change. No new contract tests,
  app acceptance, live signing or transactions were performed.

After a docs merge to `develop`, the repository's `Notify GAIBE of docs
changes` workflow requests a webapp knowledge refresh. That produces a
separate webapp PR; its merge and deployment remain separate from publishing
this book.
