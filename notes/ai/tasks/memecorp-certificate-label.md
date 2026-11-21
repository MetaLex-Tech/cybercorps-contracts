# Task: neutral certificate labels for memeCorps

- **Status:** Ready for review (PR open; merge, deployment and Safe signing are not authorized by this record)
- **Updated:** 2026-11-13 (UTC)
- **Owner:** Claude Code desktop session (memeCorps), acting for lex-node
- **Collaborators / boundaries:** Renderers only: `src/CertificateUriBuilder.sol`, `src/CertificateImageContentBuilder.sol`, the `CertificateSVGParams` struct and the new `MEMECORP_COMPANY_TYPE` constant in `src/CyberCorpConstants.sol`, their tests and this record. No change to the `SecurityClass` enum, `LedgerEntryToken`, `IssuanceManager`, `CyberCorp`, factories, storage, agreement IDs or signatures.
- **Objective:** A certificate of a company whose type is exactly `memeCorp (no legal entity)` shows "Meme Units" and never a security class, share wording or a securities ledger claim. Every other company's certificate renders exactly as before.
- **Out of scope:** Deployment, the renderer refresh transactions and Safe batches; webapp changes (tracked in metalex-webapp `notes/ai/tasks/memecorps.md`).
- **Canonical plan / sources:** metalex-webapp `notes/ai/tasks/memecorps.md` (Phase 0 discovery, PR MetaLex-Tech/metalex-webapp#2653).
- **Repository / branch:** MetaLex-Tech/cybercorps-contracts; base `develop` `32c59e3`; branch `claude/memecorp-certificate-label`.

## Owner decision

On 2026-11-13 the owner chose the renderer-only option over a new `SecurityClass` value. The stored class of a memeCorp LET stays an existing class (the webapp will issue `CommonStock`). Only the rendered metadata and image change. The owner accepted that the stored class value, events and indexer data still name that class.

## What changed

1. `MEMECORP_COMPANY_TYPE = "memeCorp (no legal entity)"`. The match is exact (`keccak256` of the bytes); case, spacing and substrings do not match.
2. `CertificateUriBuilder`:
   - `isMemeCorpType(string)` (public, pure).
   - For a memeCorp, the JSON `type`, the root `securityType` and the `securityType` attribute read `MemeUnit`.
   - It sets `CertificateSVGParams.memeUnits`, read from the raw company type before JSON escaping.
3. `CertificateSVGParams` gains a trailing `bool memeUnits`.
4. `CertificateImageContentBuilder`, when `memeUnits` is true:
   - Class line "Meme Units", for every class.
   - Unit tile "Units".
   - Price suffix "/unit".
   - Footer "{company} is not a legal entity. Meme units carry no rights." The name keeps the footer's escaping and 26-code-point limit.

## Acceptance and current state

| # | Criterion | State |
| --- | --- | --- |
| 1 | A memeCorp image shows the neutral labels and no "Common Stock", "Shares", "/sh" or "securities ledger", for every class value | Verified: `MemeCorpCertificateLabelTest` (image tests) |
| 2 | The company type match is exact | Verified: `testCompanyTypeMatchIsExact` |
| 3 | A memeCorp token JSON says `MemeUnit` in `type`, root `securityType` and the attribute, and contains no `CommonStock` | Verified: `testMemeMetadataUsesMemeUnitEverywhere` |
| 4 | A near-miss company type renders the security class | Verified: `testNearMissCompanyTypeKeepsTheSecurityClass` |
| 5 | Existing certificate tests are unchanged | Verified: footer, SVG compatibility, JSON escaping, legacy, recertification and renderer-upgrade suites pass |
| 6 | Live Base certificates render byte-identical after the refresh | Verified: `MemeCorpCertificateLabelForkTest` renders `tokenURI(0)` of 11 Base LETs (classes 0, 1, 2, 4, 6, 7, 8) before and after; 0 changed |
| 7 | Contract sizes stay under 24,576 bytes | Verified (production settings): `CertificateUriBuilder` 21,977; `CertificateImageContentBuilder` 22,087; `CertificateImageBuilderContract` 14,621 |
| 8 | Independent review and merge | Pending |
| 9 | Deployment and live acceptance | Not started; not authorized here |

## Decisions and evidence

- **Deployed renderer state (Base, 2026-11-13):**
  - The URI builder proxy `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3` runs implementation `0xd922503429a876a5614b90884c16f327b9751f56`. Its runtime equals the `develop` `32c59e3` build, once the UUPS self address and metadata are masked.
  - The image renderer `0x0B721658c3D1B755ce8f2E71C3350cE3149662ed` equals the `develop` build except for its linked library address and an embedded metadata hash.
  - That linked library, `0x0d19166b6bb60b6a05892ae12eec23bc2792c21e` (22,010 bytes), does not match the `develop` library build (20,884 bytes), and its source was not identified. The fork test (criterion 6) shows that the refreshed renderers produce the same output for the sampled certificates.
- **Deployment path:** the existing `script/upgrade-certificate-rendering.s.sol` deploys the image renderer and its linked library, upgrades the URI builder, and prepares the owner Safe batch. It needs no new script. Each chain needs its own run.
- **Past audit findings:**
  - Hexens MTLX1-15 (Low, Fixed): JSON injection through unescaped `legalDetails`. The new code adds only constant strings. The company name keeps `CertificateText.xml` escaping in the image and `JsonLib.jsonEscape` in the JSON. The JSON escaping suite passes.
  - The Pashov AI report flags metadata injection in LeXcheX and extension renderers only. Those are not touched.
  - No finding covers memeCorps or neutral labels.
- **Trust limitation:** `companyType` is set by the company owner and is not verified (webapp V12 F-280792). Any company can choose the memeCorp type and get the neutral labels. That is intended: the type is the company's own statement that it has no legal entity.

## Validation

| Check | Evidence and revision | Result |
| --- | --- | --- |
| Certificate suites | `forge test --match-contract '^(MemeCorpCertificateLabelTest\|MemeCorpCertificateLabelForkTest\|CertificateFooterTest\|CertificateSvgCompatibilityTest\|CertificateUriBuilderJsonEscapingTest\|CertificateUriBuilderLegacyTest\|IssuanceManagerRecertTokenUriRegressionTest\|UpgradeCertificateRenderingScriptTest\|UpgradeCertificateFooterScriptTest)$'` with `RPC_URL_BASE` set | 96 passed, 0 failed |
| Sizes | `forge build --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --sizes --skip test script` | Passed |
| Full test suite | Not run locally | CI |

## Next action and handoff

Review and merge. Then the owner decides when to run `script/upgrade-certificate-rendering.s.sol` on each chain. The webapp memeCorps Phase 1 issues meme units as `CommonStock` with series `NA` and the exact company type.
