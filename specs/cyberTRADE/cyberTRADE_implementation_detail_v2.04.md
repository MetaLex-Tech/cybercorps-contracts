# cyberTRADE v2.04 — Implementation Detail Companion

**Companion to:** `cyberTRADE_spec_v2.04.md` (Product Specification for Legion's Operation of cyberTRADE)
**Scope:** This document does not replace or amend the legal/product spec. It adds concrete protocol and application‑layer detail derived from the current state of `metalex-tech/cybercorps-contracts` and `metalex-tech/metalex-webapp`, with attention to (a) how the existing primary‑issuance plumbing in `cyberRAISE` and the bilateral‑settlement plumbing in `CyTE / LeXscroW` can be specialized into cyberTRADE's lifecycle, and (b) how individual securities are implemented as **extension contracts**, which is the cleanest unit of reuse for the new `FundInterestExtension`.

The document is written "in furtherance and not in limitation of" the v2.04 spec — it fills in mechanics, names files, identifies real (not theoretical) discrepancies between the spec and the codebase, and proposes the smallest set of additive changes that can support the secondary‑trade flow without re‑architecting cyberCORPs.

---

## 0. Reading Map

| Spec section | Mapped to in this document |
|---|---|
| §2 Protocol & UCC Framing (custody paths) | §6 Custody election under existing CertPrinter |
| §4.1.2 cyberCORP deploy / §4.1.5 DealManager deploy | §3 DealManager secondary‑trade mode, §4 OfferRegistry |
| §4.1.4 Condition contracts / §7.2 Compliance verification | §5 Conditions: existing `ICondition`, GlobalKill, TimeSettlement |
| §4.2 Phase 2: Primary issuance | §2 RoundManager parallel — what cyberRAISE already does |
| §7.3 Agreement execution | §7 CyberAgreementRegistry templates for secondary |
| §7.4 / §7.4A Escrow & settlement pathways | §3, §8 Mapped to LexScroWLite |
| §7.5 Ledger mutation | §6, §8 CertPrinter `_update`, endorsements, `safeMintAndAssign` |
| §7.6 FIX receipt | §9 Where to emit, what to stamp |
| §8 Application Layer | §10 Webapp: offer builder, discovery, acceptance, settlement |
| §10.5 Indexer | §11 Ponder additions |
| §12 / §12B Protocol upgrades | §3–§9 throughout |
| §13 Scrip token layer (future) | §12 Out of scope flag |

---

## 1. Individual Securities as Extension Contracts (the centerpiece)

The cyberCORPs codebase represents an individual security **not as a separate ERC‑721**, but as the combination of (a) the per‑token `CertificateDetails` struct on `CyberCertPrinter` and (b) a contract implementing `ICertificateExtension` that **decodes the `extensionData` bytes blob** for that printer's tokens. One printer ⇒ one security class ⇒ one extension binding. cyberTRADE inherits this pattern directly; the only required addition is a new `FundInterestExtension` that mirrors `ShareExtension` for the fund‑interest case.

### 1.1 Interface (verified)

`src/storage/extensions/ICertificateExtension.sol`:

```solidity
interface ICertificateExtension {
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool);
    function getExtensionURI(bytes memory data) external view returns (string memory);
}
```

The interface is intentionally minimal:

- It is **read‑only metadata**. It does not gate transfers, it does not produce reps and warranties, it does not enforce restrictions. Those concerns live elsewhere (restriction hooks on `_update`, `ICondition` on `DealManager`, `certLegend` on the cert).
- `extensionData` is a `bytes` field on `CertificateDetails`. The extension contract decodes that blob — the printer never sees the schema.
- `tokenURI` on `CyberCertPrinter` delegates to `ICertificateExtension(extension).getExtensionURI(data)` to produce the per‑token JSON.

This separation is why a new security class can be added without touching the printer or the printer storage layout.

### 1.2 The existing extension family

`src/storage/extensions/`:

| Extension | Security represented | Encoding helper used in webapp |
|---|---|---|
| `ShareExtension` | Corporate equity (Common / Preferred, with full Series‑A‑style preference stack) | encoded inline in `getExtensionData()` |
| `SAFEExtension` | Simple Agreement for Future Equity | `safeExtensionAbi` |
| `SAFTExtension`, `SAFTExtensionV2` | Simple Agreement for Future Tokens | `saftExtensionAbi` |
| `SAFTEExtension`, `SAFTEExtensionV2` | SAFE‑for‑Tokens hybrid | `safteExtensionAbi` |
| `TokenWarrantExtension`, `TokenWarrantExtensionV2` | Token warrants | `tokenWarrantExtensionAbi` |
| `ACESAFEExtension` | ACE‑denominated SAFE (the pumpDenominationToken variant) | `encodeAceSafeExtensionData()` |

The V2 extensions exist because the **schema is the contract**: a struct change inside the extension would change the ABI of every cert printer bound to it. Versioning is by deploying a new extension contract and binding new printers to it. Existing printers continue to read the old extension. This is the upgrade discipline cyberTRADE must respect for any future revision of `FundInterestExtension`.

### 1.3 `ShareExtension` — the template to clone

`src/storage/extensions/ShareExtension.sol` carries (verbatim from current source):

- `ShareClass` (Common | Preferred)
- `seriesName`, `parValue`, `originalIssuePrice`
- `liquidationPreferenceMultiple`, `liquidationPreferenceType`, `participationCap`
- `DividendType`, `dividendRateOrPriority`
- `isConvertible`, `conversionPrice`, `AntiDilutionType`
- `votesPerShare`, `hasClassVotingRights`, `designatedBoardSeats`
- `TransferRestrictionType` (None | BoardConsentRequired | ROFRAndCoSale | Rule144Eligible | CustomRestriction)
- `isRedeemable`, `redemptionPrice`
- `hasProtectiveProvisions`, `protectiveProvisionThreshold`
- `authorizedShares`

Critical observation: `TransferRestrictionType` is **metadata only**. It is not consumed by `CyberCertPrinter._update`. The transfer gate is the `globalRestrictionHook` (and, once §3.5 below is enabled, `restrictionHooksById`). The extension is descriptive; enforcement is at the hook layer. cyberTRADE inherits this separation: `FundInterestExtension.transferRestrictionType` is a label that the trade agreement template, the disclosure UI, and the GP's hook configuration all reference, but no part of `FundInterestExtension` itself blocks a trade.

### 1.4 `FundInterestExtension` — concrete proposal

New file: `src/storage/extensions/FundInterestExtension.sol`. Implements `ICertificateExtension`. Decodes a `FundInterestData` struct from `extensionData`:

```solidity
enum FundEntityType { LLC, LP, NonUSEquivalent }
enum ICAExemptionType { NotApplicable, Section3c1, Section3c7 }
enum RegSCategory { NotApplicable, Category1, Category2, Category3 }
enum FundTransferRestrictionType { GPConsentRequired, AccreditedOnly, QPOnly, RegSGated, CustomHook, None }

struct FundInterestData {
    // Identity
    string interestClass;            // "Class A Limited Partner Interest"
    FundEntityType entityType;
    ICAExemptionType icaExemption;   // 3(c)(1) / 3(c)(7) / NA
    RegSCategory regSCategory;       // Cat 1 / 2 / 3 / NA

    // Holding-period inputs (see §1.5)
    uint64 acquisitionDate;          // current holder's acquisition (settlement date on every trade)
    uint64 tackedFromAcquisitionDate;// 0 unless 144(d)(3) tacking applies

    // Restriction policy pointer
    FundTransferRestrictionType restrictionType;
    address restrictionHookOverride; // optional per-token hook (overrides global for this token)

    // Affiliate disclosure (informational; trade-agreement-driven)
    bool isAffiliateOrControlPerson;

    // Economics
    uint256 distributionWaterfallPosition;
    uint16  managementFeeBps;        // basis points
    uint16  carriedInterestBps;
    string  governingDocumentsURI;   // operating agreement, PPM, sub doc

    // FIX execution record (§9)
    FIXTradeRecord lastTrade;
}

struct FIXTradeRecord {
    bytes32 securityID;              // tag 48
    bytes8  securityIDSource;        // tag 22  ("EIN", "LEI", "PLATFORM")
    bytes6  securityType;            // tag 167 ("FUND" / "MLEG")
    uint64  tradeDate;               // tag 75
    uint64  settlDate;               // tag 64
    uint128 lastPx;                  // tag 31 (scaled, with `pxScale` in the extension's view fn)
    uint128 lastQty;                 // tag 32
    bytes3  currency;                // tag 15 ("USD")
    bytes3  settlCurrency;           // tag 120
    bytes32 execID;                  // tag 17 (DealManager tx hash or dealId)
    bytes32 partyBuyer;              // tag 448 (PartyRole=4)   — pseudonymous ID
    bytes32 partySeller;             // tag 448 (PartyRole=3)
    bytes32 partyGP;                 // tag 448 (PartyRole=36)
    bytes8  exemptionBasis;          // "4A7" / "144" / "144A" / "REG_S" / "4A1H"
}
```

Notes:

- The struct keeps strings short and uses fixed-width bytes for FIX fields to keep encoded size bounded.
- `acquisitionDate` and `tackedFromAcquisitionDate` are **kept on the extension**, not added to `CertificateDetails`, despite the spec's "recommended" option of putting them on the core struct (§12B.3). Reason: adding fields to `CertificateDetails` is a higher-blast-radius change that affects every printer; keeping them on the per-security extension is consistent with how `ShareExtension` already handles security-specific economics. If the protocol team decides to promote these to `CertificateDetails`, do it once for all extensions in a coordinated upgrade — do not do it inside the cyberTRADE workstream.
- `restrictionHookOverride` is the per-token hook address that §3.5 below activates in `_update`. Storing the address inside the extension blob keeps the printer's storage layout unchanged.
- `lastTrade` is **overwritten** on every settlement. Prior trade history is reconstructed from the `Endorsement[]` array on the cert plus chain events (see §9).

### 1.5 Encoding helper (webapp side)

The webapp already has the pattern: `/apps/cybercorps-web/src/features/forms/form-builder/helpers/extensionData.ts` switches on `SecuritySeries` to pick an encoder (`saftExtensionAbi.encode(...)`, `encodeAceSafeExtensionData(...)`, etc.). cyberTRADE adds one more arm:

```ts
case SecuritySeries.FundInterest:
  return encodeFundInterestExtensionData({
    interestClass, entityType, icaExemption, regSCategory,
    acquisitionDate, tackedFromAcquisitionDate, restrictionType,
    restrictionHookOverride, isAffiliateOrControlPerson,
    distributionWaterfallPosition, managementFeeBps, carriedInterestBps,
    governingDocumentsURI,
    lastTrade: emptyFIXRecord(),
  });
```

This is consumed by:

1. **Primary issuance** (cyberRAISE / `CreateRoundForm`, `useSubmitEOI`, `useAllocate`) when an LP subscribes to a fund SPV. The `SecuritySeries` enum gets a `FundInterest` case; the round form picks `FundInterestExtension` as its `certificateConfig.extensionContract`. `acquisitionDate` is set to the round's closing date (not the mint date, per §4.2.2 of the spec).
2. **Secondary settlement** (DealManager finalization, §3 below). The buyer's newly‑minted cert encodes a fresh `FundInterestData` with `acquisitionDate = block.timestamp`, `tackedFromAcquisitionDate` per the trade‑agreement‑asserted basis, `lastTrade` populated with the just‑executed FIX record.

---

## 2. RoundManager Parallel: What cyberRAISE Already Does, and What cyberTRADE Reuses

The user's question references "dealManager, roundManager, etc." It's worth being explicit that **cyberTRADE does not introduce a "TradeManager"**. Secondary trading reuses `DealManager` plus a new `OfferRegistry` (§4). `RoundManager` stays in its primary‑issuance lane. The two are coordinated through the same `IssuanceManager` / `CyberCertPrinter` / `CyberAgreementRegistry` / `BorgAuth` instances.

### 2.1 RoundManager today (verified)

`src/RoundManager.sol` + `src/RoundManagerFactory.sol`. Inherits `LexScroWLite`. Its job:

1. `createRound()` — GP configures: `SecuritySeries`, `class`, `paymentToken`, `pricePerUnit`, `valuation`, `templateId` (subscription agreement template in `CyberAgreementRegistry`), `extensionUris`, `requiresLexChex`. Webapp form: `apps/cybercorps-web/src/features/rounds/forms/CreateRoundForm.tsx`.
2. `submitEOI()` — investor commits an Expression of Interest (`minAmount`, `maxAmount`, `expiry`, subscription‑agreement signature). The investor's payment token is pulled into an escrow per `LexScroWLite`. Hook: `useSubmitEOI`.
3. `closeRoundNow()` — GP closes; hook: `useCloseRoundNow`.
4. `allocateEOIs()` — GP allocates units to specific EOIs; `IssuanceManager` mints `CyberCertPrinter` tokens to investors with `extensionData` populated per the round's extension contract. Hook: `useAllocate`.

So in the existing model, **the security is born inside `RoundManager`** with `acquisitionDate` = round close date.

### 2.2 What cyberTRADE inherits without modification

- `IssuanceManager` minting machinery — used by `DealManager` at settlement to mint the buyer's new cert (existing `proposeDeal` already calls `IssuanceManager` to mint `corpAssets`).
- `CyberAgreementRegistry` template + EIP‑712 sign infrastructure — used unchanged for trade agreements; new templates are added per exemption pathway.
- `BorgAuth` — GP / admin role authorization for legend updates, void, ledger‑administrator mutations.
- `LexScroWLite` state machine — `PENDING → PAID → FINALIZED` and the void/refund branches — used unchanged by `DealManager` for secondary trades.
- The Ponder indexer schema — already has `cyberCert`, `deal`, `certPrinter`, `officer` tables. cyberTRADE adds `offer` and extends `deal` (§11).

### 2.3 What cyberTRADE adds (no overlap with RoundManager)

- `OfferRegistry` — open‑offer / open‑bid primitive sitting upstream of `DealManager` (§4). `RoundManager` has no equivalent because primary issuance is curated, not market‑posted.
- `DealManager` secondary‑trade mode (§3) so that `buyerAssets` route to a per‑deal seller address rather than `companyPayable`.
- `FundInterestExtension` (§1) — the security being primary‑issued *and* secondary‑traded.
- New `ICondition` implementations (§5).
- FIX receipt emission on settlement (§9).

The diagrammatic separation is:

```
Primary issuance:           Secondary trading:
  RoundManager                OfferRegistry
       ↓                            ↓
   LexScroWLite               LexScroWLite
       ↓                            ↓
   IssuanceManager            IssuanceManager
       ↓                            ↓
   CyberCertPrinter           CyberCertPrinter
       ↓                            ↓
   FundInterestExtension      FundInterestExtension
```

Both columns share every component below the top row.

---

## 3. DealManager Secondary‑Trade Mode (§12B.1 made concrete)

### 3.1 The current routing — verified

`src/DealManager.sol` and `src/libs/LexScroWLite.sol`:

- `Escrow.corpAssets[]` are minted at `proposeDeal` time (or staged from existing inventory) and on `finalizeEscrow()` are pushed to `escrow.counterParty`.
- `Escrow.buyerAssets[]` are pulled from `counterParty` in `handleCounterPartyPayment()` and on `finalizeEscrow()` are routed to `ICyberCorp(LexScrowStorage.getCorp()).companyPayable()`, with `computeFee(...)` taken off the top into `IDealManagerFactory(factory).getPlatformPayable()`.

There is **no party role for "seller"**. The routing is purely positional. For a primary issuance this is fine — the company is selling, and `companyPayable` is the right destination. For a secondary trade, the seller is another LP and `companyPayable` is the wrong destination.

The spec's §12B.1(a) — "add a `tradeType` flag" — is the right minimal change. The implementation breakdown:

### 3.2 Concrete change set in `cybercorps-contracts`

1. **`src/storage/DealManagerStorage.sol`**: extend `Escrow`:

   ```solidity
   enum TradeType { PRIMARY_ISSUANCE, SECONDARY_TRADE }

   struct Escrow {
       /* existing fields ... */
       TradeType tradeType;
       address sellerAddress;     // populated only when tradeType == SECONDARY_TRADE
       address feeDestination;    // §3.3 — integrator share recipient, 0 = no split
       bytes32 offerId;           // §4 — link back to OfferRegistry (0 if none)
   }
   ```

2. **`src/DealManager.sol`** — add an alternative entry point that the `OfferRegistry.acceptOffer` flow calls:

   ```solidity
   function proposeSecondaryDeal(
       address seller,
       address buyer,
       address paymentToken,
       uint256 paymentAmount,
       uint256 tokenIdBeingTransferred,   // or 0 for split-and-mint flow
       uint256 unitsBeingTransferred,
       bytes32 agreementTemplateId,
       string[] memory globalValues,
       address[] memory conditions,
       uint256 expiry,
       address feeDestination,            // §3.3
       bytes32 offerId
   ) external returns (bytes32 dealId);
   ```

   This function does the analog of `proposeDeal` but: (a) sets `tradeType = SECONDARY_TRADE`, `sellerAddress = seller`, `feeDestination = feeDestination`, `offerId = offerId`; (b) **does not mint** the corp asset at proposal time — instead it accepts the seller's deposited cert (Pathway A) or, under Pathway B, accepts the cert that has been endorsed to the buyer; (c) registers the new agreement in `CyberAgreementRegistry` with the secondary template selected by `agreementTemplateId`.

3. **`src/libs/LexScroWLite.sol::finalizeEscrow`** — branch on `tradeType`:

   ```solidity
   address paymentDest = (escrow.tradeType == TradeType.SECONDARY_TRADE)
       ? escrow.sellerAddress
       : ICyberCorp(LexScrowStorage.getCorp()).companyPayable();
   ```

   Apply the fee split (§3.3) before transferring `paymentAmount - protocolFee` to `paymentDest`.

4. **Cert minting at finalize** — for a secondary settlement, the buyer's new cert is minted (via `IssuanceManager.safeMintAndAssign`, **not** `safeMint`, per §1 of the spec and the verified note that `safeMint` leaves `OwnerDetails.name` empty) with `FundInterestData.acquisitionDate = block.timestamp`, `lastTrade` populated, etc. The seller's cert is either `voidCert` (full sale) or `updateCertificateDetails` to decrement `unitsRepresented` (partial sale). This is the same `IssuanceManager` surface that `RoundManager.allocateEOIs` uses; the only new wiring is calling it from `DealManager.finalizeEscrow` instead of from `RoundManager`.

### 3.3 Fee split (§12B.4 made concrete)

`src/DealManagerFactory.sol` today stores `(refImplementation, platformPayable, defaultFeeRatio)`. The integrator whitelist and split layer on top:

1. **`src/storage/DealManagerFactoryStorage.sol`**:

   ```solidity
   mapping(address => bool)    approvedIntegrators;
   mapping(address => uint16)  integratorFeeShareBps; // share of the protocol fee, basis points
   ```

   Owner‑gated setters: `addApprovedIntegrator(address)`, `removeApprovedIntegrator(address)`, `setIntegratorFeeShareBps(address, uint16)`.

2. **`src/DealManagerFactory.sol`**: new helper `requireApprovedIntegrator(address)` reverts on unknown integrator; called from `OfferRegistry.postOffer` and from `DealManager.proposeSecondaryDeal` whenever `feeDestination != address(0)`.

3. **`DealManagerStorage`**: optional `defaultIntegrator` per `DealManager` instance, settable by the BorgAuth admin role on the manager (mutability required to rotate integrators on a long‑lived per‑SPV `DealManager`).

4. **`finalizeEscrow`** — compute `protocolFee = size * defaultFeeRatio / 10_000`. If `escrow.feeDestination != address(0)` and the factory still approves it, compute `integratorAmount = protocolFee * integratorFeeShareBps / 10_000` and `platformAmount = protocolFee - integratorAmount`. Otherwise `integratorAmount = 0` and the full protocol fee accrues to `platformPayable`. Emit `FeePaid(dealId, feeDestination, integratorAmount, platformAmount)`.

The whitelist check is at **proposal time**, not finalization, so the address cannot be made invalid mid‑deal by a factory‑level remove; the remove takes effect for new deals only.

### 3.4 Partial sales

Two routes exist in the codebase today; cyberTRADE should pick one per custody path:

- **Pathway A (escrow + transfer):** split the seller's cert before deposit. `IssuanceManager.updateCertificateDetails` decrements `unitsRepresented` on the seller's existing cert; `IssuanceManager.safeMintAndAssign` mints a new cert representing the sold units; the new cert is escrowed. This is the natural Direct‑Custody flow.
- **Pathway E (metadata mutation):** the seller's cert stays put; on finalize, the ledger administrator decrements `unitsRepresented` on the seller's cert and mints a new cert to the buyer. This is the natural Administered‑Custody flow.

Both are achievable today through the existing `IssuanceManager` surface; the difference is who calls it and when. Encoding this choice in `OfferRegistry`/`DealManager` requires a single boolean flag plus access control on the metadata‑mutation entry point (BorgAuth admin role for the ledger administrator).

### 3.5 Per‑token restriction hooks (§12B.2)

`src/CyberCertPrinter.sol::_update`, lines around 257–264 in the current source, has the per‑token hook block commented out. The `restrictionHooksById` mapping exists in storage and has a setter, but `_update` does not evaluate it; only `globalRestrictionHook` is active.

Required minimal change:

```solidity
ITransferRestrictionHook tokenHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
if (address(tokenHook) != address(0)) {
    (bool allowed, string memory reason) = tokenHook.checkTransferRestriction(from, to, tokenId, "");
    if (!allowed) revert TransferRestricted(reason);
}
```

Uncomment, deploy, and document that per-token hooks now fire on every transfer including DealManager-mediated ones (DealManager is the whitelisted transferer for the global `tokenTransferable` gate, but per-token hooks may still apply — this is the desired behavior, since it lets the GP impose, e.g., a `restrictionHookOverride` on a single affiliate's cert without restricting the entire printer).

The `FundInterestExtension.restrictionHookOverride` field (§1.4) is the per‑token hook address; this only becomes meaningful when this uncomment lands.

---

## 4. `OfferRegistry` — New Protocol Primitive (§12B.8 made concrete)

There is no precursor in the codebase. The proposed contract sits between the user's signed posting transaction and `DealManager.proposeSecondaryDeal`. It is intentionally **lean**: the spec is clear that visibility is gated at the UI layer (§4.4, §11.1B), not on‑chain, so this contract does **not** hold a permission ACL on who can read offers. Anyone can read; whether the webapp surfaces a given offer to a given user is decided by Legion's UI + LeXcheX.

### 4.1 Storage and surface

New file: `src/OfferRegistry.sol`. New file: `src/storage/OfferRegistryStorage.sol`.

```solidity
enum OfferSide   { SELL, BUY }
enum OfferStatus { LIVE, CANCELLED, EXPIRED, FULLY_ACCEPTED, PARTIALLY_ACCEPTED }
enum ExemptionPathway { RULE_144, SECTION_4A7, SECTION_4A1_HALF, RULE_144A, REG_S }

struct CounterpartyRestrictions {
    bool   accreditedOnly;
    bool   qpOnly;
    bool   nonUSPersonOnly;
    bytes32 requiredSoulboundCategory;   // 0 if none
    uint8   requiredSoulboundTier;
    address[] explicitAllowlist;         // empty if open to any eligible
}

struct Offer {
    address spvCyberCorp;
    address offeror;
    OfferSide side;
    uint256 interestEntryTokenId;        // sell offers; 0 for bids
    uint256 unitsOffered;
    address paymentToken;
    uint256 consideration;
    ExemptionPathway exemptionPathway;
    uint64  validUntil;
    CounterpartyRestrictions restrictions;
    bytes   additionalTerms;             // ABI-encoded GP pre-consent ref, spousal consent, etc.
    address integrator;                  // must be DealManagerFactory-approved at posting
    OfferStatus status;
    uint256 unitsAccepted;               // sum of partial acceptances
}
```

External functions:

```solidity
function postOffer(...) external returns (bytes32 offerId);    // emits OfferPosted
function cancelOffer(bytes32 offerId) external;                // offeror or BorgAuth admin
function acceptOffer(bytes32 offerId, uint256 unitsAccepted, bytes calldata acknowledgments)
    external returns (bytes32 dealId);                          // emits OfferAccepted + delegates to DealManager
function getOffer(bytes32 offerId) external view returns (Offer memory);
```

### 4.2 What `postOffer` checks

- For `SELL`: caller is the registered owner of `interestEntryTokenId` (via `OwnerDetails.ownerAddress` for Administered Custody, or `IERC721.ownerOf` for Direct Custody — read both, accept either). This is the "no phantom sells" rule from §4.4.
- SPV is registered (a mapping of approved cyberCORP addresses, owner‑managed initially).
- `integrator`, if non‑zero, is `approvedIntegrators[integrator]` on `DealManagerFactory`.
- `paymentToken` is on a per‑SPV allowlist (USDC/USDT initially, configured per cyberCORP).

`postOffer` **does not lock the asset**; cancellation remains free until acceptance. This is the QMS "nonbinding listing" posture (§6.7 of the spec).

### 4.3 What `acceptOffer` does

1. Validates the offer is `LIVE` and within `validUntil`.
2. Validates the acceptor satisfies `restrictions`. The on‑chain check is structural: jurisdiction credentials, accreditation, QP, Soulbound category/tier — all queried via the LeXcheX adapter (`creds/` directory in the contracts repo — `LeXcheXAdapter.sol` exists; cyberTRADE adds a `LegionSoulboundAdapter.sol` for the Soulbound NFT category check).
3. Calls `DealManager.proposeSecondaryDeal(...)` with the offer's pathway → maps to an agreement template ID in `CyberAgreementRegistry`, the appropriate `ICondition[]` set (built per `ExemptionPathway`), `feeDestination = integrator`, `offerId = offerId`.
4. Returns the new `dealId`. Emits `OfferAccepted(offerId, dealId, acceptor, unitsAccepted)`.
5. Updates `status` to `PARTIALLY_ACCEPTED` or `FULLY_ACCEPTED` and `unitsAccepted += unitsAccepted`.

The mapping from `ExemptionPathway` to `ICondition[]` is the same configuration the DealManager already accepts on `proposeDeal`. For example:

| Pathway | Mandatory conditions added at acceptance |
|---|---|
| `RULE_144` | `HoldingPeriodCondition`, `KYCAMLCondition`, `Rule144DisclosureCondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A7` | `AccreditedInvestorCondition`, `KYCAMLCondition`, `Section4a7DisclosureCondition`, `ERISACondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A1_HALF` | adds `LegalOpinionCondition` to the 4(a)(7) set |
| `RULE_144A` | `QualifiedInstitutionalBuyerCondition` instead of `AccreditedInvestorCondition` |
| `REG_S` | `NonUSPersonCondition`, `RegSDistributionComplianceCondition` instead of accreditation; no ERISA |

Per‑SPV additions (e.g., `QualifiedPurchaserCondition` for 3(c)(7) funds, `CFIUSCondition` for non‑fund‑exception SPVs, `LegionSoulboundCondition` for syndicate gating) are configured on the SPV's `DealManager` and inherited automatically — `OfferRegistry` does not need to know about them.

### 4.4 Visibility lives at the UI layer; compliance lives at settlement

**Technical observation first.** On-chain storage is publicly readable. There is no meaningful way to make `OfferRegistry` storage "invisible" to a determined reader — anyone with a node, a block explorer, or a script can read the raw slots. A `requireWhitelisted(msg.sender)` modifier in front of a `getOffer` view function would be cosmetic, because the underlying storage is reachable anyway. Real on-chain hiding would require encryption (ZK, threshold encryption), which is heavy machinery the spec's regulatory analysis does not call for.

So `OfferRegistry` does not pretend to gate who can read offers. It stores offers as plain state and lets the off‑chain stack decide who sees what.

**Where the gates actually live.** cyberTRADE enforces two different things in two different places:

1. **Visibility (off chain, in the UI + indexer).** The webapp (§10) reads offers through the indexer (§11) and the indexer filters before returning a list. The filter inputs are:
   - the viewer's LeXcheX credentials (KYC, accreditation, QP, non‑US),
   - the viewer's Soulbound NFT badges (Legion's per‑SPV whitelist; §4.1.3A of the spec),
   - the viewer's seasoning timestamp (§11.1B of the spec),
   - per‑SPV access entitlements maintained server‑side in Legion's UI.

   A user who is not eligible for SPV A simply never sees SPV A's offers in their feed. This is the "no general solicitation" hygiene — the same posture Nasdaq Private Market, CAIS, and iCapital occupy by surfacing private offerings only through access-restricted portals to credentialed users (cf. E.F. Hutton 1982, Bateman Eichler 1985, IPONET 1996 line of no-action letters, discussed in spec §11.1B).

2. **Compliance (on chain, in `ICondition`).** Even if a user bypassed the UI entirely — scraped the chain for an offer ID, called `OfferRegistry.acceptOffer` directly — the trade still could not *settle*. The `DealManager`'s condition set (`AccreditedInvestorCondition`, `QualifiedPurchaserCondition`, `KYCAMLCondition`, `LegionSoulboundCondition`, `NonUSPersonCondition`, etc.) would fail at finalization. Escrowed funds would return on void. This is the binding legal gate.

The two layers do different jobs. Visibility keeps the offer-posting activity inside the preexisting-substantive-relationship perimeter (a §4(a)(2) / §4(a)(7) concern about *how the offer reaches users*). Compliance keeps the executed trade inside the exemption (a concern about *who is actually on the other side at closing*). Collapsing both into one on-chain ACL would give a worse contract without any additional regulatory protection, because the visibility question is about the channel, not about the data.

**Why not encode the whitelist on chain anyway.** Even setting the regulatory analysis aside, on-chain eligibility logic is the wrong place:

- Every whitelist add/remove becomes a gas-paying transaction; thousands of users across dozens of SPVs compounds quickly.
- Eligibility rules vary per SPV (3(c)(1) cap, 3(c)(7) QP requirement, jurisdiction, syndicate badge, seasoning) and per pathway (4(a)(7), 144A, Reg S). Encoding the full rule space in `OfferRegistry` makes the contract brittle and SPV-specific.
- Composability breaks. The spec is explicit that "any third party can build a UI on the same protocol" (§10.3, §11.1A). If `OfferRegistry` encoded Legion's specific whitelist logic, a whitelabel UI or fund-administrator portal couldn't use the same registry under its own access-control terms. With visibility at the UI layer, each operator independently applies its own gating under its own Covered User Interface Provider posture.

**The scraper edge case.** A hostile third party could scrape on-chain offer state and republish it on a public site. If they did, *their* republication might constitute general solicitation — but the liability attaches to the republisher, not to the original offeror or to Legion. The original offer-poster's posture is governed by where they posted (Legion's access-restricted UI) and what surfacing Legion performed (only to whitelisted users), not by what a third party does later with public chain data. This is the same logic that applies to a leaked PPM: the leak does not retroactively convert a private placement into a public offering. If that asymmetry is uncomfortable for a particular deployment, the alternative is encryption (ZK offer pools, threshold-encrypted state) — substantially heavier, and not what spec §11.1B's analysis calls for.

