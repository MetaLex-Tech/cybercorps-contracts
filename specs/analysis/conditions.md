# cyberTRADE — Conditions Reference

**Stage:** `threshold` = checked at `postOffer` and `acceptOffer` (gates contract formation) and re-checked at
finalization (gates asset transfer) · `closing` = checked at finalization only, gates asset transfer

**`data` encoding:** All threshold conditions receive `data = abi.encode(offerAgreementId)`. There is
no `partyAddr` in `data`. Each condition derives party addresses and all other context by calling
`IDealManager(_contract).getOffer(offerAgreementId)` — no `LexScroWLite` dependency. The `Parties`
column below is descriptive (what role the condition validates internally); it is not a DealManager
dispatch mechanism.

The `offerAgreementId` is a stable DealManager-internal key that is constant across all partial fills
of the same offer (one offer → many settlement agreements). Threshold conditions always refer to the
offer; closing conditions receive `abi.encode(settlementAgreementId)` and refer to the specific lot.

One row per condition contract; the spec names that are parameterizations of one contract are listed
under it. Every condition is a shared singleton — see `Config scope` for what each keys its settings by.

| Condition                             | Stage     | Parties          | Deployment scope                 | Upgradeable | Badge             | Admin scope       | Config scope            | Offer fields used                                                         |
|---------------------------------------|-----------|------------------|----------------------------------|-------------|-------------------|-------------------|-------------------------|---------------------------------------------------------------------------|
| `EligibilityCondition`                | threshold | buyer + seller   | shared                           | UUPS        | —                 | SPV               | per-SPV, per-party      | `offeror`, buyer via `settlementAgreementIds`                             |
| `LexChexBadgeKindCondition`           | threshold | buyer (+ seller) | shared, one per parameterization | UUPS        | default + per-SPV | platform          | global                  | `offeror`, buyer via `settlementAgreementIds`, `spvAddress` (scoped keys) |
| `USStateOfResidenceCondition`         | threshold | buyer            | shared                           | UUPS        | default + per-SPV | SPV + platform    | per-SPV                 | buyer via `settlementAgreementIds`, `spvAddress`                          |
| `LegionSoulboundCondition`            | threshold | buyer + seller   | shared                           | UUPS        | default + per-SPV | SPV + platform    | per-SPV                 | `offeror`, buyer via `settlementAgreementIds`, `spvAddress`               |
| `HolderCapCondition`                  | threshold | buyer            | shared                           | UUPS        | printer           | SPV               | per-SPV                 | `counterparty`, `spvAddress`, `certPrinter`                               |
| `CFIUSCondition`                      | threshold | buyer            | shared                           | UUPS        | default + per-SPV | SPV + platform    | per-SPV                 | `counterparty`, `spvAddress`                                              |
| `Section4a7DisclosureCondition`       | threshold | buyer            | shared                           | UUPS        | —                 | SPV + platform    | per-SPV + global        | buyer via `settlementAgreementIds`, `spvAddress`                          |
| `Rule144DisclosureCondition`          | threshold | —                | shared                           | UUPS        | —                 | SPV + platform    | per-SPV + global        | `spvAddress`                                                              |
| `HoldingPeriodCondition`              | threshold | seller           | shared                           | UUPS        | —                 | platform          | global                  | `offeror`, `certPrinter`, `tokenId`                                       |
| `LegalOpinionCondition`               | threshold | —                | shared                           | UUPS        | —                 | SPV + DealManager | per-SPV + per-DM        | `spvAddress`, DealManager address                                         |
| `RegSDistributionComplianceCondition` | threshold | buyer            | shared                           | UUPS        | —                 | SPV               | per-SPV                 | `counterparty`, `spvAddress`, `certPrinter`                               |
| `GPLPApprovalCondition`               | threshold | —                | shared                           | UUPS        | —                 | DealManager owner | per-DM                  | `spvAddress`, DealManager address                                         |
| `GPConsentCondition`                  | threshold | —                | _not implemented_                | —           | —                 | —                 | —                       | `spvAddress`                                                              |
| `QMSModeCondition`                    | threshold | —                | _not implemented_                | —           | —                 | —                 | —                       | `spvAddress`                                                              |
| `KillSwitchCondition`                 | closing   | —                | shared                           | **no**      | —                 | two fixed keys    | global + per-settlement | _(no Offer lookup; checks kill-switch state)_                             |
| `TimeSettlementPeriodCondition`       | closing   | —                | shared                           | **no**      | —                 | DealManager owner | per-DM                  | _(no Offer lookup; checks settlement timestamp)_                          |

