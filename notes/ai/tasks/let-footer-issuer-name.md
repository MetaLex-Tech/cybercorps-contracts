# Task: LET certificate footer names the issuing company

- **Status:** Ready for review (PR open; merge, deployment and Safe signing are not authorized by this record)
- **Updated:** 2026-10-11 23:40 UTC
- **Owner:** Claude Code session in worktree `keen-benz-55739a`, acting for lex-node
- **Collaborators / boundaries:** Renderer only: `src/CertificateImageContentBuilder.sol`, its tests and fixtures, and these records. No change to `CertificateImageBuilderContract`, `CertificateUriBuilder`, their interfaces, `LedgerEntryToken`, `CyberCorp`, storage, agreement IDs or signatures. The series-designation feature prototyped in the scratch worktree `ccc-wt-series-naming` is a separate decision and is not reused here.
- **Objective:** Every LET image footer names the issuing company with the sentence the owner settled, and every other byte of the SVG and of the token JSON is unchanged.
- **Out of scope:** Deployment, upgrade transactions or Safe batches; the JSON `title` field ("MetaLeX Tokenized Certificate"); designation or series-naming text; webapp changes.
- **Canonical plan / sources:** this record; [DECISIONS.md](../DECISIONS.md) entry "2026-10-11: LET certificate footer wording"; metalex-webapp `AGENTS.md` ("Smart-contract change boundaries").
- **Repository / branch:** MetaLex-Tech/cybercorps-contracts; base `develop`, working branch `claude/keen-benz-55739a`.
- **Verified base / code head:** base `10fa89f236b8dcc5b19db0d9c256fe2f1d40d035` (tip of `develop` on 2026-10-11); content commit `5d0cd208e175a7a54f990b85478687be8146c2f8`. Later commits on the branch change only these records.
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
3. The company name is XML-escaped and cut at the header's limit of 38 code
   points, so the footer shows the name exactly as the header does. **Done;
   verified by `testFooterEscapesAndTruncatesTheName`.**
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
- **Implementation choice.** `buildSVGContent` escapes `corpName` once with the
  header's limit (38) and passes it to `_buildHeaderText` and the new
  `_buildFooter`. A separate escape call for the footer cost about 2.1 KB of
  library bytecode because via-IR inlines `CertificateText.xml` at every call
  site; sharing the escaped string cut that to about 1.1 KB and keeps the two
  renderings of the name identical. The header output is unchanged.
- **Scratch prototype** (`ccc-wt-series-naming`, `_buildFooter`): matched on
  jurisdiction alone and bundled a designation feature. Read for reference;
  nothing reused.
- **Empty company name:** the footer then ends with "ledger of .". The header
  renders an empty name as an empty line today. Left unchanged; noted in the PR.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Live defect | `cast call` of `tokenURI(0)` on Base via `https://mainnet.base.org`, decoded; CyberCorp getters; 2026-10-11 | Confirmed: the footer named MetaLeX Labs, Inc. and cited the DGCL for a Wyoming LLC SAFE |
| New unit tests | `forge test --match-path "test/*Certificate*"` on the working tree equal to `5d0cd208` for all code files | `CertificateFooterTest`: 7 passed |
| Pre-existing renderer suites | same run | `CertificateSvgCompatibilityTest` 18, `UpgradeCertificateRenderingScriptTest` 6, `CertificateUriBuilderLegacyTest` 8, `CertificateUriBuilderJsonEscapingTest` 2: all passed |
| Fork tests | same run | `CertificateUriBuilderLegacyForkTest` (2 tests) not run: `vm.createSelectFork` needs `ALCHEMY_API_KEY`, which this machine does not have. They run in CI |
| Full suite | `forge test` on the same tree | 1,419 passed, 24 failed. 23 failures are fork tests that need `ALCHEMY_API_KEY` or `FORK_RPC_URL` and fail in `setUp` before any code runs (CI runs them with the key). The other, `test_VaultEmptyingConversion_FitsInABlockAtLargeSupply` in `IssuanceManagerVaultEpochAdhocTest`, hits the default per-test gas cap in a 6,500-holder setup; it uses `MockUriBuilderForIM`, so the changed library is not on its path, and CI excludes `AdhocTest` contracts (`--nmc`). CI on `develop` is green at `10fa89f2` |
| Byte identity | `testEverythingButTheFooterIsUnchanged` against `test/res/let-svg-10fa89f2-*.svg` (captured at `10fa89f2`, 15,557 and 15,835 bytes, committed byte-exact) | Passed for a Delaware corporation and a voided Wyoming LLC SAFE |
| Sizes | `forge build --sizes --skip test --skip script` at `10fa89f2` and at `5d0cd208` | `CertificateUriBuilder` 21,607 → 21,607; `CertificateImageBuilderContract` 14,856 → 14,856; `CertificateImageContentBuilder` 18,066 → 19,193 (margin 5,383); limit 24,576 |
| Diff scope | `git show --stat 5d0cd208` | `src/CertificateImageContentBuilder.sol`, `test/CertificateFooterTest.t.sol`, two fixtures. No interface, script, docs or webapp change |

No deployment, integration acceptance or external review result exists yet.

## Review and blockers

PR: [#175](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/175), open, non-draft, against `develop`, opened 2026-10-12 from the records commit `ea3a792` on top of the content commit `5d0cd208`. Auto-merge is off.

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
