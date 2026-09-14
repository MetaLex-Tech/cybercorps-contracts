# PR #116 merge plan

Reviewed 2026-09-11: PR head `9b0bf74f797ea32597e26c7b3f4f2548c9b9e6ee`, target `origin/develop` at `402b6d3`.

## Port implementation

Implemented on `codex/let-svg-compatibility`, based on `402b6d3`. The sections below retain the original review and plan; this section records the resulting design.

- The new SVG uses a separate `CertificateSVGParamsV2` / `buildCertificateSVGV2` interface. The original image selector remains callable, and the four existing encoded/unencoded, legacy/structured URI entry points are unchanged. Token, issuance, and token-storage code are unchanged.
- Issue Date uses the token's stored `issueTimestamp`, including administrative overrides. Acquisition changes do not substitute a new issue date. Unknown/unsupported dates are blank; the query block is no longer displayed. No agreement-signing-date field was added.
- Optional metadata calls are limited to 2,000,000 gas and 128 KiB of returndata. Dynamic decoding runs inside caught external frames. Missing, reverting, oversized, malformed, or gas-exhausting dependencies omit only their optional data. Known zero reservations stay explicit. Unknown status is blank rather than active.
- A missing/failing image renderer yields valid JSON with a blank image. An older image renderer is used as a fallback only for a known issue date, because those renderers interpret zero as 1970. The atomic rendering upgrade gives legacy printers the new SVG with blank unknown dates.
- SVG text is XML escaped, long display text is shortened, and the image shows at most six restrictions with a notice pointing to the full JSON list. JSON retains full source values. Consideration is currency-neutral and fractional units are preserved.
- `CertificateImageContentBuilder` is a linked public library to meet EIP-170. Deploy/link this library when deploying `CertificateImageBuilderContract`; it has no mutable state. The existing locally edited upgrade script is preserved and atomically changes the URI implementation and image address. Its dry-run must include the linked library deployment/link configuration before broadcast.
- Normal, long-text, and voided SVGs were parsed as XML and rendered in headless Chrome for visual inspection.

Validation results are recorded at the end of this document. No source merge, remote PR update, or on-chain broadcast is part of this local port.

## Recommendation

Port the new LET SVG onto current develop in a focused replacement PR. Use `732cf755766f7493ccfd844de231da193b9a5140` (New SVG Image) as the visual reference, not the whole feature branch as the implementation baseline. Preserve the later restrictive-legend text/title conversion where needed. Link the replacement to #116 and supersede #116 once the replacement passes review and merges.

GitHub reports #116 as conflicting; its recorded Build sizes, Unit tests, and Fork tests checks all failed. A local `git merge-tree` simulation confirms conflicts across the URI builder, renamed printer contracts, trading/storage logic, extensions, scripts, and tests. Some unrelated files merge automatically, so resolving only conflict markers is insufficient protection against regressions.

This is a source/history review and merge plan, not a completed implementation or a passing test report. No contract code was changed and no deployment was performed. The existing uncommitted `script/upgrade-certificate-uri-builder.s.sol` edit was inspected and preserved.

## Findings that block merging as-is

1. **Legacy reservation revert returns.** PR `unitsReservedToString()` directly calls `unitsReserved(tokenId)`. Develop's `unitsReservedToJson()` catches getter reverts and omits the unavailable field, from `5c3297a` / PR #155. Retain that behavior, including distinguishing known zero (`"0.00"`) from unavailable.
2. **Issue date is not the stored issue date.** Both renderer versions currently use `_getAgreementTimestamp()`, take the final array entry in `signedAt`, and substitute `block.timestamp` when unavailable. PR #117 introduced distinct issue/acquisition timestamps; current LET exposes both, with administrative overrides. The SVG must use those authoritative values appropriately and must not manufacture a date at read time.
3. **Read-time block number changes the image.** PR adds `block.number` to the authorization display. This is also an existing inline review finding. No stored issuance block is provided by this change; omit that display unless a reliable historical source exists.
4. **Other optional data can still revert.** `buildEndorsementHistory()` makes an unguarded registry call. Develop's certificate-level `getExtensionURI(bytes)` is unguarded. The PR's alternate extension path decodes successful low-level returndata without validation and has an unguarded legacy fallback. Guard the complete read/decode path, not only selected getters.
5. **Ordinary try/catch is not sufficient for malformed return data.** The current legacy test explicitly expects malformed reservation returndata to revert. The new resilience requirement should extend this behavior: return blank/omit optional data for empty, truncated, or invalid responses too. Replace that test expectation and isolate decoding behind a catchable boundary or validate ABI structure before decoding.
6. **Image-builder ABI changes.** Adding fields to `CertificateSVGParams` changes the external `buildCertificateSVG` selector. Upgrading only one side breaks the rendering call. The public URI-builder overloads called by older printers must retain their exact tuple layouts and selectors.
7. **New presentation needs hardening.** SVG strings are interpolated without XML escaping; consideration formatting reintroduces a dollar sign despite `8aba9a1` removing the USD assumption. Per-unit multiplication can overflow and fractional units are truncated. Carry forward the JSON escaping fixes and handle these SVG/number cases before accepting the new renderer.

