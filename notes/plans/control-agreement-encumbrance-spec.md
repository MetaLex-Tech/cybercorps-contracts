# cyberCORPs Protocol — Control-Agreement Liens & Permissionless Foreclosure (CAL) — `PROPOSED`

> **Status (2026-07-19): `PROPOSED` — nothing implemented on develop.** Spec added 2026-06-27
> (commit `93faa94`). Verified against develop: no lien/encumbrance/foreclosure code exists in
> `src/` — none of the §18 files have been touched for this feature, and `src/libs/conditions/`
> still contains only the pre-existing conditions (no `MaturityDefaultCondition` /
> `ArbiterDefaultCondition` / `OracleNonPaymentCondition` / `RepaidCondition`). The §15 roadmap
> deliverable — a stub in `notes/plans/protocol-improvement-plan.md` — is now present as **P4**. The
> plan's **P3** slot has since been taken by "Issuer-defined award templates" (commit `3923b4b`,
> interim-shipped 2026-07-08 via `7edb89d`); this spec is therefore canonical protocol item **P4**.

**Scope.** A full design spec for tying **UCC Article 8 / 9 / 12 control agreements** to cyberCORPs
share-NFTs (`CyberCertPrinter` tokens) so the underlying registered shares become **encumbered by a
lender's security interest** — perfected *by control* — and can be **permissionlessly foreclosed**
on default. This is a protocol-side feature (`src/`); a companion webapp/indexer surface is sketched
at the end. Promote to implementation as protocol item **P4**.

