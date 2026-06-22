# cyberCORPs Protocol — Improvement Plan

**Scope.** Proposed improvements to the on-chain cyberCORPs protocol (`src/`), tracked as a
living log. Items are **design-level** until promoted to a full spec / implementation — the goal
is to capture intent and rationale somewhere durable, not to settle every implementation detail
up front. Companion to the webapp-side plan (`notes/plans/mainframe-changes-plan.md` in
`metalex-webapp`), which tracks the off-chain/app surface.

**Status.** Active log. Each item: **problem → desired model → design direction → open questions**.
Items are `PROPOSED` until specced/scheduled.

---

## P1 — Board role: governance-correct appointment & removal of officers — `PROPOSED`

**Problem (current on-chain behavior).** Every company officer holds BorgAuth role **200**, and the
officer-management functions on `CyberCorp` — `addOfficer` (`src/CyberCorp.sol:191`), `removeOfficer`
(`:200`), `removeOfficerAt` (`:215`) — are gated only by **`onlyOwner()`**, which is a *threshold*
check `userRoles[caller] >= OWNER_ROLE (99)` (`src/libs/auth.sol`; cf. `isCyberCORPOfficer` =
`role >= OWNER_ROLE`, `CyberCorp.sol:185`). Because every officer sits at 200 (≥ 99),
**any officer can appoint or remove any other officer — or themselves.** Consequences:

- **Flat, mutual eviction.** Officers are a flat peer set with no hierarchy; any co-owner can
  unilaterally remove the others, and in a dispute whoever signs `removeOfficer` first wins.
- **No accountability layer.** There is no body that is *authorized to* hire/fire officers and is
  itself accountable to the equity holders — officer management is self-referential.
- **Brick risk.** There is no on-chain last-officer guard, so an officer can drive the owner set to
  zero (no address `>= 99` → `onlyOwner` can never pass again → the corp is permanently frozen).
  (The webapp `metalex-webapp` PR #745 adds a *UI-only* guard; nothing enforces it on-chain.)

This mismatches real corporate governance, where **stockholders elect the board, and the board
appoints/removes officers** — officers do not appoint or fire themselves or each other.

**Desired model.** Introduce a distinct **Board** (director) authority above officers:

- **Officers are appointed/removed by the Board**, not by other officers. Re-gate
  `addOfficer` / `removeOfficer` / `removeOfficerAt` to require **Board** authority rather than
  `onlyOwner`/officer-200.
- **The Board can only be changed in two ways:** (a) **by the Board itself** (board members
  appoint/remove board members), or (b) **by the tokenized stockholders** (the on-chain equity
  holders can replace the board).
- This encodes the real hierarchy on-chain — **tokenized stockholders → Board → officers →
  managers** — consistent with the constitutive-register thesis (the stockholders, the board, and
  their votes are all on-chain rather than pointers to an off-chain cap table).

**Design direction (high-level — details TBD).**

- A new **Board role** in BorgAuth (a distinct level/role above officer-200, or a separate Board
  module); officer-management functions check Board authority instead of `onlyOwner`.
- **Board self-management:** board-gated add/remove of board members.
- **Stockholder override:** the protocol already has the hook — BorgAuth's **`IAuthAdapter` /
  `setRoleAdapter`** lets a role's authority be delegated to an external contract. The Board role
  could use an adapter that defers to a **stockholder-governance contract** (a vote/snapshot of the
  cert/scrip holders representing equity, or a Governor/timelock), so "stockholders can replace the
  board" without hard-coding a voting mechanism into `auth.sol`.
- **Migration / backward-compat:** existing corps have officers at flat-200 with self-referential
  power. A migration seats an initial Board (e.g. the founder becomes the first board member +
  officer) and re-points officer management at the Board — likely via the existing `*WithMigration`
  pattern.
- **On-chain last-member guards:** prevent the Board (and officers) from reaching zero and bricking
  the corp — the guard the webapp currently only enforces in the UI.

**Open questions.**

1. **Role encoding:** a new numeric BorgAuth level (where, relative to 200 / 99?) vs a separate
   Board contract/module? Threshold (`>=`) semantics mean a higher Board level would also satisfy
   officer/owner gates — intended or not?
2. **What counts as "tokenized stockholders"** for the governance path — cyberSHARES / cyberSCRIP
   holders, registered cert holders, or a per-class voting weight? Quorum / threshold / timelock?
3. **Mechanism for the stockholder → board path:** an `IAuthAdapter` deferring to a Governor
   contract, a direct stockholder-vote function on a Board module, snapshot-based, …?
4. **Interaction with `OWNER_ROLE = 99` (the manager contracts) and the upgrade co-approval model**
   — does Board subsume "owner," or coexist alongside it?
5. **Legal mapping:** confirm the board / officer / stockholder split maps cleanly across the entity
   types the protocol supports (DE C-corp directors & officers; LLC managers & members; SPC; etc.).

**References.** `src/CyberCorp.sol:185-222` (officer fns + `isCyberCORPOfficer`); `src/libs/auth.sol`
(BorgAuth roles, `onlyRole` threshold, `updateRole`, `setRoleAdapter` / `IAuthAdapter`);
`src/CyberCorpFactory.sol:220` (founder granted 200 at deploy). Webapp side: `metalex-webapp` M34 /
PR #745 (Mainframe ownership UI) and the auth findings in its `notes/plans/mainframe-changes-plan.md`.

---

## Backlog (unprioritized)

_(none yet — add future protocol improvements here)_
