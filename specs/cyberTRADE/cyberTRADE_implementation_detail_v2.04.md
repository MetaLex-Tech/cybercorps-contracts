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

This document adopts a **unified settlement pathway** for all secondary trades, regardless of either party's custody mode. The pathway treats metadata mutation (mutate-and-mint via `IssuanceManager`) as the universal legally operative act, consistent with the cyberCORPs Bylaws and spec §2's statement that "no change in record ownership shall be deemed to occur solely by virtue of any transfer of any Blockchain Token." The ERC‑721 transfer mechanic that distinguishes the spec's "Pathway A" from "Pathway E" is dropped from the default secondary settlement flow; only the buyer's payment is escrowed. The seller's cert never moves between wallets during settlement. Custody mode affects only one thing: where the buyer's newly minted cert is delivered. See §3.4 for the per‑SPV `settlementMode` opt-in that preserves the legacy NFT‑escrow flow for deployments whose counsel specifically wants it.

### 3.1 The current routing — verified

`src/DealManager.sol` and `src/libs/LexScroWLite.sol`:

- `Escrow.corpAssets[]` are minted at `proposeDeal` time (or staged from existing inventory) and on `finalizeEscrow()` are pushed to `escrow.counterParty`.
- `Escrow.buyerAssets[]` are pulled from `counterParty` in `handleCounterPartyPayment()` and on `finalizeEscrow()` are routed to `ICyberCorp(LexScrowStorage.getCorp()).companyPayable()`, with `computeFee(...)` taken off the top into `IDealManagerFactory(factory).getPlatformPayable()`.

There is **no party role for "seller"**. The routing is purely positional. For a primary issuance this is fine — the company is selling, and `companyPayable` is the right destination. For a secondary trade, the seller is another LP and `companyPayable` is the wrong destination; additionally, `corpAssets` should not be transferred at finalize because the buyer's new cert is freshly minted, not handed over from the seller.

The minimal change is twofold: redirect `buyerAssets` to the seller (already in the spec at §12B.1(a) as the `tradeType` flag), **and** make `corpAssets` empty for secondary trades, with the ownership change executed by a separate `IssuanceManager.executeSecondaryTransfer` call within the finalize transaction.

### 3.2 Concrete change set in `cybercorps-contracts`

1. **`src/storage/DealManagerStorage.sol`**: extend `Escrow`:

   ```solidity
   enum TradeType { PRIMARY_ISSUANCE, SECONDARY_TRADE }

   struct SecondaryTransferIntent {
       uint256 sellerCertId;
       uint256 units;
       address buyer;             // counterParty (also stored at top level)
       bool    isFullSale;        // void seller cert if true; decrement if false
       bytes32 agreementId;
       bytes8  exemptionBasis;
   }

   struct Escrow {
       /* existing fields ... */
       TradeType tradeType;
       address sellerAddress;     // populated only when tradeType == SECONDARY_TRADE
       address feeDestination;    // §3.3 — integrator share recipient, 0 = no split
       bytes32 offerId;           // §4 — link back to OfferRegistry (0 if none)
       SecondaryTransferIntent xferIntent;  // populated only for SECONDARY_TRADE
   }
   ```

   For SECONDARY_TRADE escrows, `corpAssets` is **always empty**. The asset side of the trade is encoded in `xferIntent` and executed by `IssuanceManager` at finalize.

2. **`src/DealManager.sol`** — add the entry point that `OfferRegistry.acceptOffer` calls:

   ```solidity
   function proposeSecondaryDeal(
       address seller,
       address buyer,
       address paymentToken,
       uint256 paymentAmount,
       uint256 sellerCertId,
       uint256 units,
       bool    isFullSale,
       bytes32 agreementId,                 // already finalized in CyberAgreementRegistry
       address[] memory conditions,
       uint256 expiry,
       address feeDestination,              // §3.3
       bytes32 offerId,
       bytes8  exemptionBasis
   ) external returns (bytes32 dealId);
   ```

   This function: (a) sets `tradeType = SECONDARY_TRADE`, `sellerAddress = seller`, `feeDestination = feeDestination`, `offerId = offerId`; (b) populates `xferIntent`; (c) leaves `corpAssets` empty; (d) declares `buyerAssets = [{token: paymentToken, amount: paymentAmount, isFee: true}]`. No assets are minted at proposal time.

3. **`src/libs/LexScroWLite.sol::finalizeEscrow`** — branch on `tradeType`:

   ```solidity
   if (escrow.tradeType == TradeType.SECONDARY_TRADE) {
       // 1) Compute and pay the fee split (§3.3).
       // 2) Transfer (paymentAmount - protocolFee) to escrow.sellerAddress.
       // 3) Call IssuanceManager.executeSecondaryTransfer(escrow.xferIntent, buyer custody mode).
       //    This decrements/voids the seller's cert and mints the buyer's new cert.
       // 4) Skip the corpAssets transfer block entirely (corpAssets is empty).
   } else {
       // existing primary-issuance flow: corpAssets to counterParty, buyerAssets to companyPayable
   }
   ```

4. **No NFT deposit step.** Under the unified pathway, the only deposit is the buyer's payment. The DealManager does not call `handleCounterPartyPayment` for any cert, only for the payment token. The webapp's deposit view has only one row for the buyer; the seller has no deposit step at all (§10.4).

5. **`IssuanceManager.executeSecondaryTransfer` — the new finalize-time entry point.** See §8 below for the full mechanics. In summary: it (a) appends the seller's pre‑signed endorsement (from §4) to the seller's cert as the chain‑of‑title record (or recognizes that the endorsement was already added at `acceptOffer` time — see §4.3), (b) voids or decrements the seller's cert per `isFullSale`, (c) calls `safeMintAndAssign` to mint the buyer's new cert with destination address chosen by the buyer's custody mode, (d) appends a mirror endorsement on the new cert pointing back to the seller's cert and the agreement. All in one transaction.

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

### 3.4 Per‑SPV `settlementMode` — escape hatch for NFT escrow

The unified pathway works for all the standard cases discussed in the spec. A small number of deployments may want the legacy NFT‑escrow flow — for example, if a particular SPV's counsel insists on a DTC‑style "depository holds the asset, settlement instructs book entry" model where the escrow contract literally custodies the cert during pendency. To preserve that option:

```solidity
// On the SPV's cyberCORP or its DealManager
enum SettlementMode { UNIFIED, NFT_ESCROW }
SettlementMode settlementMode; // default UNIFIED, set per-SPV at onboarding
```

