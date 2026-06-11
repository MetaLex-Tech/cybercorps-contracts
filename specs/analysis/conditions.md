# cyberTRADE — Conditions Reference

**Stage:** `threshold` = checked at `postOffer` and `acceptOffer`, gates contract formation · `closing` = checked at
`finalizeDeal` / `signAndFinalizeDeal`, gates asset transfer

**`data` encoding:** All threshold conditions receive `data = abi.encode(offerAgreementId)`. There is
no `partyAddr` in `data`. Each condition derives party addresses and all other context by calling
`IDealManager(_contract).getOffer(offerAgreementId)` — no `LexScroWLite` dependency. The `Parties`
column below is descriptive (what role the condition validates internally); it is not a DealManager
dispatch mechanism.

The `offerAgreementId` is a stable DealManager-internal key that is constant across all partial fills
of the same offer (one offer → many settlement agreements). Threshold conditions always refer to the
offer; closing conditions receive `abi.encode(settlementAgreementId)` and refer to the specific lot.

| Condition                              | Stage         | Parties            | Offer fields used                                                                                                              |
|----------------------------------------|---------------|--------------------|--------------------------------------------------------------------------------------------------------------------------------|
| `KYCAMLCondition`                      | threshold     | buyer + seller     | `offeror`, buyer via `settlementAgreementIds`                                                                                  |
| `AccreditedInvestorCondition`          | threshold     | buyer              | buyer via `settlementAgreementIds`                                                                                             |
| `QualifiedPurchaserCondition`          | threshold     | buyer + seller     | `offeror`, buyer via `settlementAgreementIds`                                                                                  |
| `QualifiedInstitutionalBuyerCondition` | threshold     | buyer              | buyer via `settlementAgreementIds`                                                                                             |
| `NonUSNationalityCondition`            | threshold     | buyer              | buyer via `settlementAgreementIds`                                                                                             |
| `USStateOfResidenceCondition`          | threshold     | buyer              | buyer via `settlementAgreementIds`, `spvAddress`                                                                               |
| `TaxInfoCondition`                     | threshold     | buyer + seller     | `offeror`, buyer via `settlementAgreementIds`                                                                                  |
| `LegionSoulboundCondition`             | threshold     | buyer + seller     | `offeror`, buyer via `settlementAgreementIds`                                                                                  |
| ~~`AgreementSignedCondition`~~         | ~~threshold~~ | ~~buyer + seller~~ | _(dropped — agreement creation is deferred to acceptOffer; signing IS acceptance, so checking "is it signed" is tautological)_ |
| `Section4a7DisclosureCondition`        | threshold     | buyer              | buyer via `settlementAgreementIds`, `spvAddress`                                                                               |
| `HoldingPeriodCondition`               | threshold     | seller             | `offeror`, `certPrinter`, `tokenId`                                                                                            |
| `Rule144DisclosureCondition`           | threshold     | —                  | `spvAddress`                                                                                                                   |
| `LegalOpinionCondition`                | threshold     | —                  | `spvAddress`                                                                                                                   |
| `RegSDistributionComplianceCondition`  | threshold     | buyer              | `counterparty`, `spvAddress`                                                                                                   |
| `HolderCapCondition` — §3(c)(1)        | threshold     | buyer              | `counterparty`, `spvAddress`                                                                                                   |
| `HolderCapCondition` — §3(c)(1)(C)     | threshold     | buyer              | `counterparty`, `spvAddress`                                                                                                   |
| `HolderCapCondition` — Touche Remnant  | threshold     | buyer              | `counterparty`, `spvAddress`                                                                                                   |
| `CFIUSCondition`                       | threshold     | buyer              | `counterparty`, `spvAddress`                                                                                                   |
| `GPLPApprovalCondition`                | threshold     | —                  | `spvAddress`                                                                                                                   |
| `GPConsentCondition`                   | threshold     | —                  | `spvAddress`                                                                                                                   |
| `QMSModeCondition`                     | threshold     | —                  | `spvAddress`                                                                                                                   |
| `ERISACondition`                       | threshold     | buyer              | buyer via `settlementAgreementIds`                                                                                             |
| `GlobalKillCondition`                  | closing       | —                  | _(no Offer lookup; checks kill-switch state)_                                                                                  |
| `TimeSettlementPeriodCondition`        | closing       | —                  | _(no Offer lookup; checks settlement timestamp)_                                                                               |

---

## Evaluation Rules

### Condition call protocol (threshold conditions)

DealManager calls each condition once:

```solidity
condition.checkCondition(address(this), msg.sig, abi.encode(offerAgreementId))
```

