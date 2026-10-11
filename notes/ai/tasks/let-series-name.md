# Task: LET certificate shows its own series name

- **Status:** Ready for review (branch pushed; no PR yet)
- **Updated:** 2026-10-11
- **Owner:** Claude Code session for the owner; the owner opens the PR after diff review
- **Collaborators / boundaries:** Renderer only. No change to LedgerEntryToken, CyberCertPrinter, IssuanceManager, extensions, factories, agreement IDs, signatures or authorization.
- **Objective:** The Ledger Entry Token image and tokenURI JSON show each certificate's free-text series name in the class and series line, for example "Preferred Stock Series Seed 2". The fixed `SecuritySeries` label stays the fallback.
- **Out of scope:** Deployment, upgrade transactions, Safe batches, any company-contract or extension change.
- **Canonical plan / sources:** `src/CertificateUriBuilder.sol`, `src/CertificateImageBuilderContract.sol`, `src/CertificateImageBuilder.sol`, `src/CertificateImageContentBuilder.sol`, `src/libs/CertificateSeries.sol`.
- **Repository / branch:** `MetaLex-Tech/cybercorps-contracts`; base `develop` at `10fa89f2`, branch `claude/let-series-name`.
- **Verified base / code head:** tests ran on the code commits that precede this record on the branch.
- **Worktree locator:** local worktree, not shared.
- **PR / artifact:** not yet created.

## Acceptance and current state

- Verified (unit): V1 share cert terms name; Share V3 cert, series and class layers; SAFE V3 and SAFT V3 series data; empty name and NA fallback; malformed, oversized and reverting extension reads; two certs on one printer; an image builder without V3.
- Verified (Ethereum fork, block 26,171,000): printer `0xc0449f24cf28dDA64aFfB74b81a460Fb9b1E0E37` tokens 0, 1 and 3 show "Series Seed 2" and token 2 shows "Series Seed" after the atomic upgrade. A URI-only upgrade keeps the deployed image builder, which shows the fixed label.
- Not done: independent review, merge, deployment, upgrade of the URI builder proxy `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3`, live acceptance.

## Decisions and evidence

- Line rule: class label, one space, series text. The series text is the stored name when it is not empty, else the fixed enum label ("Pre-Seed", "Series Seed", "Series A" ... "ACE"; NA has none). The name is printed as stored: no "Series" is added and no word is removed, so "Series Seed Preferred" on Preferred Stock prints "Preferred Stock Series Seed Preferred". The image escapes the name and shows at most 48 code points, then "...". The JSON keeps the full name.
- JSON: `securitySeries` is unchanged. A new root `seriesName` and a `seriesName` attribute carry the series text that the image shows (NA without a name gives "").
- Name sources: V1 share extension (`supportsExtensionType(SHARE)`) gives `terms.seriesName` from the cert payload. Share, SAFE, SAFT, SAFTE, token warrant and ACE SAFE V3 extensions (by their V3 type) answer `resolveCert(printer, tokenId)`; the renderer reads the first string of the first member. Fund interest V3 and all other extensions use the fallback. The reader checks every offset against the data length, does no ABI decoding and cannot revert.
- Image: new `buildCertificateSVGV3(params, timestamp, seriesName)` on a new stateless image builder. The URI builder tries V3, then V2, then V1. V3 with an empty name is byte-identical to V2.
- `CertificateUriBuilder` storage layout is unchanged (the new values are constants).

## Validation

| Check | Evidence | Result |
| --- | --- | --- |
| New tests on `develop` | Same e2e and fork file run on `10fa89f2` | 22 of 23 fail; the passing one records the live state before the upgrade |
| New tests on the branch | `forge test --match-contract '(CertificateSeries\|CertificateUriBuilderLegacyForkTest\|ShareExtensionForkTest)'` with public RPCs | 42 passed |
| Unit suite | `forge test --nmc '(ForkTest\|AdhocTest)'` | branch 1,443 passed, 0 failed; `develop` 1,412 passed, 0 failed |
| Sizes | `forge build --sizes --skip test script` | URI builder 23,069 B (was 21,607); image builder 15,099 B (was 14,856); content library 19,245 B (was 18,066); company contracts unchanged |
| Share V3 tokenURI gas | `ShareExtensionIntegrationTest` log | 21,978,906 (was 21,533,343) |

## Review and blockers

Independent review not started. Deployment needs the MetaLeX Safe: `script/upgrade-certificate-rendering.s.sol` deploys the new image builder and URI implementation and queues one `upgradeToAndCall(implementation, setImageBuilder(image))`.

## Next action and handoff

Owner reviews the diff on `claude/let-series-name` and opens the PR.
