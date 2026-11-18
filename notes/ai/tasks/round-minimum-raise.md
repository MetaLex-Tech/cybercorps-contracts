# Task: RoundManager minimum raise (DEPLOY_VERSION 5.1)

- **Status:** Ready for review: [#202](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/202)
- **Updated:** 2026-11-18 (merge of the remote 59af5ef/65fec4e with the local follow-ups 0a1b797)
- **Owner:** Claude Code desktop session, for the owner
- **Collaborators / boundaries:** RoundManager, its storage library and interface only. No
  factory, condition, registry or escrow-library change. No deployment, factory reference
  update, company upgrade, indexer change or audit was started.
- **Objective:** A founder-approved round can carry a minimum raise. Nothing is allocated and
  no funds move until commitments reach the minimum while the round is open; then anyone
  settles them in any number of transactions. Below the minimum, every payment stays
  refundable through the existing `reject` and `recallEOI`.
- **Out of scope:** Factory changes. CyberCorpFactory, PumpCorpFactory and other factories
  keep calling `createRound`; the owner can add a minimum to such a round later with
  `setRoundMinimum`. Passport-condition changes (MTLX1-33); webapp support.
- **Canonical plan / sources:** metalex-webapp
  `notes/plans/cyberraise-minimum-close-and-investor-limits-20261113.md`, sections "Onchain
  minimum (L3)" and "Two-step close". Owner approvals on 2026-11-13: the L3 scope, then the
  two-step close with a fixed 2-day `SETTLE_WINDOW` and permissionless settlement.
- **Repository / branch:** cybercorps-contracts; base `origin/develop` 32c59e3, branch
  `claude/round-minimum-raise`
- **Verified base / code head:** tests ran on the merge of 65fec4e and 2f8d6a5 (base 32c59e3), committed with this record. Earlier runs: dbeead3, a465719, 0a1b797, 65fec4e
- **PR / artifact:** https://github.com/MetaLex-Tech/cybercorps-contracts/pull/202, opened 2026-11-13, ready for review. Desktop Auto-fix could not be enabled from the opening session (repository outside its folders); the owner can switch it on in the PR bar.

## Change

- **Storage** (`RoundManagerStorage.RoundManagerData`): five mappings appended after
  `agreementToEOI`: `minRaise`, `minRaiseDeadline`, `minRaiseMet`, `committedAmount`
  (per agreement), `committedTotal` (per round). Existing members keep their position. The
  `Round` struct, round id hash, escrowed-signature type and `RoundCreated` event do not change.
- **Create:** `createRoundWithMinimum` and `createRoundWithPrintersAndMinimum` (owner only) run
  the existing `_validateRound`, create the round, then `RoundManagerStorage.setMinimum`
  refuses FCFS, a zero minimum, a minimum above `raiseCap` and a deadline before `endTime`.
  `setRoundMinimum(roundId, minRaise, deadline)` (owner only) runs the same check on an
  existing round. A minimum is set one time only (`MinimumAlreadySet`). Event `RoundMinimumSet`.
- **Step 1, commit:** `setCommitments(ids, amounts)` (owner only, while the round is open and
  the minimum unmet). A positive amount commits or replaces a commitment after the checks
  `allocate` makes (escrow paid and unallocated, ticket and EOI minimum, cap including other
  commitments, conditions) plus an escrow expiry at least `SETTLE_WINDOW` (2 days) away; an
  amount above the payment is reduced to it. Zero removes a commitment. No funds move.
  Events `AllocationCommitted`, `AllocationUncommitted`.
- **Met:** `markMinimumMet(roundId, committedIds)` (owner only, round open). `committedIds` lists
  every commitment in strictly ascending order; the contract checks the list sums to the
  committed total, that the total reaches the minimum and that each escrow is still at least
  `SETTLE_WINDOW` from expiry. Event `RoundMinimumMet`.
- **Step 2, settle:** `settle(ids)` (anyone, non-reentrant, after met) allocates each committed
  agreement at its committed amount through the existing allocation logic.
- **Gates:** `allocate` reverts `MinimumNotMet` while a minimum is unmet; the allocation body
  refuses a committed agreement (`CommitmentLocked`), so commitments settle only at their
  committed amount.
- **Refunds:** `reject` and `recallEOI` call `releaseCommitment`. Before met, a refund clears
  the commitment. After met, neither the owner nor the investor can refund a committed
  agreement until its escrow has expired (when it can no longer settle); then either can, which
  frees the capacity it held.
- **Deadline:** `setRoundEndTime` refuses an end time past the deadline while the minimum is
  unmet.
- **Escrow expiry:** on a minimum round without timed offers, a new EOI's escrow and agreement
  expire at `max(endTime, deadline + SETTLE_WINDOW)` (`_escrowExpiry` in `submitEOI`), not at
  the end time when it was submitted. Extending the round up to the deadline therefore keeps
  earlier EOIs committable and settleable. Before met, `recallEOI` still refunds as soon as the
  current end time passes. Timed offers keep the investor's expiry; rounds without a minimum
  keep the end time.
- **Reads:** `getRoundMinimum` (minimum, deadline, met, raised, committed), `getCommittedAmount`,
  `SETTLE_WINDOW`. `DEPLOY_VERSION` is "5.1"; the webapp parses the major version.
- **Review fixes (Codex P2 on #202):** ordinary allocation reserves open commitments
  (`raiseCap - raised - committedTotal`); the commit check skips only the LeXcheX condition, and
  only when `allocate` would mint that credential (shared `_mintsLexChex`). Tests in
  `RoundManagerMinimumRaiseCommitmentTest` (separate contract: a larger test contract hits a
  via-IR "Tag too large" compiler error). Third Codex P2 (on a465719, `RoundManager.sol:556`):
  an expired commitment held round capacity until the investor recalled it. Fixed 2026-11-17
  on both lines of work (59af5ef/65fec4e and 0a1b797, merged 2026-11-18): the owner can
  `reject` a commitment after its escrow expiry, with a full refund to the investor
  (`test_AfterMet_RejectAfterEscrowExpiry_RefundsAndFreesCapacity` and
  `test_AfterMet_ExpiredCommitment_OwnerRejectsAndFreesCapacity`; both fail on the old code).
- **Review follow-ups (2026-11-17, 0a1b797):** the escrow expiry above; the owner reject above;
  `allocateBatch` removed (also removed in 59af5ef by the owner's ABI review); stale comments on
  `allocate` and `isMinimumPending` fixed.
- **Merge (2026-11-18):** `origin/claude/round-minimum-raise` (59af5ef, 65fec4e) merged into the
  local follow-ups (0a1b797, 2f8d6a5). Both lines made the same reject change and removed
  `allocateBatch`; the conflicts were comments, formatting and this record. The deadline-based
  escrow expiry (only in 0a1b797) and `setRoundMinimum` (only in 59af5ef) are both kept.
- **Size:** RoundManager runtime 24,010 bytes (limit 24,576; 566 bytes left) after the merge;
  RoundManagerStorage 22,208 bytes. Before the 2026-11-17 changes: 24,216 bytes. The first draft
  was 204 bytes over; it fits after `settle` and `allocateBatch` stopped returning token-id
  arrays, the minimum validation moved into the library, and uncommit folded into
  `setCommitments`. Little room is left for later fixes in this contract; prefer the library.

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Creation refusals and the kept signature check | Verified (unit) |
| `allocate` refused while the minimum is unmet | Verified (unit, fork) |
| `setRoundMinimum` on an existing round; set one time only; unknown round and non-owner refused | Verified (unit) |
| Commit records without moving funds; amounts capped at the payment; replace and remove | Verified (unit) |
| Commit refusals: non-owner, round without minimum, below ticket, mixed round, length, inside settle window (timed offer), after end | Verified (unit) |
| Met refused below the minimum, with an incomplete, unsorted or duplicate list, inside the settle window (timed offer), after the end or early close, and by non-owners | Verified (unit) |
| Settle refused before met; anyone settles after; second settle refused | Verified (unit, fork) |
| After met: commitments locked against change, reject and direct allocate; uncommitted EOIs allocate normally | Verified (unit) |
| After met: owner reject of a commitment refused up to its expiry; after it, full refund and the capacity is freed | Verified (unit) |
| Committed EOI settles at its expiry; investor recall locked until after expiry, then refunds in full | Verified (unit) |
| 40 EOIs committed in two transactions, met, settled in four transactions | Verified (unit) |
| Unmet after end: recall refunds and clears the commitment (escrow still open to the deadline); reject while pending refunds and clears | Verified (unit) |
| Deadline binds only while unmet | Verified (unit) |
| Escrow of a minimum round runs to `deadline + SETTLE_WINDOW`; after extending to the deadline, a commitment made before the original end is met and settled after it | Verified (unit; fails on a465719) |
| After met, an expired commitment cannot settle; the owner can reject it only after its expiry, refunding in full and freeing its capacity; a later EOI on a round extended past the deadline expires at the new end | Verified (unit; fails on a465719) |
| Rounds without a minimum: escrow still expires at the round end | Verified (unit) |
| Rounds without a minimum unchanged | Verified: unit tests; all existing RoundManager suites pass unchanged |
| Upgrade from the deployed Base v5 implementation keeps state and paths; minimum flow works after | Verified: Base fork tests |
| External audit of the diff | Not started (needs separate authorization) |
| Merge, factory update, deployment, company upgrades | Not done |

## Decisions and evidence

- **Two-step close (owner, 2026-11-13).** Replaces "one batch must reach the minimum", which fit
  only about 10 EOIs per transaction on Ethereum. Gas with this repository's single-transaction
  tests (warm storage, so these understate cold costs): about 46k per commitment, 8k per
  listed commitment when marking met, 1.5M per settlement. Settlements are independent.
- **ABI review (owner, 2026-11-17).** `allocateBatch` removed: the minimum flow does not use
  it, and the owner batches `allocate` through a Safe. `setRoundMinimum` added as a set-once
  setter; the two create functions stay as one-call shortcuts. A simpler `markMinimumMet`
  without a list (minimum rounds with no timed offers and no extension while pending) was
  considered and not taken: the owner kept timed offers on minimum rounds. The setter has no
  "no EOI yet" rule: the per-EOI checks cover that case, and a later minimum only blocks the
  owner's own `allocate`.
- **`markMinimumMet` takes the full list** instead of tracking the earliest committed expiry,
  which could not be recomputed after an uncommit. The sum check makes the list complete; the
  ascending order makes duplicates impossible.
- **Escrow expiry follows the deadline (review follow-up, 2026-11-17).** With the end-time
  expiry, an extension could not help EOIs already submitted: they fell inside the settle
  window 2 days before the original end. The expiry is not in the investor's signature or the
  agreement id (`CyberAgreementRegistry.createContract` leaves it unbound), and the webapp
  reads the escrow expiry from the chain, so no app change is needed for existing flows. Side
  effect: after the original end, an uncommitted EOI of a met round can still be allocated
  until its escrow expiry unless the investor recalls first, as already holds for timed offers.
  With `setRoundMinimum`, the expiry is fixed at submission: EOIs submitted before the minimum
  was set keep the end-time expiry, so an extension does not keep them open. Founders who want
  extensions to count earlier EOIs should set the minimum before EOIs arrive (or use the create
  functions).
- **No condition re-check in `markMinimumMet` (review follow-up, 2026-11-17).** Considered so
  that a commitment whose time-based condition has lapsed cannot be counted. Not added: with
  the deadline-based expiry a commitment that cannot settle is held at most until
  `deadline + SETTLE_WINDOW`, then either party can refund it. It stays in the residual risks
  below.
- **Residual risks accepted in the design:** a committed EOI can fail at settlement (replayed
  credential MTLX1-17, auto-mint failure MTLX1-21, a time-based condition such as a passport
  proof expiry lapsing after commit, or nobody settling before expiry), so the
  company may raise less than the minimum although commitments reached it; settled totals can
  sit a few base units below committed totals from price rounding.
- **Related past audit findings** (Hexens Jul–Aug 2026 report in `audits/`; the AI review at the
  repository root has no RoundManager allocation finding):
  - MTLX1-26, Low, Fixed: round authorization reuse through a factory with weaker validation.
    The new create functions call the same `_validateRound`; a test checks the refusal.
  - MTLX1-24, Low, Acknowledged: the officer signature does not bind agreement values. The
    minimum is also outside the signed struct; creation stays owner-only. Unchanged residual.
  - MTLX1-17, Medium, Acknowledged, and MTLX1-21, Low, Acknowledged: an investor's allocation
    can be made to revert. Settlement is per EOI, so one failure no longer blocks the others;
    the affected EOI stays refundable after expiry. Not fixed here.
  - MTLX1-3, Medium, Fixed: unrelated to these entry points.
  - webapp V12 F344 (allocation recovery) and F-102: app-side, unchanged.

## Validation

| Check | Evidence | Result / limitation |
| --- | --- | --- |
| Source build with sizes (CI form) | `forge build --sizes --skip test script` on the merge | Passes; RoundManager 24,010 bytes, RoundManagerStorage 22,208 bytes |
| New unit tests | `RoundManagerMinimumRaiseTest`, `RoundManagerMinimumRaiseCommitmentTest` on the merge | 37 + 4 pass |
| Regression check for the follow-ups | Old `releaseCommitment` lock and end-time expiry restored locally, commitment suite run (on 0a1b797) | The 2 new tests fail; the other 2 pass |
| Fork upgrade tests | `RoundManagerMinimumRaiseUpgradeForkTest` (Base block 56,958,568), local `RPC_URL_BASE` on the merge | 2 pass |
| Existing RoundManager suites | `RoundManagerTest`, `RoundManagerFCFSTest`, `CyberCorpFactoryPublicRoundTest`, `RoundManagerEOIExpiryTest`, `RoundManagerFactoryTest` on the merge | 48 + 1 + 7 + 18 + 16 pass; `RoundManagerFCFSForkTest` and `RoundManagerV3NextForkTest` not run locally (need `RPC_URL_BASE_SEPOLIA`; CI runs them) |
| Full repository unit suite | `forge test --nmc '(ForkTest|AdhocTest)'` on the merge | 1,573 pass (88 suites); fork suites other than the upgrade test not run |
| Independent external-model review | — | Not run (required before merge) |

## Next action and handoff

Review follow-ups (0a1b797) merged locally with the remote 59af5ef/65fec4e on
`claude/round-minimum-raise`; push and the matching PR description update wait for the owner's
go-ahead. The PR description should add `setRoundMinimum` and the note that EOIs submitted
before it keep the end-time expiry. The webapp record `notes/ai/tasks/round-investor-eligibility.md`
still expects `allocateBatch` in 5.1; it needs updating to the owner's ABI decision (Safe batch
of `allocate`). Reply on the Codex P2 thread (`RoundManager.sol:556`) once pushed, if 65fec4e
has not already. Before merge: independent external-model
review and the full CI suite. Audit, factory update, upgrades and the webapp support (commit
screen, met status, settlement service; founders should know an extension keeps earlier EOIs
open until `deadline + SETTLE_WINDOW`) need separate authorization.
