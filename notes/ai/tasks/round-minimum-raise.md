# Task: RoundManager minimum raise (DEPLOY_VERSION 5.1)

- **Status:** Ready for review: [#202](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/202)
- **Updated:** 2026-11-17 (review follow-ups, code commit 0a1b797)
- **Owner:** Claude Code desktop session, for the owner
- **Collaborators / boundaries:** RoundManager, its storage library and interface only. No
  factory, condition, registry or escrow-library change. No deployment, factory reference
  update, company upgrade, indexer change or audit was started.
- **Objective:** A founder-approved round can carry a minimum raise. Nothing is allocated and
  no funds move until commitments reach the minimum while the round is open; then anyone
  settles them in any number of transactions. Below the minimum, every payment stays
  refundable through the existing `reject` and `recallEOI`.
- **Out of scope:** Minimum rounds created through CyberCorpFactory, PumpCorpFactory or other
  factories that create a company and its first round in one call (they keep calling
  `createRound`); passport-condition changes (MTLX1-33); webapp support.
- **Canonical plan / sources:** metalex-webapp
  `notes/plans/cyberraise-minimum-close-and-investor-limits-20261113.md`, sections "Onchain
  minimum (L3)" and "Two-step close". Owner approvals on 2026-11-13: the L3 scope, then the
  two-step close with a fixed 2-day `SETTLE_WINDOW` and permissionless settlement.
- **Repository / branch:** cybercorps-contracts; base `origin/develop` 32c59e3, branch
  `claude/round-minimum-raise`
- **Verified base / code head:** tests ran on code commit 0a1b797 (base 32c59e3); this record update follows it. Earlier runs: dbeead3, a465719
- **PR / artifact:** https://github.com/MetaLex-Tech/cybercorps-contracts/pull/202, opened 2026-11-13, ready for review. Desktop Auto-fix could not be enabled from the opening session (repository outside its folders); the owner can switch it on in the PR bar.

## Change

- **Storage** (`RoundManagerStorage.RoundManagerData`): five mappings appended after
  `agreementToEOI`: `minRaise`, `minRaiseDeadline`, `minRaiseMet`, `committedAmount`
  (per agreement), `committedTotal` (per round). Existing members keep their position. The
  `Round` struct, round id hash, escrowed-signature type and `RoundCreated` event do not change.
- **Create:** `createRoundWithMinimum` and `createRoundWithPrintersAndMinimum` (owner only) run
  the existing `_validateRound`, create the round, then `RoundManagerStorage.setMinimum`
  refuses FCFS, a zero minimum, a minimum above `raiseCap` and a deadline before `endTime`.
  Event `RoundMinimumSet`.
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
  via-IR "Tag too large" compiler error).
- **Review follow-ups (2026-11-17, 0a1b797):** the escrow expiry above; owner `reject` of an
  expired commitment after met (Codex P2 on `RoundManager.sol:556`); `allocateBatch` removed
  (refused on pending minimum rounds, not needed by commit/settle, and it used scarce bytecode);
  stale comments on `allocate` and `isMinimumPending` fixed.
- **Size:** RoundManager runtime 23,712 bytes (limit 24,576; 864 bytes left) after removing
  `allocateBatch`; RoundManagerStorage 22,130 bytes. Earlier the first draft was 204 bytes over
  and fit only after `settle` stopped returning arrays, the minimum validation moved into the
  library and uncommit folded into `setCommitments`.

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Creation refusals and the kept signature check | Verified (unit) |
| `allocate` refused while the minimum is unmet | Verified (unit, fork) |
| Commit records without moving funds; amounts capped at the payment; replace and remove | Verified (unit) |
| Commit refusals: non-owner, round without minimum, below ticket, mixed round, length, inside settle window (timed offer), after end | Verified (unit) |
| Met refused below the minimum, with an incomplete, unsorted or duplicate list, inside the settle window (timed offer), after the end or early close, and by non-owners | Verified (unit) |
| Settle refused before met; anyone settles after; second settle refused | Verified (unit, fork) |
| After met: commitments locked against change, reject and direct allocate; uncommitted EOIs allocate normally | Verified (unit) |
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
| Source build with sizes (CI form) | `forge build --sizes --skip test script` on 0a1b797 | Passes; RoundManager 23,712 bytes, RoundManagerStorage 22,130 bytes |
| New unit tests | `RoundManagerMinimumRaiseTest`, `RoundManagerMinimumRaiseCommitmentTest` on 0a1b797 | 32 + 4 pass |
| Regression check for the follow-ups | Old `releaseCommitment` lock and end-time expiry restored locally, commitment suite run | The 2 new tests fail; the other 2 pass |
| Fork upgrade tests | `RoundManagerMinimumRaiseUpgradeForkTest` (Base block 56,958,568), local `RPC_URL_BASE` on 0a1b797 | 2 pass |
| Existing RoundManager suites | `RoundManagerTest`, `RoundManagerFCFSTest`, `CyberCorpFactoryPublicRoundTest`, `RoundManagerEOIExpiryTest`, `RoundManagerFactoryTest` on 0a1b797 | 48 + 1 + 7 + 18 + 16 pass; `RoundManagerFCFSForkTest` and `RoundManagerV3NextForkTest` not run locally (need `RPC_URL_BASE_SEPOLIA`; CI runs them) |
| Full repository test suite | — | Not run locally; CI runs it |
| Independent external-model review | — | Not run (required before merge) |

## Next action and handoff

Review follow-ups committed on `claude/round-minimum-raise` (0a1b797 and this record); push
and the matching PR description update wait for the owner's go-ahead. Reply on the open Codex
P2 thread (`RoundManager.sol:556`) once pushed. Before merge: independent external-model
review and the full CI suite. Audit, factory update, upgrades and the webapp support (commit
screen, met status, settlement service; founders should know an extension keeps earlier EOIs
open until `deadline + SETTLE_WINDOW`) need separate authorization.