When `settlementMode == NFT_ESCROW`:

- `OfferRegistry.acceptOffer` for a Direct Custody seller routes through the legacy Pathway A flow: the seller is prompted to deposit the cert (after a split for partial sales), the cert lives in `LexScroWLite` during pendency, and `finalizeEscrow` transfers the cert to the buyer plus reconciles `OwnerDetails` via `_update`.
- Administered Custody sellers under `NFT_ESCROW` mode still use the unified pathway, because there is no cert to escrow (the cert is already in the multisig). There is no useful third option.

For the initial deployment, all SPVs use `UNIFIED`. `NFT_ESCROW` is designed for, not built. Add it when a deployment's counsel specifically requests it. The dispatch in `LexScroWLite.finalizeEscrow` is a single additional branch and does not complicate the unified-mode path.

### 3.5 Partial sales

Under the unified pathway, partial sales need no split-first step. At finalize, `IssuanceManager.executeSecondaryTransfer`:

- Decrements `unitsRepresented` on the seller's existing cert via `updateCertificateDetails` (and updates `FundInterestExtension` fields as needed).
- Mints a new cert to the buyer for the sold units via `safeMintAndAssign`.

Both operations happen in the same transaction as payment release. No intermediate cert exists; no extra signature is required from the seller for the split (the seller's pre‑signed endorsement at `postOffer` time authorizes the units to be carved off as part of the trade — see §4.2). Under the legacy `NFT_ESCROW` mode (§3.4), the spec's existing "split first, then escrow the new cert" sequence applies.

### 3.6 Per‑token restriction hooks (§12B.2)

`src/CyberCertPrinter.sol::_update`, lines around 257–264 in the current source, has the per‑token hook block commented out. The `restrictionHooksById` mapping exists in storage and has a setter, but `_update` does not evaluate it; only `globalRestrictionHook` is active.

Required minimal change:

```solidity
ITransferRestrictionHook tokenHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
if (address(tokenHook) != address(0)) {
    (bool allowed, string memory reason) = tokenHook.checkTransferRestriction(from, to, tokenId, "");
    if (!allowed) revert TransferRestricted(reason);
}
```

Uncomment, deploy, and document that per-token hooks now fire on every transfer. Under the unified pathway, the seller's cert is not transferred during settlement (it is voided or decremented in place), so per‑token hooks fire only when the seller separately tries to move their cert during pendency or post-settlement. The endorsement-lock added at `acceptOffer` (§4.3) provides the pendency-period transfer protection for Direct Custody sellers via the existing `endorsementRequired` check in `_update`; per‑token hooks are an additional configurable gate the GP can use for cert-specific policies (e.g., affiliate-specific restrictions).

The `FundInterestExtension.restrictionHookOverride` field (§1.4) is the per‑token hook address; this only becomes meaningful when the uncomment lands.

---

## 4. `OfferRegistry` — New Protocol Primitive (§12B.8 made concrete)

There is no precursor in the codebase. The proposed contract sits between the user's signed posting transaction and `DealManager.proposeSecondaryDeal`. It is intentionally **lean**: the spec is clear that visibility is gated at the UI layer (§4.4, §11.1B), not on‑chain, so this contract does **not** hold a permission ACL on who can read offers. Anyone can read; whether the webapp surfaces a given offer to a given user is decided by Legion's UI + LeXcheX.

This document adopts the **binding-offer model** (Architecture B in the design discussion): the seller's posting signature is the legally operative offer, signed against a partially-populated trade agreement in `CyberAgreementRegistry`. The buyer's `acceptOffer` signature completes mutual assent and forms the binding contract. The on-chain condition set (`ICondition`) operates as **conditions precedent to performance**, not to formation — if a condition fails between acceptance and settlement expiry, performance is excused and assets return to their owners. See §4.5 for the framing and §4.6 for the QMS-mode deferral.

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

    // Contract-formation linkage (binding-offer model, §4.5)
    bytes32 agreementId;                 // CyberAgreementRegistry record created at postOffer,
                                         // signed by offeror as party A, openToMatching = true

    // Pre-signed endorsement (§4.3 — required for unified settlement, §3)
    bytes   offerorEndorsementSignature; // EIP-712 signature by offeror over OPEN_ENDORSEMENT
                                         // typed data: {offerId, certId, units, agreementId, validUntil}
                                         // No endorsee fixed at posting — bound to "any qualifying
                                         // counterparty who accepts this offer" by reference to offerId.
}
```

External functions:

```solidity
function postOffer(
    address spv,
    OfferSide side,
    uint256 tokenIdOrZero,
    uint256 units,
    address paymentToken,
    uint256 consideration,
    ExemptionPathway exemptionPathway,
    uint64  validUntil,
    CounterpartyRestrictions calldata restrictions,
    bytes calldata additionalTerms,
    address integrator,
    string[] calldata partyAValues,         // populated party-A side of the agreement
    bytes calldata offerorAgreementSignature,// EIP-712 signature over the agreement digest
    bytes calldata offerorEndorsementSignature// EIP-712 signature over the open-endorsement digest (§4.3)
) external returns (bytes32 offerId);

function cancelOffer(bytes32 offerId) external;   // offeror or BorgAuth admin

function acceptOffer(
    bytes32 offerId,
    uint256 unitsAccepted,
    string[] calldata partyBValues,      // buyer's reps, acknowledgments, attestations
    bytes calldata acceptorSignature     // EIP-712 signature; completes the agreement
) external returns (bytes32 dealId);

