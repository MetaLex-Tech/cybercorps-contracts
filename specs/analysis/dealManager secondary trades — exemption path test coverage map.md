# dealManager secondary trades — exemption path test coverage map

Coverage map for `test/DealManagerSecondaryTradeExemptionPathwayTest.t.sol`, an integration test
that drives a **full secondary trade (`post → accept → finalize`) through each exemption pathway**
with the *real* secondary-trading conditions and the *real* `LeXcheXBadge` credential layer wired in.

Pathway → condition mapping is grounded in `cyberTRADE Exemption Pathways v3.52.md`
(§"Condition Contracts per Pathway"), verified against `cyberTRADE_spec_v3.55.dev0.md` §5 / §6.1–6.5
and §4.1.4 — consistent, same five pathways and same per-pathway conditions.

**Every condition in the map is now a real implementation from `src/libs/conditions/secondary/` —
no in-file mocks remain.** The closing set (`KillSwitchCondition`, `TimeSettlementPeriodCondition`)
is enforced for real on every pathway: each happy path warps past the 24h minimum settlement period
between acceptance and finalization, and two dedicated tests exercise the closing conditions' own
blocking behavior.

**Latest run:** `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15
--match-contract DealManagerSecondaryTradeExemptionPathwayTest` →
**12 passed / 0 failed** (5 pathway happy paths + 3 closing-condition tests + 4 pathway-election tests).

**Who elects the pathway.** The exemption is the buyer's to claim, so the buyer elects it: on a sell offer at
`acceptOffer`, on a buy offer at `postOffer` (there the offeror *is* the buyer). A sell offeror may leave
`exemptionPathway` as `NONE` — the ordinary shape — or pin one to restrict who can accept. Because the
pathway is per-settlement, so is its Layer 1 condition set: the offer snapshots only the SPV layer, and each
settlement snapshots the exemption layer for the pathway its buyer elected.

## Legend

- ✓ real condition, enforced and passing
- ○ real condition attached but auto-silent for this pathway (short-circuits to pass)
- — not attached for this pathway

## Scenario × condition

All scenarios: SELL offer, full fill (100 units), expected terminal state **FINALIZED**. Distinct
buyer per pathway. SPV-layer conditions apply to every pathway; pathway-layer conditions are keyed
by `exemptionPathway`; closing conditions are evaluated at finalize (after a +24h warp to clear the
settlement period).

| Scenario (test fn)              | Pathway         | Buyer profile                            | Seller cert `acquisitionDate` | KYCAML | TaxInfo | HolderCap | ERISA | USState | Legion | AgreementSigned | HoldingPeriod | Accredited | QIB | NonUSPerson | RegSCompliance | Rule144Disc | §4a7Disc | LegalOpinion | KillSwitch | TimeSettlement |
|---------------------------------|-----------------|------------------------------------------|-------------------------------|:------:|:-------:|:---------:|:-----:|:-------:|:------:|:---------------:|:-------------:|:----------:|:---:|:-----------:|:--------------:|:-----------:|:--------:|:------------:|:----------:|:--------------:|
| `test_Rule144_HappyPath`        | RULE_144        | US individual, state CA                  | > 365 d ago                   |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |        ✓        |       ✓       |     —      |  —  |      —      |       —        |      ✓      |    —     |      —       |     ✓      |       ✓        |
| `test_Section4a7_HappyPath`     | SECTION_4A7     | US **accredited**, CA                    | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |        ✓        |       —       |     ✓      |  —  |      —      |       —        |      —      |    ✓     |      —       |     ✓      |       ✓        |
| `test_Section4a1Half_HappyPath` | SECTION_4A1HALF | US sophisticated (KYC only), CA          | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |        ✓        |       —       |     —      |  —  |      —      |       —        |      —      |    —     |      ✓       |     ✓      |       ✓        |
| `test_Rule144A_HappyPath`       | RULE_144A       | US **QIB**, CA                           | any                           |   ✓    |    ✓    |     ✓     |   ✓   |    ✓    |   ✓    |        ✓        |       —       |     —      |  ✓  |      —      |       —        |      —      |    —     |      —       |     ✓      |       ✓        |
| `test_RegulationS_HappyPath`    | REGULATION_S    | **non-US person** (juris KY, no usState) | > compliance period ago       |   ✓    |    ✓    |     ✓     |   ○   |    ○    |   ✓    |        ✓        |       —       |     —      |  —  |      ✓      |       ✓        |      —      |    —     |      —       |     ✓      |       ✓        |