`LexChexBadgeKindCondition` is deployed once per parameterization and shared across all SPVs:
`AccreditedInvestorCondition` (`K_ACCREDITED`, buyer), `QualifiedPurchaserCondition` (`K_QP`, buyer +
seller), `QualifiedInstitutionalBuyerCondition` (`K_QIB`, buyer), `NonUSNationalityCondition`
(`K_NON_US`, buyer), plus the SPV-scoped entitlements (`K_SPV_WHITELIST`, `K_SYNDICATE`).
`HolderCapCondition` covers §3(c)(1), §3(c)(1)(C) and Touche Remnant through its per-SPV config.

**Badge** — `printer` = read from `offer.certPrinter.lookThroughBadge()`, which is the only registry that
can be weighed against the printer's own holder tally. `default + per-SPV` = a platform-set `defaultBadge`
(non-zero at `initialize`) with an optional per-SPV override, both admin-set; the SPV cannot pick the
registry that judges its own parties. Every other condition reads no credential at all.

**Admin scope** — `platform` = `onlyAdmin` on the shared BorgAuth; `SPV` = `_requireAuthAdmin(offer.spvAddress)`;
`DealManager` = gated on that DealManager's own BorgAuth.

### Unconfigured SPVs

For most conditions, attaching one to an SPV is itself the statement that it applies there, so silence is
never a finding. `USStateOfResidenceCondition` is the exception:

| Condition                     | unconfigured | what is missing                                                                                         |
|-------------------------------|--------------|---------------------------------------------------------------------------------------------------------|
| `CFIUSCondition`              | **blocks**   | no TID U.S. business determination; a recorded `tidUsBusiness = false` is the fund exception and passes |
| `HolderCapCondition`          | **blocks**   | no ICA exception named — `cap == 0` is a real §3(c)(7) setting, so a `configured` flag keeps it apart   |
| `RegSDistributionCompliance`  | **blocks**   | no issuer category or compliance period — same `configured` flag                                        |
| `LegionSoulboundCondition`    | **blocks**   | no circle named                                                                                         |
| `EligibilityCondition`        | **blocks**   | that SPV has cleared nobody                                                                             |
| `Rule144` / `Section4a7`      | **blocks**   | no disclosure package on record                                                                         |
| `USStateOfResidenceCondition` | **passes**   | nothing — it is a deny-list, so an empty one permits (NY still blocks by the Martin Act default)        |

The deny-list is why it has no `configured` flag: an SPV that blocks only NY and one whose GP never
touched it write identical state, so the flag would have nothing to key off. The screen still enforces
its own reads — an acquirer with no recorded jurisdiction, or a U.S. one carrying no state, is refused.
Deliberate: naming every state the SPV must avoid is the GP's call, not something the platform can default.

Globally configured conditions follow the same rule as the per-SPV ones: `HoldingPeriodCondition` blocks
when its period reads 0, since Rule 144 has no zero hold and both setters reject one.

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

Both sets are owner-managed DealManager config (never offeror-supplied). Each stage resolves the set from
live config, so a trade is judged by the SPV's rules as they stand at that moment.

| Set                                          | Resolved from                                                     | Evaluated at                                                  |
|----------------------------------------------|-------------------------------------------------------------------|---------------------------------------------------------------|
| Threshold (§6 fund-specific ++ §5 exemption) | `spvThresholdConditions` ++ `pathwayThresholdConditions[pathway]` | `postOffer`, `acceptOffer`, `finalizeSecondaryTradeAgreement` |
| Closing                                      | `closingConditions`                                               | `finalizeSecondaryTradeAgreement`                             |

