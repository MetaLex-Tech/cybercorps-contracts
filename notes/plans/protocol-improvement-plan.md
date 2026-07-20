# cyberCORPs Protocol — Improvement Plan

**Scope.** Proposed improvements to the on-chain cyberCORPs protocol (`src/`), tracked as a
living log. Items are **design-level** until promoted to a full spec / implementation — the goal
is to capture intent and rationale somewhere durable, not to settle every implementation detail
up front. Companion to the webapp-side plan (`notes/plans/mainframe-changes-plan.md` in
`metalex-webapp`), which tracks the off-chain/app surface.

**Status.** Active log. Each item: **problem → desired model → design direction → open questions**.
Items are `PROPOSED` until specced/scheduled.

**Last audited:** 2026-07-20 against the current worktree. P1 is **implemented locally for new
corps / unreleased**: Board and officer roles are distinct, direct ACL mutation is locked behind
the `CyberCorp`, Board membership is stored on-chain, officer and Board last-member guards are
enforced, and a Board-role adapter provides the stockholder-governance execution hook. P2 is
**implemented locally / unreleased** through an externalized `ShareClassTermsController`: the
controller stores and hashes canonical `SeriesTerms`, enforces the authorized-share cap, maintains
issued-unit accounting across update/void/unvoid/burn and scrip representation changes, and
exposes governed configuration/amendment paths. `IssuanceManager` supplies the enforcement hooks
and an atomic, one-way legacy-printer migration; the webapp resolves the controller through the
printer and locks its canonical terms. This replaced an earlier in-printer prototype that exceeded
EIP-170. The focused P2 suite passes 10/10, including atomic `upgradeToAndCall`, batch rollback,
length validation, and migration replacement prevention, and all
production contracts fit the runtime-size limit. P3's interim implementation remains
live on-chain (commit `7edb89d`, 2026-07-08), while the recommended Option A hardening is
**implemented locally / unreleased**: arbitrary caller-chosen IDs are owner-only again,
`createTemplatePublic` is content-addressed and idempotent, empty legal URIs are rejected,
the focused registry suite passes 18/18 including proxy state preservation, and the webapp
ABI/call site is updated locally.
All 50 current non-fork Foundry test files pass individually on the final local tree. The monolithic
whole-suite command was not used as release evidence because unrelated legacy external-fork
tests can spend an unbounded period retrying remote RPCs; the release-critical pinned fork
suites are recorded under P1 below.
Coordinated proxy upgrade plus webapp rollout/runtime verification remain. P4
control-agreement liens / permissionless foreclosure is `PROPOSED`; no lien code exists.

---

## P1 — Board role: governance-correct appointment & removal of officers — `TARGET LOCAL / UNRELEASED`

**Status update (2026-07-19).** The forward-deployment target is implemented locally and its
available fork suites pass. It has not been deployed. The matching webapp v5
roster/mutation/consent integration is implemented locally but has not received
authenticated hosted-runtime acceptance.

The historical/live behavior was a flat ACL: every company officer held BorgAuth role **200**, and
the officer-management functions were gated by the numeric `onlyOwner()` threshold. Any officer
could therefore appoint or remove any other officer, including the last officer. That caused:

- **Flat, mutual eviction.** Officers are a flat peer set with no hierarchy; any co-owner can
  unilaterally remove the others, and in a dispute whoever signs `removeOfficer` first wins.
- **No accountability layer.** There is no body that is *authorized to* hire/fire officers and is
  itself accountable to the equity holders — officer management is self-referential.