## Implementation sequence

### 1. Isolate the renderer change

- Start an isolated branch/worktree from the latest develop, using a `codex/` branch name. Leave the current workspace edit intact.
- Port the layout from `CertificateImageBuilder.sol`, `CertificateImageContentBuilder.sol`, and the thin `CertificateImageBuilderContract.sol` wrapper.
- Adapt `CertificateUriBuilder.sol`, `CyberCorpConstants.sol`, and the image interface together. Prefer a separately named V2 SVG parameter struct/interface and retain the old image-builder entry point as an adapter if direct consumers need it. Do not change the printer-facing `IUriBuilder` ABI.
- Keep current LET names, storage, trading contracts, V3 series/extension architecture, constructor initializer protection, and compiler-size fixes. Do not import old printer, issuance, conditions, or extension implementations from #116.
- Maintain the legacy string-array and structured restrictive-legend URI overloads. Keep current JSON root fields and attributes for available data.

### 2. Define and implement datetime behavior

- Read `issueTimestamp(tokenId)` defensively. A valid nonzero stored value, including an administrative override, is authoritative for **Issue Date**.
- Read `acquisitionTimestamp(tokenId)` separately if acquisition data is displayed. Never substitute it for Issue Date. Preserve current legal-owner-change, migration, and override semantics; rendering must not write timestamp storage.
- When the issue timestamp is unavailable/zero, default the Issue Date display to blank. A registry signature date is not necessarily issuance: if retained, expose it as a separately labeled **Agreement signed** date, using the greatest valid nonzero signature timestamp rather than the final array position. Do not infer signing order from party order.
- Use zero only as an internal unavailable sentinel. Render unavailable dates as an empty string or omit optional JSON attributes; never show January 1, 1970 or today's date as a fallback.
- Use a single Gregorian UTC conversion with bounded input/work, preserving leap-year correctness. Very large unsupported values return blank rather than causing excessive loops or arithmetic errors. If time of day is shown, label it UTC and include seconds consistently.
- Remove the current-block authorization line. Advancing the clock or block alone must not change metadata for a token whose source data is unchanged.

### 3. Make optional metadata best-effort throughout

- Centralize safe optional reads for reservations, timestamps, void status, issuer/manager/corp metadata, certificate extensions, series extensions, and registry agreement details.
- Probe capabilities by calls, not `DEPLOY_VERSION()`: older deployments can lack version getters or expose mixed capabilities.
- Handle no-code addresses, missing selectors, explicit reverts, empty successful returns, malformed fixed/dynamic ABI data, and missing nested dependencies. Ensure decoding failure is caught outside the decoding call frame. Apply reasonable returndata/gas limits where needed so optional metadata cannot consume the whole render budget.
- Preserve supported values exactly. Missing reservations are omitted, supported zero remains explicit; missing text is blank; missing collections/extensions are omitted or empty. Do not label an unknown void status as confirmed active: render a neutral/blank status unless the source returned a valid boolean.
- Guard registry enrichment inside endorsement history. Preserve known endorsements even if purchase-agreement details are unavailable. Assemble JSON fields without leading/dangling commas when collections are empty.
- Keep develop's V1/V2 certificate extension and V3 series behavior. Add compatibility for another historical selector only where a real deployed implementation/test fixture requires it; do not replace current interfaces with the PR's obsolete two-blob interface.
- Catch image-renderer failure as a final availability measure and return valid metadata with a blank image when necessary. A blank image is an acceptable degraded fallback, but healthy current and legacy fixtures must still produce the intended SVG.
- Keep nonexistent-token errors in the token contract. The compatibility promise concerns valid tokens with missing optional metadata, not suppressing token existence checks.

### 4. Preserve formatting and existing fixes

- Preserve `JsonLib.jsonEscape` use from the newer metadata fixes (`5293a32`, `a2b5e66`) and the guarded issuer/series enrichment already on develop.
- XML-escape every dynamic SVG text/attribute value independently of JSON escaping, including company/officer/owner names and restrictions. Keep XML valid for quotes, ampersands, angle brackets, control characters, and Unicode.
- Keep consideration currency-neutral unless a trustworthy currency source is available. Preserve fractional unit precision; handle zero units and use overflow-safe per-unit math with a blank fallback for unrepresentable values.
- Confirm the issuer-address label corresponds to the displayed address: the PR supplies the printer address, not the corporation address. Label it as the token contract or resolve the corporation defensively.
- Keep known voided stamps and restrictions readable; check long names and many restrictions for clipping/overlap.

### 5. Tests required before merge

