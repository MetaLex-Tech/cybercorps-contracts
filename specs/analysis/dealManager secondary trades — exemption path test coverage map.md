# dealManager secondary trades — exemption path test coverage map

Coverage map for `test/DealManagerSecondaryTradeExemptionPathwayTest.t.sol`, an integration test
that drives a **full secondary trade (`post → accept → finalize`) through each exemption pathway**
with the *real* secondary-trading conditions and the *real* `LeXcheXBadge` credential layer wired in.

Pathway → condition mapping is grounded in `cyberTRADE Exemption Pathways v4.1.md`
(§"Condition Contracts per Pathway"), verified against `cyberTRADE_spec_v3.55.dev0.md` §5 / §6.1–6.5
and `cyberTRADE_spec_v4.1.docx.md` §4.1.4 — consistent, same five pathways and same per-pathway
conditions. §5 and its two decision diagrams are unchanged from v3.52: neither the v4 nor the v4.1
redline reproduces §5, so the pathway selection logic carries forward untouched.

**Every condition in the map is now a real implementation from `src/libs/conditions/secondary/` —
no in-file mocks remain.** The closing set (`KillSwitchCondition`, `TimeSettlementPeriodCondition`)
is enforced for real on every pathway: each happy path warps past the 24h minimum settlement period
between acceptance and finalization, and two dedicated tests exercise the closing conditions' own
blocking behavior.

**Latest run:** `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15
--match-contract DealManagerSecondaryTradeExemptionPathwayTest` →
**27 passed / 0 failed** (5 pathway happy paths + 3 closing-condition tests + 5 pathway-election tests +
4 decision-tree tests + 6 gate/staging negatives + 2 mid-flight lapse tests + 2 buy-side tests).

**Who elects the pathway.** The exemption is the buyer's to claim, so the buyer elects it: on a sell offer at
`acceptOffer`, on a buy offer at `postOffer` (there the offeror *is* the buyer). A sell offeror may leave
`exemptionPathway` as `NONE` — the ordinary shape — or pin one to restrict who can accept. Because the
pathway is per-settlement, so is its Layer 1 condition set: at posting only the SPV layer applies, and from
acceptance onward the exemption layer for the pathway that lot's buyer elected. Condition sets are resolved
live at each stage and never stored — only the election itself is recorded, on `SecondaryEscrow`.

| Offer side    | Pathway set by                                  | NONE allowed?                        |
|---------------|-------------------------------------------------|--------------------------------------|
| SELL unpinned | buyer, at acceptOffer                           | at post yes; at accept never         |
| SELL pinned   | seller restricts; buyer must elect the same one | mismatch -> ExemptionPathwayMismatch |
| BUY           | offeror (who is the buyer), at postOffer        | no -> ExemptionPathwayRequired;      |
|               |                                                 | acceptor's election ignored          |

## Legend

- ✓ real condition, enforced and passing
- ○ real condition attached but auto-silent for this pathway (short-circuits to pass)
- — not attached for this pathway

## Scenario × condition

All scenarios: SELL offer, full fill (100 units), expected terminal state **FINALIZED**. Distinct
buyer per pathway. SPV-layer conditions apply to every pathway; pathway-layer conditions are keyed
by `exemptionPathway`; closing conditions are evaluated at finalize (after a +24h warp to clear the
settlement period).

| Scenario (test fn)              | Pathway         | Buyer profile                            | Seller cert `acquisitionDate` | Eligibility | HolderCap | USState | Legion | HoldingPeriod | Accredited | QIB | NonUSPerson | RegSCompliance | Rule144Disc | §4a7Disc | LegalOpinion | KillSwitch | TimeSettlement |
|---------------------------------|-----------------|------------------------------------------|-------------------------------|:-----------:|:---------:|:-------:|:------:|:-------------:|:----------:|:---:|:-----------:|:--------------:|:-----------:|:--------:|:------------:|:----------:|:--------------:|
| `test_Rule144_HappyPath`        | RULE_144        | US individual, state CA                  | > 365 d ago                   |      ✓      |     ✓     |    ✓    |   ✓    |       ✓       |     —      |  —  |      —      |       —        |      ✓      |    —     |      —       |     ✓      |       ✓        |
| `test_Section4a7_HappyPath`     | SECTION_4A7     | US **accredited**, CA                    | any                           |      ✓      |     ✓     |    ✓    |   ✓    |       —       |     ✓      |  —  |      —      |       —        |      —      |    ✓     |      —       |     ✓      |       ✓        |
| `test_Section4a1Half_HappyPath` | SECTION_4A1HALF | US sophisticated (KYC only), CA          | any                           |      ✓      |     ✓     |    ✓    |   ✓    |       —       |     —      |  —  |      —      |       —        |      —      |    —     |      ✓       |     ✓      |       ✓        |
| `test_Rule144A_HappyPath`       | RULE_144A       | US **QIB**, CA                           | any                           |      ✓      |     ✓     |    ✓    |   ✓    |       —       |     —      |  ✓  |      —      |       —        |      —      |    —     |      —       |     ✓      |       ✓        |
| `test_RegulationS_HappyPath`    | REGULATION_S    | **non-US person** (juris KY, no usState) | > compliance period ago       |      ✓      |     ✓     |    ○    |   ✓    |       —       |     —      |  —  |      ✓      |       ✓        |      —      |    —     |      —       |     ✓      |       ✓        |