**Legal anchor.** Permanent Editorial Board for the UCC, *Report on the "Tokenization" of Securities
Transfers Under the Uniform Commercial Code* (Draft for Public Comment, Apr 24 2026), **Case Study 2
— Security Interest in the ABC Shares**. This design implements that case study on-chain. The PEB
report is the controlling mental model; section [§13 PEB/UCC traceability](#13--pebucc-traceability-matrix)
maps every legal concept to a concrete mechanism.

**Provenance.** Synthesized from three competing architectures (in-place encumbrance / escrow-custody
vault / control-agreement-extension), scored by a judge panel, then hardened against three
independent adversarial reviews (legal-fidelity, smart-contract-security, integration/upgrade-safety).
Every reviewer issue is folded in as a resolved decision; see [§11 Security analysis](#11--security-analysis-resolved-adversarial-findings).

---

## 1 — Summary

The chosen model is **Control-Agreement Lien (CAL): in-place encumbrance with an issuer-bound
foreclosure registrar.**

- **No custody.** The share-NFT stays in the **borrower's** wallet. The borrower remains *both* the
  ERC-721 `ownerOf` **and** the registered owner (`owners[tokenId].ownerAddress` / `legalOwnerOf`,
  `src/CyberCertPrinter.sol:516`) for the entire life of the loan. This is the keystone PEB fn-97
  behavior: *the secured party obtains control without becoming the registered owner.*
- **Control is reified as a record, not as possession.** A new `Lien` struct on the cert printer
  names the **lender** as the party whose re-registration **instruction** the protocol will honor.
  "Control" (UCC 12-105 / 8-106(c)(2)) is the senior active `Lien.lender` — distinct from `ownerOf`
  and `legalOwnerOf`.
- **The control agreement is a real, signed instrument.** A finalized 3-party
  `CyberAgreementRegistry` agreement (issuer officer + borrower + lender), whose signed terms commit
  to *this* `certAddress`+`tokenId`, *is* the on-chain UCC 8-106(c)(2) consent. `encumberCert`
  validates that instrument before installing the lien.
- **Encumbrance is a hard regime owned by the cert printer.** While a lien is `Active`, the printer
  itself reverts every borrower-escape and every issuer-de-perfection lever — transfer, scripify,
  convert-scrip-to-cert, void, burn, assign, re-enabling transferability — with `CertEncumbered()`.
  Enforcement lives in the contract that owns the state, **not** in a swappable/disable-able transfer
  hook.
- **Foreclosure is permissionless w.r.t. the issuer.** A single new `foreclose(...)` entry point on
  `IssuanceManager` (no role modifier, idiomatic to the existing modifier-less `scripifyCert` /
  `convertScripToCert`) re-registers the shares to the lender or a designated buyer **once a pluggable
  default `ICondition` reads true** — with **no fresh discretionary act by the issuer**. The issuer's
  only act was the one-time `encumberCert` pre-consent.
- **Release protects the borrower.** Repayment releases the lien via a permissionless `repaidCondition`
  or a signed satisfaction agreement, so a lender cannot grief a repaid borrower.

**Why in-place won.** The escrow-custody vault makes the vault the ERC-721 owner, which (a) implements
the *wrong* PEB token-use (an **instruction/custody token**, PEB use (a)) instead of the **control-
agreement token** (use (b)); (b) cannot represent two competing perfected-by-control interests on one
indivisible NFT (breaks UCC 9-328 ranking); and (c) risks stripping the borrower's registered
ownership. The standalone-manager extension model fails because any separate manager that drives the
printer needs `BorgAuth` role ≥ 98, which hands it the **entire** issuer-admin surface (mint/void/
re-register any cert) — an unacceptable privilege escalation. CAL avoids both by keeping the NFT in
place and adding the three new entry points **directly on the existing `IssuanceManager`**, the single
address the printer already trusts (`onlyIssuanceManager`, `src/CyberCertPrinter.sol:97-100`).

---

## 2 — Goals / non-goals

**Goals.**

1. A lender can obtain a security interest in specific registered shares, **perfected by control**,
   that survives the borrower remaining registered owner.
2. The borrower keeps **voting and distributions** (registered-owner rights) until foreclosure.
3. The borrower **cannot dissolve or move** the collateral while encumbered.
4. The issuer **cannot de-perfect or destroy** the collateral once it has consented.
5. On default, the lender (or anyone — only the lender's instruction is honored) can **foreclose
   permissionlessly**, re-registering the shares to the lender or a buyer, with **no issuer action**.
6. Multiple liens on one cert with **deterministic priority** (control beats off-chain filing;
   senior-before-junior among control liens).
7. **Release** on repayment with a borrower-protective permissionless escape.

**Non-goals (v1).**

- On-chain commercially-reasonable **sale-proceeds waterfall** (buyer → lender → surplus to borrower).
  v1 re-registers to a lender-designated `to`; proceeds economics are off-chain. (See [§12 Open
  decisions](#12--open-decisions) Q2.)
- **Contractual subordination / re-ranking** of existing liens (senior agrees to rank below junior).
  v1 is strict first-recorded order; re-rank is v2. (Q5.)
- A new on-chain voting or dividend engine. This protocol has none today (ShareExtension fields are
  metadata-only; `computeAccruedDividends` is commented out) — CAL relies on that and simply keeps
  `legalOwnerOf` with the borrower.
- Tokenizing the **security itself** in the property-transfer sense. Per the PEB report, we tokenize
  the **instruction / control agreement**, not the share's proprietary interest.

---

## 3 — Architecture overview

```
            ┌──────────────────────── CyberAgreementRegistry ────────────────────────┐
            │  Control Agreement (finalized, 3 parties, signed terms bind cert+tokenId)│
            │   parties: issuerOfficer, borrower, lender   →  agreementId               │
            └───────────────▲──────────────────────────────────────────┬──────────────┘
                            │ (1) create + sign + finalize              │ validated by
                            │                                           │ encumberCert
   ┌────────────┐   (2) encumberCert (onlyAdmin, one-time consent)   ┌──┴───────────────┐
   │ Issuer     │──────────────────────────────────────────────────▶│ IssuanceManager  │
   │ officer    │                                                    │  (the ONLY        │
   └────────────┘                                                    │  onlyIssuanceMgr  │
                                                                     │  caller)          │
   ┌────────────┐   (4b) foreclose(...)  [NO modifier — permissionless]                  │
   │ Lender     │──────────────────────────────────────────────────▶│  encumberCert     │
   │ (control)  │   (4a) releaseEncumbrance(...) [permissionless]    │  releaseEncumbrance│
   └────────────┘                                                    │  foreclose        │
                                                                     └──┬───────────────┘
                                  onlyIssuanceManager calls               │
                                                                          ▼
   ┌──────────────────────────────── CyberCertPrinter (ERC721) ──────────────────────────┐
   │  liens[tokenId]: Lien[]   lienActive[tokenId]: bool                                   │
   │  encumber() / releaseLien() / forecloseTo() (nonReentrant)                            │
   │  _update(): hard encumbrance gate — reverts CertEncumbered except foreclosure context │
   │  borrower stays ownerOf + legalOwnerOf until foreclosure                              │
   └──────────────────────────────────────────────────────────────────────────────────────┘
                                          │ default trigger (view)
                                          ▼
   ┌──────────── ICondition default predicates (src/libs/conditions) ─────────────┐
   │  MaturityDefaultCondition (trustless)  ArbiterDefaultCondition  OracleNonPayment │
   └──────────────────────────────────────────────────────────────────────────────┘
```

**The three actors and their on-chain capabilities:**

| Actor | Pre-encumbrance | While encumbered | At default |
|---|---|---|---|
| **Borrower** (registered owner) | full control of NFT | keeps voting/distributions (off-chain, keyed to `legalOwnerOf`); **cannot** transfer/scripify/convert/void/burn/assign; **cannot** push endorsements | loses shares to foreclosure |
| **Lender** (secured party / control) | — | holds **control** (the lien record); cannot re-register before default | calls `foreclose` to re-register to itself or a buyer |
| **Issuer** (cyberCORP officer) | — | one-time `encumberCert` consent already given; **cannot** void/burn/assign/re-enable transfer to de-perfect | **does nothing** (permissionless) |

---

## 4 — Data model

A single new struct on the cert printer's storage library, plus three maps.

```solidity
// src/storage/CyberCertPrinterStorage.sol — defined at file scope alongside Endorsement/OwnerDetails
enum LienStatus { None, Active, Released, Foreclosed }   // 0/1/2/3; Released & Foreclosed terminal

struct Lien {
    address lender;            // securedParty: the ONLY instruction foreclose() honors. "Control" reified.
    address registry;          // CyberAgreementRegistry holding the control agreement
    bytes32 agreementId;       // the finalized 8-106(c)(2) instrument (reuses Endorsement's (registry,agreementId) pair)
    address defaultCondition;  // ICondition; only thing that can flip the foreclosure gate true
    address repaidCondition;   // ICondition for permissionless release; address(0) => lender/satisfaction only
    address arbiter;           // per-lien NEUTRAL address for attested default; MUST NOT be issuer (enforced)
    uint256 maturity;          // timestamp consumed by MaturityDefaultCondition; 0 if not maturity-triggered
    uint256 createdAt;         // block.timestamp at encumber — evidences time-of-control for 9-328(2)
    uint256 sunset;            // optional backstop: after this, releaseEncumbrance is permissionless (anti-stuck-collateral); 0 = none
    uint256 ranking;           // priority rank, mirrors array index (0 = senior); stored for indexing clarity
    LienStatus status;         // None/Active/Released/Foreclosed
}
```

```solidity
// APPENDED to struct CyberCertStorage, AFTER issuerSignatures (respect the
// "New variables must be appended below" marker, ~src/storage/CyberCertPrinterStorage.sol:100;
// fixed slot keccak256('cybercorp.cert.printer.storage.v1') — append-only, no __gap consumed)
mapping(uint256 => Lien[]) liens;        // ordered, append-only; index 0 = senior
mapping(uint256 => bool)    lienActive;  // hot-path boolean read in _update (any lien Active?)
uint256                     encumberedCount; // class-level count — INDEXING ONLY (not an enforcement lock; see §11-I8)
```

**Foreclosure context flag (not in the struct).** `_update` must recognize the foreclosure path. A
struct field **cannot** carry Solidity's `transient` keyword (it applies only to contract-level state
variable declarations, not to members accessed via the diamond `s.slot := position` pattern). Declare
it **directly on the `CyberCertPrinter` contract**:

```solidity
// contract-level on CyberCertPrinter (NOT in the storage library struct)
uint256 private transient _foreclosingToken;   // TSTORE/TLOAD, auto-zeroed per tx (Base is post-Cancun)
```

Fallback if the pinned 0.8.28 build/target does not enable transient storage: a regular appended slot,
**set before `_transfer` and cleared after**, inside the `nonReentrant forecloseTo`. (See Q3.)

**No shape changes** to `CertificateDetails`, `Endorsement`, or `OwnerDetails` — this preserves the
`CertificateEndorsed` event ABI, the URI-builder inputs, and the `getEndorsementHistory` tuple in
`ICyberCertPrinter.sol`. The lien deliberately **reuses** the `(registry, agreementId)` pair the
`Endorsement` struct already carries (`src/storage/CyberCertPrinterStorage.sol:61-69`).

---

## 5 — Lifecycle & state machine

```
   (no lien)
      │  encumberCert  (issuer onlyAdmin, one-time; validates signed control agreement)
      ▼
   ACTIVE ───────────────────────────────────────────────┐
      │                                                   │
      │ releaseEncumbrance                                │ foreclose
      │ (lender OR repaidCondition true OR satisfaction   │ (lender; defaultCondition true; senior lien)
      │  agreement OR past sunset)                        │
      ▼                                                   ▼
   RELEASED  (terminal; borrower regains full control)  FORECLOSED (terminal; shares re-registered to to)
```

1. **Control agreement (the legal instrument).** Borrower/lender propose; **issuer officer**
   (BorgAuth role 200), borrower, and lender each EIP-712-sign the actual control-agreement doc URI
   via `CyberAgreementRegistry.signContractFor`; `finalizeContract` on the last signature. The
   issuer's signature on the doc **is** the on-chain 8-106(c)(2) consent. **The agreement's signed
   terms must include `certAddress` + `tokenId` (and `unitsRepresented`)** — see [§10](#10--control-agreement-binding--party-verification).
2. **Encumber (perfection by control).** Issuer officer calls `IssuanceManager.encumberCert(...)`
   (`onlyAdmin` — the deliberate one-time pre-consent). `executeEncumberCert` validates the agreement
   (finalized, not voided, signed by the resolved issuer/borrower/lender addresses, signed terms bind
   *this* cert+tokenId), validates the cert (not voided, not partly-scripified, `legalOwnerOf ==
   borrower`, `arbiter != issuer`), then `cert.encumber(...)` pushes a `Lien{Active}`, sets
   `lienActive[tokenId]=true`, `encumberedCount++`, stamps `createdAt`. **NFT never moves; `owners[]`
   never touched. Security interest perfected by control.**
3. **During the loan.** Borrower stays `ownerOf` + `legalOwnerOf` → voting/distributions stay with
   borrower. Borrower and issuer are both barred from the dissolution levers (see [§9](#9--collateral-integrity-closing-every-escape)).
4a. **Repayment → release.** `IssuanceManager.releaseEncumbrance(...)` — permissionless. Internal
   gate passes if `msg.sender == lien.lender` **OR** `repaidCondition.checkCondition() == true` **OR**
   a finalized satisfaction agreement exists **OR** `block.timestamp >= lien.sunset` (if set). Sets
   `status = Released`, recomputes `lienActive`. Registration was continuous — nothing re-registers.
4b. **Default → permissionless foreclosure.** `IssuanceManager.foreclose(certAddress, tokenId,
   lienIndex, to, toName)` — no modifier. Internal gates: `lienIndex == seniorActiveLien`,
   `msg.sender == lien.lender`, `defaultCondition.checkCondition() == true`, agreement not voided.
   Then `cert.forecloseTo(...)` (nonReentrant) re-registers `owners[tokenId] = to` and moves the NFT.
   `status = Foreclosed`. **Issuer did nothing at default time.**
5. **Multiple liens.** Each `encumberCert` appends (index 0 senior). `foreclose` honors only the
   senior active lien; a junior lender's call reverts `NotSeniorLien`.

---

## 6 — Contract changes

### 6.1 `src/CyberCertPrinter.sol`

- **ADD** `encumber(uint256 tokenId, Lien calldata lien) external onlyIssuanceManager` — push lien
  (`Active`), set `lienActive[tokenId]=true`, `encumberedCount++`, emit `CertEncumbered`. Revert if
  `isVoided(tokenId)` or the cert is partly-scripified (`getCertScripifiedStatus(...).scripifiedUnits
  > 0`) unless its scrip pool is frozen.
- **ADD** `releaseLien(uint256 tokenId, uint256 lienIndex) external onlyIssuanceManager` —
  `setLienStatus(Released)`, recompute `lienActive[tokenId]`, decrement `encumberedCount` if it falls
  to zero, emit `CertReleased`.
- **ADD** `forecloseTo(uint256 tokenId, uint256 lienIndex, address to, string calldata toName)
  external onlyIssuanceManager nonReentrant` — the registrar. Detailed in [§7](#7--foreclosure-design).
  **Add `ReentrancyGuard` to the printer** (it is not guarded today).
- **EDIT `_update` (`~:246-311`)** — insert the encumbrance gate and the foreclosure branch. Pinned
  control flow in [§8](#8--the-_update-control-flow-pinned).
- **EDIT dissolution levers** to honor the lien (revert `CertEncumbered()` when
  `lienActive[tokenId]`, except the foreclosure context): `voidCert` (`~:344`), `burn` (`~:234`),
  `assignCert` (`~:180`), `setTokenTransferable` (`~:508`, when `value` would re-enable). Guard the
  storage-owning `updateCertificateDetails` (`~:229`) too, so a future re-enable of the external
  setter cannot zero `unitsRepresented` on encumbered collateral.
- **EDIT `addEndorsement` (`~:198`)** — while `lienActive[tokenId]`, reject pushes where
  `msg.sender == ownerOf(tokenId)` (the borrower). Only `issuanceManager`-mediated foreclosure
  endorsements may be added, eliminating borrower endorsement-shadowing.
- **Class-wide setters** `setGlobalTransferable` (`~:137`) / `setGlobalRestrictionHook` (`~:132`):
  **do not** add an `encumberedCount` lock (it would freeze policy for an entire share class — possibly
  hundreds of holders — because one position is pledged). Instead the per-token lien gate in `_update`
  is **authoritative and positioned before the global-hook consultation**, so flipping class flags can
  never free an encumbered token. (See [§11-I8](#11--security-analysis-resolved-adversarial-findings).)
- **ADD views** `getLiens(uint256)`, `seniorActiveLien(uint256) returns (Lien, uint256 index, bool
  found)`, `hasActiveLien(uint256)`.

### 6.2 `src/storage/CyberCertPrinterStorage.sol`

- **APPEND** the `Lien` struct (file scope) + the three maps (§4), after `issuerSignatures`.
- **ADD** internal helpers: `addLien`, `getLiens`, `setLienStatus`, `seniorActiveLien` (lowest-index
  `Active`), `hasActiveLien`, `recomputeLienActive`.

### 6.3 `src/IssuanceManager.sol`  (add `ReentrancyGuard`; mark the three entry points `nonReentrant`)

- **ADD** `encumberCert(address certAddress, uint256 tokenId, address lender, address registry,
  bytes32 agreementId, address defaultCondition, address repaidCondition, address arbiter,
  uint256 maturity, uint256 sunset, uint256 ranking) external onlyAdmin nonReentrant`
  → `IssuanceManagerStorage.executeEncumberCert`. `onlyAdmin` = the issuer's one-time discretionary
  8-106(c)(2) pre-consent.
- **ADD** `releaseEncumbrance(address certAddress, uint256 tokenId, uint256 lienIndex) external
  nonReentrant` (**no role modifier — permissionless**) → `executeReleaseEncumbrance`.
- **ADD** `foreclose(address certAddress, uint256 tokenId, uint256 lienIndex, address to,
  string calldata toName) external nonReentrant` (**no role modifier — permissionless**) →
  `executeForeclose`.
- Mirror all three in `src/interfaces/IIssuanceManager.sol`; keep `IssuanceManagerStorage`
  error/event declarations in sync (house duplication convention).

### 6.4 `src/storage/IssuanceManagerStorage.sol`

- **ADD `executeEncumberCert`** — validation gate before `cert.encumber` (full detail in §10):
  - `ICyberCertPrinter(certAddress).legalOwnerOf(tokenId) == borrower`;
  - agreement `isFinalized && !isVoided`;
  - the resolved **issuer officer address**, the **borrower**, and the **lender** each
    `registry.hasSigned(agreementId, addr) == true` (not mere `getParties` membership);
  - the agreement's signed terms bind **this** `certAddress`+`tokenId` (read signed global values);
  - reject role collisions (`borrower != lender`, `borrower != issuer`, `lender != issuer`);
  - `arbiter != issuerOfficer && arbiter != owner`;
  - cert not voided and not partly-scripified.
- **ADD `executeReleaseEncumbrance`** — gate: `msg.sender == lien.lender` OR
  `ICondition(repaidCondition).checkCondition(...) == true` OR a finalized **satisfaction** agreement
  exists OR `block.timestamp >= lien.sunset`. Then `cert.releaseLien`.
- **ADD `executeForeclose`** — gates in [§7](#7--foreclosure-design); then `cert.forecloseTo`.
- **EDIT `executeScripifyCert` (`~:855`)** — add `if (ICyberCertPrinter(certAddress).hasActiveLien(id))
  revert CertEncumbered();` **before** the `legalOwnerOf` check. (`id` exists here — this is the real
  drain chokepoint.)
- **EDIT `_selectRecertToken` (`~:1190-1205`)** — skip any tokenId with `hasActiveLien`, so
  `convertScripToCert` can never write reconstituted scrip **into** an encumbered cert and mutate its
  `unitsRepresented`. (See [§9](#9--collateral-integrity-closing-every-escape) for why the naive
  `convertScripToCert` guard in earlier drafts was unbuildable.)

### 6.5 New `ICondition` predicates — `src/libs/conditions/`

All implement the existing one-method interface `checkCondition(address,bytes4,bytes) view returns
(bool)` (`src/interfaces/ICondition.sol`) and inherit `BaseCondition`
(`src/libs/conditions/baseCondition.sol`), exactly like the shipped
`IssuerApprovalRecertificationCondition` / `NonUSNationalityCondition` / `lexchexCondition`. They are
**view-only — they authorize, they never move the NFT** (the "may I?" vs "do it" separation the
escrow `conditionCheck` already uses, `src/libs/LexScroWLite.sol:260-270`). Each decodes
`data = abi.encode(certAddress, tokenId, lienIndex)` so it is scoped to the exact lien, and branches
on the `foreclose` selector (cf. `IssuerApprovalRecertificationCondition` `~:63`).

- **`MaturityDefaultCondition`** (canonical, trustless): `block.timestamp >= lien.maturity`.
- **`ArbiterDefaultCondition`**: a per-lien **neutral arbiter address** (stored in `Lien.arbiter`,
  validated `!= issuer` at encumber) flips `defaultDeclared[cert][tokenId][lienIndex]`;
  `checkCondition` reads it. **Not** gated on a BorgAuth role — that would let the issuer (officer 200
  ≥ ADMIN 98) declare/suppress default and re-grant a foreclosure veto.
- **`OracleNonPaymentCondition`**: reads a non-payment boolean from an external loan-servicing /
  repayment registry (clone of `lexchexCondition`); trustless iff the loan's cash leg is on-chain.
- **`RepaidCondition`** (for permissionless release): on-chain-repayment variant reads a **finalized/
  snapshot** loan-escrow balance == 0 (not a spot balance — see [§11-S6](#11--security-analysis-resolved-adversarial-findings)).
- Compose triggers via the existing `OrCondition` (`src/libs/conditions/OrCondition.sol`); there is no
  `AndCondition` — AND is implicit by stacking checks.

### 6.6 `src/storage/extensions/ControlAgreementExtension.sol` — OPTIONAL, read-only

Implements `ICertificateExtension` for `tokenURI` surfacing, exactly as `ShareExtension` serializes
its terms (pure serialization, **zero enforcement**). `supportsExtensionType` returns true for
`keccak256("CONTROL_AGREEMENT")`; `getExtensionURI` decodes `{securedParty, agreementId, ranking,
status, maturity}` from the per-token `extensionData` blob into a JSON fragment. It reads **lien
state / `Lien.status`** — never the raw registry `isVoided` — so the displayed encumbrance always
matches the enforced lien.

### 6.7 `src/CyberAgreementRegistry.sol` — small read additions (correction)

The synthesis claimed "no registry change"; the legal/integration reviews show two **read** helpers
are needed for `executeEncumberCert` to bind the agreement to the collateral on-chain:

- A getter returning the agreement's **parties** and, critically, the **signed global values by key**
  (so `encumberCert` can read the signed `certAddress`/`tokenId`/`unitsRepresented` the parties
  committed to). `hasSigned(agreementId, addr)` and `isParty` already exist (`~:692-712`); confirm a
  `getParties(agreementId)` / `globalValue(agreementId, key)` view is exposed, or add minimal views.
- No storage change (the `uint256[40] __gap` stays untouched); these are view additions only.

---

## 7 — Foreclosure design

`foreclose(...)` on `IssuanceManager` has **no access-control modifier** — permissionless at the call
layer, idiomatic to the protocol's existing modifier-less `scripifyCert` / `convertScripToCert`.
Anyone may call it; **only the senior lender's instruction is honored.** The entire security perimeter
is the internal checks in `executeForeclose(certAddress, tokenId, lienIndex, to, toName, msg.sender)`:

1. Load `seniorActiveLien(tokenId)`; revert `NoActiveLien` if none.
2. `require(lienIndex == seniorIndex)` — a junior lien cannot foreclose ahead of a senior (UCC 9-328
   ordering); else `NotSeniorLien`.
3. `require(msg.sender == lien.lender)` — only the controller per the control agreement may originate
   the instruction; else `NotLender`. *(This is what makes it the lender's self-help, not the
   public's — "permissionless" means no **issuer** gate, not anybody-can-seize.)*
4. `require(ICondition(lien.defaultCondition).checkCondition(certAddress, this.foreclose.selector,
   abi.encode(certAddress, tokenId, lienIndex)) == true)` — the default trigger; else `DefaultNotMet`.
5. `require(!ICyberAgreementRegistry(lien.registry).isVoided(lien.agreementId))` — the legal control
   agreement is still live (secondary kill-switch; the primary gate is `lien.status == Active`).
6. (optional) `require(to == lien.lender || isDesignatedBuyer(...))`.

Then `cert.forecloseTo(tokenId, lienIndex, to, toName)` (`onlyIssuanceManager`, `nonReentrant`).
`forecloseTo` follows strict **checks-effects-interactions**:

```
a. set lien.status = Foreclosed; recompute lienActive/encumberedCount;   // EFFECT before interaction
b. set _foreclosingToken = tokenId;                                       // foreclosure context
c. push an audit Endorsement{endorser: lien.lender, endorsee: to, endorseeName: toName,
       registry: lien.registry, agreementId: lien.agreementId};          // the on-chain INSTRUCTION (8-102(a)(12)) — RECORD ONLY
d. _transfer(borrower, to, tokenId);     // routes through _update foreclosure branch (§8)
e. clear _foreclosingToken;
// post-condition assertion: legalOwnerOf(tokenId) == to  (registration actually moved)
```

**Re-registration is driven by the LIEN RECORD, not by an endorsement.** `_update` reads only
`endorsements[len-1]` today (`~:282,293`), and `addEndorsement` is callable by the borrower — so a
"pre-place endorsement then transfer" scheme is borrower-shadowable. The fix (adopted from the
security review): the `_update` **foreclosure branch re-registers `owners[tokenId] =
OwnerDetails(toName, to)` directly from the lien-derived `(to, toName)` and never consults
`endorsements[]`**. The pushed endorsement is an **audit artifact only**. This removes the `len-1`
dependency and any shadow/append race entirely. (Borrower endorsements are *also* blocked while
encumbered, as defense-in-depth.)

**Why no fresh issuer act:** the issuer's only act was the up-front `encumberCert` pre-consent, paired
with the signed registry agreement. At default the trigger is the `defaultCondition`; no issuer
transaction is needed ⇒ **permissionless w.r.t. the issuer**.

**Buyer vs lender:** both supported via the same path (`to` is a parameter). On-chain proceeds
waterfall deferred to v2 (Q2).

---

## 8 — The `_update` control flow (pinned)

The single most security-critical edit. `_update` must (a) **block all non-foreclosure movement** of
an encumbered token — including the existing `from == ownerAddress` no-revert branch (`~:289`), the
`endorsementRequired == false` auto-resync (`~:277`), and the `dealManager`/`roundManager` carve-out
(`~:254`) — and (b) let the **foreclosure context** through, bypassing the built-in transferability
check **and** any external `globalRestrictionHook` (e.g. `WhitelistTransferHook`), then re-register
directly from lien state. Pinned pseudocode (replacing the body of the `if (from != address(0) && to
!= address(0))` block, `~:250-301`):

```solidity
address from = _ownerOf(tokenId);
if (from != address(0) && to != address(0)) {                      // not mint, not burn
    bool isForeclosure = (msg.sender == issuanceManager && _foreclosingToken == tokenId);

    if (!isForeclosure) {
        // ── ENCUMBRANCE GATE (authoritative; OUTSIDE the dealManager/roundManager carve-out) ──
        if (lienActive[tokenId]) revert CertEncumbered();

        // ── existing transferability check (unchanged) ──
        bool globalTransferable = ...transferable;
        bool tokenTransferable  = isTokenTransferable(tokenId);
        if (!globalTransferable && !tokenTransferable
            && from != corp.dealManager() && from != corp.roundManager())
            revert TokenNotTransferable();

        // ── existing global restriction hook (unchanged) ──
        if (address(globalRestrictionHook) != address(0)) {
            (bool ok, string memory reason) = globalRestrictionHook.checkTransferRestriction(from, to, tokenId, "");
            if (!ok) revert TransferRestricted(reason);
        }

        // ── existing endorsement / registered-owner re-registration logic (unchanged) ──
        ... (lines ~274-299 as today) ...
    } else {
        // ── FORECLOSURE PATH: authoritative over transferable flags AND the external hook ──
        // (a perfected secured party's foreclosure is not subject to the issuer's KYC gate)
        emit CertificateAssigned(tokenId, to, toName, companyName());
        owners[tokenId] = OwnerDetails(toName, to);   // re-register DIRECTLY from lien-derived (to,toName)
    }
}
emit CyberCertTransfer(from, to, tokenId);
return super._update(to, tokenId, auth);
```

Notes:
- `toName` is passed into `forecloseTo` and read by the foreclosure branch (thread it via the
  transient context or a paired transient `_foreclosingToName`, cleared with `_foreclosingToken`).
- The encumbrance gate sits **above** the carve-out and the hook, so `dealManager`/`roundManager`
  senders and any global hook cannot move or veto an encumbered token; and the foreclosure path is
  **authoritative** over both the `TokenNotTransferable` revert and the whitelist hook — so foreclosure
  works even on a corp running `transferable == false` and even to a non-whitelisted lender (this
  resolves Q1 in-spec; it is the legal reality that foreclosure is not subject to issuer KYC).
- Mint (`from == 0`) and burn (`to == 0`) paths are unchanged — but `burn` itself is gated
  `CertEncumbered` at the function level (§6.1).

---

## 9 — Collateral integrity: closing every escape

A lien the debtor can empty, or the issuer can neuter, is not a perfected security interest. Every
escape the adversarial reviews found is closed at the **state-owning contract**:

| Escape vector | Why it works absent a guard | Closure |
|---|---|---|
| **Scrip drain** (the most-cited fatal flaw) | `executeScripifyCert` authorizes on `legalOwnerOf == account` (`~:891`), and the borrower stays `legalOwnerOf`; it deducts `unitsRepresented` into class-fungible `CyberScrip`, draining the pledged cert | `executeScripifyCert` (`~:855`) reverts `CertEncumbered` on the specific `id`; **and** `encumberCert` rejects an already-partly-scripified cert (or freezes its scrip pool) so the lender perfects against a fixed quantity |
| **Convert-scrip-to-cert** | `convertScripToCert(certAddress, amount)` has **no tokenId** and `_selectRecertToken` (`~:1190-1205`) auto-picks the first active cert or **mints a fresh** one — could mutate an encumbered cert or reconstitute shares into a new unencumbered cert | `_selectRecertToken` **skips** encumbered tokens, so scrip can never flow into an encumbered cert; the drain source (scripify) is already blocked, so a fresh-cert mint cannot draw from the pledged cert. *(A naive `hasActiveLien(id)` guard on `convertScripToCert` is unbuildable — there is no `id` parameter; do not add it.)* |
| **Ungated transfer** (`from == ownerAddress` no-revert branch, `~:289`; `endorsementRequired==false` auto-resync, `~:277`) | borrower transfers without a matching endorsement and the cert simply moves | the `_update` encumbrance gate reverts **all** non-foreclosure transfers (§8), including these branches |
| **`dealManager`/`roundManager` carve-out** | the `~:254` carve-out relaxes the transferable flag for these senders | the encumbrance gate is placed **above** the carve-out, so it blocks them too |
| **Issuer void / burn / assign** | `voidCert`/`burn`/`assignCert` are `onlyIssuanceManager` and could destroy or administratively re-register the collateral | each reverts `CertEncumbered` while `lienActive` |
| **Issuer re-enables transfer / swaps hook** | `setTokenTransferable(true)` / class-wide flips could relax the token | per-token lien gate is authoritative in `_update` (runs before the hook), so class flags can't free an encumbered token; `setTokenTransferable(true)` on an encumbered token reverts |
| **Borrower endorsement shadowing** | `addEndorsement` is callable by `ownerOf`; a borrower-pushed `endorsements[len-1]` could redirect a transfer | foreclosure re-registers from **lien state**, not endorsements; and borrower `addEndorsement` is blocked while encumbered |
| **Reentrancy via `onERC721Received`** | a malicious `to` re-enters `releaseEncumbrance`/`encumberCert` (different contract than the printer guard) mid-foreclosure | `ReentrancyGuard` on **both** the printer and `IssuanceManager`; strict CEI (status set `Foreclosed` before `_transfer`) |

**Registered-owner retention is preserved throughout.** `encumberCert` never touches `owners[]`; the
NFT never leaves the borrower's wallet. Voting/distributions are off-chain and keyed to `legalOwnerOf`
(this protocol has no on-chain tally and `computeAccruedDividends` is commented out), so they stay
with the borrower with **zero leakage** to the lender. The borrower keeps the governance/economic
rights PEB grants, while being barred from the value-dissolving acts PEB does **not** grant. Only
`foreclose()` (on default) re-registers `owners[tokenId]`.

---

## 10 — Control-agreement binding & party verification

The instrument the whole architecture rests on must be **cryptographically tied to the specific
shares and signed by the actual issuer** — not merely asserted by `encumberCert`'s parameters
(legal review, two HIGH findings).

- **Bind the shares to what the issuer signs.** The control-agreement **template** must include signed
  fields carrying `certAddress`, `tokenId`, and `unitsRepresented`. `executeEncumberCert` reads those
  signed global values from the registry and `require`s they equal the `encumberCert` arguments
  **before** installing the lien. This makes the issuer's EIP-712 signature commit to *"I will comply
  with the secured party's re-registration instruction for tokenId X on cert Y"* — a true 8-106(c)(2)
  instrument — and stops a stale/foreign finalized agreement from being repurposed to encumber an
  unconsented security.
- **Verify signatures by resolved address, not membership.** `getParties` is an **unordered**
  `address[]`, party "roles" are off-chain template semantics, the duplicate-party check is commented
  out (`~:276-282`), and `signContractFor` lets an open (`address(0)`) slot be claimed via
  `fillUnallocated` + secret (`~:487-500`). So `executeEncumberCert` must:
  1. **resolve the issuer's authorizing address** from the corp (e.g. require the agreement to name
     the `CyberCorp` officer EOA / the `IssuanceManager`'s AUTH owner) and assert
     `registry.hasSigned(agreementId, issuerOfficer) == true` for **that specific address**;
  2. assert `hasSigned` for the **borrower** (`== legalOwnerOf(tokenId)`) and the **lender**
     specifically;
  3. reject `borrower == lender`, `borrower == issuer`, `lender == issuer` (close the commented-out
     duplicate-party hole at the encumber layer).
- **Liveness caveat (acceptable).** `encumberCert` is `onlyAdmin`, so an absent/malicious issuer can
  refuse to encumber. This is inherent: perfection by control under 8-106(c)(2) **requires** the
  issuer's participation. It is the one unavoidable issuer gate — and it is *up-front*, not at
  default.

---

## 11 — Security analysis (resolved adversarial findings)

All three verifiers returned **sound-with-fixes**. Each finding below is folded into the spec above;
listed here so the implementer sees the reasoning and the test that proves the fix.

**Legal (UCC/PEB) lens**

- **L1 (HIGH) Agreement not bound to the shares** → §10 signed `certAddress`/`tokenId` fields, verified
  in `executeEncumberCert`.
- **L2 (HIGH) Party-set unverifiable** → §10 resolve-and-`hasSigned` per role; reject collisions.
- **L3 (HIGH) Foreclosure endorsement vs `_update` reality** → §7/§8 re-register directly from lien
  state; endorsement is audit-only; post-condition asserts `legalOwnerOf == to`.
- **L4 (MED) Stale control agreement after release** → all read surfaces key off `Lien.status` (§6.6);
  registry-path release requires a finalized **satisfaction** agreement; `RELEASED` surfaced on the
  instrument.
- **L5 (MED) Arbiter can wrongly de-perfect via forced "repaid"** → **separate** the default arbiter
  from the release path; prefer the on-chain `RepaidCondition` for permissionless release; arbiter-
  forced release requires a lender-signed satisfaction agreement.
- **L6 (LOW) 9-328 priority overstated** → stamp `Lien.createdAt` as time-of-control evidence; spec
  states on-chain order is **presumptive/rebuttable** by off-chain subordination; v2 dual-consent
  re-rank.

**Smart-contract-security lens**

- **S1 (CRITICAL) Scrip/convert laundering** → §9: block scripify on the encumbered `id`;
  `_selectRecertToken` skips encumbered; reject partly-scripified at encumber. (The earlier
  `convertScripToCert` `hasActiveLien(id)` guard was unbuildable — no `id` arg.)
- **S2 (HIGH) Whitelist hook bricks foreclosure** → §8 foreclosure path bypasses the global hook.
- **S3 (HIGH) `IssuanceManager` not reentrancy-guarded** → add `ReentrancyGuard`; `nonReentrant` on
  all three entry points; CEI in `forecloseTo`.
- **S4 (MED) Endorsement-selection prose contradiction** → resolved by re-registering from lien state.
- **S5 (MED) `updateCertificateDetails` / carve-out latent escapes** → §6.1 guard
  `updateCertificateDetails`; §8 gate above the carve-out.
- **S6 (LOW) Premature seizure / stuck collateral** → `RepaidCondition` must be a snapshot/finalized
  predicate, not a spot balance; per-lien `sunset` backstop makes release permissionless after a
  bound; arbiter replaceable by joint borrower+lender action (v2).

**Integration / upgrade-safety lens**

- **I1 (HIGH) `convertScripToCert` guard unimplementable** → see S1.
- **I2 (HIGH) Foreclosure re-registration underspecified for `endorsementRequired==false`** → §8
  dedicated foreclosure branch bypasses both the `true` last-endorsement path and the `false`
  auto-resync.
- **I3 (HIGH) Foreclosure bricked by `transferable==false`** → §8 foreclosure path bypasses the
  `TokenNotTransferable` check; test asserts foreclosure on a non-transferable cert.
- **I4 (MED) `transient` cannot be a struct member** → §4 declare contract-level transient on the
  printer (or regular-slot fallback under `nonReentrant`).
- **I5 (MED) Class-wide `encumberedCount` lock too coarse** → §6.1 drop the class lock; per-token lien
  gate is authoritative and runs before the global hook. `encumberedCount` is indexing-only.
- **I6 (MED) Whitelist+foreclosure ordering** → §8 pinned control flow (`isForeclosure` computed once;
  foreclosure skips transferable + hook).
- **I7 (LOW) Registry exposes no party/tokenId accessor** → §6.7 small **read** additions
  (`getParties`/`globalValue`), correcting the "no registry change" claim.

---

## 12 — Open decisions

1. **Foreclosure vs an existing `WhitelistTransferHook`.** **Resolved in-spec (§8):** the in-printer
   foreclosure path is authoritative over the external whitelist hook — a perfected secured party's
   foreclosure is not subject to the issuer's discretionary KYC. (Defense-in-depth: `encumberCert` may
   also validate the lender is/will-be whitelisted.)
2. **On-chain sale-proceeds waterfall for a third-party buyer.** **Recommend v1:** re-register to any
   `to` the lender designates; proceeds handled off-chain. v2: route buyer→lender→surplus-to-borrower
   via the existing `computeFee`/`companyPayable` plumbing (`src/libs/LexScroWLite.sol:229-241`).
3. **Transient flag storage.** **Recommend:** Solidity transient storage (TSTORE) on Base
   (post-Cancun); fall back to a regular appended slot set→clear inside the `nonReentrant forecloseTo`
   if the pinned 0.8.28 target does not enable it. Either is safe.
4. **Who may call `encumberCert`.** **Recommend v1:** `onlyAdmin` (issuer officer) only — the one-time
   8-106(c)(2) act paired with the signed agreement. Liveness dependency on the issuer is inherent to
   perfection by control (§10).
5. **Contractual subordination / re-ranking.** **Recommend:** defer to v2 (strict first-recorded
   array order in v1, rebuttable off-chain per L6).

---

## 13 — PEB/UCC traceability matrix

| PEB / UCC concept | On-chain mechanism |
|---|---|
| Shares = uncertificated securities; issuer's books = on-chain ledger; **registered owner** = what the books say | `owners[tokenId].ownerAddress` via `legalOwnerOf(tokenId)` (`CyberCertPrinter:516`); the cap-table / §219 ledger keys off this |
| Share-NFT = the **token / CER** (Art 12) | the `CyberCertPrinter` ERC-721 `tokenId`; `unitsRepresented` = the share count it carries |
| **Control** of the token = power to instruct re-registration | the **senior active `Lien.lender`** in `liens[tokenId]` — *not* raw `ownerOf`. Pre-encumbrance, control = ordinary `ownerOf` |
| **Instruction** (8-102(a)(12)) to re-register | `foreclose()` → `forecloseTo` pushes a lien-derived foreclosure `Endorsement` (audit) and re-points `owners[tokenId]` |
| **Control agreement** (8-106(c)(2)): issuer complies with secured party's instructions without registered-owner consent | (a) finalized 3-party `CyberAgreementRegistry` agreement (issuer officer EIP-712-signs the doc, terms bind cert+tokenId); (b) the validated `encumberCert` that pre-wires `foreclose()` to honor the lender. The validated `Lien` IS the operative on-chain control agreement |
| **Perfection by control** (9-314(a), 9-106(a), 8-106(c)(2)) | existence of an `Active` `Lien` + `lienActive[tokenId]`; `encumberCert` is the perfection event |
| **Priority**: control beats filing; ranking among control parties (9-328(1),(2)) | ordered append-only `liens[]` (index 0 senior); off-chain UCC-1 filings have no on-chain handle and are subordinated by construction; `createdAt` evidences time-of-control; senior-only foreclosure |
| Borrower **remains registered owner**, keeps voting + distributions (fn 97) | `encumberCert` never touches `owners[]`; NFT stays in borrower's wallet; voting/distributions off-chain keyed to `legalOwnerOf` (unchanged until foreclosure) |
| Lender agrees **not** to instruct re-registration unless borrower defaults | `foreclose()` requires `defaultCondition.checkCondition() == true`; the lender cannot re-register before default because the predicate gates the only re-registration path |
| On default: secured party instructs re-registration to lender or buyer = **foreclosure** | `executeForeclose` → `forecloseTo` re-registers `owners[tokenId] = to` and moves the NFT |
| **Permissionless** (no fresh discretionary issuer act on default) | `foreclose()` has no role modifier; the issuer's only act was the up-front `encumberCert`; trigger is the `defaultCondition` at call time |
| **Release** on repayment: control returns to borrower, lien removed | `releaseEncumbrance()` (lender, OR permissionless via `repaidCondition` / finalized satisfaction agreement / `sunset`) → `status = Released` → `lienActive` clears; registration was continuous |
| Single token cannot represent two competing interests (the custody-model objection) | in-place model: control is a **record**, so multiple `Lien` entries coexist on one indivisible NFT — a fidelity win the vault model structurally cannot match |

---

## 14 — Events & errors

**Events (new, on `CyberCertPrinter`):**

- `CertEncumbered(address indexed cert, uint256 indexed tokenId, address indexed lender, bytes32 agreementId, address registry, uint256 ranking)`
- `CertReleased(address indexed cert, uint256 indexed tokenId, uint256 lienIndex, address releasedBy)`
- `CertForeclosed(address indexed cert, uint256 indexed tokenId, uint256 lienIndex, address indexed to, address lender, bytes32 agreementId)`
- **Reuse** `CertificateAssigned` (emitted in `_update` on re-registration), `CyberCertTransfer`, and
  `CertificateEndorsed` so existing indexers pick up the ownership change and the foreclosure
  instruction with no ABI churn.

**Errors (new):** `CertEncumbered()`, `NoActiveLien()`, `NotSeniorLien()`, `NotLender()`,
`DefaultNotMet()`. Mirror declarations in `IssuanceManagerStorage` per house duplication convention.

---

## 15 — Migration & deploy

- **Upgrade paths (existing).** `IssuanceManager` is UUPS — the new logic lands as a new factory
  reference implementation; `_authorizeUpgrade` stays `onlyOwner` **and** requires
  `newImplementation == factory.getRefImplementation()` (co-approval preserved). `CyberCertPrinter` is
  a `BeaconProxy` child — the new `_update` gate + `encumber`/`forecloseTo`/`releaseLien` + lien
  storage land via `upgradeCertPrinterBeaconImplementation` (factory-ref gated). Bump
  `DEPLOY_VERSION` (`CyberCertPrinter` `"4"`→`"5"`; `IssuanceManager` accordingly).
- **Storage is append-only.** New fields go after existing tails (`CyberCertStorage` after
  `issuerSignatures`; `IssuanceManagerData` append) — no reorder, no `__gap` consumed, preserving the
  fixed-slot diamond layout. Verify with `forge inspect <C> storage-layout` diff.
- **No back-fill.** Existing certs read `lienActive == false` / `encumberedCount == 0` post-upgrade;
  normal behavior preserved until an explicit `encumberCert`. Provide `*WithMigration` variants that
  back-fill nothing.
- **New contracts** (`MaturityDefaultCondition` etc., optional `ControlAgreementExtension`) deploy via
  the standard `script/libs/` + `ERC1967Proxy`/deterministic-salt scripts (`deploy-*.s.sol`).
  Solidity 0.8.28, optimizer runs per repo config, MetaLeX proprietary header on all new files;
  condition files follow the existing `conditions/` SPDX style.
- **Roadmap.** **P4 entry added** to `notes/plans/protocol-improvement-plan.md`
  (house format: problem → desired model → design direction → open questions), pointing
  at this spec. Implementation itself remains unstarted.

---

## 16 — Webapp / indexer surface (companion)

For `metalex-webapp` / `apps/cybercorps-web` and the shared cap-table features (tracked separately in
`notes/plans/mainframe-changes-plan.md`):

1. **Encumbrance badge** on any position whose `tokenId` has `lienActive == true` — an "Encumbered /
   Perfected by control" chip on the position row + cert detail, showing lender, `agreementId`
   (deep-link to the cyberSign control agreement), ranking, maturity — from `getLiens` /
   `seniorActiveLien` or the new indexer events.
2. **Create-lien flow (officer-gated):** wizard → create the 3-party control agreement in
   `CyberAgreementRegistry` (issuer officer + borrower + lender, terms binding cert+tokenId) → collect
   signatures via the existing cyberSign deep-link → `IssuanceManager.encumberCert` with the chosen
   `DefaultCondition` (Maturity is the default/recommended option; arbiter/oracle are advanced),
   maturity, sunset, arbiter, ranking.
3. **Foreclose button** visible to the lender wallet when `defaultCondition` reads true (UI calls
   `checkCondition` off-chain to enable/disable) → `IssuanceManager.foreclose`. **Release button**
   (lender) plus a permissionless "Mark released" affordance for the borrower when `repaidCondition`
   is satisfied or `sunset` has passed.
4. **Disabled/greyed** Tokenize, Transfer, Void, Terminate actions on encumbered positions with an
   explanatory tooltip, matching the on-chain `CertEncumbered` reverts so the UI never offers a call
   that will revert.
5. **Indexer (Envio):** new `Lien`/`Encumbrance` entity from `CertEncumbered`/`CertReleased`/
   `CertForeclosed` + the existing `CertificateAssigned` re-registration event, tied to the corp via
   the same per-corp agreement-indexing correlation already used for `CyberAgreementRegistry` docs, so
   encumbrances appear in the corp's cap-table lens with Registered/Beneficial framing intact
   (registered owner = borrower until foreclosure).

---

## 17 — Test plan (Foundry)

- **`encumberCert` happy path:** sets `lienActive`, leaves `owners[]`/`ownerOf == borrower`; reverts
  when agreement not finalized / voided / party-set wrong / signed cert+tokenId mismatch /
  `arbiter == issuer` / cert voided / partly-scripified.
- **Encumbrance invariant (fuzz):** while `lienActive[tokenId]`, **every** transfer path reverts
  `CertEncumbered` — direct `transferFrom`/`safeTransferFrom`, the `from == ownerAddress` no-revert
  branch, the `endorsementRequired == false` auto-resync, and `dealManager`/`roundManager`-originated
  transfers (carve-out closed).
- **Scrip:** `scripifyCert` reverts `CertEncumbered` on an encumbered cert (fuzz amounts);
  `convertScripToCert` cannot select an encumbered cert (`_selectRecertToken` skip).
- **Issuer levers:** `voidCert`, `burn`, `assignCert`, `setTokenTransferable(true)`,
  `updateCertificateDetails` revert while encumbered.
- **Endorsement shadowing:** borrower `addEndorsement` reverts while encumbered;
  issuanceManager-mediated foreclosure endorsement succeeds.
- **Foreclosure:** `MaturityDefaultCondition` false → `DefaultNotMet`; warp past maturity → succeeds,
  re-registers `owners[] = to`, moves NFT, `status = Foreclosed`; **asserts `legalOwnerOf == to`**;
  uses the lien-derived `to` even if a stale endorsement exists; **succeeds on a cert with
  `transferable == false` and with a `WhitelistTransferHook` global hook to a non-whitelisted `to`**.
- **Reentrancy:** malicious ERC-721 receiver re-enters `forecloseTo` / `releaseEncumbrance` /
  `encumberCert` during `onERC721Received` → reverts (printer + manager `nonReentrant`; flag cleared).
- **Priority:** two liens; junior `foreclose` reverts `NotSeniorLien`; release senior → junior becomes
  senior and can foreclose; indices stable after status changes.
- **Default-condition spoofing:** `ArbiterDefaultCondition` flip by non-arbiter reverts; flip by issuer
  reverts (`arbiter != issuer`); only the named neutral arbiter can declare.
- **Release:** lender release; permissionless via `repaidCondition`; via finalized satisfaction
  agreement; via `sunset`; lender refusal does not block the borrower's `repaidCondition` path.
- **Fork (Base 8453):** full lifecycle against a real deployed corp/cert via `*ForkTest`, including the
  beacon/UUPS upgrade → encumber → foreclose sequence.
- **Upgrade-safety:** `forge inspect storage-layout` confirms append-only; existing certs read
  `lienActive == false` post-upgrade with no migration.

---

## 18 — File-by-file change list (implementation index)

| File | Change |
|---|---|
| `src/CyberCertPrinter.sol` | add `ReentrancyGuard`; `encumber`/`releaseLien`/`forecloseTo`; `_update` gate + foreclosure branch (§8); guards on `voidCert`/`burn`/`assignCert`/`setTokenTransferable`/`updateCertificateDetails`/`addEndorsement`; views `getLiens`/`seniorActiveLien`/`hasActiveLien`; contract-level transient `_foreclosingToken`/`_foreclosingToName`; new events + `CertEncumbered()` error |
| `src/storage/CyberCertPrinterStorage.sol` | `LienStatus` enum + `Lien` struct (file scope); append `liens`/`lienActive`/`encumberedCount`; helpers `addLien`/`getLiens`/`setLienStatus`/`seniorActiveLien`/`hasActiveLien`/`recomputeLienActive` |
| `src/IssuanceManager.sol` | add `ReentrancyGuard`; `encumberCert` (`onlyAdmin`), `releaseEncumbrance` / `foreclose` (no modifier), all `nonReentrant` |
| `src/storage/IssuanceManagerStorage.sol` | `executeEncumberCert` (§10 validation), `executeReleaseEncumbrance`, `executeForeclose` (§7); guard `executeScripifyCert` (`~:855`); `_selectRecertToken` skip encumbered (`~:1190`); errors/events |
| `src/interfaces/IIssuanceManager.sol` | add the three signatures |
| `src/interfaces/ICyberCertPrinter.sol` | add `encumber`/`releaseLien`/`forecloseTo`/`getLiens`/`seniorActiveLien`/`hasActiveLien`; `Lien` type; events/error |
| `src/CyberAgreementRegistry.sol` | small **read** views: `getParties` / `globalValue(agreementId,key)` (no storage change) |
| `src/libs/conditions/MaturityDefaultCondition.sol` | new (trustless default) |
| `src/libs/conditions/ArbiterDefaultCondition.sol` | new (neutral per-lien arbiter) |
| `src/libs/conditions/OracleNonPaymentCondition.sol` | new (external loan-servicing oracle) |
| `src/libs/conditions/RepaidCondition.sol` | new (permissionless release predicate) |
| `src/storage/extensions/ControlAgreementExtension.sol` | optional, read-only `tokenURI` surfacing |
| `script/deploy-*.s.sol` | deploy conditions + extension; beacon/UUPS upgrade scripts |
| `notes/plans/protocol-improvement-plan.md` | **P4 entry added** pointing here; implementation remains unstarted |

---

*End of spec. Reviewer status: legal / security / integration all `sound-with-fixes`, fixes folded in
above (§11).*