At `postOffer` the pathway is the offeror's pin (`NONE` on an unpinned sell offer resolves the §6 layer
alone); from `acceptOffer` onward it is the buyer's election, recorded per lot on
`SecondaryEscrow.exemptionPathway`.

Every condition in the set is walked in sequence at each entry point. Any failure reverts immediately.
Live resolution also means a pathway withdrawn or a condition added after posting takes effect on the next
stage, and re-running the threshold set at finalize means eligibility lost after acceptance (revoked
credential, breached holder cap, blocked-state move, withdrawn approval) blocks the asset transfer.

An SPV trades only under exemptions it currently supports, so pathway enablement is gated at all three
stages alongside the set. Withdrawing one stops settlements already accepted under it; those lots unwind
through the void/expiry path.

Off-chain reconstruction works two ways, which must agree:

- `SecondaryTradeAgreementFinalized` carries the threshold and closing sets the settlement was judged
  against, read directly — no replay, no knowledge of how the layers compose.
- The config setters emit `SpvThresholdConditionsSet` / `PathwayThresholdConditionsSet` /
  `ClosingConditionsSet`, each carrying the whole replacement list. Replaying those against a settlement's
  elected pathway covers the stages the finalize event does not: posting and acceptance.

Replay carries assumptions the logs do not state, so an indexer relying on it must: compose the threshold
set as SPV layer ++ pathway layer in that order (`NONE` omits the pathway layer); order events by
`(blockNumber, logIndex)`, since a config change and a finalize can share a block; partition config by
`log.emitter`, as each DealManager has its own; and bootstrap from the getters at a pinned block, because
an absent `PathwayThresholdConditionsSet` is indistinguishable from one emitted before the start block
(and `pathwayEnabled` defaults to false).

Either route reports which conditions were *consulted*, not which ones bound: conditions that self-silence
(e.g. `ERISACondition` on Reg S) appear in the set having returned `true` unconditionally.

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

DealManager holds two distinct condition sets, both owner-managed and snapshotted onto the offer at `postOffer`:

| Set                     | Scope                         | Snapshotted onto offer? | Default contents                                       |
|-------------------------|-------------------------------|-------------------------|--------------------------------------------------------|
| Closing-condition set   | Every offer                   | Yes — at `postOffer`    | `KillSwitchCondition`, `TimeSettlementPeriodCondition` |
| Threshold-condition set | Every offer (two §7.2 layers) | Yes — at `postOffer`    | See below                                              |

The closing-condition set is copied onto the offer at `postOffer` and evaluated at finalization (gating asset
transfer). The threshold-condition set is resolved (fund-specific (§6) ++ exemption-specific (§5)) and copied onto the
offer at `postOffer`, then evaluated at `postOffer` and re-evaluated at `acceptOffer` (gating contract formation)
and again at finalization (gating asset transfer). Offerors supply only the exemption pathway, never condition
addresses.

### Default closing set

Every DealManager gets `KillSwitchCondition` and `TimeSettlementPeriodCondition` as closing conditions:

