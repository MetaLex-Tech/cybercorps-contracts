# Task: Section 12(g) holder counts outside the LET contract (HolderLimitTracker)

- **Status:** Active (implementation and tests; not merged, not deployed)
- **Updated:** 2026-11-25
- **Owner:** Claude Code session for the repository owner
- **Collaborators / boundaries:** PR #208 (`claude/holder-cap-per-class-7a38a8`, holder cap for each LET contract) is the base. PR #209 (`claude/holder-cap-nonaccredited-plan-label`) is the linked-library version of the same feature; this branch replaces its structure and does not modify that branch.
- **Objective:** Section 12(g) limits in `HolderCapCondition` (a cap on holders of record, a cap on holders of record who are not accredited, and a plan-security exclusion under Rule 12g5-1(a)(8)), with every new count kept in a separate, opt-in `HolderLimitTracker` contract instead of inside `LedgerEntryToken`.
- **Out of scope:** Moving the existing look-through total and U.S. count out of LET (they stay; decided 2026-11-25). Primary-issuance caps. Deployment scripts, deployment, upgrade, webapp support.
- **Canonical plan / sources:** this record; the review of PR #209 in the session of 2026-11-24/25; `src/HolderLimitTracker.sol`; `src/libs/conditions/secondary/HolderCapCondition.sol`.
- **Repository / branch:** `MetaLex-Tech/cybercorps-contracts`; base `claude/holder-cap-per-class-7a38a8` (fa0269a4); working branch `claude/holder-limit-tracker`.
- **Verified base / code head:** base fa0269a4; code head recorded in the validation table at commit time.
- **Worktree locator:** separate worktree `holder-limit-tracker` beside the main checkout.
- **PR / artifact:** not yet created.

## Decisions (owner, 2026-11-25)