function getOffer(bytes32 offerId) external view returns (Offer memory);
```

### 4.2 What `postOffer` does

The seller's posting is structurally a signed irrevocable offer (subject to `validUntil` and to `cancelOffer` before any acceptance). Two signatures are collected at posting, both EIP‑712 typed:

- the **agreement signature** — the seller's party‑A signature on the partially-populated trade agreement, used by `CyberAgreementRegistry.createOpenAgreement`;
- the **open‑endorsement signature** — the seller's signature on an open endorsement intent (§4.3 below), used by `IssuanceManager.executeSecondaryTransfer` at finalize to record an attested chain‑of‑title entry on the seller's cert.

Both are produced by the seller's wallet in one signing step at "Sign and Post Offer" in the webapp; the EIP‑712 typed-data presentation bundles them so the seller sees and authorizes both in a single user action.

Concretely the function:

1. Validates seller eligibility and ownership:
   - For `SELL`: caller is the registered owner of `interestEntryTokenId` (via `OwnerDetails.ownerAddress` for Administered Custody, or `IERC721.ownerOf` for Direct Custody — read both, accept either). This is the "no phantom sells" rule from spec §4.4.
   - SPV is registered (a mapping of approved cyberCORP addresses, owner‑managed initially).
   - `integrator`, if non‑zero, is `approvedIntegrators[integrator]` on `DealManagerFactory`.
   - `paymentToken` is on a per‑SPV allowlist (USDC/USDT initially, configured per cyberCORP).

2. Creates a partially-signed trade agreement record:
   - Calls `CyberAgreementRegistry.createOpenAgreement(templateId = templateFor(exemptionPathway), partyA = offeror, partyAValues, partyASignature = offerorAgreementSignature, expiry = validUntil, openToMatching = true)`.
   - The agreement record now has `parties = [offeror]`, `signedAt[offeror] = block.timestamp`, `finalized = false`, `openToMatching = true`. It is **waiting for any qualifying party B to attach** (§7 below).

3. Stores the `Offer` struct, including `offerorEndorsementSignature`, with the returned `agreementId` and `status = LIVE`. Emits `OfferPosted(offerId, agreementId, ...)`.

**What `postOffer` does *not* do.** It does not lock the seller's asset. It does not transfer anything. It does not write to the seller's cert. It does not bind the seller against canceling — `cancelOffer` is callable by the offeror until an acceptance lands, and acts as a withdrawal of the offer in the standard contract-law sense, retracting both the agreement signature and the endorsement signature in one operation. Once `acceptOffer` lands, the cancellation right ends; the offer has been accepted and the contract is formed.

### 4.3 The open‑endorsement signature — what the seller is signing

The cert's `Endorsement` struct (`src/CyberCertPrinter.sol`) carries `{endorser, timestamp, signatureHash, registry, agreementId, endorsee, endorseeName}`. The cyberCORPs Bylaws describe endorsement as the registered owner's act authorizing transfer to a named endorsee. Under the binding-offer model, the endorsee is not known at posting — the seller is offering to "any qualifying counterparty." The seller's pre‑signed endorsement is therefore an **open endorsement** in the commercial-law sense: it is signed without naming a specific endorsee, and is bound to a particular offer (and through the offer's `counterpartyRestrictions`, to a particular class of qualifying counterparties) by reference to the `offerId`.

This is analogous to an indorsement in blank or an indorsement to bearer in negotiable‑instruments law — the indorsement is the holder's authorization that the instrument is transferable in accordance with the indorsement's terms; the actual taker is determined by who properly performs in accordance with those terms.

The EIP‑712 typed data the seller signs:

```
struct OpenEndorsement {
    bytes32 offerId;
    address spvCyberCorp;
    uint256 certId;
    uint256 units;
    bytes32 agreementId;
    bytes8  exemptionBasis;
    uint64  validUntil;
}
```

At `acceptOffer` (§4.4), the IssuanceManager assembles the full `Endorsement` struct by combining the seller's pre‑signed `signatureHash` with the now-known buyer's address and name (from LeXcheX), and writes the endorsement to the seller's cert. The endorsement is the legal record that the seller — by signature — authorized the transfer to the party who satisfied the offer's terms. Any auditor or counsel reviewing the chain of title can recover the seller's signature against the OpenEndorsement typed data and verify it.

### 4.4 What `acceptOffer` does

`acceptOffer` is the single contract-formation event and the moment when the seller's pre‑signed endorsement is materialized onto the cert. In one transaction:

1. Validates the offer is `LIVE` and within `validUntil`. Validates `unitsAccepted ≤ unitsOffered − unitsAccepted_already`.
2. Validates the acceptor satisfies `restrictions`. The on‑chain check is structural: jurisdiction credentials, accreditation, QP, Soulbound category/tier — all queried via the LeXcheX adapter (`creds/` directory in the contracts repo — `LeXcheXAdapter.sol` exists; cyberTRADE adds a `LegionSoulboundAdapter.sol` for the Soulbound NFT category check).
3. **Completes the trade agreement.** Calls `CyberAgreementRegistry.attachAndSignAsPartyB(agreementId, partyB = msg.sender, partyBValues, partyBSignature = acceptorSignature)`. The registry verifies the EIP-712 signature, appends `msg.sender` to `parties`, records `signedAt[msg.sender]`, and sets `finalized = true`, `openToMatching = false`. From this transaction onward, `AgreementSignedCondition.checkCondition(...)` returns true. **The contract is now binding on both sides.**
4. **Materializes the seller's endorsement on the cert (endorsement‑lock).** Calls `IssuanceManager.attachOpenEndorsement(offerId, certId, units, endorsee = msg.sender, endorseeName = leXcheXNameLookup(msg.sender))`. The IssuanceManager (under its standing BorgAuth role) constructs the full `Endorsement` struct using `signatureHash = offer.offerorEndorsementSignature` (the pre‑signed open endorsement from §4.3), `endorser = offer.offeror`, `registry = CyberAgreementRegistry`, `agreementId = offer.agreementId`, `timestamp = block.timestamp`, and the now‑known `endorsee` and `endorseeName`. The endorsement is appended to the seller's cert via `addEndorsement`. The seller's cert printer has `endorsementRequired = true`, so the `_update` hook will now reject any transfer of this cert to anyone other than `msg.sender` (the buyer). For Direct Custody this is a real transferability lock; for Administered Custody the cert never moves anyway, but the endorsement is still added because it is the chain‑of‑title record.
5. Calls `DealManager.proposeSecondaryDeal(...)` with the offer's pathway → maps to the appropriate `ICondition[]` set (built per `ExemptionPathway`), `feeDestination = integrator`, `offerId = offerId`, and the just-finalized `agreementId`. The DealManager records the escrow with `tradeType = SECONDARY_TRADE`, `sellerAddress = offeror`, `counterParty = msg.sender`, `xferIntent` populated. `corpAssets` is empty.
6. Returns the new `dealId`. Emits `OfferAccepted(offerId, dealId, acceptor, unitsAccepted)`.
7. Updates `status` to `PARTIALLY_ACCEPTED` or `FULLY_ACCEPTED` and increments `unitsAccepted`.

**Implication:** the seller signs once (at posting, covering both agreement and endorsement). The buyer signs once (at acceptance, covering the agreement). The endorsement on the seller's cert is materialized at acceptance using the seller's pre‑signed signature. There is no separate "seller countersigns the agreement" step and no separate "seller signs the endorsement after buyer is known" step. The flow downstream of `acceptOffer` is: buyer deposit → `TimeSettlementPeriod` clock → conditions clear → finalize. The buyer's deposit is performance of the buyer's payment obligation under an already-formed contract; the metadata mutation at finalize (§8) is performance of the seller's transfer obligation under the same contract.

**On void / cancel.** If the deal voids by expiry or by mutual `signToVoid`, the IssuanceManager appends a `voidEndorsement` record to the seller's cert that supersedes the prior endorsement‑lock. The `_update` hook treats a superseded endorsement as released; the cert is freely transferable again. The original endorsement remains in the array as a historical record of the attempted trade.

The mapping from `ExemptionPathway` to `ICondition[]` is the same configuration the DealManager already accepts on `proposeDeal`. For example:

| Pathway | Mandatory conditions added at acceptance |
|---|---|
| `RULE_144` | `HoldingPeriodCondition`, `KYCAMLCondition`, `Rule144DisclosureCondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A7` | `AccreditedInvestorCondition`, `KYCAMLCondition`, `Section4a7DisclosureCondition`, `ERISACondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A1_HALF` | adds `LegalOpinionCondition` to the 4(a)(7) set |
| `RULE_144A` | `QualifiedInstitutionalBuyerCondition` instead of `AccreditedInvestorCondition` |
| `REG_S` | `NonUSPersonCondition`, `RegSDistributionComplianceCondition` instead of accreditation; no ERISA |

Per‑SPV additions (e.g., `QualifiedPurchaserCondition` for 3(c)(7) funds, `CFIUSCondition` for non‑fund‑exception SPVs, `LegionSoulboundCondition` for syndicate gating) are configured on the SPV's `DealManager` and inherited automatically — `OfferRegistry` does not need to know about them.

### 4.5 Contract-formation model

The architecture above treats the offer-and-acceptance flow as ordinary contract formation, with the on-chain condition set serving as conditions precedent to performance rather than to formation.

**Seller's posting signature.** Alice's `postOffer` is a binding offer in the contract-law sense. It is an irrevocable commitment by Alice to sell the specified units at the specified consideration to *any* counterparty who (a) satisfies the offer's stated counterparty restrictions, (b) provides the buyer-side reps and acknowledgments the agreement requires, and (c) accepts within `validUntil`. "Irrevocable" is qualified only by Alice's right of withdrawal via `cancelOffer` before any acceptance — the standard right to withdraw an unaccepted offer.

**Buyer's acceptance signature.** Bob's `acceptOffer` is acceptance. Because the trade agreement template at issuance already contains Alice's filled-in party-A side and her signature, Bob's signature completes mutual assent in the same transaction that attaches him as party B. The agreement record in `CyberAgreementRegistry` transitions from `openToMatching = true, finalized = false` to `openToMatching = false, finalized = true` atomically. The contract is binding from this transaction.

**Conditions as conditions precedent to performance.** Every `ICondition` attached to the `DealManager` for this trade — accredited investor, KYC/AML, Soulbound, holder cap, tax info, Reg S compliance, ERISA, etc. — operates as a condition precedent to *settlement*, not to *contract formation*. The contract exists from the moment of acceptance. If a condition fails by the deal's expiry, performance is excused, the escrow voids, and assets return to their owners. This is consistent with standard commercial-contract drafting in which conditions to closing are distinct from offer-and-acceptance.

**Why this maps cleanly onto the existing primitives.** The `DealManager` already supports this structure: it accepts a deal with a condition set, allows deposits, evaluates conditions at finalization, and voids on expiry if conditions fail. `LexScroWLite`'s `PENDING → PAID → FINALIZED` machine and its void/refund branches are the contract-law structure of "contract formed, performance pending, performance either completes or is excused" expressed in code. No additional state machine is required.

**What the seller's offer says, in substance.** A plain-English rendering of the offer Alice signs at `postOffer`:

> I, Alice, irrevocably offer to sell N units of SPV X for the consideration C in payment token T to any person who: (i) satisfies the counterparty restrictions specified herein, (ii) provides the buyer-side representations and acknowledgments enumerated in the attached trade agreement, and (iii) accepts this offer through the OfferRegistry protocol on or before `validUntil`. Acceptance is effected by countersigning the trade agreement and depositing the consideration into the protocol escrow. Performance of my transfer obligation is subject to the satisfaction of the conditions enumerated in the escrow's condition set; failure of any such condition by the deal expiry shall excuse performance and void the transaction. This offer may be withdrawn by me via `cancelOffer` at any time before acceptance.

That is a perfectly conventional binding conditional offer. The protocol mechanizes it.

**Where the buyer's substantive duties live.** The buyer-side reps and acknowledgments are encoded as `partyBValues` on the agreement (not as separate clicks or transactions). Bob's single EIP-712 signature at `acceptOffer` covers all of them. Examples by exemption pathway:

| Pathway | Buyer-side `partyBValues` (representative) |
|---|---|
| `SECTION_4A7` | Accredited investor representation; receipt-of-information-package acknowledgment; ERISA negative attestation; tax info (W-9/W-8BEN) reference |
| `SECTION_4A1_HALF` | Sophistication and information access representation; investment-intent representation |
| `RULE_144` | Acknowledgment of restricted status; acknowledgment of acquisition-date reset |
| `RULE_144A` | QIB status representation; 144A basis acknowledgment |
| `REG_S` | Non-U.S. person representation; jurisdiction attestation; distribution-compliance-period acknowledgment |

In every case, one signature from the buyer covers the full set; the conditions then verify the substantive truth of the attestations at settlement (LeXcheX queries, registry lookups). The webapp's Acceptance view surfaces each rep as a checkbox or rendered clause so the buyer is meaningfully consenting; the on-chain signature is over the agreed text.

### 4.6 QMS mode — deferred enhancement

The model in §4.1–§4.5 is fast: one seller signature, one buyer signature, 24-hour `TimeSettlementPeriod`, settlement. It does **not** preserve the Qualified Matching Service safe harbor under Treas. Reg. §1.7704-1(g), which requires (i) no binding agreement entered into during the first 15 calendar days after listing and (ii) no closing within 45 calendar days of listing. Under the binding-offer model, acceptance forms a binding agreement on day 0, which is incompatible with the 15-day rule.

This is an explicit and considered trade-off:

- **3(c)(1) funds** (the dominant initial use case): the §7704 risk is structurally bounded by the private-placement safe harbor (Treas. Reg. §1.7704-1(h), 100-partner ceiling), which `HolderCapCondition` enforces by construction. QMS is not required.
- **3(c)(7) funds** (later use case): the 100-partner safe harbor is unavailable. PTP risk is managed by the 2% de minimis safe harbor (which active trading may exceed) and by the facts-and-circumstances analysis discussed in spec §6.7 (Davis Polk and Holland & Knight non-PTP opinions). Active 3(c)(7) deployments may want QMS available as a backstop.
- **Future LP-interest secondaries with high turnover** or with counsel opinions requiring belt-and-suspenders treatment may also want QMS.

For these reasons, **QMS mode is architected for but not built in the initial deployment**. The implementation contract is preserved by the following design notes; actual code lands later, on demand:

1. **Per-SPV (or per-offer) `qmsMode` flag.** A boolean stored on the SPV's `OfferRegistry` configuration (or on the offer itself). Default `false`.
2. **`qmsListedAt` timestamp.** When `qmsMode = true`, `postOffer` records `qmsListedAt = block.timestamp` on the offer.
3. **`AgreementSignedCondition` behavior.** Extends to consult `qmsListedAt`: returns `true` only when `block.timestamp >= qmsListedAt + 15 days` *and* the agreement is finalized. Under QMS mode the buyer's `acceptOffer` still attaches and signs party B, but the agreement record is held in a `qmsCoolOff` substate (`finalized = false, qmsCoolOffUntil = qmsListedAt + 15 days`); after the 15 days elapse, the agreement transitions to `finalized = true` automatically on the next read (or via a no-cost transition function). This preserves the regulation's "no binding agreement entered into during the 15 calendar day period" language.
4. **`TimeSettlementPeriodCondition` parameterization.** Already supports an arbitrary `delaySeconds`. Under QMS mode, set per-SPV to `max(24h, 45 days − (qmsCoolOffElapsed))` so total time from listing to settlement is ≥45 days.
5. **Webapp deal-flow timeline.** The Acceptance and Deposit views render QMS-mode timelines distinctly (a real, multi-week timeline rather than a 24-hour wait). This is a pure UI change on top of the contract-level configuration.

Until and unless QMS mode is built, the initial deployment runs purely in the binding-offer mode of §4.1–§4.5. The spec's §11.1B should be updated to reflect this stance: the platform relies on the private-placement safe harbor for 3(c)(1) funds and on facts-and-circumstances for 3(c)(7) funds in the initial deployment, with QMS held as a configurable future enhancement when a deployment's risk profile demands it.

### 4.7 Visibility lives at the UI layer; compliance lives at settlement

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

The spec assumes Path 3 (Hybrid). Under the unified settlement pathway adopted in §3, custody mode has a much smaller footprint than the spec's two-pathway framing suggests: it determines only **where the cert is delivered at mint time**, not how settlement runs. The existing CertPrinter primitives are sufficient; the only new artifact is a per-cert flag recording the elected mode.

**Mechanic:**

- **Administered Custody.** The cert's ERC‑721 `ownerOf` is the ledger administrator's multisig. `OwnerDetails.ownerAddress` is the LP. `OwnerDetails.name` is the LP's name. The cert never moves between wallets, ever — not on primary issuance (mint to multisig), not on secondary trade (the seller's cert stays in the multisig; the buyer's new cert is minted to the multisig with the buyer as `OwnerDetails.ownerAddress`).
- **Direct Custody.** `IERC721.ownerOf` and `OwnerDetails.ownerAddress` are the same address (the LP's wallet). Mints go to the LP's wallet. The cert does not move during secondary settlement (it is voided or decremented in place), but the LP retains the option to scripify, collateralize, or otherwise act on the cert outside of cyberTRADE — subject to the endorsement‑lock during any pending trade (§4.4) and to whatever transfer‑restriction hooks the GP has configured.

**Per‑cert flag:** `FundInterestExtension.custodyMode` (a `CustodyMode` enum: `ADMINISTERED | DIRECT`). Set at mint time (primary issuance from the LP's election in the cyberRAISE subscription flow; secondary settlement from the buyer's election in the prospective‑buyer onboarding flow). Read by `IssuanceManager.executeSecondaryTransfer` to decide the mint destination.

**Settlement implication:** under the unified pathway, the seller's custody mode does **not** branch the settlement code path. The seller's cert is mutated in place regardless. The buyer's custody mode is read once, by `IssuanceManager.executeSecondaryTransfer`, to choose the `to` address for `safeMintAndAssign` — multisig or buyer wallet. That is the entire settlement-time effect of custody election.

**Why the spec's Pathway A vs Pathway E distinction collapses.** Under the cyberCORPs Bylaws and spec §2, the legally operative act of transfer is the metadata mutation, not the ERC‑721 transfer. Pathway A's ERC‑721 escrow‑and‑transfer was an *additional* bookkeeping operation on top of the metadata mutation, executed only for Direct Custody. Dropping that bookkeeping leaves both custody modes settling through identical primitives. The asymmetry that remains — "where does the new cert physically sit?" — is a delivery question, not a settlement question. See §3.4 for the per‑SPV `settlementMode = NFT_ESCROW` opt‑in that preserves Pathway A for deployments whose counsel specifically wants on‑chain NFT escrow.

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

### 7.1 `openToMatching` agreements — small but necessary extension

The binding-offer model in §4 requires a small additive capability on `CyberAgreementRegistry`: the ability to create an agreement record that is signed by party A but **left open for any qualifying party B to attach and sign**, until a counterparty does so or the offer expires. This is the only piece the current registry does not already do; otherwise the template, signing, finalization, and delegation surfaces are reused unchanged.

Required additions to `src/CyberAgreementRegistry.sol`:

```solidity
struct AgreementData {
    /* existing fields ... */
    bool   openToMatching;        // true while waiting for a counterparty to attach
    bytes32 partyADigest;         // EIP-712 digest party A signed over (for re-verification on attach)
}

