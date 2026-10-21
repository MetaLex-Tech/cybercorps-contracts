# SAFO extension and v0.22 legal alignment

- Status: Implementation, local review and legal document QA complete. Clean SAFO v1.0 and cumulative v0.22 redline saved in the editable form bank. Not deployed or enabled in the webapp.
- Updated: 2026-10-17 (America/Bogota).
- Owner: Codex, current cyberForms cleanup task.
- Authorization: owner approved a dedicated SAFO extension and the eight scoped SAFO cleanup recommendations after reviewing v0.22. V0.22 remains the settled substantive position.
- Base: `2510ff38723f6e084e7399325958220daa859d61` (`origin/develop`, freshly fetched).
- Branch: `codex/safo-extension`.
- Scope: standalone per-LET metadata extension, focused tests and schema documentation; matched clean legal master and cumulative comparison against v0.22 are managed in the editable legal form bank.
- Out of scope: core storage, SecurityClass enum, payment/signature/authorization/lifecycle changes, frontend enablement, live issuance, template registration, IPFS publication, merge or deployment.

## Discovery and approach

Reviewed CyberCorp identity/authentication, IssuanceManager printer creation, LedgerEntryToken and its storage, CertificateUriBuilder, agreement registry, DealManager/RoundManager responsibilities and the existing extension versions. The earlier protocol-wide cyberRaise audit and fresh current-source check establish that the existing `CertificateDetails.extensionData` payload and `ICertificateExtension` renderer support a separate decoder without changing LET storage. This extension does not calculate conversion entitlements or implement the issuance/payment lifecycle.

Use a single per-LET `SAFOData` payload. No series/class inheritance or custom-provision precedence is introduced. The base extension surface avoids V3's v5-only scoped reads. This is source-level compatibility, not a statement that any specific live company has been verified for SAFO.

Existing investment amount and project valuation remain `CertificateDetails.investmentAmountUSD` and `issuerUSDValuationAtTimeOfInvestment` (18 decimals). SAFO adds minimum project reserve (four decimal places of percentage points; 100%=1,000,000), maximum cliff/unlock durations (seconds from launch), explicit tokenholder-governance boolean, optional outside date (enabled flag plus whole calendar years from original Issue Date), optional copied unlock parameters, and per-LET custom provisions. Explicit presence flags distinguish an omitted option from a legitimate zero value. Structure elections, launch configuration and the derived calculation method remain offchain as v0.22 provides.

No existing SAFE/SAFT/SAFTE enum value is treated as a native SAFO classification. Native classification, renderer labels and app selection remain a separately scoped integration decision. New deployment would require deploying this new extension/proxy, selecting it only for compatible new SAFO payloads, a new registered legal template and matching frontend configuration. No existing extension proxy should be upgraded to decode SAFO payloads.

## Invariants and acceptance cases

1. Exact roundtrip of each SAFO term, including false/zero, optional outside date, custom text and optional unlock schedule. Empty/malformed/wrong-schema payloads refuse decoding.
2. Reserve and cliff percentages use percentage points with four decimals; monetary values remain only in core fields. No valuation, conversion formula, election, priority, tax or launch rule is implemented or changed by this metadata contract.
3. JSON is valid and escapes arbitrary custom text; booleans and optional presence are unambiguous; no duplicate economic sources or series overrides.
4. Implementation initialization is disabled; proxy initializes once; upgrades retain existing BorgAuth owner checks.
5. Current URI-builder base-extension path renders SAFO data without V3 reads. Existing extension regression tests continue to pass.
6. Encoder/decoder validation is not a mint-time enforcement hook: opaque core payload writes can bypass it. Application and release acceptance must validate payloads before issuance.
7. No real transaction, registration, deployment or new native classification is performed. Unknown issuer runtime capabilities remain a release blocker.

## Validation and review

- Added `SAFOExtension`, its focused Foundry suite, extension index entry and `docs/reference/safo-extension.md` (explicitly include this new file despite the repository's `docs/` ignore pattern).
- `forge test --match-path 'test/{SAFOExtensionTest,ExtensionJsonEscapeTest,CertificateUriBuilderJsonEscapingTest,CertificateUriBuilderLegacyTest}.t.sol' -vv`: 33 local tests passed, including all eight SAFO cases and 256 fuzz runs. The two `CertificateUriBuilderLegacyForkTest` cases could not start because `ALCHEMY_API_KEY` is absent. They remain unverified; this is not a fully passing fork run.
- `forge fmt --check` on the two new Solidity files and `git diff --check` passed. No new compiler warning originated in the SAFO files.
- Independent internal reviewer found no contract defect and independently passed 20 ABI/render acceptance and refusal probes against the compiled bytecode on ephemeral local Anvil. Review and probe evidence: `/home/lex/repos/metalex-webapp/output/safo-revision-20261017/qa/contract-review.md` and `contract-abi-probes.json`.
- Legal deliverables and immutable v0.22 baseline: `/home/lex/repos/metalex-webapp/output/safo-revision-20261017/manifest.json`. The clean instrument's field units match the implementation. Actual v0.22 already contains the Proceeds definition; it was preserved, correcting the earlier review's mistaken missing-definition observation.
- Final legal QA passed: exactly 23 scoped paragraph revisions and 154 unchanged retained paragraphs; all 30 clean and 32 redline pages reviewed; both DOCX packages validated. Independent XML acceptance/rejection projections reproduce the clean instrument and original v0.22, including headers and tabs. Native processor accept-all automation was unavailable and is not represented as a passing test. The two identified layout defects were repaired and visually rechecked.
- Delivery receipt: `/home/lex/repos/metalex-webapp/output/safo-revision-20261017/delivery.json`; final QA receipt: `qa/final-check.json` in the same output directory. Clean master: `cyberForms/cyberSAFO/MetaLeX_cyberSAFO_jx-neutral_Reg_D_v1.0.docx`; comparison and baseline archive: `cyberForms/_Revision archive/2026-10-17 SAFO v1.0/`. The original v0.22 remains byte-identical. Cloud synchronization has not been independently verified.
- Tests ran on the uncommitted extension/test additions on the stated base; the independent contract report records their SHA-256 fingerprints. The delivery receipt records the resulting local commit after the reviewed files are committed.
- No source changes to core classification/storage, issuance lifecycle, authorization, signatures or payment paths. No deployment, registration, IPFS publication, merge or live enablement performed.

Internal agent review is not represented as the required external-model release review. End-to-end live-runtime acceptance is not established by local source tests. Native SAFO classification/application support, release review and target-runtime acceptance remain separate release gates.
