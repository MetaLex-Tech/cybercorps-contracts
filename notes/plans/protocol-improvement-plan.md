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

## P3 — Control-agreement liens & permissionless foreclosure for share-NFTs — `PROPOSED`

**Problem.** The protocol can mint registered-share NFTs (`CyberCertPrinter` certs), but there is no
on-chain way for a lender to take a perfected-by-control security interest in a specific cert while the
borrower remains the registered owner. Today, a borrower that remains `ownerOf` / `legalOwnerOf` can still
move or dissolve the collateral through ordinary transfer, endorsement, scripification, conversion, or
issuer-admin paths; and a lender has no permissionless foreclosure path that honors an up-front issuer
control agreement without requiring a fresh issuer act at default.

This leaves the protocol unable to model the PEB/UCC Article 8 / 9 / 12 control-agreement case study for
tokenized registered shares: control by the secured party must be distinct from possession or registered
ownership, and foreclosure must be driven by the secured party's instruction once default is objectively
established.

**Desired model.** Add a **Control-Agreement Lien (CAL)** regime directly to the cert printer / issuance
manager surface:

- The share-NFT stays in the borrower's wallet, and `legalOwnerOf(tokenId)` remains the borrower until
  foreclosure, preserving voting and distribution rights keyed to the registered owner.
- Control is represented by an ordered, active `Lien` record on the cert printer, not by custody. The
  senior active `Lien.lender` is the party whose re-registration instruction the protocol will honor.
- `encumberCert` is the issuer's one-time 8-106(c)(2) pre-consent: it validates a finalized, signed
  three-party `CyberAgreementRegistry` control agreement whose signed terms bind the exact
  `certAddress`, `tokenId`, and units represented.
- While a lien is active, the cert printer itself blocks borrower and issuer escape paths: transfer,
  borrower endorsement shadowing, scripification drain, convert-scrip mutation of the encumbered cert,
  void, burn, assign, per-token re-enabling of transferability, and latent certificate-detail mutation.
- `foreclose` is permissionless with respect to the issuer: it has no role modifier, but internally honors
  only the senior lender's instruction after the lien's `defaultCondition` reads true.
- Release is borrower-protective: the lender can release, but repayment / satisfaction / sunset paths can
  also clear the lien without letting a repaid lender grief the borrower.

**Design direction (implementation sketch).**

- Append a `Lien` model and lien indexes to `CyberCertPrinterStorage`: ordered `liens[tokenId]`,
  `lienActive[tokenId]`, and indexing-only `encumberedCount`, with terminal `Released` / `Foreclosed`
  statuses and `createdAt` evidence for time-of-control.
- Add `CyberCertPrinter.encumber`, `releaseLien`, `forecloseTo`, and views
  `getLiens`, `seniorActiveLien`, `hasActiveLien`. Add a foreclosure context flag on the printer so
  `_update` can distinguish authorized foreclosure from ordinary transfer.
- Edit `CyberCertPrinter._update` so the encumbrance gate runs before transferability checks,
  deal/round-manager carve-outs, and global restriction hooks. The foreclosure branch bypasses those
  gates and re-registers `owners[tokenId]` directly from lien-derived `to` / `toName`; foreclosure
  endorsements are audit records only.
- Add `IssuanceManager.encumberCert`, `releaseEncumbrance`, and `foreclose`, with `ReentrancyGuard` on
  both the manager and printer. `encumberCert` stays `onlyAdmin`; release and foreclosure are
  modifier-less but internally gated by lien status, signature/condition checks, seniority, and lender
  identity.
- Add on-chain validation helpers around `CyberAgreementRegistry`: the agreement must be finalized,
  non-voided, signed by the resolved issuer officer, borrower, and lender, and expose signed global
  values for `certAddress`, `tokenId`, and units represented.
- Add `ICondition` predicates under `src/libs/conditions/` for default and release triggers:
  maturity default, neutral-arbiter default, oracle/non-payment default, and repayment/satisfaction
  release. Conditions authorize; they never move the NFT.
- Close collateral-integrity drains in the state-owning contracts: `executeScripifyCert` rejects
  encumbered certs; `_selectRecertToken` skips encumbered certs; issuer void/burn/assign/detail-update
  paths reject active liens; borrower `addEndorsement` rejects while encumbered.
- Surface events and errors for indexers and callers: `CertEncumbered`, `CertReleased`,
  `CertForeclosed`, plus `CertEncumbered()`, `NoActiveLien()`, `NotSeniorLien()`, `NotLender()`, and
  `DefaultNotMet()`.
- Treat storage as append-only and deploy through the existing UUPS / beacon upgrade paths, with storage
  layout diff tests and no back-fill: existing certs read unencumbered until explicitly pledged.

**Open questions.**

1. **Sale proceeds.** v1 can re-register to the lender or a lender-designated buyer with proceeds handled
   off-chain; v2 may add an on-chain buyer → lender → surplus-to-borrower waterfall.
2. **Foreclosure buyer policy.** Should v1 allow any lender-designated `to`, or require `to == lender`
   unless a designated-buyer condition / agreement value is present?
3. **Transient storage.** Use Solidity transient storage for foreclosure context on Base if the pinned
   0.8.28 target supports it; otherwise use an appended regular slot set and cleared inside
   `nonReentrant forecloseTo`.
4. **Subordination / re-ranking.** v1 should use strict first-recorded array order; contractual
   subordination or dual-consent re-ranking is a v2 feature.
5. **Satisfaction evidence.** Define the minimal registry shape for a lender-signed satisfaction
   agreement and the safest snapshot/finalized repayment predicate so a spot balance cannot trigger
   premature release.
6. **Webapp/indexer split.** Track the companion surface separately: encumbrance badges, create-lien
   wizard, lender foreclosure action, release action, disabled borrower/issuer escape actions, and Envio
   `Lien` / `Encumbrance` entities.

**References.** `src/CyberCertPrinter.sol` (`_update`, ownership registration, transferability,
endorsement, void/burn/assign paths); `src/storage/CyberCertPrinterStorage.sol` (append-only cert
storage); `src/IssuanceManager.sol` / `src/storage/IssuanceManagerStorage.sol` (issuance, scripify,
convert-scrip-to-cert, UUPS surface); `src/CyberAgreementRegistry.sol` (finalized signed control
agreement and signed global values); `src/interfaces/ICondition.sol` and `src/libs/conditions/`
(default/release predicates); PEB UCC tokenization report, Case Study 2.

---

## Backlog (unprioritized)

_(none yet — add future protocol improvements here)_
