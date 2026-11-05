---
description: November 4 change survey, inspected revisions, prior publication baseline and verification limits
---

# Documentation status and source review

Reviewed on **November 4, 2026** (America/Bogota). The source for this
GitBook is `docs/` in `MetaLex-Tech/cybercorps-contracts`, with navigation
and redirects in `.gitbook.yaml`. `docs.metalex.tech` is the published book;
there is no separate GitHub Pages build in this repository.

## Baseline and scope

The public welcome page showed **October 27, 2026** when this pass began.
Its source was the broad refresh in
[PR #188](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/188),
merged as `0a598592`. No later `docs/` change was present on the fetched
contracts `develop` branch. The earlier broad reorganization was October 2
(PRs #163/#164); focused updates continued through October 19 before #188.

This survey reads the contract changes after #188 and the application
changes after the October 27 reviewed development revision. It compares the
current production tree as well, so a feature formerly labeled
development-only is not left there after release. Internal tests, CI,
formatting and security hardening with no new user workflow were grouped
with their affected feature rather than presented as product launches.

## Inspected revisions

| Source | Exact revision | Meaning |
| --- | --- | --- |
| Contracts `develop` | [`caa83643b09806d5e0036e627e7cd14cd02a3b23`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/caa83643b09806d5e0036e627e7cd14cd02a3b23) | Current source, including registry signer conditions and round reuse. |
| Webapp `production` | [`4ef010e5c58cc10eae16cdf395a0134a3b9ba84d`](https://github.com/MetaLex-Tech/metalex-webapp/tree/4ef010e5c58cc10eae16cdf395a0134a3b9ba84d) | Guide comparison through welcome links and current legal-terms changes. |
| Webapp `develop` | [`f441c30de6324ee57586279563f0c55ac97bdc77`](https://github.com/MetaLex-Tech/metalex-webapp/tree/f441c30de6324ee57586279563f0c55ac97bdc77) | Comparison for development-only work; not proof of deployment. |
| Prior webapp review | [`3ad76d665b6df9fe084db8a883e135ad7cf4425b`](https://github.com/MetaLex-Tech/metalex-webapp/tree/3ad76d665b6df9fe084db8a883e135ad7cf4425b) | Starting point for the application change survey. |

A source merge, deployment, enabled setting and successful user operation
remain separate facts. Release task records supplied deployment context;
this documentation pass did not deploy or transact through the apps.

## Changes since October 27

| Area | Documentation change | Source anchors |
| --- | --- | --- |
| Agreement registry | New conditioned bound-id domain, evidence-bound signature type, per-party requirements and configuration. Historical finalizer page retained with its removal notice. | Contracts [#189](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/189), [registry](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/caa83643b09806d5e0036e627e7cd14cd02a3b23/src/CyberAgreementRegistry.sol), [signer conditions guide](contracts/SignerConditions.md). |
| Rounds | `createRoundWithPrinters`, registration/manager and duplicate checks; explicitly source-only until actual runtime and caller support are established. | Contracts [#192](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/192), [RoundManager](contracts/RoundManager.md#reuse-existing-let-contracts). |
| cyberSign | Creator-bound creation for new supported requests, evidence signing and preserved historical ids. | App [#2100](https://github.com/MetaLex-Tech/metalex-webapp/pull/2100), [guide](../webapp/cybersign.md). |
| ENS identity | Formation opt-out, authority-approved existing-company claims, background progress, operator control, eligibility and public-document publication. | App [#2068](https://github.com/MetaLex-Tech/metalex-webapp/pull/2068), [#2168](https://github.com/MetaLex-Tech/metalex-webapp/pull/2168), [company guide](../webapp/company.md#company-ens-identity-and-public-documents). |
| Cap table | File-drop preview, duplicate stakeholder grouping, separate drafts, tokenized quantities/LET links, reviewed identity/terms, replacement provenance and interrupted-send recovery. | App #2095, #2098, #2101, #2123, #2125, #2126, #2240, #2244 and #2245; [cap table guide](../webapp/captable.md). |
| Legal terms and plans | Reusable/inherited share terms, approval followed by activation, version ordering and backdated replacement; declare a stock plan's class from its reserve LET. | App #2156, #2210, #2251, #2261, #2272 and #2274; [terms](../webapp/captable.md#legal-classes-series-and-versioned-terms), [plans](../webapp/grants.md#declare-a-stock-plans-underlying-class). |
| Stakeholders | Welcome links for wallets already linked, claim-only wallet-control timestamps and retained invitation expiry/revocation. | App [#2276](https://github.com/MetaLex-Tech/metalex-webapp/pull/2276), [invitations](../webapp/captable.md#invite-a-stakeholder-to-the-holder-portal). |
| Advanced raises and membership | Advanced PDF/issuer setup moved into the production-source description; v1.2 governance paper distinguished from prior signed identities and economic Units. | App #2052 and #2250; [raise guide](../webapp/cyberraise.md#explore-advanced-raises-and-custom-documents). |
| Investment recovery | Retained EOI/allocation attempts across reloads, unknown-outcome holds, live economics and eligibility checks. | App #2082, #2085, #2087, #2193 and #2213; [recovery guide](../webapp/cyberraise.md#recover-an-interrupted-investment). |
| Agentic transactions | New guide for private revisions, human authorization, wallet/server/Safe steps, partial completion, recovery and MCP scopes. Hosted switch not independently read. | App #2249, #2256, #2257, #2267 and #2269; [guide](../webapp/agentic-transactions.md). |
| Networks | Robinhood Chain 4663, USDG and per-workflow exclusions. | App [#2217](https://github.com/MetaLex-Tech/metalex-webapp/pull/2217), [availability](../webapp/README.md#network-availability). |
| Formation and document access | Correction/cost review, backup names, publication consent and document gateways; no change to execution or authority implied by a URL. | App #2056, #2060, #2157, #2223 and #2232; [formation guide](../webapp/formation.md#correct-formation-details-and-names). |

## Verification and remaining limits

- The public book baseline and current repository history were checked.
  Link/navigation, headings, frontmatter, fences and GitBook hint checks
  apply to this docs change. Publication must be checked after merge.
- New read-only registry implementation/getter evidence is recorded in
  [Deployments](deployments.md#registry-checks-on-november-4-2026). Ethereum
  RPC failed; verifier configuration and a target company's components were
  not checked. The older deployment tables remain explicitly historical.
- Agentic transactions require `AGENTIC_TRANSACTIONS_ENABLED`; its hosted
  value was not read. Source coverage is not a live catalog guarantee.
- SAFO remains paused/preview-only. New source, legal paper, partial
  deployment or a registry getter does not lift that hold.
- No live signing, invitation delivery, legal approval, company adoption,
  protocol change, factory upgrade or hosted configuration change occurred.
  Existing owners and audit dispositions remain unchanged.

The docs-change workflow requests a separate GAIBE knowledge-refresh PR in
the webapp repository. Publishing this book does not merge or deploy that
application PR.