The condition decodes `offerAgreementId`, calls `IDealManager(_contract).getOffer(offerAgreementId)`,
and derives whatever it needs — `offeror`, `spvAddress`, `certPrinter`, `tokenId` — from the returned
`Offer` struct. There is no per-party dispatch loop in DealManager; the condition owns all
party-resolution logic internally.

**Resolving the buyer address:** `Offer` has no `counterparty` field — one offer can have many
acceptors (partial fills). Buyer-facing conditions instead check `offer.settlementAgreementIds`:

- `length == 0` → posting context, no buyer yet → short-circuit to `true`
- `length > 0` → acceptance context →
  `buyer = IDealManager(_contract).getEscrowDetails(offer.settlementAgreementIds[offer.settlementAgreementIds.length - 1]).counterParty`

### Two-array lifecycle

DealManager maintains two separate condition arrays per deal:

| Array                         | Evaluated at              | Entry points                          |
|-------------------------------|---------------------------|---------------------------------------|
| `thresholdConditionsByEscrow` | Offer posted and accepted | `postOffer`, `acceptOffer`            |
| `conditionsByEscrow`          | Finalization              | `finalizeDeal`, `signAndFinalizeDeal` |

Every condition in the array is walked in sequence at each entry point. Any failure reverts immediately.

### Within threshold: posting vs. acceptance

DealManager calls `checkCondition` identically at `postOffer` and `acceptOffer`. Whether a condition
enforces at posting depends on its internal logic and whether `offer.counterparty` is set:

| Parties        | At posting (`settlementAgreementIds.length == 0`)   | At acceptance      |
|----------------|-----------------------------------------------------|--------------------|
| buyer + seller | Seller-side enforces; buyer-side must return `true` | Both sides enforce |
| seller         | **Enforces** — `offer.offeror` is known             | Re-evaluated       |
| buyer          | **Must return `true`** — no buyer exists yet        | Enforces           |
| —              | Enforces                                            | Enforces           |

Buyer-facing conditions detect posting context by checking `offer.settlementAgreementIds.length == 0`
and short-circuit to `true`. DealManager calls every condition in the array at every evaluation
point without filtering.

## DealManager Configuration

### Two condition sets (§4.1.5)

DealManager holds two distinct condition sets, scoped differently:

| Set                                                     | Scope                        | Attached to escrow?          | Default contents                                       |
|---------------------------------------------------------|------------------------------|------------------------------|--------------------------------------------------------|
| Closing-condition set (`conditionsByEscrow`)            | Every secondary-trade escrow | Yes — attached at acceptance | `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| Threshold-condition set (`thresholdConditionsByEscrow`) | DealManager (not the escrow) | No                           | See below                                              |

The closing-condition set is attached to the escrow object at acceptance and is evaluated at finalization. Threshold
conditions gate the escrow's creation — they are not part of the escrow record and are evaluated by DealManager at
`postOffer` and `acceptOffer`.

### Default closing set

Every DealManager gets `GlobalKillCondition` and `TimeSettlementPeriodCondition` as closing conditions:

| Condition                       | Deployment                                                                      | Admin                                                                                                       |
|---------------------------------|---------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| `GlobalKillCondition`           | Deployed once at protocol initialization; shared across all Legion DealManagers | MetaLeX + Legion each hold one admin key; either can raise unilaterally; both required to lower             |
| `TimeSettlementPeriodCondition` | Deployed once; configured per-DealManager                                       | Default delay: 24h from acceptance; reparameterized to 45-day gate from listing timestamp for QMS-mode SPVs |

### Threshold set: three layers

The threshold-condition set combines three layers, scoped to different points in the deployment lifecycle:

| Layer            | Where configured                  | When                                                                                                          | Conditions                                                                                                                                                                                                                                                  |
|------------------|-----------------------------------|---------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| L1 — Universal   | `DealManagerFactory`              | Protocol initialization; injected into every DealManager at deployment                                        | `KYCAMLCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `ERISACondition`, `USStateOfResidenceCondition`                                                                                                                                          |
| L2 — Per-SPV     | Individual `DealManager`          | SPV onboarding; added after factory deployment                                                                | `HolderCapCondition`, `QualifiedPurchaserCondition`, `CFIUSCondition`, `LegionSoulboundCondition`, `GPLPApprovalCondition`, `QMSModeCondition`                                                                                                              |
| L3 — Per-pathway | Individual `DealManager` registry | Protocol initialization (addresses registered); selected per-offer at `postOffer` based on `exemptionPathway` | `HoldingPeriodCondition`, `Rule144DisclosureCondition`, `AccreditedInvestorCondition`, `Section4a7DisclosureCondition`, `LegalOpinionCondition`, `QualifiedInstitutionalBuyerCondition`, `NonUSNationalityCondition`, `RegSDistributionComplianceCondition` |