**SPV-layer (all pathways):** KYCAML, TaxInfo, HolderCap, ERISA, USState, Legion, AgreementSigned.
**Closing set (all):** KillSwitch, TimeSettlement.
**Pathway-layer:** the columns between AgreementSigned and KillSwitch.

## Closing-condition behavior tests

| Test fn                                           | What it proves                                                                                                                                                                                                                                         |
|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_KillSwitch_BlocksFinalize_UntilLowered`     | Platform-wide flag: either admin raises unilaterally mid-deal → finalize reverts `SecondaryConditionsNotMet(killSwitch)`; the proposer alone cannot confirm the lower (two-call, two-admin lowering); once the other admin confirms, finalize succeeds |
| `test_SettlementKill_BlocksFinalize_UntilLowered` | Per-settlement flag: raising it blocks that agreement's finalize end-to-end; two-admin lower then clears it (cross-settlement isolation covered by the `KillSwitchCondition` unit suite)                                                               |
| `test_TimeSettlement_BlocksEarlyFinalize`         | `finalizableAt == acceptance + 24h`; finalize before the window reverts `SecondaryConditionsNotMet(timeSettlement)`; after the warp it succeeds                                                                                                        |

## Condition → coverage

| Condition                             | Real? | Covered by                     | Notes                                                                                                                                            |
|---------------------------------------|:-----:|--------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| KYCAMLCondition                       |   ✓   | all 5                          | both buyer & seller hold a valid KYC_AML badge                                                                                                   |
| TaxInfoCondition                      |   ✓   | all 5                          | admin records `setTaxForm(buyer, W9, …)`                                                                                                         |
| HolderCapCondition                    |   ✓   | all 5                          | §3(c)(1), cap 100; buyer is a fresh holder (+1 ≤ 100)                                                                                            |
| ERISACondition                        |   ✓   | 144, 4a7, 4a1½, 144A (○ Reg S) | buyer's attestation recorded as a signer value on the settlement agreement                                                                       |
| USStateOfResidenceCondition           |   ✓   | 144, 4a7, 4a1½, 144A (○ Reg S) | buyer state CA (NY is default-blocked, unused); silent for the non-US Reg S buyer                                                                |
| LegionSoulboundCondition              |   ✓   | all 5                          | buyer holds the Legion custom-category credential                                                                                                |
| AgreementSignedCondition              |   ✓   | all 5 (SPV-layer)              | `registry.allPartiesSigned(settlementId)`; silent at posting, satisfied from acceptance onward                                                   |
| HoldingPeriodCondition                |   ✓   | 144                            | reads the seller cert's base `acquisitionTimestamp` (tacking anchor still from the extension); seller lot aged past HOLD by minting then warping |
| LexChexBadgeKind(ACCREDITED_INVESTOR) |   ✓   | 4a7                            | buyer-only                                                                                                                                       |
| LexChexBadgeKind(QIB)                 |   ✓   | 144A                           | buyer-only                                                                                                                                       |
| LexChexBadgeKind(NON_US_PERSON)       |   ✓   | Reg S                          | buyer-only; approximates the spec's zkPassport `NonUSPersonCondition` (a generic `ICondition`, not typed)                                        |
| RegSDistributionComplianceCondition   |   ✓   | Reg S                          | `setRegSConfig(corp, 3, 365 d)`; reads the seller cert's base `acquisitionTimestamp`                                                             |
| Rule144DisclosureCondition            |   ✓   | 144                            | SPV admin records `setDisclosurePackage(corp, uri, asOf)`; 16-month freshness policy                                                             |
| Section4a7DisclosureCondition         |   ✓   | 4a7                            | package freshness (from posting) + buyer's acknowledgment-of-receipt signer value (from acceptance)                                              |
| LegalOpinionCondition                 |   ✓   | 4a1½                           | GP records `recordGPSignOff(dm, offerId)` between post and accept, pre-approving the offer's settlements                                         |
| KillSwitchCondition                   |   ✓   | all 5 (closing) + kill tests   | plain singleton; two admin slots (MetaLeX + Legion), raise unilateral / lower two-call, at both platform-wide and per-settlement scope           |
| TimeSettlementPeriodCondition         |   ✓   | all 5 (closing) + timing test  | 24h default from acceptance (reconstructed as `escrow.expiry − settlementWindow`); happy paths warp past                                         |
| CFIUSCondition                        |   ✓   | none                           | implemented; optional per-SPV, out of scope for these happy paths                                                                                |
| GPLPApprovalCondition                 |   ✓   | none                           | implemented; optional per-SPV, out of scope                                                                                                      |

## Pathway-election tests

The five happy paths above run on offers that pin their pathway. These cover the unpinned (`NONE`) shape,
where the buyer elects at acceptance.

| Test fn                                                     | What it proves                                                                                                                                     |
|-------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_UnpinnedOffer_BuyersElectDifferentPathways`           | One unpinned offer, two half-fills: a QIB elects 144A and an accredited buyer elects §4(a)(7); each settlement snapshots only its own pathway's Layer 1 set, and both finalize |
| `test_RevertIf_UnpinnedOffer_BuyerElectsPathwayTheyDoNotQualifyFor` | An accredited non-QIB electing 144A is stopped at acceptance by the QIB condition — the layer an unpinned offer never ran at posting        |
| `test_RevertIf_UnpinnedOffer_BuyerElectsNoPathway`          | `NONE` at acceptance reverts `ExemptionPathwayRequired`; a settlement always has a real pathway                                                     |
| `test_RevertIf_PinnedOffer_BuyerElectsAnotherPathway`       | A seller's pin restricts the election: a qualifying QIB electing 144A on a Rule 144 offer reverts `ExemptionPathwayMismatch`                        |

