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

## P2 — Class-level security terms have no on-chain home (stored per-certificate) — `PROPOSED`

**Problem.** A `CyberCertPrinter` is the per-security-class contract, but it stores only class
**identity** — `initialize(... name, ticker, certificateUri, SecurityClass, SecuritySeries, extension)`
(`src/CyberCertPrinter.sol:107`); there is no slot for the class's economic terms. The actual
class-level terms — `seriesName, parValue, authorizedShares, originalIssuePrice, effectiveDate,
liquidationPreferenceMultiple / Type, conversionPrice` — live in the **`ShareExtension` terms struct**
(`src/storage/extensions/ShareExtension.sol:143-150`) and are **ABI-encoded into EACH certificate's
`extensionData` per mint** (`CertificateDetails.extensionData`, `src/storage/CyberCertPrinterStorage.sol:51`),
surfaced only on the per-cert `tokenURI` JSON (`ShareExtension.sol:286-305`). So terms that are
conceptually **class invariants are modeled per-certificate.** Consequences:

- **Divergence.** Every issuance re-supplies the terms; nothing keeps them consistent, so two certs of
  the *same* class can carry different `parValue` / `authorizedShares` / `originalIssuePrice`.
- **No authoritative class record.** There is no single on-chain source of truth for a class's terms —
  which the cap table, §219 reporting, and OCF export all want, and which is exactly why the webapp
  cannot pre-fill them when issuing under an existing class (see `metalex-webapp` **M1**).
- **`authorizedShares` is unenforced.** Authorized shares is a hard **class-level cap**, but because it
  lives per-cert there is nothing on-chain that tracks issued-vs-authorized or prevents over-issuance —
  and different certs can even claim different authorized amounts.

**Desired model.** Give the security class (the `CyberCertPrinter`, or a class-config record it owns) an
on-chain home for its **class-level terms**, set once at class creation, so issuance **reads/validates
against the class** (the source of truth) and `authorizedShares` can be enforced as a cap. Genuinely
per-certificate fields (units represented, investment amount, holder, issuance date) stay per-cert.

**Design direction (high-level — details TBD).**

- Add a class-terms struct to `CyberCertPrinter` storage, populated at `initialize` / `createCertPrinter`
  (`src/IssuanceManager.sol:229`); split the `ShareExtension` terms into **class-level** (seriesName, par
  value, original issue price, effective date, authorized shares, liquidation preference) vs **per-cert**.
- On issuance, default per-cert extension data from the class terms and **validate**: reject mismatched
  class terms and enforce `Σ unitsRepresented ≤ authorizedShares` at the class.
- **Migration / back-compat:** existing printers have no class terms; backfill from the most-recent prior
  cert (the only current source) or via a one-shot migration (cf. the `*WithMigration` pattern). Until
  then the webapp M1 pre-fill can only seed from a prior cert.

**Open questions.**

1. Which terms are truly class-level vs allowed to vary per cert (e.g. can `originalIssuePrice` differ by
   round / tranche, or is it fixed per class)?
2. On-chain class storage vs a canonical off-chain class row — and how that interacts with the
   constitutive-register thesis (the class terms are arguably part of the authoritative record).
3. Enforce the `authorizedShares` cap **on-chain** at issuance, or track/report it off-chain only?
4. Interaction with scrip / unit accounting (scripified units still count against authorized) and with
   non-share instruments (SAFE/SAFT/etc., which have different "class terms").
5. OCF / cap-table mapping for the class-level fields.

**References.** `src/CyberCertPrinter.sol:107` (initialize — identity only, no terms);
`src/storage/extensions/ShareExtension.sol:143-150` (the terms struct, encoded per-cert) + `:286-305`
(rendered per-cert into tokenURI); `src/storage/CyberCertPrinterStorage.sol:51` (`CertificateDetails.extensionData`);
`src/IssuanceManager.sol:229` (`createCertPrinter`). Webapp side: `metalex-webapp` **M1** (pre-fill blocked by
this) in its `notes/plans/mainframe-changes-plan.md`.

---

## P3 — Issuer-defined award templates (grants) — `PROPOSED`