**SPV-layer (all pathways):** Eligibility, HolderCap, USState, Legion.
**Closing set (all):** KillSwitch, TimeSettlement.
**Pathway-layer:** the columns between Legion and KillSwitch.

## Closing-condition behavior tests

| Test fn                                           | What it proves                                                                                                                                                                                                                                         |
|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_KillSwitch_BlocksFinalize_UntilLowered`     | Platform-wide flag: either admin raises unilaterally mid-deal → finalize reverts `SecondaryConditionsNotMet(killSwitch)`; the proposer alone cannot confirm the lower (two-call, two-admin lowering); once the other admin confirms, finalize succeeds |
| `test_SettlementKill_BlocksFinalize_UntilLowered` | Per-settlement flag: raising it blocks that agreement's finalize end-to-end; two-admin lower then clears it (cross-settlement isolation covered by the `KillSwitchCondition` unit suite)                                                               |
| `test_TimeSettlement_BlocksEarlyFinalize`         | `finalizableAt == acceptance + 24h`; finalize before the window reverts `SecondaryConditionsNotMet(timeSettlement)`; after the warp it succeeds                                                                                                        |

## Condition → coverage

| Condition                             | Real? | Covered by                     | Notes                                                                                                                                                                                               |
|---------------------------------------|:-----:|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| EligibilityCondition                  |   ✓   | all 5 + D1/E2                  | admin clears both buyer & seller (`setClearance(party, true)`); catch-all for KYC/AML, tax, ERISA, …                                                                                                |
| HolderCapCondition                    |   ✓   | all 5 + G3/G4                  | §3(c)(1), cap 100; buyer is a fresh holder (+1 ≤ 100). G3/G4 re-run it under `usResidentOnlyCount` (Touche Remnant)                                                                                 |
| USStateOfResidenceCondition           |   ✓   | 144, 4a7, 4a1½, 144A (○ Reg S) | buyer state CA (NY is default-blocked, unused); the non-US Reg S buyer's state is not consulted                                                                                                     |
| LegionSoulboundCondition              |   ✓   | all 5                          | buyer holds the Legion custom-category credential                                                                                                                                                   |
| HoldingPeriodCondition                |   ✓   | 144 + G2                       | reads the seller cert's base `acquisitionTimestamp` (tacking anchor still from the extension); seller lot aged past HOLD by minting then warping. G2 covers the unseasoned case, blocked at posting |
| LexChexBadgeKind(ACCREDITED_INVESTOR) |   ✓   | 4a7 + C1                       | buyer-only; C1 shows a QIB credential does not satisfy it                                                                                                                                           |
| LexChexBadgeKind(QIB)                 |   ✓   | 144A + E1/F1/F2                | buyer-only; E1 lapses it before finalize, F2 fires it at posting on a buy offer                                                                                                                     |
| LexChexBadgeKind(K_NON_US)            |   ✓   | Reg S                          | buyer-only; the attested fact-key, not the buyer's recorded country — negative case covered                                                                                                         |
| RegSDistributionComplianceCondition   |   ✓   | Reg S + A7                     | `setRegSConfig(corp, 3, 365 d)`; reads the seller cert's base `acquisitionTimestamp`. A7 covers a lot still inside the period                                                                       |
| Rule144DisclosureCondition            |   ✓   | 144 + G1                       | SPV admin records `setDisclosurePackage(corp, uri, asOf)`; 16-month freshness policy. G1 covers a stale package, blocked at posting                                                                 |
| Section4a7DisclosureCondition         |   ✓   | 4a7 + A3/A4                    | package freshness (from posting) + buyer's acknowledgment-of-receipt signer value (from acceptance); both negatives covered                                                                         |
| LegalOpinionCondition                 |   ✓   | 4a1½ + A5                      | GP records `recordGPSignOff(dm, offerId)` between post and accept, pre-approving the offer's settlements; A5 skips it                                                                               |
| KillSwitchCondition                   |   ✓   | all 5 (closing) + kill tests   | plain singleton; two admin slots (MetaLeX + Legion), raise unilateral / lower two-call, at both platform-wide and per-settlement scope                                                              |
| TimeSettlementPeriodCondition         |   ✓   | all 5 (closing) + timing test  | 24h default from acceptance (`escrow.acceptedAt`, stamped per lot); happy paths warp past                                                                                                           |
| CFIUSCondition                        |   ✓   | none                           | implemented; optional per-SPV, out of scope for these happy paths                                                                                                                                   |
| GPLPApprovalCondition                 |   ✓   | none                           | implemented; optional per-SPV, out of scope                                                                                                                                                         |

## Pathway-election tests

The five happy paths above run on offers that pin their pathway. These cover the unpinned (`NONE`) shape,
where the buyer elects at acceptance.

| Test fn                                                             | What it proves                                                                                                                                                                               |
|---------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_UnpinnedOffer_BuyersElectDifferentPathways`                   | One unpinned offer, two half-fills: a QIB elects 144A and an accredited buyer elects §4(a)(7); each lot settles under its own election, resolving a different Layer 1 set, and both finalize |
| `test_RevertIf_UnpinnedOffer_BuyerElectsPathwayTheyDoNotQualifyFor` | An accredited non-QIB electing 144A is stopped at acceptance by the QIB condition — the layer an unpinned offer never ran at posting                                                         |
| `test_RevertIf_UnpinnedOffer_BuyerElectsNoPathway`                  | `NONE` at acceptance reverts `ExemptionPathwayRequired`; a settlement always has a real pathway                                                                                              |
| `test_RevertIf_PinnedOffer_BuyerElectsAnotherPathway`               | A seller's pin restricts the election: a qualifying QIB electing 144A on a Rule 144 offer reverts `ExemptionPathwayMismatch`                                                                 |
| `test_RevertIf_RegulationS_BuyerNotAttestedNonUsPerson`             | Reg S turns on the attested `K_NON_US` fact, not the recorded country: a KY-jurisdiction buyer with no attestation is refused by the NonUSPerson condition                                   |

