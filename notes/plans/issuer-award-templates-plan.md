# Issuer-defined award templates — design evaluation & recommendation

**Status:** `TARGET IMPLEMENTED LOCALLY / UNRELEASED` (2026-07-19). The **temporary**
variant remains live on-chain; see §0. The §6 recommendation is implemented in the current
worktrees and awaits coordinated contract/webapp rollout. The §0 app-layer mitigations are
already
**SHIPPED** in `metalex-webapp` — PR **#801** (self-serve per-corp award templates,
content-addressed registration + DB-backed provenance, merged 2026-07-08), PR **#803**
(bespoke per-recipient agreements, zero protocol change, merged 2026-07-08), PR **#805**
(Ethereum mainnet controller factory configured, merged 2026-07-08). Companion to the webapp
grants feature (`metalex-webapp` PR #771 + `notes/plans/cybercorps-grants-build-spec.md`).
This doc is referenced by **P3** in `protocol-improvement-plan.md`.

---

## 0. Status update (2026-07-08) — interim solution shipped

**Local hardening update (2026-07-19).** The target end state is implemented but not
deployed:

- `createTemplate` is owner-only again, restoring the curated caller-chosen namespace;
- `createTemplatePublic(title, uri, globalFields, partyFields)` is permissionless,
  derives the content hash on-chain, returns the ID, and is idempotent;
- empty legal-contract URIs are rejected, eliminating the registry's ambiguous
  “nonexistent” sentinel state;
- the deployment salt is bumped to `UpgradeV3.3.0`;
- five focused security/upgrade tests were added and the 18-test registry suite passes via IR; and
- the webapp ABI and issuer-template hook now call `createTemplatePublic` and still
  re-derive stored content before use to protect against legacy pre-upgrade records.

Deployment is intentionally not implied by this code status. Upgrade simulation, coordinated
proxy/webapp rollout, live owner/public-path calls, and post-upgrade content read-back remain.

**What shipped.** Commit `7edb89d` ("Opening up template creation") dropped the `onlyOwner`
modifier from the **caller-chosen-id** `createTemplate` (`src/CyberAgreementRegistry.sol`),
and a new implementation was deployed (`script/deploy-cyber-agreement-registry.s.sol`, salt
`MetaLex.CyberAgreementRegistry.UpgradeV3.2.0`). The proxy upgrade is **live**: verified
2026-07-08 by `eth_call` simulation from an unprivileged EOA on **Base (8453)** and
**Ethereum mainnet (1)** — a bare `createTemplate` call now succeeds where it previously
reverted on the owner gate.

**This is a deliberate temporary solution** (product decision, 2026-07-08): it unblocks
issuer self-serve template registration immediately with a one-line contract change. It is
*not* the §6-recommended configuration — it is the "naive permissionless caller-chosen-id"
variant §4 warns about. Accepted drawbacks while interim:

1. **Squatting / front-running.** Template ids are caller-chosen `bytes32`, so a guessable
   id (e.g. the keccak of a published label) can be pre-registered by anyone, pointed at a
   bogus document; a pending registration can also be front-run in the mempool. Creation is
   create-only (`TemplateAlreadyExists`), so *existing* templates cannot be overwritten —
   the exposure is claiming an id before its intended owner does.
2. **No curated namespace.** The owner-gated entry point no longer exists, so there is no
   on-chain distinction between a MetaLeX-canonical template and an arbitrary one, and
   `TemplateCreated` carries no creator — **registry presence must not be treated as
   MetaLeX approval** anywhere downstream.
3. **Ungated storage spam.** Anyone may write templates (bounded: gas-priced, create-only,
   no integrity impact).

Unchanged: templates remain **inert** — only a corp's funding authority can turn one into a
real grant (§4 "capability ≠ funds"), so none of the above moves value.

**Required app-layer mitigations while this interim configuration is live** (webapp) —
✅ **ALL SHIPPED** via `metalex-webapp` PR **#801** (merged 2026-07-08):
- Derive template ids **content-addressed** client-side —
  `keccak256(abi.encode(title, legalContractUri, globalFields, partyFields))` — never from
  a human label. This makes squatting moot for app-originated templates (an id can only
  resolve to its own content) and is forward-compatible with the §6 end-state.
- Keep template **provenance/trust in the app DB** (per-corp and staff-approved rows); never
  enumerate or trust the registry as a source of approved templates.
- **Verify content on-chain before use**: read the template back and check the document URI
  + field schema against expectations before binding a deal to the id.

*Shipped as specified (webapp #801, merged 2026-07-08): content-addressed ids
(`keccak256(abi.encode(title, uri, globalFields, partyFields))`), a `cybercorps.corpTemplates`
provenance table (migration 0032) written only by an authenticated corp officer, and a server
that re-verifies the claimed content against the chain before trusting the row. Webapp #803
(merged 2026-07-08) extends the same pattern to bespoke per-recipient documents — a single-use
content-addressed template pinned at `vesting.bespokeTemplateId`, with the server re-deriving
the content hash from on-chain content to defeat caller-chosen-id front-running.*

**Recommended optimal configuration (target end-state — unchanged from §6):** restore
`onlyOwner` on the caller-chosen-id `createTemplate` (reinstating a curated MetaLeX
namespace) **and** add the content-addressed, idempotent `createTemplatePublic` (Option A)
for permissionless issuer registration; optionally add creator provenance to
`TemplateCreated`. Because the app-layer mitigations above already use content-addressed
ids, migrating to the end-state later requires **no app-flow change** — issuer
registrations simply switch to calling `createTemplatePublic` with identical ids.

---

## 1. Problem

cyberCORPs grants vest company stock (as `CyberScrip`) through a MetaVesT allocation, with
the award agreement signed via the `CyberAgreementRegistry`. The deal-create call —
`MetaVesTController.proposeAndSignDeal(templateId, …)` — passes a **pre-registered
`templateId`** to `registry.createContract`, which **reverts `TemplateDoesNotExist`** if the
template is not already in the registry:

```solidity
// MetaVesTControllerStorage.sol:220 — the controller's propose path
ICyberAgreementRegistry(st.registry)
    .createContract(templateId, salt, globalValues, parties, partyValues, secretHash, address(this), expiry);

// CyberAgreementRegistry.sol:263-266 — createContract requires the template to exist
Template storage template = templates[templateId];
if (bytes(template.legalContractUri).length == 0) revert TemplateDoesNotExist();
```

The only way to register that template is `createTemplate`, which is **owner-only**:

```solidity
// CyberAgreementRegistry.sol:230-244
function createTemplate(bytes32 templateId, string title, string legalContractUri,
    string[] globalFields, string[] partyFields) external onlyOwner { _createTemplate(...); }

// BorgAuthACL.onlyOwner (src/libs/auth.sol:190-193)
modifier onlyOwner() { AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender); _; }   // role >= 99
```

Crucially, the `CyberAgreementRegistry` is a **single, global, MetaLeX-controlled instance**
(`0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` on every non-zkSync chain). Its `AUTH` is
MetaLeX's BorgAuth — **not** any corp's BorgAuth. So today **every cyberCORP shares one
award template that only MetaLeX can register**; a founder cannot register their own custom
award agreement. This is the last setup blocker for self-serve grants (the webapp already
ships an admin "Register award template" page, but it can only be driven by the registry
owner — see PR #771). *(Since resolved: the interim ship (§0) plus webapp #801, merged
2026-07-08, made template registration officer self-serve.)*

**Goal:** let an **issuer** (corp officer) define and register their **own** award-agreement
template, without MetaLeX in the loop per corp, without weakening the registry's integrity.

---

## 2. What the registry already does (load-bearing facts)

The registry is **not** a pure owner-gated template store. It already has a **permissionless,
content-addressed, just-in-time template path**:

```solidity
// CyberAgreementRegistry.sol:341-399 — note: PUBLIC, no access modifier
/// Standalone means it creates its own template just-in-time if needed.
/// No more waiting for admin to create the template for you
function createStandaloneContractAndSignFor(
    string title, string legalContractUri, string[] globalFields, string[] partyFields,
    uint256 salt, string[] globalValues, address[] parties, string[][] partyValues,
    uint256 expiry, address signer, bytes signature
) public returns (bytes32 contractId) {
    bytes32 templateId = keccak256(abi.encode(title, legalContractUri, globalFields, partyFields));
    if (bytes(templates[templateId].legalContractUri).length == 0)
        _createTemplate(templateId, title, legalContractUri, globalFields, partyFields); // permissionless!
    contractId = createContract(templateId, salt, globalValues, parties, partyValues, "", address(0), expiry);
    signContractFor(signer, contractId, partyValues[0], signature, false, "");
}
```

Two facts follow:

1. **Permissionless template creation already exists** — anyone can cause `_createTemplate`
   to run via the standalone path. The `onlyOwner` gate on `createTemplate` only governs the
   **caller-chosen-`templateId`** entry point.
2. **The standalone path is content-addressed**: `templateId = keccak256(title, uri,
   globalFields, partyFields)`. The id *is* the hash of the content, so it cannot be
   squatted — two issuers with identical content deterministically get the same id (idempotent
   reuse), and you always resolve to *your* content's id.

The difference between the two entry points is the **squatting surface**:

| path | who | templateId | squattable? |
|------|-----|------------|-------------|
| `createTemplate` (owner-only) | MetaLeX | **caller-chosen** `bytes32` | yes if made permissionless naively (front-run your id with a bogus doc) |
| standalone `_createTemplate` | anyone | **content hash** | no (id ≡ content) |

This table is the key to the recommendation: *permissionless template creation is safe iff the
id is derived from content.*

A template stores only `{legalContractUri, title, globalFields, partyFields}` — i.e. a title,
a document URI, and field **names**. It carries **no per-grant data** (recipient, units,
schedule live in the agreement's `globalValues`/`partyValues` and on the allocation). So
templates are safe to share across corps; there is nothing corp-private in a template.

---

## 3. The three options

### Option A — permissionless, **content-addressed** `createTemplate` on the registry  ✅ recommended

Add a thin, additive entry point that is the template-creation half of the standalone path,
exposed on its own (no contract, no signature):

```solidity
// new in CyberAgreementRegistry — additive, no change to existing paths
function createTemplatePublic(
    string memory title, string memory legalContractUri,
    string[] memory globalFields, string[] memory partyFields
) external returns (bytes32 templateId) {
    templateId = keccak256(abi.encode(title, legalContractUri, globalFields, partyFields));
    if (bytes(templates[templateId].legalContractUri).length == 0)
        _createTemplate(templateId, title, legalContractUri, globalFields, partyFields);
    // idempotent: returns the existing id if already registered (no revert)
}
```

- **Squat-proof**: id ≡ content hash; an officer always gets *their* document's id, and a
  front-runner registering the same content only helps (idempotent).
- **No controller change.** `proposeAndSignDeal(templateId, …)` is unchanged — it just now
  references an issuer-registered template instead of the single MetaLeX one.
- **No corp-identity verification needed** (see Option A2 for why that matters). The template
  is harmless to anyone — only the *issuer who funds and proposes the deal* can turn it into a
  real grant.
- **Consistent with the protocol's existing stance** ("no more waiting for admin"): it merely
  unbundles capability the standalone path already grants.
- Keep the existing owner-only, caller-chosen-id `createTemplate` for MetaLeX canonical/vanity
  ids — unchanged, so no regression and MetaLeX retains a curated namespace.

**Contract changes (cybercorps-contracts):** — *NOT YET BUILT; the interim ship (§0, commit
`7edb89d`) de-gated the existing caller-chosen-id `createTemplate` instead. This block remains
the target end-state.*
- Add `createTemplatePublic(...)` (≈6 lines, reuses `_createTemplate`). Make it idempotent
  (return existing id rather than revert `TemplateAlreadyExists`) so re-running is safe.
- (Optional) emit a distinct event or include `msg.sender` in `TemplateCreated`'s provenance
  for off-chain attribution; not required for correctness.

**App changes (metalex-webapp, `apps/cybercorps-web`):** — ✅ **SHIPPED** via webapp PR
**#801** (merged 2026-07-08), calling the interim permissionless `createTemplate` with
content-derived ids (identical ids to a future `createTemplatePublic`, so the end-state
migration needs no app-flow change); per-corp templateId is DB-backed
(`cybercorps.corpTemplates`, migration 0032) with the chain-level id kept only as the
MetaLeX-default fallback.
- Repoint the existing admin page (`features/grants/useRegisterAwardTemplate.ts` +
  `grants/_components/RegisterAwardTemplateForm.tsx`, PR #771) from the owner-gated,
  label-hashed `createTemplate` to `createTemplatePublic`, deriving `templateId` from
  `(title, uri, globalFields, partyFields)` instead of `keccak(label)`. Drop the
  owner-only warning (or downgrade it to informational) — officers can now self-serve.
- Make the template id **per-corp** instead of per-chain: change
  `controllerConfig.METAVEST_GRANTS_TEMPLATE_ID` from a `Record<chainId, …>` to a per-corp
  source (store the registered `templateId` on the corp/grant record in `cybercorps-db`, or
  derive it on the fly from the corp's chosen award doc). `isGrantsChainConfigured` becomes a
  per-corp `isGrantsConfigured(corp)`.
- No change to `useTokenizeGrant` beyond sourcing the per-corp templateId.

**Net:** smallest blast radius, no MetaVesT change, no new trust assumptions. Each corp
registers its own award document once and grants are unblocked.

---

### Option A2 — per-corp-**namespaced** `createTemplate` with on-chain officer verification  (heavier variant of A)

Instead of (or on top of) content-addressing, namespace the id by corp and require the caller
be a verified officer of that corp:

```solidity
function createCorpTemplate(address corp, string title, string uri,
    string[] globalFields, string[] partyFields) external returns (bytes32 templateId) {
    require(CyberCorpFactory(factory).isCyberCorp(corp), "not a real corp");   // <-- does not exist yet
    require(CyberCorp(corp).isCyberCORPOfficer(msg.sender), "not an officer"); // CyberCorp.sol:184
    templateId = keccak256(abi.encode(corp, title, uri, globalFields, partyFields)); // corp-namespaced
    _createTemplate(...);
}
```

**Why this is more than a one-function change:** the registry cannot authenticate `corp`
today. `CyberCorpFactory` keeps **no on-chain registry of deployed corps** — only a
`registryAddress` field and a `CyberCorpDeployed` event (`src/CyberCorpFactory.sol`). Without
an `isCyberCorp(address)` source of truth, a griefer deploys a fake contract whose
`isCyberCORPOfficer` returns `true` and spoofs membership. So A2 entails **two** contract
changes:
1. `CyberCorpFactory`: add an `mapping(address => bool) public isCyberCorp` populated at
   deploy (and a getter), so the registry has an authenticity oracle.
2. `CyberAgreementRegistry`: add `createCorpTemplate` (+ a `factory` reference).

**Benefit over A:** templates carry verifiable corp provenance (enables "list this corp's
templates," per-corp admin UI, and prevents an unrelated party from creating a template
"as if" for your corp — though, again, a stray template is harmless because only the funding
authority can mint a real grant). **Cost:** larger change, a new registry→factory dependency,
and it ties the global registry to cyberCORP-specific identity (the registry is currently
corp-agnostic — a flat global template+agreement store with **no** notion of CyberCorp).

**Recommendation:** ship **A** first (content-addressing already gives the security property
A2's verification is meant to provide). Add A2's namespacing/provenance later **only if** the
product needs per-corp template listings or attributable creation.

---

### Option B — route grants through `createStandaloneContractAndSignFor` (per-grant doc, no pre-registered template)

> **Status (2026-07-12):** NOT BUILT, and its motivating use case is now largely served
> without it — webapp **#803** (merged 2026-07-08) ships bespoke per-recipient agreements with
> **zero protocol change** by registering each bespoke document as a single-use
> content-addressed template through the interim permissionless `createTemplate` and pinning
> the grant to it (resolution precedence: bespoke > corp template > chain default). B remains
> in reserve only if a no-pre-registration flow is ever specifically required.

Use the registry's existing permissionless standalone path so each grant carries its **own**
inline document with **no pre-registration step at all**.

- **Registry change: none.** The path already exists and is content-addressed/permissionless.
- **Controller change: required.** `proposeAndSignDeal` calls
  `registry.createContract(templateId, …)` (`MetaVesTControllerStorage.sol:220`). To use the
  standalone path you need a **new propose variant** on the (registry-gated) controller
  (`feat/re-enable-options`) — e.g. `proposeAndSignDealStandalone(title, uri, globalFields,
  partyFields, salt, dealDraft, globalValues, parties, partyValues, signature, expiry)` — that
  calls `registry.createStandaloneContractAndSignFor(...)` instead of `createContract`, then
  records the returned `agreementId` in the controller's deal storage exactly as the existing
  path does.

**Finalize incompatibility (verified — the real catch):** the standalone path hard-codes
`finalizer = address(0)` (`CyberAgreementRegistry.sol:387`), whereas the existing controller
path sets `finalizer = address(this)` (`MetaVesTControllerStorage.sol:220`). This matters
because `signContractFor` **auto-finalizes when all parties have signed AND `finalizer ==
address(0)`** (`:550-554`). In the grant flow the grantee's signature is the last one and runs
inside `signDealAndCreateMetavest` (`MetaVesTControllerStorage.sol` does `signContractFor(grantee,
…)` then `finalizeContract(agreementId)` at `:331`). With a zero finalizer the grantee's sign
**auto-finalizes**, so the controller's subsequent **explicit `finalizeContract` reverts
`ContractAlreadyFinalized`** (`:681`). The existing path is safe precisely because its finalizer
is the controller (`address(this) != address(0)`), which suppresses auto-finalize and lets the
explicit finalize succeed. **So Option B is not a drop-in.** It needs one of:
- **(b-i)** a registry change so the standalone path accepts a `finalizer` param (pass the
  controller) — suppresses auto-finalize and keeps the controller the sole finalizer. This makes
  B a *registry + controller* change (so it loses its "no registry change" advantage); or
- **(b-ii)** a controller standalone-propose variant whose finalize step is **conditional** —
  detect `finalized` (or just don't call `finalizeContract` when the deal was created via the
  zero-finalizer standalone path) and rely on auto-finalize. Controller-only, but it forks the
  finalize logic and accepts that *anyone* can be the (auto-)finalizer.

**Signature/flow note:** the standalone call signs for the **proposer** (the grantor/officer)
in the same tx (`signContractFor(signer, …)`). The grantee's signature + finalize still flow
through `signDealAndCreateMetavest` (which does `signContractFor(grantee, …)` then
`finalizeContract`). So the two-party grantor→grantee→fund sequence composes; the new variant
just folds grantor-sign + template-create into the propose tx.

**When B wins:** when each grant genuinely needs a **bespoke** agreement document (different
per recipient), so there is no shared template to pre-register. **Cost:** per-grant template
proliferation in registry storage (deduped only when documents are byte-identical), and a
MetaVesT contract change + redeploy of the controller.

**B and A are complementary, not exclusive:** A serves the common case (one shared/per-corp
award template, reused across many grants); B serves the bespoke-per-grant case. Shipping A
unblocks self-serve today with zero MetaVesT change; B can follow if/when custom per-grant
docs are required.

---

### Option C — owner-delegated template creation (a `TEMPLATE_CREATOR` role)  ❌ not recommended

Have the registry owner (MetaLeX) grant officers a capability to create templates.

Mechanisms and why each is poor:
- **C1 — re-gate `createTemplate` to `onlyOwner || hasRole(TEMPLATE_CREATOR)`** and have
  MetaLeX `updateRole` each corp officer on the **global** registry BorgAuth. This keeps
  MetaLeX in the loop **per corp** (the opposite of the goal) and is operationally heavy
  (every officer change → a MetaLeX tx on the shared ACL).
- **C2 — `setRoleAdapter` delegation** (`auth.sol:117`): point a role's adapter at an
  `IAuthAdapter` that returns the role for verified corp officers (`onlyRole` consults
  `IAuthAdapter(adapter).isAuthorized(user) >= role`, `auth.sol:126-136`). But `createTemplate`
  is gated on `OWNER_ROLE`; an `OWNER_ROLE` adapter would grant **full owner powers** over the
  global registry (void contracts, register canonical templates, etc.) to every corp officer —
  wrong granularity and dangerous. Scoping to template-creation only would require a
  **dedicated** `TEMPLATE_CREATOR` role *and* re-gating `createTemplate` to it *and* an adapter
  that still needs the same corp-authenticity oracle Option A2 needs.
- The registry's existing `delegations` mapping (`:113`, `setDelegation` `:418`) is for
  **signing** delegation only (consumed in `signContractFor`/escrow-sign paths), not template
  creation — not reusable here.

**Verdict:** most centralized, heaviest, wrong granularity. Choose C **only** if the product
explicitly wants MetaLeX to **curate/vet** every template (a gatekeeping feature, not a
self-serve one).

---

## 4. Security analysis (template spoofing / squatting / griefing)

- **Squatting (caller-chosen ids).** The decisive risk. The existing `createTemplate` takes a
  caller-chosen `templateId`; if that entry point were simply made permissionless, an attacker
  could front-run and register *your* id pointing at a bogus document, so your
  `proposeAndSignDeal(yourId)` would bind to their doc. **Content-addressing (Options A/B)
  eliminates this**: the id is `keccak(content)`, so you can only ever resolve to your own
  content, and a collision means identical content. This is why A uses content-addressing, not
  a permissionless version of the caller-chosen-id function.
- **Spoofing a corp (A2/C).** On-chain officer verification needs to authenticate the corp
  address; `CyberCorpFactory` has no `isCyberCorp` oracle today, so naive verification is
  spoofable by a fake corp contract. Mitigation = add the factory mapping (an extra change A
  avoids entirely).
- **Template-spam / storage griefing.** Permissionless creation lets anyone write templates.
  Content-addressing dedups identical docs; distinct docs cost the griefer gas per template and
  never collide with or overwrite a legitimate template (creation is create-only:
  `TemplateAlreadyExists`/idempotent). Impact is bounded SSTORE bloat, not integrity loss.
  Optional hardening: emit-only (no storage) templates, or a per-sender rate limit — unwarranted
  for v1.
- **No corp-private data in templates.** Templates hold only title/URI/field-names; per-grant
  values live on the agreement + allocation. Cross-corp id sharing of identical content is
  therefore safe.
- **Capability ≠ funds.** A registered template is inert. Only the allocation **authority**
  (the corp owner who holds + approves the scrip and signs the grantor EIP-712) can turn a
  template into a funded grant via `proposeAndSignDeal` + `signDealAndCreateMetavest`. So a
  stray/forged template cannot move value — it can at worst clutter the registry.

---

## 5. Interaction with the existing deal flow

- **Option A:** `proposeAndSignDeal(templateId, …)` and `signDealAndCreateMetavest` are
  **unchanged**; only the *source* of `templateId` changes (issuer-registered instead of the
  single MetaLeX template). The webapp's `useTokenizeGrant` keeps working once it reads a
  per-corp templateId. Lowest-risk integration.
- **Option B:** changes the **propose** leg (new controller variant calling the standalone
  path); the **sign/fund/finalize** legs are unchanged (finalize verified compatible with the
  zero finalizer, §3-B). Requires a controller redeploy on Base/mainnet (the controller is
  already deployed on Base at `0xCD71…` from PR #771 — a B redeploy would supersede it;
  Ethereum mainnet grants have since been enabled via the controller factory, webapp #805,
  merged 2026-07-08).
- **Option C:** no change to the deal flow itself; only to who may pre-register the template.

---

## 6. Recommendation

1. **Ship Option A** — add `createTemplatePublic` (permissionless, content-addressed,
   idempotent) to `CyberAgreementRegistry`, and repoint the webapp admin page to it +
   make the grants template id per-corp. This unblocks issuer-defined award templates with a
   ~6-line registry change, **no** MetaVesT/controller change, and **no** new trust
   assumptions (content-addressing supplies the anti-squat property).
   *(Status 2026-07-19: app half ✅ SHIPPED in webapp #801; the contract half and
   matching ABI/call-site cutover are implemented locally/unreleased. The live
   proxies still run the §0 interim permissionless caller-chosen path until the
   coordinated upgrade.)*
2. **Keep Option B in reserve** as a complementary path for genuinely bespoke per-grant
   agreements: add a `proposeAndSignDealStandalone` variant on the controller when that need
   appears. *(Status 2026-07-12: bespoke need since served app-side with zero protocol
   change — webapp #803, merged 2026-07-08; see §3-B status note.)* Note it is **not** zero-registry-change as first appears — the standalone path's
   zero finalizer auto-finalizes on the grantee's signature, so B needs either a registry
   `finalizer` param (b-i) or a conditional controller finalize (b-ii) (§3-B). Controller
   redeploy required either way.
3. **Do not pursue Option C** unless MetaLeX wants to curate/vet templates; it is the most
   centralized and the wrong granularity.
4. **Defer Option A2** (corp-namespaced + factory `isCyberCorp` oracle) until per-corp
   template **provenance/listing** is a product requirement — A already provides the security
   guarantee.

### Change summary

| | Registry | MetaVesT controller | CyberCorpFactory | Webapp |
|---|---|---|---|---|
| **A** (rec.) | + `createTemplatePublic` (content-addressed, idempotent) | — | — | repoint admin page to content-addressed call; per-corp templateId |
| **B** (reserve) | — *(b-ii)* or + `finalizer` param on standalone path *(b-i)* | + `proposeAndSignDealStandalone` (+ conditional finalize) | — | new bespoke-grant propose path |
| **A2** (defer) | + `createCorpTemplate` (+ factory ref) | — | + `isCyberCorp` mapping/getter | per-corp template UI/listing |
| **C** (reject) | re-gate `createTemplate` to a new role | — | (oracle, if verifying) | — |

---

## 7. Open questions

1. **Idempotent vs revert** for `createTemplatePublic` when the content already exists — return
   the existing id (recommended, re-run-safe) or revert `TemplateAlreadyExists` (matches the
   current internal guard)? Recommend idempotent. *(App-side, #801/#803 already implement
   adopt-on-duplicate — identical content adopts the existing id; the contract-side choice
   stays open for `createTemplatePublic`.)*
2. **Provenance:** do we need on-chain attribution of *who* registered a template (an event
   field or A2 namespacing), or is content-addressing + off-chain indexing enough?
   *(Interim answer shipped in #801: provenance lives off-chain in the `corpTemplates` DB
   table; on-chain attribution remains open for the end-state.)*
3. **Per-corp config storage (webapp):** store the registered `templateId` on the corp/grant
   row in `cybercorps-db`, or re-derive it client-side from the corp's award document each time?
   ✅ **RESOLVED** — stored in `cybercorps-db` (`corpTemplates` table, migration 0032, webapp
   #801); bespoke per-grant pins live at `vesting.bespokeTemplateId` (webapp #803).
4. **B finalize handling:** because the zero-finalizer standalone path **auto-finalizes** on
   the grantee's signature (`:550-554`), a B variant must either add a `finalizer` param to the
   standalone path so the controller stays sole finalizer (b-i, registry + controller change) or
   make the controller's finalize step conditional and rely on auto-finalize (b-ii,
   controller-only but anyone becomes the auto-finalizer). Which trade-off is acceptable?
5. **Should the curated MetaLeX `createTemplate` (caller-chosen id) stay?** Recommended yes —
   it costs nothing and preserves a vetted canonical namespace alongside permissionless,
   content-addressed issuer templates.

---

## 8. References

- `src/CyberAgreementRegistry.sol`: `createTemplate`/`_createTemplate` (`:230`, `:985`),
  `onlyOwner` via BorgAuthACL, `createContract` + `TemplateDoesNotExist` (`:246`, `:263-266`),
  `createStandaloneContractAndSignFor` (permissionless, content-addressed, `:341-399`),
  `finalizeContract` + `onlyFinalizerIfSet` (`:677`, `:209-215`), `delegations`/`setDelegation`
  (`:113`, `:418`), `templates` mapping (`Template{legalContractUri,title,globalFields,partyFields}`).
- `src/libs/auth.sol`: roles (`OWNER_ROLE=99` `:52`, `ADMIN_ROLE=98`, `PRIVILEGED_ROLE=97`),
  `userRoles` (`:58`/`:185`), `onlyRole`/adapter consult (`:126-136`), `roleAdapters` +
  `setRoleAdapter` (`:59`, `:117`), `BorgAuthACL.onlyOwner` (`:190`).
- `src/CyberCorp.sol:184`: `isCyberCORPOfficer(addr) = AUTH.userRoles(addr) >= OWNER_ROLE`.
- `src/CyberCorpFactory.sol`: `registryAddress` + `CyberCorpDeployed` event; **no** on-chain
  corp registry mapping today (the gap A2 must fill).
- MetaVesT `feat/re-enable-options`: `MetaVesTController.proposeAndSignDeal` (`:130`) /
  `signDealAndCreateMetavest` (`:156`); `MetaVesTControllerStorage` registry calls —
  `createContract(…, address(this), expiry)` (`:220`), `finalizeContract` (`:331`);
  `MetaVesTControllerFactory.deployMetavestController` (permissionless, per-factory registry).
- Webapp: `apps/cybercorps-web/src/features/grants/{controllerConfig,useTokenizeGrant,
  useRegisterAwardTemplate}.ts` + `grants/_components/RegisterAwardTemplateForm.tsx` (PR #771);
  global registry `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`; Base controller `0xCD71…`.