**Full evaluation:** `notes/plans/issuer-award-templates-plan.md` (three options, recommendation,
per-option contract + app changes). Summary below.

**Problem.** cyberCORPs grants register the award agreement in the **global, MetaLeX-owned**
`CyberAgreementRegistry`, and the MetaVesT controller's `proposeAndSignDeal(templateId, …)`
calls `registry.createContract`, which reverts `TemplateDoesNotExist` unless the template is
pre-registered (`src/CyberAgreementRegistry.sol:263-266`; `MetaVesTControllerStorage.sol:220`).
The only registration entry point, `createTemplate`, is **`onlyOwner`** (`:230-244`;
`onlyOwner` = registry BorgAuth role ≥ 99, `src/libs/auth.sol:190`). So **every corp shares one
award template that only MetaLeX can register** — a founder cannot register their own custom
award agreement. This is the last setup blocker for self-serve grants (the webapp already ships
an admin "Register award template" page, but it can only be driven by the registry owner —
`metalex-webapp` PR #771).

**Desired model.** An **issuer (corp officer)** registers their **own** award template
permissionlessly, without MetaLeX per corp, without weakening registry integrity.

**Design direction.** The registry **already** creates templates permissionlessly + **content-
addressed** in `createStandaloneContractAndSignFor` (`:341-399`, `public`): `templateId =
keccak256(title, uri, globalFields, partyFields)`, `_createTemplate` just-in-time. Content-
addressing is the key security property — a content hash id **cannot be squatted** (the
caller-chosen-id `createTemplate` could be, which is exactly why it's owner-gated). Options:
- **(A, recommended)** add a thin permissionless **content-addressed** `createTemplatePublic`
  (the template-half of the standalone path, idempotent). Squat-proof, **no** controller change,
  **no** corp-identity verification; app makes the grants templateId per-corp and opens the
  admin page to officers. ~6-line registry change.
- **(B, reserve)** route grants through the existing permissionless `createStandaloneContract
  AndSignFor` (bespoke per-grant doc). Needs a new controller propose variant; **caveat:** the
  zero finalizer auto-finalizes on the grantee's signature (`:550-554`), so it also needs either
  a registry `finalizer` param or a conditional controller finalize. Best for per-grant custom
  docs; complementary to A.
- **(A2, defer)** per-corp-namespaced `createCorpTemplate` with on-chain officer verification —
  needs a new `CyberCorpFactory.isCyberCorp` oracle (no corp registry exists today) + a
  registry→factory dependency. Adds provenance/listing; content-addressing already gives the
  security guarantee, so defer.
- **(C, reject)** owner-delegated `TEMPLATE_CREATOR` role / `setRoleAdapter` — most centralized,
  wrong granularity (an `OWNER_ROLE` adapter grants full owner powers); the existing
  `delegations` mapping is signing-only. Only if MetaLeX wants to curate templates.

**Recommendation:** ship **A**; keep **B** for bespoke per-grant docs; defer **A2**; reject **C**.

**Open questions.** Idempotent vs revert on duplicate content; on-chain creator provenance
(event field / A2) vs off-chain indexing; per-corp templateId storage in the webapp; B's
finalize trade-off (registry `finalizer` param vs conditional controller finalize); whether to
keep the curated owner-only `createTemplate` (recommended yes). See the full doc.

**References.** `src/CyberAgreementRegistry.sol` (`createTemplate` `:230`, `createContract`
`:246`, standalone path `:341-399`, auto-finalize `:550-554`, `finalizeContract`/
`onlyFinalizerIfSet` `:677`/`:209`); `src/libs/auth.sol` (roles, `setRoleAdapter` `:117`);
`src/CyberCorp.sol:184` (`isCyberCORPOfficer`); `src/CyberCorpFactory.sol` (no corp registry);
MetaVesT `feat/re-enable-options` `MetaVesTControllerStorage.sol:220/331`. Webapp:
`metalex-webapp` PR #771 + `notes/plans/cybercorps-grants-build-spec.md`.

---

## Backlog (unprioritized)

_(none yet — add future protocol improvements here)_
