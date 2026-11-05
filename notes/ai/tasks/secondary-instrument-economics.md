# Preserve the purchase amount and cap in secondary sales

- Status: Implementation complete; PR preparation and review monitor setup in progress.
- Date: November 4, 2026, America/Bogota.
- Owner: Codex chat `01a1a94a-6d4e-7643-98d1-cab96d4668d2`.
- Repository: `MetaLex-Tech/cybercorps-contracts`.
- Branch: `codex/preserve-secondary-instrument-economics`.
- Base: `caa83643b09806d5e0036e627e7cd14cd02a3b23` on `develop`.
- Authorization: The owner requested a contracts fix and a PR after the explanation of zero buyer fields.
- Scope: Preserve the recorded purchase amount and cap for SAFE, SAFT and SAFTE transfers.
- Additional approval: The owner approved a narrow guard against scrip conversion into a reserved convertible lot on November 4, 2026.
- Exclusions: Merge, deployment, upgrades, live signatures, new audits, legal amendments, signature changes, bundles and warrant group limits.
- Other owners: Gpxl retains the webapp secondary-sale work. The parent chat retains the common product and agreement plan.
- Plan: This record states the invariants and acceptance cases for this small change.

## Invariants before implementation

1. A whole transfer passes the recorded purchase amount and cap to the buyer.
2. A partial transfer divides the recorded purchase amount in proportion to the transferred units.
3. Buyer amount plus retained seller amount equals the source amount before the transfer.
4. A cap stays unchanged. It is not a balance to divide.
5. The denominator includes active units and the source lot's current vault claim. Only active units can transfer.
6. The buyer amount rounds down. The seller retains the remainder. A final exhaustive transfer passes that remainder.
7. If positive source principal rounds to zero for the buyer, the transfer reverts with `InvalidAmount`.
8. Other security classes keep their existing zero-basis behavior.
9. Payment, fees, authorization, signatures, extension bytes, custody and acquisition clocks keep their existing behavior.
10. The fix does not reconstruct historical zero amounts or prove that an instrument allows a partial assignment.

No storage layout or public function selector change is planned. A new linked IM library and IM implementation require deployment.
Factory references and each target company's IM upgrade require separate approval. Existing deployments do not change when this PR opens.

## Related audit history

Read the Hexens final report, the Pashov AI report, the secondary scope, vault accounting notes and existing audit regressions.
Also read the webapp's secondary assessment and SAFO V12 response records.

| Finding | Original severity and response | Relation to this change |
| --- | --- | --- |
| Hexens MTLX1-28 | Low; Acknowledged | Extension-level paid balances remain copied. This PR changes separate core purchase fields and does not resolve this finding. |
| Hexens MTLX1-9 | Medium; Acknowledged | Extension tacking data remains copied. The original response stays unchanged. |
| Hexens MTLX1-8 | Medium; Acknowledged | Independent review found a new economic consequence after this fix. A seller could add units after acceptance and reduce buyer principal. The owner approved a guard for reserved convertible destinations. The broader timestamp and cross-lot behavior remains unchanged. |
| Hexens MTLX1-32 | Medium; Fixed | Payment uses cumulative price allocation. This PR must not alter that calculation. |
| Hexens MTLX1-25 | Low; Fixed | Voided sources must still refuse transfers. |
| Hexens MTLX1-12 | Low; Fixed | Custody checks must still refuse a zero administrator address. |
| Hexens MTLX1-22 | Low; Fixed | Legal transfer restrictions must remain effective for manager custody. |
| V12 F-295271 | High; unresolved, with a scoped SAFO owner risk acceptance | No signature change or new waiver is included. Existing ownership stays unchanged. |

These source responses are not deployed-runtime verification. No new external audit or dashboard change is authorized.

## Acceptance cases

- Full and partial transfers for SAFE, SAFT and SAFTE.
- A later resale from a buyer lot.
- Repeated partial fills and the final rounding remainder.
- Positive amounts too small for the proposed allocation.
- Full-precision arithmetic near the uint256 limit.
- Randomized amount and unit conservation.
- Retained vault units and direct redemption by the same seller.
- Actual DealManager acceptance, escrow and finalization with resale cash separate from original purchase amount.
- Unchanged stock, custody, raw-unit, vault, condition, void and refund tests.

## Evidence and gates

Verified code: `77a1b51906b03dd5eed6daf3e52df92bc5bc5930`.
The full local suite passed 1,544 tests. The final allocation test passed 10,000 randomized cases.
Before-fix regressions produced eight failures and one pass.
The build passed. IM runtime is 18,692 bytes. The linked library is 24,554 bytes, with 22 bytes below EIP-170.
The library size has an explicit regression check.

The independent Claude Opus 5.5 review found no introduced material defect after the approved guard.
The local signed sale had 37 successful receipts and correct state reads.
The local guard case refused a signed conversion transaction and then settled with $50,000 assigned to each side.
See `notes/verification/secondary-instrument-economics.md` and its local test JSON for evidence and limits.

PR monitoring will use the owning chat. No other chat owns this new PR.
No target company was supplied. Target-runtime verification and deployed acceptance remain separate gates.
No contract merge is authorized. Do not enable auto-merge for this PR.