1. Do not use the linked library and forwarder of PR #209. Keep the new counts in a separate contract.
2. Leave the existing look-through total and U.S. count in LET. They are live in v5 and hold the Hexens fixes.
3. Each printer opts in by setting its own tracker (`setHolderTracker`), so a printer without one makes no call and pays no gas for the feature.
4. Carried over from #209 unchanged: a lapsed accreditation credential keeps the booking; a voided one ends it at the next sync; any `K_ACCREDITED` credential counts (any issuer, any scope; open question below); the company mark overrides the registry; the plan label holds only for the legal owner it was set for.
5. Section 12(g) counts registered holders (holders of record) only. Beneficial owners are not counted and there is no look-through: each legal owner with a live lot is one holder, whatever its `K_BO_COUNT`. No flag and no per-entity override (owner, relaying legal review, 2026-11-25, in response to the external review's item 2A). The Investment Company Act cap keeps the LET look-through tally.
6. The section 12(g) limits get their own total cap (`ClassLimits.totalCap`) beside `nonAccreditedCap`; the plan exclusion applies only to these two and never to the ICA cap (`SpvConfig.cap`). This fixes the external review's item 3 (the exclusion lowered the 3(c)(1) count, whose own exclusion is the narrower Rule 3c-5). `IcaException.NONE` is appended for operating companies (review item 2B).

## Design

- **LET (`LedgerEntryToken` + `LedgerEntryTokenStorage`):** one appended storage member `holderTracker`. `setHolderTracker` (admin) tells the old tracker `onDetach()` (gas-limited, result ignored, so no tracker can block a switch) and the new one `onAttach()`. After each of the four paths that change a lot's live state (`_setLegalOwner`, `recordBurnLegalOwner`, `recordVoidLegalOwner`, `recordUnvoidLegalOwner`), the library calls `onLotChange(tokenId, owner, liveCounted[tokenId])`. The call is in assembly to save library space. The tally functions `_countLot`, `_uncountLot`, `_resyncHolder`, `_sample` and `_trackNonUs` are unchanged.
- **Push, not pull, for lot changes:** a mint records the legal owner before `_safeMint`, so `legalOwnerOf` and `isVoided` revert during that hook. The printer therefore passes the lot's owner and live state; the tracker keys the write by `msg.sender`.
- **`HolderLimitTracker` (new, UUPS, MetaLeX-owned singleton):** one book per (printer, generation); `onAttach` starts a new generation and records the supply; `backfill` (permissionless) covers the tokens that existed at attach; the book is ready when it has. Holder records hold live lots, plan lots, whether the holder is counted, accredited booking and plan-only state; four totals, each a number of holders of record. The tracker never reads `K_BO_COUNT`. Permissionless `syncLot`, `syncHolder`, `syncHolders`. Admin (the printer's issuance manager or an admin of its AUTH): `setPlanSecurity`, `setNotAccreditedMark`. Registry reads never revert: malformed answers read as not accredited and voided.
- **`HolderCapCondition`:** two independent checks after the no-U.S. floor. (1) The ICA cap (`SpvConfig.cap`), exactly as in #208: the LET look-through tally (or its U.S. subset), the buyer's `K_BO_COUNT` added, existing holders pass. (2) The section 12(g) limits (`setClassLimits(spv, printer, totalCap, nonAccreditedCap, excludePlanOnly)`), read only when a 12(g) cap is non-zero: the trusted tracker (`setHolderTracker`, owner only) must be set and the printer's book ready; a new holder, or a plan-only holder with the exclusion on, adds exactly one to the tracker's total and (when not accredited) non-accredited counts. Because the exclusion no longer touches the ICA count, the earlier per-SPV conflict counters and `UsResidentCountWithPlanExclusion` are removed; `usResidentOnlyCount` and `excludePlanOnly` may be combined.

## Invariants

| ID | Invariant |
| --- | --- |
| T1 | For each printer book: `total` = number of counted holders; `accredited`, `planOnly`, `planOnlyAccredited` = number of counted holders booked accredited, plan-only, both. |
| T2 | For an attached, ready book, each holder's `liveLots` equals the number of the printer's lots it owns that are not void; a holder is counted exactly when `liveLots > 0`; so `total` is the number of legal owners with a live lot (holders of record), never above `printer.lookThroughHolderCount()`. |
| T3 | Only a printer writes its own book through `onAttach` / `onDetach` / `onLotChange`; every other write path recomputes from the printer and its registry, or is an admin setter that checks the printer's admin. |
| T4 | A sale under class limits passes only when the condition's trusted tracker is set, the printer reports to it and its book is ready. It never reverts for that reason. |
| T5 | A printer without a tracker makes no external call, and an SPV without class limits never reads the tracker: the #208 behaviour is unchanged. |
| T6 | Section 12(g) settings never change the ICA check: it always uses the LET look-through tally (full, or U.S. only), plan-only holders included, as in #208. Section 12(g) checks never use look-through: a new legal owner adds one. |
| T7 | Malformed registry answers never revert a tracker sync. |
| T8 | A plan label is in force only for the legal owner it was set for; any change of legal owner clears it; a re-attach starts without labels; company marks persist across generations. |
| T9 | The LET tally functions of the Hexens fixes (MTLX1-18, -34, -36) are byte-for-byte unchanged; the hooks run after them. |
| T10 | Setting the tracker to zero always succeeds for the admin and stops all calls, even when the old tracker reverts or uses all gas. |

## Acceptance tests

- Tracker with a real `LedgerEntryToken` and a real `LeXcheXBadge`: no-tracker path; attach on an empty printer (ready at once); attach with holders (not ready until backfill in batches); every lot path (mint, assign, void, unvoid, burn); accredited booking (credential, lapse, void, supersede, mark set and removed, mark across re-attach); plan label (set, mixed lots, sale clears it, buy-back does not revive it, no owner reverts, non-admin reverts); an entity with a `K_BO_COUNT` is one holder of record while the LET tally looks through; detach and re-attach; a reverting tracker blocks changes until the admin detaches; writes keyed by msg.sender; malformed registry; fuzzed sequences (including entity credentials) checking T1 and T2 after each step.
- Condition: class limits with no tracker, an untrusted tracker, a tracker that is not ready (all fail); non-accredited cap lands on and breaches; accredited buyer; existing holder; total cap lands on and breaches; an entity holder and an entity buyer each count once under the 12(g) caps while the ICA cap still counts the entity's beneficial owners; both 12(g) caps refuse independently; the plan exclusion never lowers the ICA count (external review item 3 regression); plan exclusion on the 12(g) total cap; plan-only holder buying an unlabelled lot; a plan-only holder whose credential lapsed reads accredited (review finding #6 of PR #209); no 12(g) cap (or the exclusion alone) never reads the tracker; an operating company with `IcaException.NONE`; U.S.-only ICA count combined with the plan exclusion; `setHolderTracker` owner only; storage layout P+2..P+3.
- The existing unit suites, including `HolderCapConditionTest` and the `test/Audit*.t.sol` regressions, pass unchanged.

## Past audit findings

Searched: `audits/hexens-metalex-jul-aug26(Final).pdf` (text extracted locally), `specs/analysis/` (audit scope v2, conditions), `test/Audit*.t.sol`, PR #209's audit table. No finding covers `HolderCapCondition`'s class limits or a holder tracker (both new).

| Finding | Severity / response | How this change keeps it |
| --- | --- | --- |
| Hexens MTLX1-18, look-through tally can be corrupted if the badge is wired late | Low, Fixed | LET tally unchanged. The tracker reads the badge from the printer at each sync, and `backfill` / `syncHolders` re-read it, so a late badge is repaired the same way. |
| Hexens MTLX1-34, `revokeDeal` leaves cancelled certificates active | Low, Fixed | The fix voids through `voidCert` → `recordVoidLegalOwner`, which now also reports the lot to the tracker after `_uncountLot`; `_uncountLot` itself is unchanged. |
| Hexens MTLX1-36, cross-holder de-scripification leaves ghost holders | Low, Fixed | The fix voids emptied lots through the same `voidCert` path, so the tracker drops them with the LET tally. |
| Hexens MTLX1-16, `voidCert` allows non-existent certificates to be marked as void | Informational, Fixed | `voidCert` still checks existence; `setPlanSecurity` reverts for a lot with no legal owner. |
| Hexens MTLX1-25, voided certificates can be used in secondary trades | Low, Fixed | Not affected: the tracker only counts; void status still comes from LET. |

## Open questions for the owner

- Accreditation from any issuer and any scope (#209 review finding #5): keep, or filter by issuer list or SPV scope.
- A voided credential reaches the counts only at the next sync of that holder (pull). Keepers or the app must call `syncHolders` after voids.
- The fiscal-year-end measurement of accredited status, and whether a lapsed credential should keep the booking, for counsel (external review item 1).
- Primary issuance is not capped by `HolderCapCondition`.
- External review items not yet addressed: a detach that runs out of gas can leave the old tracker attached and reporting stale counts as ready (item 4; fix by a gas floor before the `onDetach` call or a LET getter); an existing holder whose `K_BO_COUNT` rises passes the ICA check without counting the increase (item 3, from #208 and `develop`); the ICA cap is per class, and scrip and primary issuance are outside it (item 3, document).

## Validation

Tested tree: the code committed with this record (no code change after the runs), on base fa0269a4. Local Forge 1.2.0, solc 0.8.28, via-IR, 15 optimizer runs; CI uses Forge 1.8.5 and is the authoritative size check.

| Check | Evidence | Result / remaining limitation |
| --- | --- | --- |
| Sizes | `forge build --sizes --skip test script` | `LedgerEntryToken` 24,417 (159 free; #208: 24,288, #209: 115 free). `LedgerEntryTokenStorage` 23,671 (905 free; #208: 1,452, #209: 879 free). `HolderLimitTracker` 9,199. `HolderCapCondition` 9,316 (#208: 7,076). |
| New tests | `forge test --match-path 'test/{HolderLimitTracker.t.sol,conditions/secondary/HolderCapConditionClassLimits.t.sol}'` | 49 passed (25 tracker incl. a 64-run fuzz of T1/T2 with entity credentials and a gas report; 24 condition) |
| Unit suite | `forge test --nmc '(ForkTest\|AdhocTest)'` | 91 suites, 1,650 passed, 0 failed (#208: 1,601). The run deletes four tracked `script/res/gnosis-batch-safe-let-image-*.unverified.json` files (an existing test's cleanup); restored, not part of this change. |
| Gas | `test_Gas_WithAndWithoutTracker`, same snapshot, registry wired, buyer accredited | Mint 487,948 → 551,350 (+63,402); change of legal owner 168,278 → 231,711 (+63,433) with a tracker. Without a tracker the cost is one storage read per change. |
| Fork tests | not run | Remaining |
| Hexens tally functions unchanged (T9) | `git diff` of `LedgerEntryTokenStorage.sol`: only the storage member, `DETACH_GAS`, four hook calls after the tally code, `_notifyHolderTracker`, `setHolderTracker` | Verified by diff |

## Review and blockers

Independent external-model review required before merge (AGENTS.md); not started. No merge, deployment or upgrade is approved. Deploy scripts are not changed: a release must deploy `HolderLimitTracker` behind a proxy, a new `LedgerEntryTokenStorage` and LET implementation, upgrade `HolderCapCondition`, and call `HolderCapCondition.setHolderTracker`. The condition adds only `classLimits` (P+2) and `holderTracker` (P+3) to #208's layout, so it can follow #208 in a later upgrade without any state to rebuild.

## Next action and handoff

Branch pushed (authorized by the owner on 2026-11-25). Next: open a PR stacked on #208 (base `claude/holder-cap-per-class-7a38a8`) when the owner asks, run the independent external-model review, and decide the open questions above. PR #209 should be closed or marked superseded by the owner once this approach is accepted.
