# Issuer-defined award templates — design evaluation & recommendation

**Status:** `PROPOSED` (design-level). Companion to the webapp grants feature
(`metalex-webapp` PR #771 + `notes/plans/cybercorps-grants-build-spec.md`). This doc is
referenced by **P3** in `protocol-improvement-plan.md`.

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
owner — see PR #771).

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

**Contract changes (cybercorps-contracts):**
- Add `createTemplatePublic(...)` (≈6 lines, reuses `_createTemplate`). Make it idempotent
  (return existing id rather than revert `TemplateAlreadyExists`) so re-running is safe.
- (Optional) emit a distinct event or include `msg.sender` in `TemplateCreated`'s provenance
  for off-chain attribution; not required for correctness.

**App changes (metalex-webapp, `apps/cybercorps-web`):**
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
  already deployed on Base at `0xCD71…` from PR #771 — a B redeploy would supersede it).
- **Option C:** no change to the deal flow itself; only to who may pre-register the template.

---

## 6. Recommendation

1. **Ship Option A** — add `createTemplatePublic` (permissionless, content-addressed,
   idempotent) to `CyberAgreementRegistry`, and repoint the webapp admin page to it +
   make the grants template id per-corp. This unblocks issuer-defined award templates with a
   ~6-line registry change, **no** MetaVesT/controller change, and **no** new trust
   assumptions (content-addressing supplies the anti-squat property).
2. **Keep Option B in reserve** as a complementary path for genuinely bespoke per-grant
   agreements: add a `proposeAndSignDealStandalone` variant on the controller when that need
   appears. Note it is **not** zero-registry-change as first appears — the standalone path's
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
   current internal guard)? Recommend idempotent.
2. **Provenance:** do we need on-chain attribution of *who* registered a template (an event
   field or A2 namespacing), or is content-addressing + off-chain indexing enough?
3. **Per-corp config storage (webapp):** store the registered `templateId` on the corp/grant
   row in `cybercorps-db`, or re-derive it client-side from the corp's award document each time?
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
