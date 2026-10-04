# Task: GitBook register paragraph and LeXcheXBadge deployment claims

- **Status:** Ready for review (PR open; merge not authorized by this record)
- **Updated:** 2026-10-04 02:45 UTC
- **Owner:** Claude Code session in worktree `gitbook-pr-updates-20d451`, acting for lex-node
- **Collaborators / boundaries:** Documentation only. No change to Solidity, scripts or the webapp. Thesis sentences outside the one rewritten paragraph are listed for the owner's decision, not edited.
- **Objective:** The GitBook (`docs/`) makes no false claim that MetaLeX keeps no offchain register and no false claim that `LeXcheXBadge` is undeployed, and the surviving register paragraph states the owner's specified content in the pinned terminology.
- **Out of scope:** Contract or script changes; the webapp; the GAIBE mirror import in MetaLex-Tech/metalex-webapp; the ownership of the badge BorgAuth (reported to the owner, not published).
- **Canonical plan / sources:** metalex-webapp `notes/guidelines/terminology.md`; the "Terms for tokenized securities" section of metalex-webapp `packages/gaibe/src/knowledge/00-metalex-overview.md` on that repository's `develop`; `script/libs/DeploymentConstants.sol`; [Constitutive vs. pointer tokenization](../../../docs/explanation/constitutive-vs-pointer.md).
- **Repository / branch:** MetaLex-Tech/cybercorps-contracts; base `develop`, working branch `claude/relaxed-raman-c1ded3`.
- **Verified base / code head:** base `39ca18f282100097f449e25c1f1210ef5f8c7488` (tip of `develop` on 2026-10-03); content commit `5437430c28e422446ea5c60a969bc9f89572b6d9`. Later commits on the branch change only this record.
- **Worktree locator:** shared at handoff; not committed.
- **PR / artifact:** [#172](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/172), non-draft, against `develop`; app monitor on with `auto_fix` and `address_comments`; auto-merge off.

## Acceptance and current state

1. Sentence 1, "Maintain a separate offchain register. There is no offchain
   register." (old `docs/explanation/role-of-metalex.md`): already gone from
   `develop` before this task. PR #163 (`d72389af`, 2026-10-02) rewrote it,
   and PR #164 (`183e84d4`, 2026-10-02) moved the page's content to
   `docs/explanation/upgrades-and-control.md` with a GitBook redirect. This
   task rewrites the successor paragraph to the owner's specification.
   **Done in this PR; review pending.**
2. Sentence 2, "`LeXcheXBadge` is not yet deployed on any chain." (old
   `docs/reference/deployments.md`): already gone from `develop` since
   `b491a11` (2026-09-19). The production table lists the badge and its
   BorgAuth on Ethereum, Base and Arbitrum, and the test-environment table
   implies both testnets share those addresses. **Verified onchain on
   2026-10-04 (see Validation); no docs change needed.**
3. No other sentence in `docs/` repeats either claim
   (`grep -rn "offchain register\|not yet deployed\|LeXcheXBadge" docs`).
   **Verified.**
4. Every changed sentence follows the terminology guide (cap table vs.
   securities ledger, tokenized vs. onchain axes, unhyphenated onchain and
   offchain, "Ledger Entry Token (LET)" at first mention, no "cyberCERT").
   **Verified by hand on the diff.**
5. Relative links in `docs/` resolve. **See Validation.**
6. After merge, the `Notify GAIBE of docs changes` workflow fires the
   webapp's knowledge refresh. **Pending merge.**

## Decisions and evidence

- The two sentences the owner named were verified against a checkout that
  predates PRs #163 and #164. On the 2026-10-03 tip of `develop` neither
  sentence exists. The remaining gap was content, not truth: the successor
  paragraph did not say that the LET contracts are the register for
  tokenized units, that the company's officers keep the cap table, or that
  the cap table exports to CSV, Excel and OCF.
- Thesis-level sentence left unchanged for the owner:
  `docs/explanation/constitutive-vs-pointer.md` lines 17 to 19, "For the
  securities this covers, the chain and the legal record cannot drift
  apart, because there is no offchain copy of the register to reconcile and
  no transfer agent to instruct." Proposed wording is in the PR body.
- `docs/README.md` lines 13 to 15 ("For those shares the onchain record is
  the register itself, and the tokens do not point at a register kept
  somewhere else.") is scoped to designated shares and is true as written.
  Left unchanged.
- `script/libs/DeploymentConstants.sol` carries a TODO on `lexchexBadgeAuth`
  in the Arbitrum block and in the Ethereum/Base block: the deployer still
  owns it, and it should move to the MetaLeX Safe. Reported in the PR body
  for the owner. Not published in `docs/`.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Badge proxy has code on five chains | `cast code 0x114664773Ba721a6AA43890d5FDE7939aF37618F` on chain ids 1, 8453, 42161, 11155111, 84532 via public RPCs, 2026-10-04T02:24Z | Passed: 130 bytes of proxy code on every chain |
| Badge is a live ERC-1967 proxy | `cast storage <badge> 0x3608...bbc` on the same five chains | Passed: implementation `0xf2fed468afa26a9c11ba8ce5995543eb9e3b308b` on every chain; implementation holds 19885 bytes of code on every chain |
| Badge version | `cast call <badge> "VERSION()(uint256)"` on the five chains | Passed: returns 2 everywhere, matching `docs/reference/contracts/LexChex.md` |
| Badge BorgAuth has code | `cast code 0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d` on the five chains | Passed: 2188 bytes on every chain; implementation slot is zero, as expected for a plain `BorgAuth` |
| Diff scope | `git show --stat 5437430` | Three files: `docs/explanation/upgrades-and-control.md` (the rewritten paragraph), `notes/ai/CURRENT-STATE.md` (one pointer line) and this record. No other `docs/` file, no Solidity, scripts or webapp |
| Line endings | CR count equals line count before and after the edit | Passed; the diff shows only the rewritten paragraph |
| Terminology | Grep of the edited page for `on-chain`, `off-chain`, `cyberCERT`, `un-tokenized` | Clean |
| Relative links | Script over every `.md` under `docs/` resolving relative `.md` targets, run at `5437430` | Passed: 65 files, 0 broken links |

No contract or runtime tests apply. No deployment, integration acceptance or
external review is established by this record.

## Review and blockers

PR: [#172](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/172),
open, non-draft, against `develop`, opened 2026-10-04 02:32 UTC from the
content commit `5437430`. The Claude desktop app monitor is on with
`auto_fix` and `address_comments`; auto-merge is off. Independent review:
the repository's normal PR review (Codex bot plus the owner). Codex's first
round on `5437430` returned one P2 finding, that this section did not name
the PR; fixed in the record. No other unresolved findings.

## Next action and handoff

Run the PR review loop until the owner merges or closes the PR. After merge,
check the `Notify GAIBE of docs changes` run for the merge commit on
`develop` (`gh run list --workflow notify-gaibe.yml`) and the matching
`Refresh GAIBE knowledge` run in metalex-webapp. If the dispatch did not
fire, a manual GAIBE import PR in metalex-webapp is required; do not open it
from this worktree. Record the outcome here. Ownership stays with this task.
