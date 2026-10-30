# Structured rounds using an existing stock printer

Owner: this Codex implementation chat. Authorized 2026-10-30 after design and deployed-size assessment. Branch: codex/structured-round-printer-reuse in both repositories. No merge, deployment, factory update, company upgrade or live signing authorization.

## Scope and invariants

One existing classified Common/Preferred printer per new structured round. Preserve createRound, existing round IDs/signature schema, storage layout, allocation/refund/escrow lifecycle and supported older frontend flows. New entrypoint checks recognized printer, issuer manager, native class/type/series, and a creation-time configuration commitment; new domain-tagged ID binds normalized complete round inputs and configuration. Existing officer signature covers this ID. No printer creation, no mutation of previous certificates, no global authorized-share ledger or freeze of later owner-authorized printer updates.

Frontend must select exact activated legal class/series through existing server approval adapter, revalidate terms/runtime before and after signing and immediately before send, reject unknown/missing capability, and invalidate held signatures after input/identity/runtime changes. No fallback to a new printer when reuse was requested.

## Discovery

Inspected CyberCorp ownership/managers, RoundManager admission/allocation, linked LexScrow escrow/refunds, registry agreement lifecycle/signature handling, IssuanceManager printer/mint/class registry, LET/ShareExtension data, DealManager individual ticket path and factory upgrades. Existing createRound unconditionally creates printers. DealManager can reuse printers for tickets but does not replace shared structured-round lifecycle. RoundManager upgrades require owner plus factory-approved implementation. New capability is not deployed.

Read-only deployed comparison at Ethereum block 26308806: RoundManager runtime 20,727 bytes, linked library 18,589. Local prior source artifacts differed in enum-validation bounds; not an exact reproducible deployed build. Current contract feature base is 7ce4e1c825998de5cf309e620d1e9d8e0d1b543d. First prototype compile: manager 20,733, library 22,445; both under 24,576. Recheck after final changes.

## Acceptance

Behavioral create/sign/allocate to same printer; preserve old token IDs/details; wrong issuer/class/series, stale configuration, changed signed terms, old/replayed signature, unauthorized caller and unsupported runtime refuse. Test cap, rejection/refund and old createRound regressions. Fork sign/simulate/submit on applicable runtime plus independent external-model review required before sign-off. Test results still in progress; no acceptance claim yet. Independent reviews launched in separate local Claude processes; not external audit services. Do not duplicate live reviewers.

## Current state

Implementation prepared for review; no deployment. Current dirty-tree checks: 19 contract success/refusal/legacy lifecycle tests pass; 152 frontend matching/adapter/signing/version tests pass; app TypeScript passes. Browser computes the same ID as an actual Solidity preview vector. Final runtime sizes after review fixes: RoundManager 20,733; linked RoundManagerStorage 23,562 (1,014 bytes remaining). An initial fork upgrade/create/mint reached delivery, then reverted because the widely used test investor key already had mainnet contract code; changed the fixture to a fresh synthetic EOA and rerunning. No failure attributed to production code from that fixture issue. Fork transaction acceptance remains pending.

Independent Claude reviews found no critical/high contract issue, two medium contract concerns, and a high frontend V3-template mismatch. Fixed publicly readable configuration omissions, independent browser ID computation, V3 request list, restored requireApprovedPrinterSelections, explicit unavailable selection UI, v5-only/non-advanced selection, RPC wording and library error ABI. Follow-up independent review running; no final clearance yet. Test isolation mocks are not substitutes for the real matching/adapter tests, which also pass.

Commitment boundary: deployed printers have no public getters for global/per-token transfer hooks; the hash does not promise to bind inaccessible hook mappings, future per-token overrides or later owner-authorized mutations. Public class/series settings, default legends, global transfer/registration flags, endorsement/badge/renderer addresses and printer beacon implementation are included. Existing owner metadata setters, including primary classification, retain their existing behavior. No new LET getters, lifecycle locks or global share-cap ledger added.

Next: finish fork test and independent follow-up; review PR surfaces and affected-flow browser acceptance before merge eligibility. Neither implementation is deployed; saved production raise draft must remain unchanged.

## Follow-up checkpoint

Verified isolated fork at Ethereum block 26308939 passes upgrade, preview, signed reuse-round creation, EOI and allocation on the actual existing Preferred printer (1 test, 0 failures). This is Foundry execution, not browser sign/simulate/RPC-submit acceptance. No live writes. Contract code parent 16c8b77; frontend parent 8d717158a9e.

Independent follow-up confirmed previous seven corrections but found a blocking integration assumption: RoundCreated overwrites CyberCertPrinter.roundId, and round views filter by that field. Reuse needs per-round printer membership and agreement-scoped certificate views. Indexing source changes require owner approval; requested in this chat, still pending. No indexer code modified. Keep both PRs unmerged and feature disabled until this is resolved and affected-flow acceptance passes.

Added fixed Solidity/browser hash assertion, reuse-specific refund/cap/FCFS and configuration-refusal tests, exact owner error, and explicit qualifier clearing. Expanded tests in progress. Existing fork Preferred path supplies actual Preferred coverage. forge-std local dependency dirt is excluded from all commits; no submodule change in PR. New errors are in the additive ABI actually used by the new path. No additional contract capability requested.

PRs: contracts https://github.com/MetaLex-Tech/cybercorps-contracts/pull/191 and webapp https://github.com/MetaLex-Tech/metalex-webapp/pull/2161. Expanded contract suite: 27 passed, 0 failed; browser fixed-vector tests: 3 passed; app TypeScript passed after selection fix. Independent follow-up’s indexing blocker remains open. Both PRs on explicit merge hold.
