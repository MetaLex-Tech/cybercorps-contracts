# SAFE Purchase Amount semantics — planning only

- **Status:** Proposed; no implementation authorized.
- **Updated:** 2026-11-11, America/New_York.
- **Owner:** Planning in this Codex chat; implementation/PR owner unknown. Conversation identifies lex_node as new-template owner; ownership is not transferred here.
- **Objective:** Scope the smallest change that makes newly issued/traded SAFEs use current nominal dollar units independently of secondary consideration.
- **Sources:** User-supplied conversation and summary, 2026-11-11; repository source below. General roadmap: `notes/plans/protocol-improvement-plan.md`; no existing SAFE-specific task/plan was located.
- **Repository snapshot:** `codex/robinhood-intermediate-20261028`, HEAD `f90978dbf333abb19a20696fd879cb8aad55bdc4`. Existing unrelated dirty Robinhood scripts/tests/records and `.gitignore` were preserved. Remote fetch failed because `.git/FETCH_HEAD` was not writable; this is a local snapshot, not verification of current develop or the discussed PR.
- **PR:** Unidentified; its actual diff has not been reviewed.
- **Boundaries:** No source, tests, templates, global indexes or canonical roadmap changed. No tests, independent review, integration submissions, publication, merge or deployment performed. This record is local-only until deliberately shared.

## Proposed sequence and decision owners

1. lex_node finalizes a new versioned SAFE template: Purchase Amount is current `unitsRepresented`, normalized for its actual decimal scale. Decide whether Purchase Price Paid is omitted (recommended) or explicitly linked to an acquisition record. Specify the authoritative Mapping/field and treatment of scripified units; do not assume raw and effective balances are interchangeable.
2. Engineering/PR owner (unknown) inventories the actual PR and all relevant consumers. Existing secondary-transfer code already decrements seller units and mints a fresh buyer lot for sold units. Remove unnecessary parallel principal accounting, historical-field redistribution, multiplier logic and legacy compatibility from the proposed scope. Do not globally redefine shared fields across instrument types.
3. Reporting owner plus legal/tax stakeholders (unknown) confirm whether finalized settlement logs and a reconstructible per-lot index meet reporting requirements. Trace agreement ID to printer and buyer token ID, payment token/decimals, amount, fees, time and finalization/refund status. Specify any required USD valuation separately from token amount. Add storage/event changes only if an actual requirement cannot be met.
4. Decide the zero-field issue after steps 1–3: retain `investmentAmountUSD` in the shared struct; deprecate its contractual use for the new SAFE template. A zero secondary value alone is not a demonstrated bug once no required consumer relies on it. If a retained consumer does need it, define expected semantics and reproduce its failure before a minimal fix. Do not populate it with nominal transferred units while describing it as consideration paid.
5. Prepare template/app/indexer/renderer changes only where required for consistent labels and version selection. New-template activation is separate from contract upgrades. Existing SAFEs retain their original definitions; any voluntary void/reissue requires the separately established consent/authorization process, not an automatic migration.

## Local evidence

- `src/storage/IssuanceManagerStorage.sol:893-932`: seller active units decrease, buyer gets sold units on a new lot, buyer `investmentAmountUSD` and issuer valuation are explicitly zero. Source comments describe blank primary-issuance basis.
- `test/IssuanceManagerSecondaryTransferTest.t.sol:97`, `:135`, `:146`, `:322`: tests explicitly require blank buyer basis and unchanged seller primary snapshot. These were read, not run.
- `src/interfaces/ILedgerEntryToken.sol:48-55`: `investmentAmountUSD` and `unitsRepresented` belong to shared `CertificateDetails`, not SAFE extension data.
- `src/storage/LedgerEntryTokenStorage.sol:1006-1029`: active getter returns stored details; effective getter adds scripified units. Legal wording and accounting must address this distinction without double counting claims/scrip.
- `src/CertificateUriBuilder.sol:694`, `:728`: renderer receives and JSON exposes `investmentAmountUSD`; assess consumer/display meaning before deprecating.
- Follow-up image inspection: `src/CertificateUriBuilder.sol:365-367` marks consideration known and assigns the passed `investmentAmountUSD`. `src/CertificateImageContentBuilder.sol:283-296` forces SAFE displayed units to `1` and formats that consideration rather than nominal units. Consequently the secondary-sale example renders one instrument on each image, seller consideration still 100,000 and buyer consideration 0, instead of showing current nominal amounts 90,000/10,000. Proposed SAFE-only display change: show explicitly labeled Purchase Amount from the approved units balance; omit or mark unavailable any untracked price paid. Keep other convertible/share rendering semantics separately scoped. This is source-derived behavior, not a fresh rendered-image test or deployment check; no implementation performed.
- `src/interfaces/ISecondaryTradeStorage.sol:184-224` and finalization in `src/storage/SecondaryTradeStorage.sol:614-625`: logs carry settlement/payment/finalization information; `SecondaryTransferExecuted` links the newly minted lot. Sufficiency for reporting is pending, not established by source inspection.
- `src/converters/SafeCertificateConverter.sol:23-78`: conversion logic referencing `investmentAmountUSD` is commented out. Do not claim this proves an active conversion dependency or implement a converter as part of this task. Conversion documentation/tests still warrant consumer inventory.

## Acceptance to specify before implementation

- Primary SAFE amount and units agree at the approved scale and issuance terms.
- A 100,000-dollar SAFE selling 10,000 nominal units leaves 90,000 with the seller and 10,000 with the buyer whether consideration is 5,000, 10,000 or 15,000 dollars.
- Partial, repeated and full sales conserve nominal entitlements across resulting lots; full-sale voiding respects outstanding scrip claims. Fractional sends, scripify/recertify and relevant loan-value consumers preserve entitlement without double counting.
- Required cap/valuation and other legal terms survive the transfer where the new template requires them; inspect the currently blank buyer valuation field rather than assuming it is harmless.
- Renderer/app/reporting distinguish nominal SAFE amount from acquisition consideration and historical issuance fields.
- Finalized payment records reconstruct per acquisition; cancelled/refunded agreements do not count as completed acquisitions.
- Priced shares retain share counts and price-per-unit behavior. Other instruments using the shared struct keep their existing semantics.
- Existing SAFE definitions/records are not silently rewritten. New issuances select the intended approved template version.
- Any retained substantive bug fix has a failing behavioral regression first. Unit checks, integration acceptance, required independent external-model review, merge and deployment remain separate. Any transaction-flow change requires authorized test-environment sign -> simulate -> submit success/refusal coverage; none is authorized or performed by this planning request.

## Next action

Obtain the exact PR/head and lex_node's approved definitions, then resolve the balance/getter and reporting questions before selecting any contract patch. This plan does not start implementation or an external audit and does not waive existing review gates.