- Extend `CertificateUriBuilderLegacyTest.t.sol`: retain all #155 supported/missing getter assertions; change malformed response coverage to assert blank data without a revert. Add no-code/empty-return cases.
- Test full encoded and unencoded URI paths through both old and current caller ABIs, not just helper functions. Decode base64, parse JSON, and parse the embedded SVG as XML.
- Exercise legacy printer fixtures without each optional selector, current LETs, V1/V2 extensions, V3 series extensions, missing/reverting registries, truncated return data, empty arrays, mismatched registry arrays, and extension failures. One failed enrichment must not discard unrelated fields.
- Test stored issue vs. acquisition time, both admin overrides, secondary ownership changes, same-owner updates, scripification/recertification, zero dates, and legacy missing getters. Include leap days (2000/2024), non-leap century 2100, month/year boundaries, unordered/trailing-zero signing timestamps, and extreme timestamp inputs.
- Assert URI bytes remain identical after `vm.warp` and `vm.roll` when all source state is unchanged. Update the original SVG fork test, which currently expects the read-time block number.
- Preserve `IssuanceManagerRecertTokenUriRegression.t.sol`, extension/JSON escaping tests, and current timestamp/ownership tests. Add SVG cases for hostile text, fractional units, zero units, extreme consideration, and unknown versus confirmed void status.
- Extend the existing pinned Base Sepolia v3 fixture at block `46_649_711`, printer `0x2614b85a83bE8a5B4c007F29910E9Ec75f5498BC`, token 1. Upgrade only the URI/image rendering path; leave the old printer implementation intact. Assert owner/data preservation, valid JSON, and a nonblank new SVG. Add representative deployed versions on supported networks where fixtures are available.
- Run focused tests first, then the repository's unit/fork CI suites and production build-size checks. Inspect UUPS storage compatibility and selector compatibility. Linked libraries must be included in size/deployment validation; do not raise code-size limits to make the production build pass.

### 6. Upgrade and merge gate

- Incorporate the existing upgrade-script improvement when implementing: deploy the matching image builder and URI implementation, then call `upgradeToAndCall(implementation, abi.encodeCall(setImageBuilder, (newImageBuilder)))` so the implementation/pointer switch is atomic.
- Retain chain-specific target selection, owner authorization preflight, fresh deployment behavior, and post-upgrade implementation/image/AUTH checks. Validate linked-library deployment requirements introduced by the thin wrapper.
- Dry-run the script on pinned forks and verify representative old/current `tokenURI()` results, ownership, proxy storage, and roles before and after. Record old implementation/image addresses for an atomic rollback. No legacy printer upgrade or data migration should be required for metadata availability.
- Review the final diff against fresh develop: only rendering, narrowly required interfaces/helpers, regression tests, and the upgrade script should remain. Rerun checks after any base update.
- Merge the focused replacement only when compatibility, dates, JSON/XML, storage/ABI, code-size, and CI checks pass. Publishing a deployment is a separate action from merging the source.

## Evidence

- [PR #116](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/116): head state, failed checks, and inline current-block review.
- [Visual source commit](https://github.com/MetaLex-Tech/cybercorps-contracts/commit/732cf755766f7493ccfd844de231da193b9a5140): six-file SVG change.
- [PR #117](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/117): issuance/acquisition timestamp lineage, also verified in current LET source.
- [PR #155](https://github.com/MetaLex-Tech/cybercorps-contracts/pull/155): reservation-getter compatibility fix, verified in current source and legacy tests.

The target branch remains the authority for all later fixes. Recheck its tip when implementation starts; this review does not establish that every unrelated historical fix has been audited.

## Local validation of the port

Validation uses Solidity 0.8.28, via-IR, optimizer enabled, 15 runs. Local Forge is 1.2.0 on Windows; CI remains pinned to 1.7.1 and was not changed.

- Full unit command (`forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --nmc '(ForkTest|AdhocTest)'`): **1,223 passed, zero failures/skips**, across 60 suites. This includes all 15 new SVG compatibility tests and the reservation/JSON/recertification regressions.
- Full fork command (`forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --threads 1 --mc ForkTest --nmc AdhocTest`): **176 passed, zero failures/skips**, across 19 suites on the final source. Both pinned legacy v3 tests pass, including the atomic renderer upgrade without upgrading the printer.
- Production size command (`forge build --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --sizes --skip test script`): **passed**. Runtime sizes: URI builder 21,719 bytes; image builder 14,856 bytes; linked content library 19,152 bytes, all below 24,576 bytes.
- Upgrade-script dry run on Base Sepolia: **passed**, targeting URI proxy `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3`. Forge included the content-library deployment, both renderer deployments, and one atomic `upgradeToAndCall(address,bytes)`. No transactions were broadcast. Estimated total script gas was 16,677,574.
- Normal, long-text/restriction, and voided samples: valid XML and visually inspected in headless Chrome at 1024 × 1024.
- `git diff --check`: passed. Existing URI-builder storage declarations, legacy SVG tuple, printer-facing interfaces, and token/issuance code remain unchanged.

The upgrade script's pre-existing local edit is retained. Dry-run addresses are simulation results, not new live deployments. A source PR and any live deployment remain separate from this local implementation.
