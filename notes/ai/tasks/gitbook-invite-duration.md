# GitBook invitation duration correction

- **Updated:** 2026-11-10 (America/Bogota).
- **Owner:** Codex, the chat handling metalex-webapp PR #2470.
- **Scope:** Owner-authorized corrections to the issuer and holder GitBook guides. No contract, signing, deployment or application behavior changes.
- **Branch/base:** `codex/gitbook-invite-duration`, based on `238237a6f433cd5f9c74d7f9cc1e287b16348f29`.
- **Finding:** [webapp #2470 P2](https://github.com/MetaLex-Tech/metalex-webapp/pull/2470#discussion_r4521792312). The refresh imported stale fixed-14-day guidance over the configurable-duration documentation from webapp #2461.

## Verified changes

The invitation panel accepts 1–365 whole days and defaults to 14 for invite and welcome links. Existing links retain their expiry until rotated. GAIBE uses the default. Both guides now describe this behavior and holders are directed to the expiry shown for their link.

Validation covers the base above plus the two documentation edits: webapp importer tests passed (17 tests, 113 assertions), knowledge compilation passed, and a second import/build produced identical artifacts. The import changed only the webapp guide and its compiled knowledge. `git diff --check` passed. Independent read-only Claude review confirmed the behavior and artifact parity. Its Low wording suggestion was addressed: the default sentence now names invite links from agentic transactions, including GAIBE and MCP clients. No protocol tests were needed or run.

## Review and next action

Upstream [PR #197](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/197) is open. Heartbeat `review-gaibe-invite-documentation-prs` is verified persisted ACTIVE, every 30 minutes, in the same owning chat as webapp #2470. The initial full sweep found no actionable findings; Codex review on `c93e01cd922257033233e16c813c160b23060161` completed without findings. Final wording clarification and this record follow that revision. Preserve existing audit owners; no new audit was started. Review all PR surfaces, address scoped findings, and verify checks before merge. Source changes are not yet on upstream develop or the published GitBook. The automated webapp refresh reads upstream develop, so the correction must land there to survive future refreshes.