| Condition                       | Deployment                                                                      | Admin                                                                                                                                                                                 |
|---------------------------------|---------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `KillSwitchCondition`           | Deployed once at protocol initialization; shared across all Legion DealManagers | MetaLeX + Legion each hold one admin key; either can raise unilaterally; both required to lower. Two scopes: platform-wide, and per-settlement (blocks a single agreement's finalize) |
| `TimeSettlementPeriodCondition` | Deployed once; configured per-DealManager                                       | Default delay: 24h from acceptance; reparameterized to 45-day gate from listing timestamp for QMS-mode SPVs                                                                           |

### Threshold set: two layers (§7.2)

The threshold-condition set combines two layers per v3.53 §7.2. At `postOffer` they are resolved in the
order fund-specific (Layer 2) ++ exemption-specific (Layer 1) and snapshotted onto the offer:

| Layer                             | Where configured                  | When                                                                                                          | Conditions                                                                                                                                                                                                                                                  |
|-----------------------------------|-----------------------------------|---------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Layer 2 — Fund-specific (§6)      | Individual `DealManager`          | SPV onboarding; applies to every offer for the SPV                                                            | `EligibilityCondition`, `USStateOfResidenceCondition`, `HolderCapCondition`, `QualifiedPurchaserCondition`, `CFIUSCondition`, `LegionSoulboundCondition`, `GPLPApprovalCondition`, `QMSModeCondition`                                                       |
| Layer 1 — Exemption-specific (§5) | Individual `DealManager` registry | Protocol initialization (addresses registered); selected per-offer at `postOffer` based on `exemptionPathway` | `HoldingPeriodCondition`, `Rule144DisclosureCondition`, `AccreditedInvestorCondition`, `Section4a7DisclosureCondition`, `LegalOpinionCondition`, `QualifiedInstitutionalBuyerCondition`, `NonUSNationalityCondition`, `RegSDistributionComplianceCondition` |

#### Layer 2 — Fund-specific (§6) (individual `DealManager`, configured at SPV onboarding)

Added to the individual DealManager during SPV onboarding and applied to every offer for that SPV. Only conditions
applicable to the SPV are added. §7.2 classifies the baseline buyer-credential gates (the first two below) as
fund-specific, so each SPV must register them explicitly — there is no platform-wide tier that injects them
automatically.

| Condition                     | When present                                                                | Parameterization                                                                                                                                                                                    |
|-------------------------------|-----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `EligibilityCondition`        | All SPVs / all paths; admin-cleared flag per party (KYC/AML, tax, ERISA, …) | None                                                                                                                                                                                                |
| `USStateOfResidenceCondition` | All SPVs                                                                    | Issuer-configurable blocked-states list; **New York is on the default blocked-states list** for every SPV that has not registered under NY Martin Act Article 23-A, regardless of exemption pathway |
| `HolderCapCondition`          | All SPVs                                                                    | ICA exception (`§3(c)(1)`, `§3(c)(1)(C)`, or `§3(c)(7)`); SPV domicile (for Touche Remnant U.S.-resident-only count); cap (100 / 250 / none)                                                        |
| `QualifiedPurchaserCondition` | §3(c)(7) funds only                                                         | Parameterizes `LexChexBadgeKindCondition` with `kindKey = K_QP`, buyer + seller                                                                                                                     |
| `CFIUSCondition`              | SPVs that do not satisfy the FIRRMA §800.307 fund exception                 | SPV CFIUS sensitivity flag; blocked jurisdictions                                                                                                                                                   |
| `LegionSoulboundCondition`    | Optional; GP-configurable                                                   | Soulbound credential category/tier required of buyer (and optionally seller)                                                                                                                        |
| `GPLPApprovalCondition`       | Optional; only if governing documents require per-deal approval             | Authorized approver address (GP, managing member, or delegated compliance officer)                                                                                                                  |
| `QMSModeCondition`            | Optional; per-SPV opt-in for §1.7704-1(g) QMS safe harbor                   | Frequency cap value (counsel-determined per SPV); listing timestamp stored at `postOffer`                                                                                                           |

> Note: `AgreementSignedCondition` was previously listed in this baseline set but has been dropped.

#### Layer 1 — Exemption-specific (§5) (individual `DealManager`, selected at `postOffer`)

Condition contract addresses are registered in the DealManager (or a shared registry) at protocol initialization. At
`postOffer`, DealManager reads the offer's `expectedExemptionPathway` field and appends the corresponding subset to the
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

| Scope                                                             | Who     | When                                                                                 |
|-------------------------------------------------------------------|---------|--------------------------------------------------------------------------------------|
| Layer 1 (exemption-specific) condition addresses                  | MetaLeX | Protocol initialization                                                              |
| `KillSwitchCondition` + `TimeSettlementPeriodCondition` (closing) | MetaLeX | Protocol initialization; MetaLeX + Legion admin roles assigned at deploy             |
| Layer 2 (fund-specific) conditions                                | MetaLeX | Protocol initialization; MetaLeX or Legion configures each SPV's entry at onboarding |