Buy-side election rules (pathway required at `postOffer`, acceptor's election ignored), the EIP-712 binding
of the elected pathway, and the per-SPV pathway enablement gate are covered in
`DealManagerSecondaryTradeTest`. That gate is why this suite's `setUp` enables all five pathways: an SPV
must declare which pathways it supports, so an unconfigured one blocks trades instead of settling them with
no Layer 1 checks.

## Test-fixture notes

- The agreement template carries a single party field (`section4a7Ack`); every buyer submits it at
  acceptance, and the condition scans signer values for its marker, so carrying the §4(a)(7) ack on
  non-4a7 pathways is harmless.
- Per-SPV setters (`setRegSConfig`, `setDisclosurePackage`, `setStateBlocked`,
  `recordGPSignOff`) are gated on the SPV's / DealManager's own BorgAuth via
  `IBorgAuthProvider(target).AUTH()`; the test corp exposes `AUTH()` for this.
- Closing conditions are plain (non-proxied) singletons; the threshold conditions are
  ERC1967-proxied UUPS deployments, matching the intended production topology.

## Which suite owns which negative

Three suites cover secondary trading, and a negative case belongs to exactly one of them.

| Suite                                           | Owns                                                                                            | Conditions used     |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------|---------------------|
| `test/conditions/secondary/*.t.sol`             | One condition's own logic: every branch, boundary, fail-closed default, and setter guard        | the real one, alone |
| `DealManagerSecondaryTradeTest`                 | Framework mechanics: set resolution, layering, pathway enablement, staging, config events       | stubs               |
| `DealManagerSecondaryTradeExemptionPathwayTest` | Whether a real buyer profile clears the right pathway at the right stage, with the set composed | all real            |

The test to write here is the one that fails if the *composition* is wrong — wrong condition in a
pathway's set, or the right condition firing at the wrong stage. A test that would still fail with
one condition deployed alone belongs in that condition's unit suite.

### Unit-negatives — already covered, no work needed

The earlier "not yet covered" list was stale; every item on it exists.

| Case                   | Covered by                                                                                                                                                                         |
|------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Unmet hold             | `HoldingPeriodCondition::test_OneDayShort_Fails` (+ tacking, unconfigured fail-closed)                                                                                             |
| Blocked state          | `USStateOfResidenceCondition::test_NewYork_Default_Fails`, `test_GpBlockedState_Fails`                                                                                             |
| Holder-cap breach      | `HolderCapCondition::test_FreshUsBuyer_BreachesCap_Fails` (+ look-through, US-block modes)                                                                                         |
| Unconfigured Reg S SPV | `RegSDistributionComplianceCondition::test_Unconfigured_FailsClosed`                                                                                                               |
| Stale disclosure       | `Rule144DisclosureCondition::test_StaleByOneSecond_Fails`, `Section4a7…::test_Accepted_StalePackage_Fails`                                                                         |
| Missing GP sign-off    | `LegalOpinionCondition::test_Accepted_NoAssurance_Fails` (+ per-mechanism, revocation)                                                                                             |
| Expired badge          | `LeXcheXBadge::test_HasValidCredentialOf_DeniedWhenExpiredOrVoided` and siblings                                                                                                   |
| Partial fills          | `test_UnpinnedOffer_BuyersElectDifferentPathways` (two half-fills of one offer)                                                                                                    |
| `setDelayOverride`     | `TimeSettlementPeriodCondition::test_Override2d_*`, `test_OverrideZero_RestoresDefault`                                                                                            |
| Kill-switch rotation   | `KillSwitchCondition::test_RotateOwnSlot`, `test_RotateToExistingAdmin_Reverts`, `test_ProposeThenRotateThenConfirm_Reverts` (+ settlement scope, `test_LowerAfterRotation_Works`) |

Expired badge needs no per-condition test: every badge-reading condition goes through
`hasValidCredentialOf` / `_mostRecentValidWith`, which drop expired and voided credentials before the
condition sees them, so an expired badge reduces to the already-tested no-credential path.

## Target matrix — exemption-specific cases

**POST** = `postOffer`, **ACC** = `acceptOffer`, **FIN** = `finalizeSecondaryTradeAgreement`. The expected
revert is `SecondaryConditionsNotMet(<condition>)` unless noted.

### A. The pathway's own gate, at the right stage

| #  | Case                                          | Pathway | Defect injected                                  | Stage | Fails on             | Covered by                                                          |
|----|-----------------------------------------------|---------|--------------------------------------------------|:-----:|----------------------|---------------------------------------------------------------------|
| A1 | Unseasoned lot rejected at posting            | 144     | seller lot aged < 365 d                          | POST  | holdingPeriod        | `test_UnseasonedLot_ClosesRule144_ForkSettles`                      |
| A2 | Stale disclosure package rejected at posting  | 144     | package older than the freshness policy          | POST  | rule144Disclosure    | `test_SeasonedLot_StaleInfo_ClosesRule144_ForkSettles`              |
| A3 | Stale information package rejected at posting | 4a7     | package older than the freshness policy          | POST  | section4a7Disclosure | `test_SeasonedLot_StaleInfo_ClosesRule144_ForkSettles`              |
| A4 | Buyer never confirms getting the package      | 4a7     | accepts without the required confirmation string |  ACC  | section4a7Disclosure | `test_RevertIf_Section4a7_BuyerOmitsAcknowledgment`                 |
| A5 | GP sign-off never recorded                    | 4a1½    | `recordGPSignOff` skipped                        |  ACC  | legalOpinion         | `test_RevertIf_Section4a1Half_NoGpSignOff`                          |
| A6 | Non-QIB buyer                                 | 144A    | buyer lacks `K_QIB`                              |  ACC  | qib                  | `test_RevertIf_UnpinnedOffer_BuyerElectsPathwayTheyDoNotQualifyFor` |
| A7 | Lot still inside the compliance period        | Reg S   | lot aged < compliance period                     | POST  | regS                 | `test_RevertIf_RegulationS_LotInsideCompliancePeriod`               |
| A8 | Buyer never attested non-US                   | Reg S   | jurisdiction KY, no `K_NON_US`                   |  ACC  | nonUsPerson          | `test_RevertIf_RegulationS_BuyerNotAttestedNonUsPerson`             |

A1–A3 are the blocking halves of the two group G tests, asserted on the same lot those tests then settle
under another pathway; A3 is asserted by both of them.

### B. Pinning a pathway at acceptOffer

| #  | Case                                        | Pathway | What it proves                                                                                       | Covered by                                             |
|----|---------------------------------------------|---------|------------------------------------------------------------------------------------------------------|--------------------------------------------------------|
| B1 | Unpinned offer defers the seller-side check | 144     | Pinning is what surfaces a seller-side defect before a buyer commits, rather than after they fund it | `test_UnpinnedOffer_DefersSellerSideCheckToAcceptance` |

All three halves run on one lot: refused at posting when pinned to Rule 144, accepted at posting when
unpinned, then refused at acceptance on the buyer's election.

### C. Fact-keys do not substitute across pathways

| #  | Case                                 | Pathway | Buyer holds                    | Stage | Fails on   | Covered by                                                          |
|----|--------------------------------------|---------|--------------------------------|:-----:|------------|---------------------------------------------------------------------|
| C1 | QIB is not accredited-by-implication | 4a7     | `K_QIB` but not `K_ACCREDITED` |  ACC  | accredited | `test_RevertIf_Section4a7_QibIsNotAccreditedByImplication`          |
| C2 | Accredited is not QIB                | 144A    | `K_ACCREDITED` only            |  ACC  | qib        | `test_RevertIf_UnpinnedOffer_BuyerElectsPathwayTheyDoNotQualifyFor` |

C2 is the same test as A6. Together the pair proves the badge asserts discrete facts rather than a status
ladder — neither credential implies the other.

### D. The SPV layer is pathway-independent

| #  | Case                                   | Pathway  | Defect injected               | Stage | Fails on    | Covered by                                       |
|----|----------------------------------------|----------|-------------------------------|:-----:|-------------|--------------------------------------------------|
| D1 | SPV-layer failure blocks every pathway | all five | buyer clearance never granted |  ACC  | eligibility | `test_RevertIf_SpvLayerFails_BlocksEveryPathway` |

Posts one seasoned lot per pathway and asserts the same uncleared buyer is refused on all five. Guards
against a future refactor that resolves the SPV layer per pathway instead of unconditionally.

### E. Lapse between acceptance and finalization

Finalize re-runs the threshold set, so a profile that was good at acceptance must still be good at
settlement. `DealManagerSecondaryTradeTest` proves the re-check happens with stubs; these prove a real
credential lapse trips it.

| #  | Case                                    | Pathway | Defect injected                        | Stage | Fails on    | Covered by                                             |
|----|-----------------------------------------|---------|----------------------------------------|:-----:|-------------|--------------------------------------------------------|
| E1 | Pathway credential expires pre-finalize | 144A    | warp past the QIB badge's `expiryDate` |  FIN  | qib         | `test_RevertIf_PathwayCredentialExpiresBeforeFinalize` |
| E2 | SPV clearance revoked pre-finalize      | 144     | `setClearance(buyer, false)` after ACC |  FIN  | eligibility | `test_RevertIf_SpvClearanceRevokedBeforeFinalize`      |

Both accept successfully first, so the only thing that changed by finalize is the lapse itself. E1 mints the
QIB credential with a 2-day expiry and warps 3 days — past the badge, past the 24h settlement delay, still
inside the 7-day settlement window.

### F. BUY side inverts the staging

On a buy offer the offeror is the buyer, so buyer-facing pathway conditions enforce at posting and a
pathway is mandatory there.

| #  | Case                              | Pathway | Stage | Expected                         | Covered by                                    |
|----|-----------------------------------|---------|:-----:|----------------------------------|-----------------------------------------------|
| F1 | Buy offer settles under a pathway | 144A    |   —   | full trade, `FINALIZED`          | `test_BuyOffer_Rule144A_Settles`              |
| F2 | Non-QIB cannot post a 144A bid    | 144A    | POST  | `SecondaryConditionsNotMet(qib)` | `test_RevertIf_BuyOffer_NonQibCannotPost144A` |

Buy-side mechanics that do not depend on real credentials — pathway required at `postOffer`, the
acceptor's election ignored, EIP-712 binding of the elected pathway — stay in
`DealManagerSecondaryTradeTest`.

### G. Decision-tree leaves — happy paths

The five happy paths above cover one leaf each of Diagrams 5a/5b. The diagrams assert more than that: a
buyer who fails one branch **falls through to another pathway that settles**. These four walk every
root-to-leaf path in both diagrams (P1–P11 in `cyberTRADE Exemption Pathways v4.1.md`), and every closed
pathway is asserted closed — refused at posting or acceptance, naming the condition — so no leg rests on
the settlement alone.

| #  | Test fn                                                | Paths | What it proves                                                                                                                                                                         |
|----|--------------------------------------------------------|-------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| G1 | `test_SeasonedLot_StaleInfo_ClosesRule144_ForkSettles` | P2–P5 | 5a "Current Public Info? → No": a stale 144(c)(2) package closes Rule 144 on a seasoned lot (`rule144Disclosure`), then the buyer-type fork settles under §4(a)(7), 144A and §4(a)(1½) |
| G2 | `test_UnseasonedLot_ClosesRule144_ForkSettles`         | P6–P9 | 5a "Holding Period Elapsed? → No": an unseasoned lot is refused Rule 144 (`holdingPeriod`) and the same fork settles under the other three                                             |
| G3 | `test_ToucheRemnant_UsBuyerConsumesAUsSeat`            | P11   | 5b right branch: under `usResidentOnlyCount` a U.S. buyer is refused at acceptance when the U.S. count is at cap (`holderCap`), and settles once a seat opens                          |
| G4 | `test_ToucheRemnant_NonUsBuyerSettlesAtUsCap`          | P10   | 5b left branch + Touche Remnant: at that same full cap a non-U.S. buyer settles, because they never increment the U.S.-resident count                                                  |

G1 and G2 are the same shape — close Rule 144 one of its two ways, then walk the fork: accredited (§4(a)(7)),
QIB (144A), sophisticated (§4(a)(1½)), then accredited again with the §4(a)(7) package aged out, which leaves
that buyer only §4(a)(1½). G3 and G4 are a pair — same SPV posture, same cap of 1, opposite outcomes turning
only on buyer residence.

## Fixture knobs

Every branch answer is set per test rather than baked into `setUp`, so a new scenario is a combination of
these rather than a new fixture.

| Helper                                                                   | Controls                                 |
|--------------------------------------------------------------------------|------------------------------------------|
| `_setRule144Info(bool)`                                                  | "Current Public Info Available?"         |
| `_setSection4a7Package(bool)`                                            | "SPV Has GAAP Financials for 2 Years?"   |
| `_mintSellerLot()` / `_mintSeasonedLots(n)`                              | "Holding Period Elapsed?" — No / Yes     |
| `_accreditedBuyer` / `_qibBuyer` / `_sophisticatedBuyer`                 | the "Buyer Type?" fork                   |
| `_mintCred(..., expiry)`                                                 | a credential that lapses mid-trade       |
| `_setClearance(account, bool)`                                           | the SPV layer's admin gate               |
| `_postBuyOffer` / `_acceptBuyOffer`                                      | buy side, where the offeror is the buyer |
| `_expectPostRefused` / `_expectAcceptRefused` / `_expectFinalizeRefused` | a refusal at one of the three stages     |

`false` on either package means aged past `DISCLOSURE_MAX_AGE`, not removed — the setter rejects a zero
`asOf`, and both conditions read an absent record and a stale one identically. Freshness is measured from the
call, so re-assert any package a test still needs after a warp that outruns the max age; `_mintSeasonedLots`
is exactly such a warp. A refused post reserves nothing, so a blocked attempt and the settlement that follows
can share one lot. The three `_expect*Refused` helpers all assert `SecondaryConditionsNotMet(<condition>)`,
which is what pins a check to its stage: the same condition failing at the wrong stage fails the test.

### Out of scope here

Pathway enablement toggles, condition-list config (zero address, duplicates, interface checks), event
emission, and withdrawal-mid-flight recovery are framework mechanics and live in
`DealManagerSecondaryTradeTest`. `CFIUSCondition` and `GPLPApprovalCondition` are implemented and
unit-tested but attached to no pathway here — they are optional per-SPV additions to the SPV layer.