---

## 5. Conditions — concrete additions

The codebase has `src/interfaces/ICondition.sol`:

```solidity
interface ICondition {
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data)
        external view returns (bool);
}
```

`data` is the encoded agreement ID; custom conditions read agreement parameters back through `DealManager` and `CyberAgreementRegistry`. cyberTRADE adds the conditions enumerated in §4.1.4 of the spec under `src/conditions/`:

```
src/conditions/HolderCapCondition.sol
src/conditions/AccreditedInvestorCondition.sol
src/conditions/QualifiedPurchaserCondition.sol
src/conditions/QualifiedInstitutionalBuyerCondition.sol
src/conditions/KYCAMLCondition.sol
src/conditions/HoldingPeriodCondition.sol
src/conditions/Section4a7DisclosureCondition.sol
src/conditions/Rule144DisclosureCondition.sol
src/conditions/AgreementSignedCondition.sol
src/conditions/ERISACondition.sol
src/conditions/NonUSPersonCondition.sol
src/conditions/RegSDistributionComplianceCondition.sol
src/conditions/LegalOpinionCondition.sol
src/conditions/LegionSoulboundCondition.sol
src/conditions/CFIUSCondition.sol
src/conditions/TaxInfoCondition.sol
src/conditions/PriceAnomalyCondition.sol
src/conditions/GPLPApprovalCondition.sol
src/conditions/GlobalKillCondition.sol
src/conditions/TimeSettlementPeriodCondition.sol
```