- **Brick risk.** There is no on-chain last-officer guard, so an officer can drive the owner set to
  zero (no address `>= 99` → `onlyOwner` can never pass again → the corp is permanently frozen).
  (The webapp `metalex-webapp` PR #745 adds a *UI-only* guard; nothing enforces it on-chain.)

This mismatched real corporate governance, where **stockholders elect the board, and the board
appoints/removes officers**.

**Implemented target.**

- **Officers are appointed/removed by the Board**, not by other officers. Re-gate
  `addOfficer` / `removeOfficer` / `removeOfficerAt` to require **Board** authority rather than
  `onlyOwner`/officer-200.
- **The Board can be changed by the Board itself** through explicit director add/remove functions,
  or by an executor authorized through the Board role's `IAuthAdapter` hook. The actual
  class-aware stockholder voting adapter/Governor is still a separate implementation item.
- This encodes the real hierarchy on-chain — **tokenized stockholders → Board → officers →
  managers** — consistent with the constitutive-register thesis (the stockholders, the board, and
  their votes are all on-chain rather than pointers to an off-chain cap table).

Implementation details:

- `BorgAuth` defines `OFFICER_ROLE = 200` and `BOARD_ROLE = 300`, and supports an irreversible,
  one-time `roleManager`. Once the factory hands role management to the new `CyberCorp`, officers
  cannot bypass Board policy by calling `updateRole` or `setRoleAdapter` directly.
- `CyberCorp` v5 stores separate director/officer rosters and membership mappings. It exposes
  Board activation, director add/remove, membership/count reads, and Board adapter configuration.
- New deployments seed the founder as both the first director and first officer. All four corp
  factories complete the ACL handoff and activate Board governance only after their manager roles
  are configured. ParentCo additionally completes its configured multi-officer bootstrap before
  the one-way handoff, so it does not lose authority midway through initialization.
- The forward rollout deploys a separate v5 `CyberCorpSingleFactory` and atomically pairs each
  upgraded top-level factory implementation with that pointer via `upgradeToAndCall`. The legacy
  single factory/reference stays unchanged, preventing an omitted legacy factory from silently
  deploying an unactivated v5 corp.
- Officer appointment/removal is Board-gated once governance is enforced. Removing the last
  officer or director reverts, and removing one capacity preserves the other for dual-role people.
- Legacy upgraded proxies remain explicitly in compatibility mode until governance activation;
  the app/plans must not label that mode as Board-enforced.

**Verification.** `CyberCorpBoardAuthorityTest` passes 7/7, covering the one-way role-manager lock,
officer bypass prevention, Board-controlled officers, Board self-management, last-member guards,
dual-role preservation, and adapter-authorized Board replacement. `CyberCorpSingleFactoryTest`
passes. The pinned fork suites now model the required rollout order by updating the shared
`CyberCorpSingleFactory` reference to v5 before using a P1-aware top-level factory:
`CyberCorpForkTest` passes 47/47, `PumpCorpFactoryForkTest` passes 36/36, and
`DeployParentCoFactoryForkTest` passes 25/25. Pump and ParentCo include explicit assertions for
the role-manager lock, Board activation, and exact founder/additional-officer roles. The rollout
scripts compile, and `ParentCoFactory` remains 3,423 bytes below EIP-170. No transaction has been
broadcast.

**What remains before the first real pilot.**

1. Runtime-test and release the locally implemented webapp branch that uses v5
   director reads and `addDirector`/`removeDirector`, gates officer controls on
   Board authority, routes consent signers from the protocol roster, labels
   legacy mode, and suppresses the legacy transfer flow for v5.
2. The root action matrix is now implemented locally: legal identity, manager
   pointers, treasury payable address, and corp upgrades are Board-gated when
   enforcement is active; reusable escrowed signatures remain an officer
   operation. Confirm this policy in legal/product review and extend it to
   manager-contract actions only where a concrete corporate-approval rule
   requires Board consent.
3. Because existing `BorgAuth` deployments are immutable, inventory the small set of corps with
   real records and choose per-corp migration/redeployment. Given current usage, do not attempt a
   blanket migration of hundreds of test corps.
4. Fork acceptance is complete. Dry-run the rollout script against the intended target block,
   deploy a fresh test corp through every enabled route, and complete the authenticated
   boardroom/consent/issuance acceptance checklist before any production cutover.
5. Limit the pilot to a corporation whose founder-seeded initial Board policy has been explicitly
   accepted. Confirm the legal mapping for LLCs, partnerships, SPCs, and funds before presenting
   director/officer vocabulary to those entity types.

The concrete class-aware stockholder voting/Governor adapter is a later or
pilot-conditional item, not a blocker for a deliberately scoped founder-Board
pilot that makes no claim of on-chain stockholder elections. Do not build it over
current spot certificate balances. It first needs historical voting checkpoints
at a record-date block, aggregation by registered/legal owner (which can differ
from NFT `ownerOf`), and canonical per-class voting terms; then class voting,
quorum, thresholds, proposal execution, replay protection, and timelocks. Until
those prerequisites exist, the adapter hook is only an execution boundary and the
UI must describe the founder-seeded Board as bootstrap policy, not stockholder
governance.

The forward rollout and selective legacy disposition are specified in
[p1-board-authority-rollout-runbook.md](p1-board-authority-rollout-runbook.md).

**References.** `src/CyberCorp.sol`; `src/libs/auth.sol`; the four factory handoff sites;
`test/CyberCorpBoardAuthorityTest.t.sol`. Webapp side:
`metalex-webapp/notes/plans/cybercorps-boardroom-plan.md`.

---

## P2 — Canonical class terms and authorized-share enforcement — `TARGET LOCAL / UNRELEASED`

_Historical baseline: PR #107 (`feat/shares-extension-logic`, merged 2026-06-02) reshaped the
per-cert struct — the old flat `ShareData` became `ShareCertData` with a dedicated `SeriesTerms` terms
struct (`ShareExtension.sol:142-183`, expanded with dividend/redemption/pro-rata/information-rights
fields), but left the storage model per-certificate and `authorizedShares` unenforced._

**Status update (2026-07-19).** The deployable target is implemented locally but not deployed:

- `ShareClassTermsController`, a UUPS extension facade, stores each printer's canonical
  `SeriesTerms` bytes/hash, authorized shares, issued units, and configured flag. It delegates
  rendering/parsing to the existing `ShareExtension`, so `CyberCertPrinter` remains at deploy
  version 4 with no storage or beacon upgrade.
- `ShareExtension.getSeriesTermsData` extracts exactly `SeriesTerms`. The controller validates
  every later share mint/update against the canonical hash; `CertificateData`, restrictions,
  triggers, and split history remain certificate-specific.
- `IssuanceManager` calls the controller on every share lifecycle path. Issuance rejects
  `issuedUnits + newUnits > authorizedShares`; normal unit updates apply deltas; void/burn release
  units; unvoid restores them. Scripification and recertification are representation-only, so
  scripified units count exactly once.
- New printers use `createCertPrinterWithClassTerms` to create and configure atomically. Existing
  printers use owner-gated `migrateClassTermsControllers`. The complete batch is valid
  `upgradeToAndCall` payload, so upgrading a corp's manager and migrating all of its supplied
  printers occurs in one transaction. It derives outstanding active plus scrip units on-chain and
  rolls back the implementation upgrade plus every prior printer change if any migration fails.
  After any controller is installed, the migration entry point refuses to replace it; later changes
  use the controller's governed UUPS/amendment paths.
- The upgraded manager deliberately fails closed for an unmigrated legacy share renderer:
  lifecycle operations cannot silently bypass cap enforcement. Upgrade and per-printer migration
  therefore belong in one owner-controlled batch for every in-scope corp.
- `amendClassTerms` supports authorized corporate amendments but refuses to reduce authorization
  below issued units.
- The first in-printer implementation was rejected after size verification: it made
  `CyberCertPrinter` 28,979 bytes, 4,403 bytes over EIP-170. On the current `develop` baseline,
  the external controller is 7,531 bytes; the final `CyberCertPrinter` is 23,644 bytes
  (932-byte margin), and `IssuanceManager` is 18,662 bytes (5,914-byte margin). The disabled
  legacy `IssuanceManagerWithMigration` prototype is not part of the deployable artifact set.
- Focused verification: `CyberCertPrinterClassTermsTest` **10/10**, including atomic manager
  upgrade plus multi-printer migration, full-batch rollback, length validation, and
  controller-replacement rejection; `IssuanceManagerScripComplianceTest` **7/7**; and
  `ScripPOCTest` **15/15**. The full production size build passes.
- Remaining rollout: upgrade the renderer, deploy the controller, set the IssuanceManager 4.2
  reference, batch-upgrade/migrate only the named demo and real-pilot printers, then release the
  matching webapp ABI/read path and verify live read-back. Test-corp migration is not a release gate.

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

**Implemented design.**

- The complete `SeriesTerms` struct is class-level. `CertificateData` and the variable-length
  per-certificate arrays remain per-certificate.
- Canonical data is stored by the external controller as ABI-encoded terms plus a hash, avoiding
  a duplicate giant Solidity struct and keeping the already-near-limit printer deployable.
- The cap is on-chain and uses the protocol's 18-decimal unit representation.
- Terms may be amended only through an explicit owner-gated operation with the issued-unit floor.

**Remaining decisions / follow-up.**

1. Define the evidence and approval record required before a production `amendClassTerms`.
2. Add indexer/OCF class-level fields if direct RPC reads prove insufficient for reporting scale.
3. Decide whether non-share instruments need analogous canonical records; P2 intentionally applies
   only to extensions that advertise `EXTENSION_TYPE == keccak256("SHARE")`.

**References.** `src/storage/extensions/ShareClassTermsController.sol`;
`src/storage/IssuanceManagerStorage.sol`; `src/CyberCertPrinter.sol:107` (initialize — identity only, no terms);
`src/storage/extensions/ShareExtension.sol:143-150` (the terms struct, encoded per-cert) + `:286-305`
(rendered per-cert into tokenURI); `src/storage/CyberCertPrinterStorage.sol:51` (`CertificateDetails.extensionData`);
`src/IssuanceManager.sol:229` (`createCertPrinter`). Webapp side: `metalex-webapp` **M1** (pre-fill blocked by
this) in its `notes/plans/mainframe-changes-plan.md`.

---

## P3 — Issuer-defined award templates (grants) — `TARGET LOCAL / UNRELEASED`

**Full evaluation:** `notes/plans/issuer-award-templates-plan.md` (three options, recommendation,
per-option contract + app changes). Summary below.

**Status update (2026-07-19).** The recommended Option A target is now implemented
locally. `createTemplate` is restored to `onlyOwner` for curated caller-chosen IDs;
permissionless issuers use the new `createTemplatePublic`, which derives
`keccak256(abi.encode(title, legalContractUri, globalFields, partyFields))` on-chain
and treats identical content idempotently. `_createTemplate` now rejects an empty legal
URI so existence cannot remain ambiguous. Five focused security/upgrade tests cover the
owner gate, permissionless content addressing, idempotency, empty-URI rejection, and proxy
state preservation; the focused registry suite passes 18/18 with `forge test --via-ir`. The deployment script
uses the new `UpgradeV3.3.0` salt. The companion webapp ABI and issuer registration call
now target `createTemplatePublic`, while retaining read-back hash verification for
pre-upgrade registry state.

This code is **not live yet**. The currently deployed **interim** variant remains:
commit `7edb89d` removed `onlyOwner` from
the caller-chosen-id `createTemplate` and the registry proxy was upgraded (verified live on
Base + Ethereum mainnet, 2026-07-08). This is deliberately **temporary** — it is the
squattable caller-chosen-id variant the full doc warns against, accepted for now to unblock
issuer self-serve; the webapp compensates with content-addressed ids + DB-side provenance.
Drawbacks, required app-layer mitigations, and the recommended optimal end-state (re-gate
`createTemplate` + add content-addressed `createTemplatePublic`, i.e. Option A) are recorded
in the full doc's §0.

**Webapp side:** the compensating app layer shipped in 2026-07, and the current local
worktree additionally switches registration to `createTemplatePublic`. The shipped layer is
self-serve
per-corp award templates with content-addressed registration against the now-permissionless
`createTemplate` (`metalex-webapp` PR #801, merged 2026-07-08) and bespoke per-recipient
agreements (`metalex-webapp` PR #803, merged 2026-07-08). The target contract and app changes
must be released together after proxy-upgrade simulation; until then the live webapp continues
to use the interim entry point.

**Problem.** cyberCORPs grants register the award agreement in the **global, MetaLeX-owned**
`CyberAgreementRegistry`, and the MetaVesT controller's `proposeAndSignDeal(templateId, …)`
calls `registry.createContract`, which reverts `TemplateDoesNotExist` unless the template is
pre-registered (`src/CyberAgreementRegistry.sol:263-266`; `MetaVesTControllerStorage.sol:220`).
The only registration entry point, `createTemplate`, is **`onlyOwner`** (`:230-244`;
`onlyOwner` = registry BorgAuth role ≥ 99, `src/libs/auth.sol:190`). So **every corp shares one
award template that only MetaLeX can register** — a founder cannot register their own custom
award agreement. This is the last setup blocker for self-serve grants (the webapp already ships
an admin "Register award template" page, but it can only be driven by the registry owner —
`metalex-webapp` PR #771). _[Stale as of the interim ship: `createTemplate` is now permissionless
(commit `7edb89d`) and the admin page is open to issuer self-serve via `metalex-webapp` PR #801 —
see Status update above. Kept as the record of the pre-2026-07-07 state that motivated this item.]_

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

## P4 — Control-agreement liens & permissionless foreclosure — `PROPOSED`

**Full spec:** `notes/plans/control-agreement-encumbrance-spec.md`.

Model a UCC Article 8/9/12 control-agreement lien over a cyberCERT without moving
custody to the lender: the borrower remains registered/ERC-721 owner until a
condition-verified foreclosure re-registers and transfers the shares. The full spec
pins the lien state machine, collateral escape guards, agreement-party verification,
conditions, upgrade/storage constraints, web/indexer surface, and Foundry test plan.

_Status check 2026-07-19:_ no `Lien`/encumbrance/foreclosure state, entry points,
conditions, extension, or tests exist in `src/`/`test/`. This item was originally
described as P3 before issuer templates took that slot; P4 is now canonical.

---

## Backlog (unprioritized)

_(none beyond P1–P4 yet)_