function createOpenAgreement(
    bytes32 templateId,
    address partyA,
    string[] calldata partyAValues,
    string[] calldata globalValues,
    bytes calldata partyASignature,
    uint64 expiry,
    address finalizer            // the OfferRegistry / DealManager that will close the agreement
) external returns (bytes32 agreementId);

function attachAndSignAsPartyB(
    bytes32 agreementId,
    address partyB,
    string[] calldata partyBValues,
    bytes calldata partyBSignature
) external;                       // callable only by the registered finalizer (OfferRegistry)
```

Semantics:

- `createOpenAgreement` is called by `OfferRegistry.postOffer`. It computes the EIP-712 digest from the template, global values, and party-A values; verifies `partyASignature` recovers to `partyA`; stores the agreement with `parties = [partyA]`, `signedAt[partyA] = block.timestamp`, `openToMatching = true`, `finalized = false`. The agreement is irrevocably bound by party A's signature, conditional only on a qualifying party B's attachment within `expiry`.
- `attachAndSignAsPartyB` is called by `OfferRegistry.acceptOffer` (the registered `finalizer`). It computes the buyer-side EIP-712 digest, verifies `partyBSignature` recovers to `partyB`, appends `partyB` to `parties`, records `signedAt[partyB]`, sets `openToMatching = false` and `finalized = true`, and emits `AgreementFinalized`.
- The existing `voidAgreement` flow still applies if both parties later agree to void, or if the deal voids by expiry (the registry registers `voided = true` and the `AgreementSignedCondition` then returns false).
- Delegation continues to work: a party A delegate signs `partyASignature` on Alice's behalf, and the EIP-712 recovery resolves through the `Delegation` mapping.

The `attachAndSignAsPartyB` access control — "only the registered finalizer can call" — is what guarantees that the agreement transitions to finalized only as part of an `OfferRegistry.acceptOffer` flow that has already validated the acceptor's counterparty restrictions. A bare-call to `attachAndSignAsPartyB` from outside the offer flow reverts.

This capability is small enough to add as an additive change to `CyberAgreementRegistry` without breaking any existing primary-issuance subscription flow, which continues to use `createContract` (both parties known up-front).

The template registration happens in a deploy script under `script/RegisterTradeAgreementTemplates.s.sol`. Per-trade population happens inside `OfferRegistry.postOffer` (which knows the seller, the exemption pathway, and the `globalValues` from the offer + the SPV's stored disclosure URIs) and inside `OfferRegistry.acceptOffer` (which fills in `partyBValues` and finalizes).

---

## 8. Ledger Mutation Mechanics — `IssuanceManager.executeSecondaryTransfer`

Under the unified settlement pathway (§3), every secondary trade — regardless of either party's custody mode, regardless of full vs partial sale — settles through a single new entry point on `IssuanceManager`. The function is called from `DealManager.finalizeEscrow` (or `signAndFinalizeDeal`) inside the same transaction as payment release.

### 8.1 Signature and access control

```solidity
function executeSecondaryTransfer(
    SecondaryTransferIntent calldata intent,  // from the DealManager escrow
    address buyer,
    string  calldata buyerName,               // from LeXcheXNameLookup
    CustodyMode buyerCustodyMode,             // from buyer's profile
    address ledgerAdministratorMultisig       // 0 if buyerCustodyMode == DIRECT
) external returns (uint256 newCertId);
```

Access control via BorgAuth: only addresses holding the `SECONDARY_TRANSFER_ROLE` on the SPV's BorgAuth can call. The role is granted, at SPV onboarding, exclusively to the SPV's `DealManager`. No other contract or EOA holds it. This is the structural authorization that the cyberCORPs Bylaws contemplate when they vest the issuer-administrator with the authority to mutate the register.

### 8.2 What it does — five steps, one transaction

1. **Resolve the buyer name.** If `buyerName` is empty, call `LeXcheXNameLookup.nameOf(buyer)` to read the buyer's KYC‑verified legal name. The lookup is gated to be readable only by IssuanceManager during a finalize call (preserves PII privacy).

2. **Append the chain‑of‑title endorsement on the seller's cert (if not already present).**

   Under the standard flow (§4.4), the endorsement was already materialized at `acceptOffer` time using the seller's pre‑signed open‑endorsement signature, and it is sitting on the seller's cert as the endorsement‑lock. At finalize, the IssuanceManager checks for the existing endorsement matching `intent.agreementId` and, if present, leaves it in place — the existing endorsement is the chain‑of‑title artifact for this transfer.

   If the existing endorsement is somehow missing (e.g., a future flow that didn't pre-sign at posting), the IssuanceManager constructs the endorsement from the trade-agreement data and appends it now. This is a fallback branch and is not exercised by the normal flow.

3. **Mutate the seller's cert per `intent.isFullSale`.**
   - Full sale: call `voidCert(intent.sellerCertId)`. Sets `SecurityStatus.Void`. The cert remains on chain as an immutable historical record; its endorsement array (with the just-confirmed transfer endorsement) provides the chain-of-title bridge to the new cert.
   - Partial sale: call `updateCertificateDetails(intent.sellerCertId, ...)` to decrement `unitsRepresented` by `intent.units` and update the `FundInterestExtension.lastTrade` field on the seller's remaining cert (recording the partial transfer in FIX form). `OwnerDetails` on the seller's cert is unchanged — Alice is still the registered owner of the remainder.

4. **Mint the buyer's new cert.** Call `safeMintAndAssign(to, name, ownerAddress, certDetails)` where:
   - `to = (buyerCustodyMode == ADMINISTERED) ? ledgerAdministratorMultisig : buyer` — the ERC‑721 host address.
   - `name = buyerName` — the buyer's legal name written into `OwnerDetails.name`.
   - `ownerAddress = buyer` — the buyer's wallet address written into `OwnerDetails.ownerAddress`. **This is the registered owner regardless of where the cert physically sits.**
   - `certDetails` populates `unitsRepresented = intent.units`, `signingOfficerName/Title` from the SPV's officer config, `legalDetails` with a reference to the voided/decremented source cert, and `extensionData` encoded from a fresh `FundInterestData` with `acquisitionDate = block.timestamp`, applicable `tackedFromAcquisitionDate` if the trade agreement asserts tacking, restriction legends per the exemption pathway, and a populated `lastTrade` FIX record.

5. **Append a mirror endorsement on the new cert.** Call `addEndorsement(newCertId, {endorser: intent.sellerAddress, signatureHash: <ref to seller's open-endorsement>, registry: CyberAgreementRegistry, agreementId: intent.agreementId, endorsee: buyer, endorseeName: buyerName, timestamp: block.timestamp})`. This makes the buyer's new cert self‑describing: looking at the cert alone reveals its origin (which agreement, which seller, which voided/decremented predecessor cert) without requiring a separate registry lookup.

   For Administered Custody, the endorser slot may instead be filled with the ledger administrator multisig as the operational executor, with the seller's signature still attached as `signatureHash` — preserving the seller's pre-signed authorization as the legal anchor while reflecting that the multisig is the holder of record. The choice is configurable per SPV.

6. **Emit events.** `SecondaryTransferExecuted(intent.agreementId, intent.sellerCertId, newCertId, intent.sellerAddress, buyer, intent.units, intent.isFullSale)`. The DealManager separately emits `DealFinalized` and `FIXTradeReceipt` (§9).

### 8.3 Verified codebase facts the implementation honors

1. **Uses `safeMintAndAssign`, not `safeMint`.** `CyberCertPrinter.safeMint` leaves `OwnerDetails.name` empty; `safeMintAndAssign` populates it and emits `CertificateAssigned`. Every cyberTRADE settlement mint goes through `safeMintAndAssign`. The spec calls this out in §7.5; the unified pathway makes it the only mint path for secondary settlements.

2. **`OwnerDetails` is set at mint time, not reconciled at transfer.** Under the unified pathway, the buyer's new cert is minted with `OwnerDetails.ownerAddress = buyer` from the start. There is no `_update` reconciliation step at settlement (the cert is not transferred between wallets at settlement — the cert is brand new). This sidesteps the `OwnerDetails` staleness problem the spec flags for Pathway E.

3. **`updateOwnerDetails` is not needed for normal secondary settlement.** The spec's proposed `updateOwnerDetails(tokenId, newOwner, newName)` admin function (for Pathway E reconciliation) becomes unnecessary under the unified pathway, because the buyer's cert is freshly minted. The function may still be useful for the Pathway F admin escape hatch (§7.4A spec) — keep it on the wish‑list for admin tooling but it is not on the cyberTRADE secondary settlement critical path.

4. **`addEndorsement` access control.** Currently callable by either `IssuanceManager` or current `ownerOf(tokenId)`. The unified pathway always calls it via `IssuanceManager.executeSecondaryTransfer`, so the `ownerOf` branch is irrelevant for cyberTRADE settlement. Existing primary‑issuance and admin flows that use the `ownerOf` branch are unaffected.

### 8.4 What is unchanged

- The buyer's new cert exists from settlement onward and can be queried by its tokenId.
- The seller's cert exists from settlement onward in either void or decremented state; its endorsement array points to the new cert via the agreement ID and the transfer endorsement.
- The chain of title is fully reconstructable from any cert by walking the endorsement array, looking up agreements by ID in `CyberAgreementRegistry`, and traversing voided certs.
- All other CertPrinter primitives (`certLegend`, `securityStatus`, `tokenTransferable`, restriction hooks) are unchanged in semantics and continue to apply to the new cert from minting onward.

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
- `TransactionActionButton` for "Sign and Post Offer", calling `OfferRegistry.postOffer` via `useWriteContract` (Wagmi), with the same react‑hook‑form + Zod pattern. Per the binding-offer model (§4.5), the seller's signing step at posting produces **two EIP‑712 signatures presented in a single typed‑data payload**: (a) the signature on the partially-populated trade agreement (party A), and (b) the signature on the open endorsement (§4.3, authorizing transfer of the offered units to whichever qualifying counterparty accepts). The wallet shows both signatures in one bundled EIP‑712 prompt; the user experiences it as one signing action. The seller will not be asked to sign again at any later step.

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
- a single "Sign and Accept" action that signs an EIP-712 payload covering both the offer acceptance and the buyer-side reps/attestations (§4.5). This is the only buyer signature in the flow. It hits `OfferRegistry.acceptOffer`, which (a) attaches and signs the open agreement via `CyberAgreementRegistry.attachAndSignAsPartyB`, finalizing the contract, and (b) opens the escrow on `DealManager.proposeSecondaryDeal`. There is no separate countersign step — the seller's offer-posting signature already covered party A.

### 10.4 Deposit + Settlement view

Closely modeled on `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/ExecuteLexscrowAgreement.tsx`. CyTE's `ExecuteLexscrowAgreement` already handles the deposit + finalize sequence under `LexScroWLite`. cyberTRADE simplifies it considerably under the unified pathway (§3):

- **Only the buyer has a deposit step**, regardless of seller's or buyer's custody mode. The deposit is the payment token (USDC / USDT / etc.). The seller has no deposit step at all — there is no NFT escrow in the unified pathway (§3). The seller's contribution to settlement is the pre‑signed open endorsement attached at `acceptOffer` (§4.4), which is already on chain.
- The status dashboard shows: agreement finalized (✓ at acceptance), endorsement‑lock active on seller's cert (✓ at acceptance), buyer payment deposited (pending → ✓), all conditions passing (live evaluation), `TimeSettlementPeriod` elapsed (countdown timer, default 24 hours), ready to finalize.
- The "Settle" action is **hidden by default**: the keeper service (§10.4 of the spec) calls `signAndFinalizeDeal` once `TimeSettlementPeriodCondition` clears. A "Settle manually" affordance is shown if the keeper hasn't fired within a configurable grace period; this preserves user agency without putting the keeper in the trust path.
- **Per‑SPV `settlementMode = NFT_ESCROW` rendering (deferred).** If a future SPV elects the legacy NFT-escrow mode (§3.4), the deposit view conditionally renders the seller's "approve and deposit Ledger Entry Token" step for Direct Custody sellers. This is a UI branch behind a feature flag; not built in the initial deployment because no SPV has been configured with `NFT_ESCROW`.

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
- **QMS mode (§4.6).** Architected for via the `qmsMode` flag on offers, `qmsListedAt` timestamp, and the cool-off behavior on `AgreementSignedCondition` and `TimeSettlementPeriodCondition`. Not built in the initial deployment. The initial deployment relies on the §1.7704‑1(h) private-placement safe harbor for 3(c)(1) funds and on facts-and-circumstances analysis for 3(c)(7) funds. Build QMS mode when (i) a 3(c)(7) deployment with high turnover lands, or (ii) counsel for a particular SPV requires the belt-and-suspenders treatment.

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
9. **§7.3 contract-formation model — binding-offer adoption.** The spec's §7.3 describes a sequential "seller proposes, buyer countersigns" agreement flow that, in conjunction with the §11.1B QMS timing constraints (15-day no-binding-agreement period), implies two seller signatures. This detail document adopts **Architecture B (binding-offer model, §4.5)** for the initial deployment: the seller's `postOffer` signature is the legally operative offer on a partially-populated trade agreement, and the buyer's `acceptOffer` signature attaches to and finalizes the same agreement in one transaction. Conditions are conditions precedent to performance, not to formation. This collapses the trade-formation flow from two seller signatures to one, at the cost of forgoing QMS safe-harbor qualification. The trade-off is acceptable because (i) the initial pipeline is 3(c)(1) funds where the private-placement safe harbor handles §7704 by construction and (ii) QMS mode is preserved as a configurable future enhancement (§4.6). When the spec is next revised, §7.3 should be reframed to describe the binding-offer flow as the default and QMS as the opt-in. Spec §11.1B's QMS treatment should be re-titled "Future Enhancement: QMS Mode" rather than the primary regulatory posture.
10. **`CyberAgreementRegistry.createOpenAgreement` / `attachAndSignAsPartyB` (§7.1).** The current `CyberAgreementRegistry` requires both parties' addresses at `createContract` time. The binding-offer model requires the ability to create an agreement signed by party A while leaving party B open until any qualifying counterparty attaches. This is a small additive change to the registry and does not alter the existing primary-issuance flow (which continues to use `createContract`).
11. **§7.4A pathway taxonomy — unified pathway adoption.** The spec's §7.4A enumerates six settlement pathways (A: escrow + transfer, B: endorsement + transfer, C: scrip intermediation, D: void + mint, E: metadata mutation, F: admin force transfer) and recommends Pathway A/B+A for Direct Custody and Pathway E for Administered Custody. This detail document adopts a **unified settlement pathway (§3, §8)** that effectively merges Pathway B (the seller's pre‑signed open endorsement) with Pathway D/E (void‑or‑decrement + fresh mint by IssuanceManager) for both custody modes. The motivation is structural symmetry: the cyberCORPs Bylaws and spec §2 both state that metadata mutation is the legally operative act and the ERC‑721 transfer is bookkeeping; the unified pathway treats them that way universally. Pathway A is retained as the per‑SPV `settlementMode = NFT_ESCROW` opt‑in (§3.4) for deployments whose counsel specifically wants on‑chain NFT escrow. Pathway F remains the off‑trade admin escape hatch. Spec §7.4A's pathway table should be revised in the next edit to lead with the unified pathway and treat A/B/C as alternative configurations rather than custody‑mode defaults.
12. **Pre‑signed open endorsement at `postOffer`.** The cyberCORPs `Endorsement` struct (`src/CyberCertPrinter.sol`) requires `endorsee` to be a known address. The binding-offer + unified-pathway architecture requires the seller to authorize transfer at posting, when the endorsee is not yet known. This detail document introduces the **open endorsement** pattern (§4.3): the seller signs an EIP-712 `OpenEndorsement` typed structure that omits the endorsee but binds the authorization to a specific `offerId`; at `acceptOffer`, the IssuanceManager combines the seller's pre-signed `signatureHash` with the now-known buyer's address and name to materialize the full `Endorsement` struct on the cert. This mirrors negotiable-instruments-law "indorsement in blank" and preserves the seller as the legal endorser of record, even though the writing of the endorsement to the cert is performed by the IssuanceManager under BorgAuth. No change to the on-chain `Endorsement` struct is required; only the `IssuanceManager.attachOpenEndorsement` entry point and the OfferRegistry's storage of the pre-signed signature. The cyberCORPs Bylaws may want a small drafting update to acknowledge that endorsements may be pre-signed in open form when authorizing transfer through the OfferRegistry/DealManager flow.

---

## 14. Sequenced Delivery Plan

A pragmatic order of work that lets each step ship independently:

1. **`FundInterestExtension`** + encoding helpers in webapp. Mergeable; immediately unblocks primary issuance of fund interests through cyberRAISE.
2. **`acquisitionDate` / `tackedFromAcquisitionDate` plumbing** in the extension and the round‑close flow (cyberRAISE side). Tested by minting fund certs and asserting the date is the round close date, not the mint date.
3. **Activate per‑token restriction hooks** in `CyberCertPrinter._update`. Behind a printer-level feature flag if needed to avoid disturbing existing deployments.
4. **`GlobalKillCondition` + `TimeSettlementPeriodCondition`**. Deployed and attached‑by‑default by `DealManagerFactory`. No behavioral effect on primary issuance because they pass when not raised / once delay elapses.
5. **`DealManagerFactory` integrator whitelist + per‑deal `feeDestination`**. No behavioral change to existing deployments because `defaultIntegrator == 0` and `feeDestination == 0` keep the legacy flow.
6. **`DealManager` secondary trade mode** (`tradeType`, `sellerAddress`, `xferIntent`, payment-only escrow, payment routing to seller, fee split — §3.2). `corpAssets` empty for secondary trades; no NFT deposit step.
7. **`IssuanceManager.executeSecondaryTransfer`** entry point (§8). BorgAuth‑gated to the SPV's DealManager. Implements the unified mutate‑and‑mint with endorsement‑lock and FIX stamping. The `attachOpenEndorsement` helper that `OfferRegistry.acceptOffer` calls also lives in `IssuanceManager`.
8. **`CyberAgreementRegistry` additive surface** (`createOpenAgreement`, `attachAndSignAsPartyB`, `openToMatching` flag — §7.1). No change to existing `createContract` flow; primary issuance unaffected.
9. **Trade agreement templates** registered in `CyberAgreementRegistry`.
10. **Remaining `ICondition` implementations** (Holding period, accredited, KYC, ERISA, NonUS, RegS, holder cap, tax info, Soulbound, CFIUS, price anomaly, GPLP approval, 4(a)(7) disclosure, Rule 144 disclosure, legal opinion, 144A QIB).
11. **`OfferRegistry`** contract (§4), including the pre‑signed open‑endorsement signature storage and the `acceptOffer` → `attachOpenEndorsement` + `attachAndSignAsPartyB` + `proposeSecondaryDeal` orchestration.
12. **Indexer schema additions** (Ponder).
13. **Webapp UI**: offer builder → discovery → acceptance → deposit/settlement → GP monitoring. Components inherited from `ProposeLexscrowAgreementForm`, `SignLexscrowAgreement`, `ExecuteLexscrowAgreement`, `CertsTable`, `useLexchexForAddress`, `useFeeBasisPoints`. EIP‑712 typed‑data bundling at `postOffer` (agreement signature + open‑endorsement signature in one wallet prompt) is the only new signing pattern.
14. **Keeper + FIX receipt event consumer**.
15. **Pathway F admin panel** for void / force transfer / Global Kill governance.

Items 1–4 are protocol upgrades with no functional change to existing flows; they can land on `main` without coordinating with the webapp. Item 5 is the first change that requires coordinated webapp release (the integrator address must be supplied somewhere). Items 6–11 are the secondary‑trade core; items 12–15 are the UI / operations layer. The legacy NFT‑escrow opt-in (§3.4) and QMS mode (§4.6) are deferred enhancements that ride on top of this sequence and are not built in the initial deployment.

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