Buy-side election rules (pathway required at `postOffer`, acceptor's election ignored) and the EIP-712
binding of the elected pathway are covered in `DealManagerSecondaryTradeTest`.

## Test-fixture notes

- The agreement template carries **two party fields** (`erisaAttestation`, `section4a7Ack`); every
  buyer submits both values at acceptance, and each condition scans signer values for its own marker,
  so carrying the §4(a)(7) ack on non-4a7 pathways is harmless.
- Per-SPV setters (`setRegSConfig`, `setDisclosurePackage`, `setStateBlocked`,
  `recordGPSignOff`) are gated on the SPV's / DealManager's own BorgAuth via
  `IBorgAuthProvider(target).AUTH()`; the test corp exposes `AUTH()` for this.
- Closing conditions are plain (non-proxied) singletons; the threshold conditions are
  ERC1967-proxied UUPS deployments, matching the intended production topology.

## Not yet covered (future work)

- Negative / revert paths per threshold condition (expired badge, unmet hold, blocked state,
  holder-cap breach, missing tax form, missing ERISA attestation, U.S. buyer on Reg S, unconfigured
  Reg S SPV, stale disclosure package, missing GP sign-off).
- BUY-side offers per pathway.
- `TimeSettlementPeriodCondition` per-DealManager `setDelayOverride` (QMS-mode 45-day parameterization).
- `KillSwitchCondition` admin rotation (`rotateAdmin`).
