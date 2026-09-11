---
description: Condition contracts that gate state transitions, including the secondary-trading family
---

# Conditions

A **condition** is a contract that gates state transitions — issuance,
scripification, de-scripification, deal close, round acceptance, secondary
settlement — on arbitrary onchain checks. Two interfaces exist:

* the generic [`ICondition`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICondition.sol)
  (opaque `bytes` payload), and
* the strongly-typed `ISecondaryTradingCondition`
  (`src/libs/conditions/BaseSecondaryTradingCondition.sol`) used on the
  secondary-trading path.

## The `ICondition` interface

```solidity
interface ICondition {
    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool);
}
```

`checkCondition` is given the calling contract, the function selector being
gated, and ABI-encoded context, and returns whether the action may proceed.
Where the protocol accepts conditions — e.g. `IssuanceManager.deployCyberScrip`
(`certToScripConditions`, `scripToCertConditions`),
`DealManager.proposeDeal` (`conditions`), `RoundManager.submitEOI`
(`conditions`) — they are passed as `address[]` / `ICondition[]`.

## Built-in `ICondition` contracts

In [`src/libs/conditions/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/libs/conditions),
all extending the abstract `BaseCondition` (which adds ERC-165 support):

| Condition | Purpose |
|---|---|
| **LexChexCondition** | Requires a valid LeXcheX credential — wraps `ILexChex.hasValidLexCheX`. See [LexChex](contracts/LexChex.md). |
| **NonUSNationalityCondition** | A zkPassport-backed check that the address is held by a non-US person (Regulation S). UUPS-upgradeable; caches proof expiry per address and supports per-manager founder overrides. See `IZKPassportVerifier`. |
| **IssuerApprovalRecertificationCondition** | Requires explicit issuer approval before a non-registered scrip holder can de-scripify into a fresh cyberCERT. |
| **OrCondition** | Composes child conditions with disjunctive (OR) logic. |

## Secondary-trading conditions

Secondary trades through the `DealManager` (`postOffer` / `acceptOffer` /
`finalizeSecondaryTradeAgreement`) use a typed variant instead of the opaque
`bytes` payload:

```solidity
interface ISecondaryTradingCondition is IERC165 {
    function checkCondition(
        IDealManager dealManager,
        bytes4 functionSignature,
        bytes32 offerId,
        bytes32 agreementId
    ) external view returns (bool);
}
```

Implementations resolve offer/escrow state through `IDealManager.getOffer` /
`getSecondaryEscrow` with compile-time-checked arguments. Conditions are
validated via ERC-165 when configured, and attached on the `DealManager` in
three sets:

* **SPV threshold conditions** — `setSpvThresholdConditions(conditions)`,
  the fund-specific layer applied to every trade.
* **Pathway threshold conditions** —
  `setPathwayThresholdConditions(pathway, conditions, enabled)`, keyed by
  the trade's elected **exemption pathway**:

  ```solidity
  enum ExemptionPathway { NONE, RULE_144, SECTION_4A7, SECTION_4A1HALF, RULE_144A, REGULATION_S }
  ```

  A buy offer pins its pathway at `postOffer`; on a sell offer each buyer
  elects a pathway at acceptance (bounded by any pin the seller set).
  Threshold conditions are re-checked once a settlement exists and at
  finalization.
* **Closing conditions** — `setClosingConditions(conditions)`, evaluated at
  finalization for every trade regardless of pathway.

All three setters are `onlyAdmin` on the SPV's own BorgAuth.

### Built-in secondary conditions

In [`src/libs/conditions/secondary/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/libs/conditions/secondary),
extending `SecondaryTradingConditionBase`. Most are shared singletons
configured per SPV (cyberCORP), with configuration gated by that SPV's own
BorgAuth admin:

| Condition | Purpose |
|---|---|
| **EligibilityCondition** | Both parties must be admin-cleared to trade; catch-all backing offchain eligibility checks (replaced the former KYCAML / TaxInfo / ERISA conditions). |
| **HoldingPeriodCondition** | Rule 144 holding-period verification. Anchors on the printer's base `acquisitionTimestamp(tokenId)` (no record = fail closed — backfill imported certs), extended earlier only by the fund-interest extension's `tackedFromAcquisitionDate` when 144(d)(3) tacking is asserted. |
| **Rule144DisclosureCondition** | Rule 144(c)(2) current-public-information gate with a freshness policy. |
| **Section4a7DisclosureCondition** | §4(a)(7) information-delivery gate. |
| **LegalOpinionCondition** | §4(a)(1½) GP / issuer-counsel assurance gate. |
| **RegSDistributionComplianceCondition** | Regulation S distribution compliance period, per issuer category. |
| **HolderCapCondition** | ICA §3(c)(1) / §3(c)(1)(C) / §3(c)(7) holder limits, counted at acceptance/finalization. |
| **CFIUSCondition** | FIRRMA gating for CFIUS-sensitive SPVs, including a blocked-jurisdictions / blocked-affiliation list with reach over foreign control. |
| **USStateOfResidenceCondition** | Blue-sky state gating for U.S. acceptors (blocked-states list; unregistered SPVs block NY by default). |
| **LexChexBadgeKindCondition** | Parameterizable investor-status gate on the LeXcheXBadge layer — the secondary-trading successor of `LexChexCondition`. Enforces status fact-keys (which follow the party anywhere) or exactly one per-SPV entitlement (which only counts for the offer's SPV). `updateIssuers` optionally restricts whose credentials count (empty accepts any issuer) — name the operator when gating on `K_SYNDICATE`, since a shared badge lets other issuers grant seats in the same SPV. |
| **LegionSoulboundCondition** | Issuer circle gate: a seat *plus* a minimum rank ("MEMBER or better", not just "in the circle"). A qualifying credential carries `K_SYNDICATE` scoped to the SPV and its rank in `K_DATA`, on one record; the gate resolves the holder's *most recent* valid seat via `getMostRecentValidWith`, so a newer seat demotes an older one even if never voided. Per-SPV `setConfig(spv, minTier, applyToSeller)` (by the SPV's BorgAuth admin); platform-level `updateIssuers` names whose seats count. For membership alone, set the lowest rung. |
| **GPLPApprovalCondition** | Per-deal GP/LP manual approval gate. |
| **KillSwitchCondition** | Finalization kill switch held jointly by two independent admins (closing condition). |
| **TimeSettlementPeriodCondition** | Minimum delay between acceptance and finalization (default 24 h, per-DealManager overrides). A closing condition an admin must opt into via `setClosingConditions` — nothing installs it by default. |

The credential-reading conditions inherit `BadgeScopedCondition`, which
selects which credential registry judges an SPV's parties (a platform
default plus per-SPV overrides). Shared jurisdiction-classification logic
lives in `src/libs/policies/` (`USJurisdictionPolicy`,
`LookThroughPolicy` — the ICA §3(c)(1)(A) U.S.-investor look-through).

## Custom conditions

Any contract implementing the relevant interface works. Because
`checkCondition` receives the calling contract, the selector, and context, a
condition can encode any onchain check — a token balance, a credential, an
oracle reading, a governance outcome — and be attached wherever the protocol
accepts a condition list. Secondary-trading conditions must advertise
`ISecondaryTradingCondition` via ERC-165 to be accepted at configuration
time.

> This page describes the interfaces precisely; verify each built-in
> condition's constructor, configuration functions, and behaviour against
> its source.
