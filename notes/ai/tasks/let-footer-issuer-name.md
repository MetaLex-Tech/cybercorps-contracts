# Task: LET certificate footer names the issuing company

- **Status:** Ready for review (PR open; merge, deployment and Safe signing are not authorized by this record)
- **Updated:** 2026-10-12 10:17 America/New_York (Codex branch review; task ownership unchanged)
- **Owner:** Claude Code session in worktree `keen-benz-55739a`, acting for lex-node
- **Collaborators / boundaries:** Renderer only: `src/CertificateImageContentBuilder.sol`, its tests and fixtures, and these records. No change to `CertificateImageBuilderContract`, `CertificateUriBuilder`, their interfaces, `LedgerEntryToken`, `CyberCorp`, storage, agreement IDs or signatures. The series-designation feature prototyped in the scratch worktree `ccc-wt-series-naming` is a separate decision and is not reused here.
- **Objective:** Every LET image footer names the issuing company with the sentence the owner settled, and every other byte of the SVG and of the token JSON is unchanged.
- **Out of scope:** Deployment, upgrade transactions or Safe batches; the JSON `title` field ("MetaLeX Tokenized Certificate"); designation or series-naming text; webapp changes.
- **Canonical plan / sources:** this record; [DECISIONS.md](../DECISIONS.md) entry "2026-10-11: LET certificate footer wording"; metalex-webapp `AGENTS.md` ("Smart-contract change boundaries").
- **Repository / branch:** MetaLex-Tech/cybercorps-contracts; base `develop`, working branch `claude/keen-benz-55739a`.
- **Verified base / code head:** base `10fa89f236b8dcc5b19db0d9c256fe2f1d40d035` (tip of `develop` on 2026-10-11); content commits `5d0cd208e175a7a54f990b85478687be8146c2f8` (footer) and `2a8e8b5b5208939c812611070d0f496537a4c252` (footer name limit 26, after Codex review). Other commits on the branch change only these records.
- **Worktree locator:** shared at handoff; not committed.
- **PR / artifact:** [#175](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/175), non-draft, against `develop`; auto-merge off.

## Acceptance and current state

1. The footer of every LET image reads "This constitutes an official entry on the
   tokenized securities ledger of {company}." with the issuer's `corpName`.
   **Done at `5d0cd208`; verified by `CertificateFooterTest`.**
2. The footer carries no statutory citation and does not depend on the
   jurisdiction or on the entity type. **Done; verified by
   `testFooterDoesNotDependOnJurisdiction` and the "DGCL" / "Stock Ledger"
   assertions.**
3. The company name is XML-escaped and cut at 26 code points, the parties
   block's limit, so a long upper-case name cannot push the 14px line past the
   1024px edge. **Done; verified by `testFooterEscapesAndTruncatesTheName`.**
4. Nothing else in the SVG changes. **Done; `testEverythingButTheFooterIsUnchanged`
   compares the bytes before and after the footer element with two fixtures
   captured from the unmodified renderer at `10fa89f2`.**
5. Nothing in the token JSON changes, and the footer reaches `tokenURI` through
   `CertificateUriBuilder`. **Done; verified by `testUriBuilderEmbedsTheIssuerFooter`.**
6. Contract sizes stay under 24,576 bytes. **Done; see Validation.**
7. Independent review and merge. **Pending: PR review by Codex and the owner.**
8. Deployment and live acceptance. **Not started and not authorized here.**

## Decisions and evidence

- **Defect.** `src/CertificateImageContentBuilder.sol` line 67 at `10fa89f2`
  wrote one constant footer into every LET image: "Recorded on the MetaLeX
  Labs, Inc. Tokenized Stock Ledger pursuant to DGCL §§219, 224." The constant
  arrived with `3bbde497` (2026-09-11, "LET svg update"). Live evidence read on
  2026-10-11 from Base (chain 8453): LET `0x8a79ebbd0ba6bf8e3c109962a6250d512cbf63a1`
  token 0, whose CyberCorp `0xff3C9acF04aa4f3FD7a56D7E49E302c8B33F1B6C` reports
  "Empulser Enterprises LLC" / "Limited liability company" / "Wyoming"; the
  token is a SAFE and its decoded image carried the MetaLeX Labs, Inc. sentence.
- **Wording, accepted by the owner on 2026-10-11 (chat):** one sentence for
  every company, "This constitutes an official entry on the tokenized
  securities ledger of {company}.", with no statutory citation and no
  jurisdiction or entity-type rule. Recorded in [DECISIONS.md](../DECISIONS.md).
- **Superseded proposal (same day, replaced by the decision above):** two
  sentences chosen by an exact match on `jurisdiction` ("Delaware" or "DE") and
  `cyberCORPType` ("Corporation"), which needed a V3 image-builder entry point
  because `CertificateSVGParams` carries no entity type. Not implemented. The
  owner's decision removed the need for the entity type, so the change stays
  inside the linked library and no ABI changes.
- **Implementation choice.** `_buildFooter` escapes `corpName` with its own
  `CertificateText.xml` call at a limit of 26. The content commit `5d0cd208`
  shared the header's 38-point escape to save about 1 KB of library bytecode
  (via-IR inlines `CertificateText.xml` at every call site). Codex's review of
  `ea3a792` showed that 38 points let a long upper-case name run past the
  1024px edge in a wide system font, because the sentence alone takes about
  620px at 14px; the footer now uses the parties block's limit and the header
  code is unchanged from `develop`.
- **Scratch prototype** (`ccc-wt-series-naming`, `_buildFooter`): matched on
  jurisdiction alone and bundled a designation feature. Read for reference;
  nothing reused.
- **Empty company name:** the footer then ends with "ledger of .". The header
  renders an empty name as an empty line today. Left unchanged; noted in the PR.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Live defect | `cast call` of `tokenURI(0)` on Base via `https://mainnet.base.org`, decoded; CyberCorp getters; 2026-10-11 | Confirmed: the footer named MetaLeX Labs, Inc. and cited the DGCL for a Wyoming LLC SAFE |
| New unit tests | `forge test --match-path "test/*Certificate*"` on the working tree equal to `2a8e8b5b` for all code files | `CertificateFooterTest`: 7 passed |
| Pre-existing renderer suites | same run | `CertificateSvgCompatibilityTest` 18, `UpgradeCertificateRenderingScriptTest` 6, `CertificateUriBuilderLegacyTest` 8, `CertificateUriBuilderJsonEscapingTest` 2: all passed |
| Fork tests | same run | `CertificateUriBuilderLegacyForkTest` (2 tests) not run: `vm.createSelectFork` needs `ALCHEMY_API_KEY`, which this machine does not have. They run in CI |
| Full suite | `forge test` on the tree equal to `5d0cd208` (before the limit change; the limit change touches only `_buildFooter` and its test) | 1,419 passed, 24 failed. 23 failures are fork tests that need `ALCHEMY_API_KEY` or `FORK_RPC_URL` and fail in `setUp` before any code runs (CI runs them with the key). The other, `test_VaultEmptyingConversion_FitsInABlockAtLargeSupply` in `IssuanceManagerVaultEpochAdhocTest`, hits the default per-test gas cap in a 6,500-holder setup; it uses `MockUriBuilderForIM`, so the changed library is not on its path, and CI excludes `AdhocTest` contracts (`--nmc`). CI on `develop` is green at `10fa89f2` |
| Byte identity | `testEverythingButTheFooterIsUnchanged` against `test/res/let-svg-10fa89f2-*.svg` (captured at `10fa89f2`, 15,557 and 15,835 bytes, committed byte-exact) | Passed for a Delaware corporation and a voided Wyoming LLC SAFE |
| Sizes | `forge build --sizes --skip test --skip script` at `10fa89f2` and at `2a8e8b5b` | `CertificateUriBuilder` 21,607 → 21,607; `CertificateImageBuilderContract` 14,856 → 14,856; `CertificateImageContentBuilder` 18,066 → 20,212 (margin 4,364); limit 24,576 |
| Diff scope | `git diff --stat 10fa89f2 2a8e8b5b -- src test` | `src/CertificateImageContentBuilder.sol`, `test/CertificateFooterTest.t.sol`, two fixtures. No interface, script, docs or webapp change |

No deployment or live integration acceptance result exists yet. Review evidence
and exact-head CI verification are recorded below; they do not establish release acceptance.

### 2026-10-12: Codex branch verification

Reviewed clean code head `a098d2f50e610c25a935bd772d717edd855cd032` against
freshly fetched `origin/develop` at `10fa89f236b8dcc5b19db0d9c256fe2f1d40d035`.
This is an internal review requested by the user, with no transfer of the
implementation task or review-monitor ownership. No actionable correctness
finding was identified and no source or test changes were needed.

- Traced issuer-name propagation through the URI builder and both image-builder
  selectors. The change uses the existing UTF-8/XML sanitizer, preserves the
  header's limit, and changes no ABI, storage, authorization or payment logic.
- Local validation at that exact code head: **41 passed, 0 failed** across the
  footer (7), SVG compatibility (18), upgrade script (6), legacy URI (8), and JSON
  escaping (2) suites. Command:
  `forge test --use 0.8.28 --match-path "test/*Certificate*" --no-match-contract CertificateUriBuilderLegacyForkTest -R "@openzeppelin/contracts/=dependencies/openzeppelin-contracts/contracts/" -R "@openzeppelin/contracts-upgradeable/=dependencies/openzeppelin-contracts-upgradeable/contracts/"`.
  Local Forge is 1.2.0-rc and needed these command-only import mappings; no
  repository configuration changed. Dependency submodules match the committed
  revisions. Local fork tests were excluded; remote fork results follow.
- [CI run 38187428896](https://github.com/MetaLex-Tech/cybercorps-contracts/actions/runs/38187428896)
  identifies the same head SHA and passed **1,419 unit tests, 202 fork tests and
  the build-size gate**. Its solc 0.8.28 size output reports runtime sizes of
  19,130 bytes for `CertificateImageContentBuilder`, 14,856 for
  `CertificateImageBuilderContract`, and 21,607 for `CertificateUriBuilder`.
  The earlier local 20,212-byte content-library measurement above is retained as
  historical evidence; the exact-head CI measurement is 19,130 bytes.
- Independently checked the prior overflow example using Pillow with DejaVu Sans
  at 14px: sentence plus 38 `W`s, ellipsis and period measures 1,038.98px;
  the new 26-`W` result measures 870.98px, within the 1,024px viewport. Windows
  Segoe UI and Arial measurements also fit. This checks the reported regression,
  not every possible Unicode glyph or font substitution.
- `git diff --check origin/develop...HEAD` passed. The non-footer SVG fixture
  comparisons passed locally. The existing URI integration test checks the
  embedded footer and two metadata fields; preservation of other JSON fields
  is additionally supported by unchanged URI-builder source, not a full JSON
  snapshot assertion.

The existing Codex bot review covered `ea3a79279b`, before the 26-point fix.
This local review is not a new external-model review or owner approval. Merge,
deployment and live acceptance remain separate gates. This record update is
local and uncommitted until deliberately shared.

## Review and blockers

PR: [#175](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/175), open, non-draft, against `develop`, opened 2026-10-12 from the records commit `ea3a792` on top of the content commit `5d0cd208`. Codex review of `ea3a792` returned one P2 finding (footer name limit); fixed in `2a8e8b5b`. Auto-merge is off.

Independent review: the repository's normal PR review (Codex bot plus the
owner). Merge, deployment, the upgrade script and Safe signing need separate
authorization; this record grants none.

## Next action and handoff

Run the PR review loop until the owner merges or closes the PR. After merge,
the fix reaches live tokens only when a new `CertificateImageBuilderContract`
(with its linked library) is deployed and set on each `CertificateUriBuilder`
proxy with `setImageBuilder`; `script/upgrade-certificate-rendering.s.sol`
does this and writes a Safe batch. That step needs its own authorization and
its own record entry. Ownership stays with this task.
