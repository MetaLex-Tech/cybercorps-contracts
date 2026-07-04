# dealManager secondary trades — exemption path test coverage map

Coverage map for `test/DealManagerSecondaryTradeExemptionPathwayTest.t.sol`, an integration test
that drives a **full secondary trade (`post → accept → finalize`) through each exemption pathway**
with the *real* secondary-trading conditions and the *real* `LeXcheXBadge` credential layer wired in.
Happy paths only.

Pathway → condition mapping is grounded in `cyberTRADE Exemption Pathways v3.52.md`
(§"Condition Contracts per Pathway"), verified against `cyberTRADE_spec_v3.55.dev0.md` §5 / §6.1–6.5
and §4.1.4 — consistent, same five pathways and same per-pathway conditions.

Not every condition the spec maps to a pathway is implemented yet. Conditions that exist in
`src/libs/conditions/secondary/` are wired for real; the essential-but-unimplemented ones are stood
in by in-file pass-through mocks so each pathway's canonical condition-set shape is represented.

## Legend

- ✓ real condition, enforced and passing
- ○ real condition attached but auto-silent for this pathway (short-circuits to pass)
- Ⓜ in-file pass-through mock (condition not yet implemented)
- — not attached for this pathway

## Scenario × condition

All scenarios: SELL offer, full fill (100 units), expected terminal state **FINALIZED**. Distinct
buyer per pathway. SPV-layer conditions apply to every pathway; pathway-layer conditions are keyed
by `exemptionPathway`; closing conditions are evaluated at finalize.

| Scenario (test fn)              | Pathway         | Buyer profile                            | Seller cert `acquisitionDate` | KYCAML | TaxInfo | HolderCap | ERISA | USState | Legion | HoldingPeriod | Accredited | QIB | NonUSPerson | RegSCompliance | Rule144Disc | §4a7Disc | LegalOpinion | AgreementSigned | GlobalKill | TimeSettlement |
|---------------------------------|-----------------|------------------------------------------|-------------------------------|:------:|:-------:|:---------:|:-----:|:-------:|:------:|:-------------:|:----------:|:---:|:-----------:|:--------------:|:-----------:|:--------:|:------------:|:---------------:|:----------:|:--------------:|
| `test_Rule144_HappyPath`        | RULE_144        | US individual, state CA                  | > 365 d ago                   |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |       ✓       |     —      |  —  |      —      |       —        |      Ⓜ      |    —     |      —       |        Ⓜ        |     Ⓜ      |       Ⓜ        |
| `test_Section4a7_HappyPath`     | SECTION_4A7     | US **accredited**, CA                    | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |       —       |     ✓      |  —  |      —      |       —        |      —      |    Ⓜ     |      —       |        Ⓜ        |     Ⓜ      |       Ⓜ        |
| `test_Section4a1Half_HappyPath` | SECTION_4A1HALF | US sophisticated (KYC only), CA          | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |       —       |     —      |  —  |      —      |       —        |      —      |    —     |      Ⓜ       |        Ⓜ        |     Ⓜ      |       Ⓜ        |
| `test_Rule144A_HappyPath`       | RULE_144A       | US **QIB**, CA                           | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |       —       |     —      |  ✓  |      —      |       —        |      —      |    —     |      —       |        Ⓜ        |     Ⓜ      |       Ⓜ        |
| `test_RegulationS_HappyPath`    | REGULATION_S    | **non-US person** (juris KY, no usState) | > compliance period ago       |   ✓    |    ✓    |     ✓     |   ○   |    ○    |   ✓    |       —       |     —      |  —  |      ✓      |       ✓        |      —      |    —     |      —       |        Ⓜ        |     Ⓜ      |       Ⓜ        |

**SPV-layer (all pathways):** KYCAML, TaxInfo, HolderCap, ERISA, USState, Legion, AgreementSigned(Ⓜ).
**Closing set (all):** GlobalKill(Ⓜ), TimeSettlement(Ⓜ).
**Pathway-layer:** the columns to the right of Legion.

## Condition → coverage

| Condition                             | Real? | Covered by                     | Notes                                                                                                     |
|---------------------------------------|:-----:|--------------------------------|-----------------------------------------------------------------------------------------------------------|
| KYCAMLCondition                       |   ✓   | all 5                          | both buyer & seller hold a valid KYC_AML badge                                                            |
| TaxInfoCondition                      |   ✓   | all 5                          | admin records `setTaxForm(buyer, W9, …)`                                                                  |
| HolderCapCondition                    |   ✓   | all 5                          | §3(c)(1), cap 100; buyer is a fresh holder (+1 ≤ 100)                                                     |
| ERISACondition                        |   ✓   | 144, 4a7, 4a1½, 144A (○ Reg S) | buyer's `acceptorPartyValues=[attestation]` recorded on the settlement agreement                          |
| USStateOfResidenceCondition           |   ✓   | 144, 4a7, 4a1½, 144A (○ Reg S) | buyer state CA (NY is default-blocked, unused); silent for the non-US Reg S buyer                         |
| LegionSoulboundCondition              |   ✓   | all 5                          | buyer holds the Legion custom-category credential                                                         |
| HoldingPeriodCondition                |   ✓   | 144                            | reads `FundInterestData.acquisitionDate` from the seller cert                                             |
| LexChexBadgeKind(ACCREDITED_INVESTOR) |   ✓   | 4a7                            | buyer-only                                                                                                |
| LexChexBadgeKind(QIB)                 |   ✓   | 144A                           | buyer-only                                                                                                |
| LexChexBadgeKind(NON_US_PERSON)       |   ✓   | Reg S                          | buyer-only; approximates the spec's zkPassport `NonUSPersonCondition` (a generic `ICondition`, not typed) |
| RegSDistributionComplianceCondition   |   ✓   | Reg S                          | `setRegSConfig(corp, 3, 365 d)`; reads acquisitionDate                                                    |
| Rule144DisclosureCondition            |   Ⓜ   | 144                            | not implemented → in-file mock                                                                            |
| Section4a7DisclosureCondition         |   Ⓜ   | 4a7                            | not implemented → in-file mock                                                                            |
| LegalOpinionCondition                 |   Ⓜ   | 4a1½                           | not implemented → in-file mock                                                                            |
| AgreementSignedCondition              |   Ⓜ   | all 5                          | not implemented → in-file mock (SPV-layer)                                                                |
| GlobalKillCondition                   |   Ⓜ   | all 5                          | not implemented → in-file mock (closing)                                                                  |
| TimeSettlementPeriodCondition         |   Ⓜ   | all 5                          | not implemented → in-file mock (closing); the real one would need a warp between accept & finalize        |
| CFIUSCondition                        |   —   | none                           | optional per-SPV; out of scope for these happy paths                                                      |
| GPLPApprovalCondition                 |   —   | none                           | optional per-SPV; out of scope                                                                            |

## Not yet covered (future work)

- Negative / revert paths per condition (expired badge, unmet hold, blocked state, holder-cap breach,
  missing tax form, missing ERISA attestation, U.S. buyer on Reg S, unconfigured Reg S SPV).
- BUY-side offers (bids) per pathway.
- Partial fills across multiple settlements.
- The real `TimeSettlementPeriodCondition` / `GlobalKillCondition` once implemented.