#### L1 — Universal (`DealManagerFactory`)

The factory injects these into every DealManager it deploys. Same instances shared across all SPVs; no per-SPV
parameterization.

| Condition                      | Notes                                                                                                                                                                                               |
|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `KYCAMLCondition`              | All paths                                                                                                                                                                                           |
| `TaxInfoCondition`             | All paths; blocks acceptance until W-9/W-8BEN recorded in LeXcheX                                                                                                                                   |
| ~~`AgreementSignedCondition`~~ | ~~All paths~~ — dropped; see table above                                                                                                                                                            |
| `ERISACondition`               | All U.S. pathways; silent for Reg S non-U.S. buyers                                                                                                                                                 |
| `USStateOfResidenceCondition`  | Issuer-configurable blocked-states list; **New York is on the default blocked-states list** for every SPV that has not registered under NY Martin Act Article 23-A, regardless of exemption pathway |

#### L2 — Per-SPV (individual `DealManager`, configured at SPV onboarding)

Added to the individual DealManager after factory deployment, during SPV onboarding. Only conditions applicable to the
SPV are added.

| Condition                     | When present                                                    | Parameterization                                                                                                                             |
|-------------------------------|-----------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `HolderCapCondition`          | All SPVs                                                        | ICA exception (`§3(c)(1)`, `§3(c)(1)(C)`, or `§3(c)(7)`); SPV domicile (for Touche Remnant U.S.-resident-only count); cap (100 / 250 / none) |
| `QualifiedPurchaserCondition` | §3(c)(7) funds only                                             | Parameterizes `LexChexCondition` for QP `investorType`                                                                                       |
| `CFIUSCondition`              | SPVs that do not satisfy the FIRRMA §800.307 fund exception     | SPV CFIUS sensitivity flag; blocked jurisdictions                                                                                            |
| `LegionSoulboundCondition`    | Optional; GP-configurable                                       | Soulbound credential category/tier required of buyer (and optionally seller)                                                                 |
| `GPLPApprovalCondition`       | Optional; only if governing documents require per-deal approval | Authorized approver address (GP, managing member, or delegated compliance officer)                                                           |
| `QMSModeCondition`            | Optional; per-SPV opt-in for §1.7704-1(g) QMS safe harbor       | Frequency cap value (counsel-determined per SPV); listing timestamp stored at `postOffer`                                                    |

#### L3 — Per-pathway (individual `DealManager`, selected at `postOffer`)

Condition contract addresses are registered in the DealManager (or a shared registry) at protocol initialization. At
`postOffer`, DealManager reads the offer's `exemptionPathway` field and appends the corresponding subset to the
threshold-condition array for that offer's `agreementId`. The same condition instances are shared across all SPVs.

| Condition                              | Rule 144 | §4(a)(7) | §4(a)(1½) | Rule 144A | Reg S |
|----------------------------------------|:--------:|:--------:|:---------:|:---------:|:-----:|
| `HoldingPeriodCondition`               |    ✓     |    —     |     —     |     —     |   —   |
| `Rule144DisclosureCondition`           |    ✓     |    —     |     —     |     —     |   —   |
| `AccreditedInvestorCondition`          |    —     |    ✓     | optional  |     —     |   —   |
| `Section4a7DisclosureCondition`        |    —     |    ✓     |     —     |     —     |   —   |
| `LegalOpinionCondition`                |    —     |    —     |     ✓     |     —     |   —   |
| `QualifiedInstitutionalBuyerCondition` |    —     |    —     |     —     |     ✓     |   —   |
| `NonUSNationalityCondition`            |    —     |    —     |     —     |     —     |   ✓   |
| `RegSDistributionComplianceCondition`  |    —     |    —     |     —     |     —     |   ✓   |

### Deployment responsibility

| Scope                                                             | Who                                     | When                                                                     |
|-------------------------------------------------------------------|-----------------------------------------|--------------------------------------------------------------------------|
| L1 conditions + L3 condition addresses                            | MetaLeX                                 | Protocol initialization                                                  |
| `GlobalKillCondition` + `TimeSettlementPeriodCondition` (closing) | MetaLeX                                 | Protocol initialization; MetaLeX + Legion admin roles assigned at deploy |
| L2 conditions                                                     | MetaLeX or Legion via factory contracts | SPV onboarding                                                           |