A few that warrant explicit mechanical detail:

### 5.1 `HoldingPeriodCondition`

Reads `FundInterestExtension.acquisitionDate` (and `tackedFromAcquisitionDate` if non‑zero) from the seller's cert via `CyberCertPrinter.getCertificate(tokenId).extensionData`, decodes via `FundInterestExtension`, applies the earlier date when tacking is asserted, and compares against the rule's required hold (one year for non‑reporting issuers under Rule 144; the Reg S compliance period derived from `regSCategory`). Pure on‑chain check, no oracle.

### 5.2 `GlobalKillCondition` (§12B.5)

Two admin slots: `metaLexAdmin` and `legionAdmin` (each can be an EOA or a BorgAuth role address). State:

```solidity
bool    killFlag;
address pendingLowerProposer;     // 0 if none pending
uint64  pendingLowerProposedAt;
uint64  constant LOWER_QUORUM_WINDOW = 48 hours;
```

`raiseKill()` callable by either admin, unilateral, sets `killFlag = true`. Lowering is two‑step: `proposeLower()` by one admin sets `pendingLowerProposer` and timestamp; `confirmLower()` by the **other** admin within `LOWER_QUORUM_WINDOW` clears `killFlag`. After the window, the proposal expires.

Attached by `DealManagerFactory.deployDealManager(...)` to every new `DealManager` automatically (factory adds the GlobalKill address into the manager's default condition set at construction). `checkCondition` returns `!killFlag`.

This is one of the few conditions that is **constant across all deals** and shared across all DealManagers — deploy once at protocol initialization, address registered in `DealManagerFactoryStorage`.

### 5.3 `TimeSettlementPeriodCondition` (§12B.6)

```solidity
struct DealClock {
    uint64 startedAt;     // set on the trigger event
    uint8  trigger;       // 0=proposal, 1=both deposits, 2=agreement countersigned
}
mapping(bytes32 dealId => DealClock) clocks;

uint64 delaySeconds; // default 86400
```

Started by a hook on `DealManager` when the trigger condition first occurs. `checkCondition` returns `block.timestamp >= clock.startedAt + delaySeconds` and `clock.startedAt != 0`.

### 5.4 `LegionSoulboundCondition`

Configured with a `categoryHash` (e.g., `keccak256("LEGION_SPV_A_WHITELIST")`) and an `address requiredIssuer`. Calls into `LegionSoulboundAdapter` which wraps the Soulbound NFT contract (deployed under Legion's custom credentialing layer in LeXcheX, §4.1.3A of the spec). The adapter pattern keeps the `ICondition` implementation thin and lets Legion rotate the underlying NFT contract without redeploying every condition that consumes it.

---

## 6. Custody Election Under Existing CertPrinter

The spec assumes Path 3 (Hybrid). The codebase has no notion of "Administered" vs "Direct" custody, but the existing CertPrinter primitives are sufficient — the work is conventions and a small registry, not new contract types.

**Mechanic:**

- Administered Custody: the cert's ERC‑721 `ownerOf` is the ledger administrator's multisig. `OwnerDetails.ownerAddress` is the LP. `OwnerDetails.name` is the LP's name. Transfers happen through `updateCertificateDetails` mutating `OwnerDetails` (legally operative) plus an `addEndorsement` for chain‑of‑title. `_update` is not called; the cert never moves between wallets.
- Direct Custody: `IERC721.ownerOf` and `OwnerDetails.ownerAddress` are the same address (the LP's wallet). Transfers go through `_update` plus `addEndorsement`.

**New artifact:** a small `CustodyRegistry` mapping `(cyberCorp, holderAddress) → CustodyMode`, or — preferably — extending `FundInterestExtension` with a `custodyMode` field so the choice rides with each cert. The webapp reads this to decide which deposit flow to show (§10.4 below).

**Settlement implication:** `DealManager.proposeSecondaryDeal` checks the seller's custody mode and selects Pathway A (Direct → escrow + transfer) or Pathway E (Administered → metadata mutation) accordingly. Both paths exist today inside `IssuanceManager`; the new code is the dispatch.

---

## 7. Trade Agreement Templates in CyberAgreementRegistry

`src/CyberAgreementRegistry.sol` has the right shape already. `Template` carries `legalContractUri`, `title`, `globalFields[]`, `partyFields[]`. `AgreementData` has `globalValues[]`, `parties[]`, `partyValues[address => string[]]`, finalization state, void state, and an `expiry`. Signing is EIP‑712 over `SignatureData`. Delegation is supported via `mapping(address => Delegation)`.

cyberTRADE adds five template IDs (one per exemption pathway), registered once by MetaLeX:

| Template constant | URI points to | globalFields[] (excerpt) |
|---|---|---|
| `TEMPLATE_RULE_144` | `ipfs://.../rule144-fund-interest-v1.pdf` | spvName, interestClass, units, price, paymentToken, acquisitionDate, settlementDate, exemptionBasis, gpAttestationHash |
| `TEMPLATE_4A7` | `ipfs://.../section4a7-fund-interest-v1.pdf` | same + disclosurePackageHash, sellerAffiliateStatus |
| `TEMPLATE_4A1_HALF` | ... | same + sellerInvestmentIntent, buyerSophistication, gpOpinionRef |
| `TEMPLATE_144A` | ... | same + buyerQIBStatusEvidence |
| `TEMPLATE_REG_S` | ... | same + regSCategory, distributionComplianceEnd, sellerNoDirectedSellingEffortsAttestation |

Every template's `globalFields` includes `gpUnderlyingProvenanceAttestationHash` from §4.1.0 of the spec; the on‑chain agreement record carries the GP's most‑recent provenance attestation as a hash. The Buyer cannot countersign without acknowledging that hash; this is what makes §4.1.0 a per‑trade record rather than only an onboarding artifact.

The template registration happens in a deploy script under `script/RegisterTradeAgreementTemplates.s.sol`. Population per trade happens inside `OfferRegistry.acceptOffer` (which knows the exemption pathway from the offer) via `CyberAgreementRegistry.createContract`, with `globalValues` derived from the offer + the SPV's stored disclosure URIs.

---

## 8. Ledger Mutation Mechanics, Verified

The spec's §7.5 is correct that the metadata mutation is the legally operative act. Two verified codebase facts the implementation must honor:

1. **Use `safeMintAndAssign`, not `safeMint`.** `CyberCertPrinter.safeMint` leaves `OwnerDetails.name` empty; `safeMintAndAssign` populates it and emits `CertificateAssigned`. Every cyberTRADE settlement must call `safeMintAndAssign` for the buyer's new cert. The spec calls this out (§7.5) — implementation must follow.
2. **`updateCertificateDetails` does not auto‑update `OwnerDetails`.** The two are reconciled by `_update` on ERC‑721 transfer. Under Pathway E (metadata mutation, Administered Custody), the ledger administrator must call `updateOwnerDetails(tokenId, newOwner)` (a new admin function to add, BorgAuth‑gated) in the same transaction as `updateCertificateDetails`. Otherwise `OwnerDetails` is stale until a subsequent transfer reconciles it — and under Administered Custody there is no subsequent transfer.

   Add to `src/CyberCertPrinter.sol`:
   ```solidity
   function updateOwnerDetails(uint256 tokenId, address newOwner, string calldata newName)
       external
       onlyIssuanceManagerOrAdmin
   {
       OwnerDetails storage od = CyberCertPrinterStorage.cyberCertStorage().ownerDetailsById[tokenId];
       od.ownerAddress = newOwner;
       od.name = newName;
       emit OwnerDetailsUpdated(tokenId, newOwner, newName);
   }
   ```

The endorsement record on the cert (`Endorsement{endorser, timestamp, signatureHash, registry, agreementId, endorsee, endorseeName}`) is the chain‑of‑title artifact. Every settlement appends one. Existing function: `addEndorsement(tokenId, ...)` callable by `IssuanceManager` or current `ownerOf`. Under Pathway E, the ledger administrator (which is `ownerOf` for the multisig‑held cert) adds the endorsement; under Pathway A/B, the seller adds it before depositing, or `DealManager.finalizeEscrow` adds it after deposit via the IssuanceManager.

---

## 9. FIX Receipt Emission

Two layers (§12B.7):

1. **Per‑cert FIX state** — populated inside `FundInterestExtension.lastTrade` (§1.4). Written at settlement via the same `IssuanceManager` call that mints / mutates the cert. Immutable after write (next trade overwrites for the next holder, but the **previous holder's** cert is voided or decremented, so historical FIX state is recoverable through the chain of voided certs + the Endorsement array on each).

2. **Per‑settlement event** — emitted by `DealManager` on every `signAndFinalizeDeal`:

   ```solidity
   event FIXTradeReceipt(
       bytes32 indexed dealId,
       bytes32 indexed offerId,
       bytes32 indexed fixID,        // FundInterestData.lastTrade.securityID
       uint64  tradeDate,
       uint128 lastPx,
       uint128 lastQty,
       bytes3  currency,
       bytes32 execID,
       bytes32 partyBuyer,
       bytes32 partySeller,
       bytes32 partyGP,
       bytes8  exemptionBasis
   );
   ```

   This is the canonical onchain trade receipt. The indexer (§11) consumes it into a `fix_trade_receipt` table to power downstream reports.

`partyBuyer` / `partySeller` are pseudonymous (hash of the wallet address with a per‑SPV salt). The cleartext identity stays in `OwnerDetails`. Anyone with access to `OwnerDetails` (the GP, fund admin, tax preparer) can map FIX records back to identities; arbitrary chain readers cannot.

---

## 10. Application Layer — Webapp Plan

Building on what the explore agent verified about `metalex-webapp`. Almost every screen reuses an existing component or hook.

### 10.1 Offer Builder (post sell / post bid)

Closely modeled on `apps/web/src/app/(frame-layout)/lexscrow/propose/_forms/ProposeLexscrowAgreement.tsx` and its design‑system form `packages/design-system/forms/ProposeLexscrowAgreementForm.tsx`. The CyTE form already captures: two parties (proposing / confirming), two locked assets, agreement URI, governing law, dispute resolution, expiry, chain. For cyberTRADE, the second party is unknown at posting, and the second asset is implicit (the consideration). Concrete reuses:

- `AssetInput`, `AssetValueLabel` (units offered, payment‑token consideration).
- `EmbeddedAgreement` for the IPFS preview of the trade template (CyTE already renders an IPFS URI).
- `DateInputField` for `validUntil`.
- `FormSelectField` for the exemption pathway dropdown (`Rule 144 / 4(a)(7) / 4(a)(1½) / 144A / Reg S`) — drives which template is pre‑loaded into `EmbeddedAgreement`.
- `TransactionActionButton` for "Sign and Post Offer", calling `OfferRegistry.postOffer` via `useWriteContract` (Wagmi), with the same react‑hook‑form + Zod pattern.

What CyTE does **not** have and must be added: a "Counterparty restrictions" sub‑form (accredited‑only, QP‑only, non‑US‑person, required Soulbound category/tier, explicit allowlist). This is a small new component under `packages/design-system/forms/components/CounterpartyRestrictionsInput.tsx`.

Sell‑side specifics: an entry-token picker (the LP's existing `cyberCert` rows under the SPV's printer, served from the Ponder indexer's `cyberCert` table — the same data source as the existing `CertsTable.tsx` on the mainframe). The picker surfaces, per cert: `unitsRepresented`, `acquisitionDate`, `certLegend`, holding‑period status (derived from `acquisitionDate` and the fund's category).

### 10.2 Offer Discovery (browse)

No CyTE precedent. New page under `apps/web/src/app/(frame-layout)/cybertrade/discover/page.tsx`. Server component pulls from `/api/offers` (new indexer route, §11), pre‑filtered by:

- session user's LeXcheX credentials (`useLexchexForAddress`),
- session user's Soulbound NFT category/tier (new hook `useLegionSoulboundForAddress`, parallel to `useLexchexForAddress`),
- session user's per‑SPV whitelist entitlements (server‑side, queried from a new `user_spv_entitlements` table in the webapp DB — administered by Legion ops, not on chain),
- session user's seasoning timestamp (set when the user finishes onboarding; gate at 30 days per §11.1B of the spec).

The list view is a thin wrapper around the indexer's denormalized response. Sort/filter is user‑driven, no recommendations or "best price" labels — this is the Covered UI Provider constraint (§11.5).

### 10.3 Acceptance view

Closely modeled on `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/SignLexscrowAgreement.tsx`. CyTE already has a per‑agreement page that:

- reads the agreement, shows the parties, renders the IPFS document inline,
- runs `useSignedAgreement` to check status,
- exposes a "confirm and adopt" call.

For cyberTRADE, the route is `apps/web/src/app/(frame-layout)/cybertrade/offer/[offerId]/page.tsx`. It adds:

- a compliance checklist (KYC valid, accreditation valid, non‑US valid, QP valid, Soulbound held, ERISA negative, Reg S distribution compliance, tax info) — each item rendered with the same `useLexchexForAddress` + onchain reads from the cert and SPV state,
- a 4(a)(7) information‑package acknowledgment modal that the acceptor must click‑through before the "Sign and Accept" button activates,
- a `signAndAccept` call that hits `OfferRegistry.acceptOffer`, which in turn calls `DealManager.proposeSecondaryDeal` and `CyberAgreementRegistry.createContract`.

### 10.4 Countersign + Deposit + Settlement view

Closely modeled on `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/ExecuteLexscrowAgreement.tsx`. CyTE's `ExecuteLexscrowAgreement` already handles the two‑party deposit + finalize sequence under `LexScroWLite`. For cyberTRADE:

- Branch on the seller's custody mode (read from the offer's referenced `FundInterestExtension.custodyMode`):
  - **Direct Custody**: seller deposit step shows "approve and deposit Ledger Entry Token" (ERC‑721 approval flow). Buyer deposit step shows "approve and deposit payment token".
  - **Administered Custody**: seller deposit step is absent (the cert never leaves the multisig). Buyer deposit step is the only deposit. A status row shows "Awaiting ledger administrator authorization" until the administrator's multisig has signed the metadata mutation.
- The "Settle" action is **hidden by default**: the keeper service (§10.4 of the spec) calls `signAndFinalizeDeal` once `TimeSettlementPeriodCondition` clears. A "Settle manually" affordance is shown if the keeper hasn't fired within a configurable grace period; this preserves user agency without putting the keeper in the trust path.

### 10.5 GP Monitoring view

Closely modeled on `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx`. Same columns plus: active offers for the SPV (joined from the indexer's `offer` table), passing/failing condition counts per open trade, holder count vs. ICA cap with color‑coded headroom, transfer‑restriction‑hook deployment status. No "approve trade" button — the spec is explicit that GPs do not approve individual trades.

### 10.6 Admin panel (Pathway F)

The void / force‑transfer / lower‑Global‑Kill / propose‑Global‑Kill‑lower flows live behind a separate admin route, gated by BorgAuth role. This is **not** part of the trading UI; it lives under `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/admin/` to keep the Covered UI Provider scope clean per §11.5.

---

## 11. Indexer Additions

The webapp uses Ponder (`apps/cybercorps-indexer/`). Schema in `ponder.schema.ts`. cyberTRADE additions:

```ts
// new tables
offer:                {id, spvCyberCorp, offeror, side, tokenId, units, paymentToken, consideration,
                       exemptionPathway, validUntil, restrictionsBlob, additionalTermsBlob,
                       integrator, status, unitsAccepted, postedAt, cancelledAt, expiredAt}
offer_acceptance:     {id, offerId, acceptor, units, dealId, acceptedAt}
fix_trade_receipt:    {id (=execID), dealId, offerId, fixID, tradeDate, lastPx, lastQty,
                       currency, partyBuyer, partySeller, partyGP, exemptionBasis}
user_spv_entitlement: {userId, spvCyberCorp, whitelistTier, addedAt, addedBy}  // off-chain only
user_seasoning:       {userId, onboardingCompletedAt, seasoningUnlockAt}        // off-chain only

// extensions to existing tables
deal:                 + offerId, sellerAddress, tradeType, feeDestination, integratorFeePaid, platformFeePaid
cyberCert:            + fundInterestData (decoded), lastTrade (decoded FIX), custodyMode
```

API routes mirror the existing patterns in `apps/cybercorps-indexer/src/api/rounds/rounds-routes.ts` and `deals/deals-routes.ts`:

```
GET /api/offers                  // filtered list, eligibility-aware via session
GET /api/offers/:offerId
GET /api/spvs/:cyberCorp/offers  // per-SPV
GET /api/users/:address/offers   // mine
GET /api/users/:address/deals    // mine (extends existing)
GET /api/spvs/:cyberCorp/fix-receipts
```

Eligibility filtering for `/api/offers` is server‑side: the route joins `user_spv_entitlement`, `user_seasoning`, and the user's LeXcheX credential cache; it never returns an offer the user is ineligible to see. This is the implementation of the spec's "UI‑level visibility gating" (§4.4, §11.1B).

A keeper component (separate Node process, deployed alongside the indexer) subscribes to `DealProposed`, `BuyerDeposit`, `SellerDeposit` and calls `signAndFinalizeDeal` when both deposits are in and `TimeSettlementPeriodCondition` clears, per §10.4 of the spec.

---

## 12. Out of Scope (Future‑Enhancement Markers)

Items the spec lists as future enhancements that are not in this implementation detail:

- **Scrip Token layer (§13).** No `CyberScrip` changes proposed; existing `src/CyberScrip.sol` is untouched. If/when scrip is adopted as a trading instrument for fund interests, it sits alongside the secondary trade primitives, not inside them.
- **AMM liquidity for scrip (§13A).** Out of scope.
- **Tag‑along / drag‑along / ROFR.** Not assumed for the initial SPVs (Addendum B).
- **Manual per‑trade GP consent.** Generalized into `GPLPApprovalCondition` (§5), deployed only on SPVs whose governing documents require it (Addendum C). The condition exists in the protocol layer; no UI work beyond a "GP approval pending" status row in the trade detail view.

---

## 13. Spec ↔ Codebase Discrepancies (verified)

Items in v2.04 that should be corrected or refined when the spec is next revised:

1. **§7.4 / §12B.1 routing description.** The spec says `LexScroWLite.finalizeEscrow` routes "buyer assets to `companyPayable` and corp assets to `counterParty`" — verified correct. The implication for cyberTRADE is that "secondary trade mode" must redirect `buyerAssets` to a per‑deal seller address. The spec already captures this in §12B.1; no change needed there, but cross‑reference the seller‑address storage requirement (§3.2 above).
2. **§12B.2 per‑token restriction hooks.** Spec says the block in `_update` is "commented out" — verified correct (around lines 257–264 of the current `CyberCertPrinter.sol`). The `restrictionHooksById` storage and setter functions exist; only the read in `_update` is dormant. Spec is accurate.
3. **§4.2 `safeMint` vs `safeMintAndAssign`.** Spec correctly identifies that `safeMint` leaves `OwnerDetails.name` empty — verified. Implementation must use `safeMintAndAssign` everywhere, including the secondary‑settlement mint. The spec calls this out in §7.5; reinforce in implementation reviews.
4. **§7.6 / §12B.7 FIX field location.** Spec is ambivalent about whether FIX fields live on the core `CertificateDetails` or on `FundInterestExtension`. This detail document recommends extension (§1.4), to minimize the blast radius of the change and stay consistent with the existing pattern where security‑class‑specific data lives in the extension.
5. **§8 reference to CyTE.** Spec states CyTE is at "`app.metalex.tech/lexscrow/propose`" and acts as the closest precedent — URL verified correct. Note however that CyTE itself does **not** integrate cyberSign explicitly; it calls `confirmAndAdoptAgreement` on the LeXscroW contract, which performs the signature inline. cyberRAISE is the actual precedent for cyberSign‑style template signing. cyberTRADE should pattern its agreement‑population step after cyberRAISE's subscription‑agreement flow, not CyTE's static IPFS document flow, because the trade agreement must carry per‑trade `globalValues` populated through `CyberAgreementRegistry.createContract`.
6. **§4.2.2 `acquisitionDate` placement.** Spec proposes adding to `CertificateDetails` "preferable" — this detail document recommends the extension (§1 above). Both are workable; placement in the extension is lower‑risk for the cyberTRADE workstream because it doesn't touch shared core storage.
7. **§12 reference to `OfferRegistry`.** Spec correctly notes none exists. New file `src/OfferRegistry.sol` proposed in §4 above.
8. **§10 reference to `CertsTable`.** The webapp already has a serviceable cap‑table view (`apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx`); the GP monitoring view extends this rather than building new.

---

## 14. Sequenced Delivery Plan

A pragmatic order of work that lets each step ship independently:

1. **`FundInterestExtension`** + encoding helpers in webapp. Mergeable; immediately unblocks primary issuance of fund interests through cyberRAISE.
2. **`acquisitionDate` / `tackedFromAcquisitionDate` plumbing** in the extension and the round‑close flow (cyberRAISE side). Tested by minting fund certs and asserting the date is the round close date, not the mint date.
3. **Activate per‑token restriction hooks** in `CyberCertPrinter._update`. Behind a printer-level feature flag if needed to avoid disturbing existing deployments.
4. **`GlobalKillCondition` + `TimeSettlementPeriodCondition`**. Deployed and attached‑by‑default by `DealManagerFactory`. No behavioral effect on primary issuance because they pass when not raised / once delay elapses.
5. **`DealManagerFactory` integrator whitelist + per‑deal `feeDestination`**. No behavioral change to existing deployments because `defaultIntegrator == 0` and `feeDestination == 0` keep the legacy flow.
6. **`DealManager` secondary trade mode** (`tradeType`, `sellerAddress`, branched routing).
7. **Trade agreement templates** registered in `CyberAgreementRegistry`.
8. **Remaining `ICondition` implementations** (Holding period, accredited, KYC, ERISA, NonUS, RegS, holder cap, tax info, Soulbound, CFIUS, price anomaly, GPLP approval, 4(a)(7) disclosure, Rule 144 disclosure, legal opinion, 144A QIB).
9. **`OfferRegistry`** contract.
10. **Indexer schema additions** (Ponder).
11. **Webapp UI**: offer builder → discovery → acceptance → deposit/settlement → GP monitoring. Components inherited from `ProposeLexscrowAgreementForm`, `SignLexscrowAgreement`, `ExecuteLexscrowAgreement`, `CertsTable`, `useLexchexForAddress`, `useFeeBasisPoints`.
12. **Keeper + FIX receipt event consumer**.
13. **Pathway F admin panel** for void / force transfer / Global Kill governance.

Items 1–4 are protocol upgrades with no functional change to existing flows; they can land on `main` without coordinating with the webapp. Item 5 is the first change that requires coordinated webapp release (the integrator address must be supplied somewhere). Items 6–9 are the secondary‑trade core; items 10–13 are the UI / operations layer.

---

## 15. Anchored Pointers (so this document stays useful as code drifts)

Contracts repo (`metalex-tech/cybercorps-contracts`):

- `src/DealManager.sol` — `proposeDeal`, `signDealAndPay`, `signAndFinalizeDeal`, `computeFee`, `voidExpiredDeal`, condition management.
- `src/DealManagerFactory.sol` — `platformPayable`, `defaultFeeRatio`, `deployDealManager`.
- `src/libs/LexScroWLite.sol` — `finalizeEscrow` (the routing branch lives here), `handleCounterPartyPayment`, `voidAndRefund`.
- `src/RoundManager.sol` — `createRound`, `submitEOI`, `closeRoundNow`, `allocateEOIs`.
- `src/IssuanceManager.sol` — `safeMint`, `safeMintAndAssign`, `updateCertificateDetails`, `voidCert`, `addEndorsement`, `endorseAndTransfer`.
- `src/CyberCertPrinter.sol` — `_update` (lines around 246–310; per‑token hook block currently disabled around 257–264), `globalRestrictionHook`, `restrictionHooksById`, `endorsementRequired`, `setGlobalRestrictionHook`.
- `src/CyberAgreementRegistry.sol` — `createTemplate`, `createContract`, `signContractFor`, `Delegation`, EIP‑712 `SignatureData`.
- `src/storage/extensions/ICertificateExtension.sol` — minimal interface.
- `src/storage/extensions/ShareExtension.sol` — the template to clone for `FundInterestExtension`.
- `src/storage/extensions/{SAFE,SAFTE,SAFT,TokenWarrant,ACESAFE}Extension*.sol` — additional patterns to study; ACESAFE in particular for fund/pump denomination handling.
- `src/hooks/transfer/{BaseTransferHook,ToggleTransferHook,WhitelistTransferHook}.sol` — restriction hook patterns.
- `src/libs/auth.sol`, `src/storage/BorgAuthStorage.sol` — BorgAuth role wiring.
- `src/creds/` — adapter pattern for off‑chain credential reads (LeXcheX); add `LegionSoulboundAdapter.sol` and `LeXcheXFundInterestAdapter.sol` here.

Webapp (`metalex-tech/metalex-webapp`):

- `apps/web/src/app/(frame-layout)/lexscrow/propose/_forms/ProposeLexscrowAgreement.tsx` — CyTE form container.
- `packages/design-system/forms/ProposeLexscrowAgreementForm.tsx` — CyTE form UI.
- `packages/design-system/forms/components/` — `AssetInput`, `PartyHeader`, `EmbeddedAgreement`, `TransactionActionButton`, `ExpiryCard`, `SummaryBox`.
- `packages/design-system/forms/fields/{DateInputField,FormSelectField,FormSelectOrInputField}.tsx`.
- `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/{SignLexscrowAgreement,ExecuteLexscrowAgreement}.tsx` — countersign + deposit/finalize.
- `apps/web/src/app/(frame-layout)/lexscrow/_hooks/{useFeeBasisPoints,useEscrowBalance,useLexscrowsForAddress,useAgreementDetails,useSignedAgreement,useReadFees}.ts` — read-side hooks.
- `apps/cybercorps-web/src/features/rounds/forms/CreateRoundForm.tsx` — round configuration; the closest precedent for cyberTRADE's exemption/template selection UX (it picks a `templateId` and an extension contract per round).
- `apps/cybercorps-web/src/features/rounds/hooks/{useSubmitEOI,useAllocate,useCloseRoundNow}.ts` — flow patterns and Wagmi usage.
- `apps/cybercorps-web/src/features/api/lexchex/useLexchexForAddress.ts` — credential check; the model for the new `useLegionSoulboundForAddress`.
- `apps/cybercorps-web/src/features/forms/form-builder/helpers/extensionData.ts` — extension encoder dispatch; add `encodeFundInterestExtensionData`.
- `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx` — GP cap‑table view; the basis for GP monitoring.
- `apps/cybercorps-indexer/ponder.schema.ts` — indexer schema; new `offer`, `offer_acceptance`, `fix_trade_receipt`, `user_spv_entitlement`, `user_seasoning` tables go here.
- `apps/cybercorps-indexer/src/api/{rounds,deals,cybercerts,cybercorps}/...-routes.ts` — REST route patterns; new `offers-routes.ts` follows them.

These pointers, plus the structural changes in §3–§11, are the bridge from the v2.04 spec to a working implementation that fits the cybercorps protocol and the metalex webapp as they exist today.
