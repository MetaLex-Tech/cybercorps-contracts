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

### 3.4 Per‑SPV settlement configuration knobs

Three per-SPV configuration flags govern variations in how secondary trades behave for a given SPV. All three default to the simple/fast case; all three are designed for at the protocol layer and either built or deferred at deployment time. They are set on the SPV's cyberCORP (or DealManager) at onboarding and are not changed thereafter without a coordinated migration.

| Flag | Default | Alternative | Effect |
|---|---|---|---|
| `settlementMode` | `UNIFIED` | `NFT_ESCROW` | UNIFIED: payment-only escrow; ownership change via `IssuanceManager.executeSecondaryTransfer` (§8). NFT_ESCROW: legacy Pathway A — Direct Custody sellers also deposit the cert into `LexScroWLite`; the cert transfers to the buyer at finalize. Built when a deployment's counsel specifically wants on-chain NFT escrow. |
| `qmsMode` | `false` | `true` | Default: agreement finalizes at `acceptOffer`. QMS mode: agreement enters a 15-day cool-off and only finalizes after `qmsListedAt + 15 days`; `TimeSettlementPeriodCondition` extended so total time from listing to settlement is ≥45 days. Preserves Treas. Reg. §1.7704‑1(g) QMS safe harbor. See §4.7. Built when a 3(c)(7) deployment or counsel opinion demands QMS. |
| `endorserOfRecord` | `SELLER` | `LEDGER_ADMINISTRATOR` | SELLER (default): the `Endorsement.endorser` field on the seller's cert records the seller's address — the natural reading of "the registered owner endorsed this transfer to the named endorsee," with the seller's signature attached as `signatureHash` and the IssuanceManager only the on-chain executor. LEDGER_ADMINISTRATOR: the administrator multisig is recorded as `endorser` (operational executor of record), with the seller's signature still attached as `signatureHash`. Useful for SPVs whose counsel prefers the administrator be the named endorser on the cert and the seller's authorization be referenced through the signature. |

**`settlementMode = NFT_ESCROW`** — the legacy NFT-escrow opt-in. The unified pathway works for all the standard cases discussed in the spec. A small number of deployments may want the legacy NFT‑escrow flow — for example, if a particular SPV's counsel insists on a DTC‑style "depository holds the asset, settlement instructs book entry" model where the escrow contract literally custodies the cert during pendency. When `settlementMode == NFT_ESCROW`:

- `OfferRegistry.acceptOffer` for a Direct Custody seller routes through the legacy Pathway A flow: the seller is prompted to deposit the cert (after a split for partial sales), the cert lives in `LexScroWLite` during pendency, and `finalizeEscrow` transfers the cert to the buyer plus reconciles `OwnerDetails` via `_update`.
- Administered Custody sellers under `NFT_ESCROW` mode still use the unified pathway, because there is no cert to escrow (the cert is already in the multisig). There is no useful third option.

For the initial deployment, all SPVs use the defaults (`UNIFIED`, `qmsMode = false`, `endorserOfRecord = SELLER`). The non-default branches are designed for, not built. Add them when a specific deployment's counsel or operating model requires them. The dispatch is a single additional branch in each affected code path and does not complicate the default-mode behavior.

### 3.5 Partial sales

Under the unified pathway, partial sales need no split-first step. At finalize, `IssuanceManager.executeSecondaryTransfer`:

- Decrements `unitsRepresented` on the seller's existing cert via `updateCertificateDetails` (and updates `FundInterestExtension` fields as needed).
- Mints a new cert to the buyer for the sold units via `safeMintAndAssign`.

Both operations happen in the same transaction as payment release. No intermediate cert exists; no extra signature is required from the seller for the split (the seller's pre‑signed endorsement at `postOffer` time authorizes the units to be carved off as part of the trade — see §4.2). Under the legacy `NFT_ESCROW` mode (§3.4), the spec's existing "split first, then escrow the new cert" sequence applies.

### 3.6 Per‑token restriction hooks (§12B.2)

**Hooks vs conditions — architectural distinction worth flagging.** The codebase has two orthogonal gating layers that this document occasionally conflates:

| Layer | Contract type | Lives on | Fires when | Examples |
|---|---|---|---|---|
| **Restriction hooks** (`ITransferRestrictionHook`) | Hook contract | Cert printer (global or per-token) | ERC-721 `_update` runs (token movement) | `ToggleTransferHook`, `WhitelistTransferHook` |
| **Conditions** (`ICondition`) | Condition contract | DealManager escrow or other operation context | Operation finalize runs (settlement, scrip conversion) | All §5 conditions; `LexChexCondition`; `NonUSNationalityCondition` |

Hooks gate **token movement**; conditions gate **operations**. Under the unified pathway the seller's cert does not move during settlement, so the per-token restriction hook layer is mostly inactive during a normal cyberTRADE settlement — but it remains the correct layer for ad-hoc cert-specific transfer restrictions the GP wants to enforce (affiliate locks, jurisdiction restrictions on a specific cert, etc.). The two layers are deliberately separate; keep them so.

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

This document adopts the **binding-offer model** (Architecture B in the design discussion): the offeror's posting signature is the legally operative offer (either a sell offer or a bid), signed against a partially-populated trade agreement in `CyberAgreementRegistry`. The acceptor's `acceptOffer` signature completes mutual assent and forms the binding contract. The on-chain condition set (`ICondition`) operates as **conditions precedent to performance**, not to formation — if a condition fails between acceptance and settlement expiry, performance is excused and assets return to their owners. See §4.5 for the symmetric buy-side / sell-side treatment, §4.6 for the contract-formation framing, and §4.7 for the QMS-mode deferral.

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

    // Contract-formation linkage (binding-offer model, §4.6)
    bytes32 agreementId;                 // CyberAgreementRegistry record created at postOffer,
                                         // signed by offeror as party A, openToMatching = true

    // Sell-side commitment (populated only when side == SELL; §4.3)
    bytes   offerorEndorsementSignature; // EIP-712 signature by offeror over OPEN_ENDORSEMENT
                                         // typed data: {offerId, certId, units, agreementId, validUntil}
                                         // No endorsee fixed at posting — bound to "any qualifying
                                         // counterparty who accepts this offer" by reference to offerId.

    // Buy-side commitment (populated only when side == BUY; §4.5)
    bytes32 bidCommitmentEscrowId;       // dealId of the LexScroWLite holding escrow that custodies
                                         // the bidder's payment tokens at postOffer time. Refunded on
                                         // cancel/expiry; consumed into the trade's settlement escrow
                                         // at acceptOffer.
}
```

External functions:

```solidity
function postOffer(
    address spv,
    OfferSide side,
    uint256 tokenIdOrZero,                   // sell only; 0 for bids
    uint256 units,
    address paymentToken,
    uint256 consideration,
    ExemptionPathway exemptionPathway,
    uint64  validUntil,
    CounterpartyRestrictions calldata restrictions,
    bytes calldata additionalTerms,
    address integrator,
    string[] calldata partyAValues,          // populated party-A side of the agreement
    bytes calldata offerorAgreementSignature,// EIP-712 signature over the agreement digest
    bytes calldata offerorEndorsementSignature// SELL only — EIP-712 over open-endorsement digest (§4.3)
                                             // For BUY, pass empty bytes; bid commitment is the
                                             // payment-token deposit consumed in the same call (§4.5)
) external returns (bytes32 offerId);

function cancelOffer(bytes32 offerId) external;   // offeror or BorgAuth admin

function acceptOffer(
    bytes32 offerId,
    uint256 unitsAccepted,
    string[] calldata partyBValues,          // acceptor's reps, acknowledgments, attestations
                                             // For SELL offers (buyer accepts): buyer-side fields
                                             // For BUY offers (seller accepts): seller-side fields
    bytes calldata acceptorAgreementSignature,// EIP-712 signature; completes the agreement
    bytes calldata acceptorEndorsementSignature// BUY only — seller (acceptor) signs the open
                                             // endorsement at acceptance time. Pass empty bytes for
                                             // SELL acceptances; the seller's endorsement was
                                             // already pre-signed at postOffer (§4.5).
) external returns (bytes32 dealId);

function getOffer(bytes32 offerId) external view returns (Offer memory);
```

### 4.2 What `postOffer` does

A posted offer (whether `SELL` or `BUY`) is structurally a signed irrevocable offer subject to `validUntil` and to `cancelOffer` before any acceptance. The mechanics differ between the two sides only in what asset the offeror commits and how. Two EIP‑712 signatures are always collected at posting:

- the **agreement signature** — the offeror's party‑A signature on the partially-populated trade agreement (party A fields are the *seller* fields when `side == SELL`, the *buyer* fields when `side == BUY`);
- a **side-specific commitment** — for `SELL`, the open‑endorsement signature (§4.3); for `BUY`, a payment-token deposit into a holding escrow (§4.5).

Both are produced by the offeror's wallet in one signing step at "Sign and Post Offer / Post Bid" in the webapp; the EIP‑712 typed-data presentation bundles them so the user sees and authorizes both in a single user action.

Concretely the function:

1. **Validates offeror eligibility and the asset side.**
   - For `SELL`: caller is the registered owner of `interestEntryTokenId` (via `OwnerDetails.ownerAddress` for Administered Custody, or `IERC721.ownerOf` for Direct Custody — read both, accept either). This is the "no phantom sells" rule from spec §4.4. `offerorEndorsementSignature` must be non‑empty; recovers to the offeror against the `OpenEndorsement` typed data (§4.3).
   - For `BUY`: caller has approved `OfferRegistry` (or the holding-escrow contract) to pull `consideration` of `paymentToken`. `offerorEndorsementSignature` must be empty. The bid's seller-side restrictions (if any — e.g., "only registered owners of cert IDs in {x,y,z}") are encoded in `restrictions.explicitAllowlist` or `additionalTerms`.
   - SPV is registered (a mapping of approved cyberCORP addresses, owner‑managed initially). SPV registration also requires the SPV's `CyberCertPrinter` to have `endorsementRequired = true` set globally — see the precondition note below.
   - `integrator`, if non‑zero, is `approvedIntegrators[integrator]` on `DealManagerFactory`.
   - `paymentToken` is on a per‑SPV allowlist (USDC/USDT initially, configured per cyberCORP).

   **Precondition: `endorsementRequired = true` on the SPV's cert printer.** The endorsement-lock that protects against the seller transferring their cert during pendency (§4.4) depends on `CyberCertPrinter._update` enforcing the `endorsementRequired` check — i.e., rejecting any transfer whose recipient does not match the most recent endorsement's endorsee. If a cyberCORP's cert printer has `endorsementRequired = false`, the materialized endorsement at `acceptOffer` is recorded but is not enforced as a transfer lock, and a Direct Custody seller could move the cert to a third party during pendency, breaking the trade. The OfferRegistry's SPV-registration function (`registerSPV(cyberCorp)`) must therefore check that the cyberCORP's cert printer has `endorsementRequired = true` (read via `CyberCertPrinter.endorsementRequired()`), and revert otherwise. Existing SPVs without this configuration must enable it before being registered; for SPVs that never want the secondary-trade flow, the precondition does not apply.

2. **Creates a partially-signed trade agreement record.** Calls `CyberAgreementRegistry.createOpenAgreement(templateId = templateFor(exemptionPathway), partyA = offeror, partyAValues, partyASignature = offerorAgreementSignature, expiry = validUntil, openToMatching = true)`. The agreement record now has `parties = [offeror]`, `signedAt[offeror] = block.timestamp`, `finalized = false`, `openToMatching = true`. It is **waiting for any qualifying party B to attach** (§7). The agreement template internally maps "party A / party B" to "seller / buyer" or "buyer / seller" based on which side posted, so the same template files render correctly for either initiation direction.

3. **Captures the side-specific commitment.**
   - For `SELL`: stores `offerorEndorsementSignature` on the Offer; no asset moves at posting time. The seller's cert is not endorsed yet; the endorsement is materialized at `acceptOffer` (§4.4).
   - For `BUY`: opens a holding escrow on `LexScroWLite` by calling an `OfferRegistry`-internal helper that pulls `consideration` of `paymentToken` from the bidder into an escrow keyed by the new `offerId`. Stores the resulting `bidCommitmentEscrowId` on the Offer. The bidder's funds are now custodied by the protocol; they will either be (a) consumed into the trade's settlement escrow at `acceptOffer`, (b) refunded to the bidder on `cancelOffer` or `validUntil` expiry.

4. **Stores the Offer struct** with the returned `agreementId` and `status = LIVE`. Emits `OfferPosted(offerId, agreementId, side, bidCommitmentEscrowId, ...)`.

**What `postOffer` does *not* do.** For `SELL`: it does not lock the seller's asset (no on-chain write to the cert); the seller is bound by signature, not by escrow. For `BUY`: it does lock the bidder's payment token via the holding escrow. Both sides remain free to `cancelOffer` until an acceptance lands; cancellation retracts the agreement signature, releases any pre‑signed endorsement, and refunds the bid commitment if one was deposited. Once `acceptOffer` lands, the cancellation right ends; the offer has been accepted and the contract is formed.

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

`acceptOffer` is the single contract-formation event. The mechanics are side‑aware: which party fills which side of the agreement, and which side's open commitment is materialized at acceptance, depends on whether the offer is `SELL` or `BUY`. The underlying logic is fully symmetric (see §4.5 for the symmetric statement).

In one transaction:

1. **Validates the offer is `LIVE` and within `validUntil`.** Validates `unitsAccepted ≤ unitsOffered − unitsAccepted_already`.
2. **Validates the acceptor's eligibility.** Structural on‑chain check via the LeXcheX adapter (`creds/LeXcheXAdapter.sol`) and the `LegionSoulboundAdapter` — jurisdiction credentials, accreditation, QP, Soulbound category/tier, etc. For `SELL` offers the acceptor must satisfy the buyer-side restrictions in `restrictions`; for `BUY` offers the acceptor must be a registered owner of a cert satisfying the bid's terms (and any seller-side filters in `restrictions` or `additionalTerms`).
3. **Completes the trade agreement.** Calls `CyberAgreementRegistry.attachAndSignAsPartyB(agreementId, partyB = msg.sender, partyBValues, partyBSignature = acceptorAgreementSignature)`. The registry verifies the EIP-712 signature, appends `msg.sender` to `parties`, records `signedAt[msg.sender]`, and sets `finalized = true`, `openToMatching = false`. From this transaction onward, `AgreementSignedCondition.checkCondition(...)` returns true. **The contract is now binding on both sides.**
4. **Materializes the seller's endorsement on the seller's cert (endorsement‑lock).** This step always runs, but the source of the open‑endorsement signature differs by side:
   - For `SELL` offers (offeror is seller; acceptor is buyer): `signatureHash = offer.offerorEndorsementSignature` — the seller's signature pre‑signed at `postOffer` (§4.3). `endorsee = msg.sender` (the buyer); `endorser = offer.offeror` (the seller).
   - For `BUY` offers (offeror is buyer; acceptor is seller): `signatureHash = acceptorEndorsementSignature` — the seller's signature **provided at acceptance time** (the acceptor's `OpenEndorsement` bundle, signed in the same EIP‑712 typed-data prompt that produced `acceptorAgreementSignature`). `endorsee = offer.offeror` (the buyer); `endorser = msg.sender` (the seller, accepting the bid).

   In both cases the IssuanceManager constructs the full `Endorsement` struct using `registry = CyberAgreementRegistry`, `agreementId = offer.agreementId`, `timestamp = block.timestamp`, the resolved endorsee name from LeXcheX, and appends it to the seller's cert via `addEndorsement`. The seller's cert printer has `endorsementRequired = true`, so `_update` will reject any subsequent transfer of this cert to anyone other than the named endorsee. For Direct Custody this is the pendency-period transferability lock; for Administered Custody the cert never moves anyway, but the endorsement is still added as the chain‑of‑title record.
5. **Settles the asset commitments into the trade's settlement escrow.**
   - For `SELL` offers: the buyer (acceptor) must subsequently deposit payment into the trade's `LexScroWLite` escrow as a separate user action (§10.4). The buyer's commitment is not yet on chain at `acceptOffer`; it is collected immediately afterward and the trade voids on expiry if the buyer fails to deposit.
   - For `BUY` offers: the bidder's payment is already in a holding escrow (`offer.bidCommitmentEscrowId`) from `postOffer`. `acceptOffer` calls a `LexScroWLite` helper to **migrate** those funds from the holding escrow into the trade's settlement escrow in the same transaction. No separate buyer deposit step is needed — the buyer's commitment was already locked at posting time. The seller's "acceptance" thus immediately produces a `PAID`-state settlement escrow.
6. **Calls `DealManager.proposeSecondaryDeal(...)`** with the offer's pathway → maps to the appropriate `ICondition[]` set (built per `ExemptionPathway`), `feeDestination = integrator`, `offerId = offerId`, and the just-finalized `agreementId`. The DealManager records the escrow with `tradeType = SECONDARY_TRADE`, `sellerAddress`, `counterParty`, `xferIntent` populated. `corpAssets` is empty. `sellerAddress` is `offer.offeror` for SELL offers and `msg.sender` for BUY offers; `counterParty` is `msg.sender` for SELL offers and `offer.offeror` for BUY offers.
7. Returns the new `dealId`. Emits `OfferAccepted(offerId, dealId, acceptor, unitsAccepted)`. Updates `status` to `PARTIALLY_ACCEPTED` or `FULLY_ACCEPTED` and increments `unitsAccepted`.

**Implication.** Every secondary trade involves exactly two EIP‑712 bundles: a seller bundle (agreement-seller-side signature + open-endorsement signature on the seller's cert) and a buyer bundle (agreement-buyer-side signature + payment commitment). On a `SELL` offer the seller bundle is signed at `postOffer` and the buyer bundle is split across `acceptOffer` + a subsequent payment deposit. On a `BUY` offer the buyer bundle is signed and committed at `postOffer` and the seller bundle is signed at `acceptOffer`. The flow downstream of `acceptOffer` is identical in both cases: `TimeSettlementPeriod` clock → conditions clear → finalize via `IssuanceManager.executeSecondaryTransfer` (§8).

**On void / cancel.** If the deal voids by expiry or by mutual `signToVoid`, the IssuanceManager appends a `voidEndorsement` record to the seller's cert that supersedes the prior endorsement‑lock. The `_update` hook treats a superseded endorsement as released; the cert is freely transferable again. For voids of BUY-initiated trades that reached `acceptOffer`, the buyer's funds are released from the trade's settlement escrow back to the bidder. The original endorsement remains in the cert's array as a historical record of the attempted trade.

The mapping from `ExemptionPathway` to `ICondition[]` is the same configuration the DealManager already accepts on `proposeDeal`. For example:

| Pathway | Mandatory conditions added at acceptance |
|---|---|
| `RULE_144` | `HoldingPeriodCondition`, `KYCAMLCondition`, `Rule144DisclosureCondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A7` | `AccreditedInvestorCondition`, `KYCAMLCondition`, `Section4a7DisclosureCondition`, `ERISACondition`, `HolderCapCondition`, `TaxInfoCondition`, `AgreementSignedCondition`, `GlobalKillCondition`, `TimeSettlementPeriodCondition` |
| `SECTION_4A1_HALF` | adds `LegalOpinionCondition` to the 4(a)(7) set |
| `RULE_144A` | `QualifiedInstitutionalBuyerCondition` instead of `AccreditedInvestorCondition` |
| `REG_S` | `NonUSPersonCondition`, `RegSDistributionComplianceCondition` instead of accreditation; no ERISA |

Per‑SPV additions (e.g., `QualifiedPurchaserCondition` for 3(c)(7) funds, `CFIUSCondition` for non‑fund‑exception SPVs, `LegionSoulboundCondition` for syndicate gating) are configured on the SPV's `DealManager` and inherited automatically — `OfferRegistry` does not need to know about them.

### 4.5 Buy-side parity: bids and seller acceptance

The OfferRegistry surface is symmetric: trades can be initiated from either side. A holder can post a sell offer that a qualifying buyer accepts; a prospective buyer can post a bid that a qualifying seller accepts. The downstream protocol flow from `acceptOffer` through finalization is identical in both directions. The mechanics differ only in *what is committed at posting* and *what is collected at acceptance*. This subsection states the symmetric model in one place so the asymmetries are not buried inside §4.2 / §4.4 branches.

**The two bundles, irrespective of side.** Every secondary trade requires exactly two EIP‑712 bundles to come together:

| Bundle | Signed by | Contents | Function |
|---|---|---|---|
| **Seller bundle** | The seller | (a) agreement-seller-side signature; (b) `OpenEndorsement` signature authorizing transfer of `units` from the seller's cert to whichever counterparty fulfills the offer | Authorizes ownership change of the cert and binds the seller as party A or B of the agreement |
| **Buyer bundle** | The buyer | (a) agreement-buyer-side signature; (b) payment-token commitment (deposited into a holding escrow for bid postings, into the trade settlement escrow for sell-offer acceptances) | Authorizes payment and binds the buyer as party A or B of the agreement |

Whichever side **posts** signs and commits its bundle at `postOffer`. Whichever side **accepts** signs and commits its bundle at `acceptOffer`. There are no other cases. The seller is always the legal endorser of record on the cert, regardless of who initiated the trade; the buyer is always the funder, regardless of who initiated the trade.

**Bid posting walkthrough.** Bob is a prospective buyer. He posts a bid for 200 units of SPV X at 50,000 USDC.

1. **Sign and Post Bid.** Bob's wallet signs an EIP‑712 typed-data bundle: (a) agreement-buyer-side signature on the 4(a)(7) trade agreement template (his accreditation rep, ERISA negative attestation, information-package acknowledgment, tax-info covenant); (b) approval to pull 50,000 USDC from his wallet.
2. **`OfferRegistry.postOffer(side = BUY, ..., offerorEndorsementSignature = empty, ...)`.** The registry: (a) calls `CyberAgreementRegistry.createOpenAgreement` with Bob as party A and his buyer-side signature; (b) opens a `LexScroWLite` holding escrow keyed by the new `offerId` and pulls Bob's 50,000 USDC into it; (c) stores the `Offer` struct with `bidCommitmentEscrowId` set, `offerorEndorsementSignature` empty, `status = LIVE`.
3. **Discovery.** The bid is surfaced through the indexer to whitelisted, eligible registered owners of SPV X interests who hold ≥200 units (filter computed by the indexer; §4.8).
4. **Alice (eligible registered owner) chooses to fill the bid.** She opens the Bid Acceptance view in the webapp. She reviews the agreement and the bid terms. The compliance checklist for her side runs (holding period elapsed, no affiliate flag, no Reg-S distribution-compliance issue, etc.). She clicks "Sign and Accept Bid."
5. **Her wallet signs an EIP‑712 bundle:** (a) agreement-seller-side signature; (b) `OpenEndorsement` signature on her cert authorizing transfer of 200 units to Bob (the offeror). The endorsee is known here because the bidder is identified from posting — this differs from the sell-side flow where the endorsement is signed before the counterparty is known.
6. **`OfferRegistry.acceptOffer(offerId, units = 200, partyBValues = sellerFields, acceptorAgreementSignature, acceptorEndorsementSignature)`.** The registry: (a) calls `CyberAgreementRegistry.attachAndSignAsPartyB` to finalize the agreement; (b) calls `IssuanceManager.attachOpenEndorsement` to materialize Alice's endorsement on her cert (endorser = Alice, endorsee = Bob, signatureHash = `acceptorEndorsementSignature`); (c) migrates Bob's 50,000 USDC from the holding escrow into the trade's settlement escrow; (d) calls `DealManager.proposeSecondaryDeal(seller = Alice, buyer = Bob, ...)`. The escrow opens in `PAID` state immediately (no separate buyer deposit step — the funds were already committed at posting).
7. **From here, the flow is identical to a sell-initiated trade.** `TimeSettlementPeriod` clock starts, conditions evaluate, keeper finalizes after 24h, `IssuanceManager.executeSecondaryTransfer` does the mutate‑and‑mint.

**Asymmetries summary.**

| Step | Sell offer (seller posts) | Bid (buyer posts) |
|---|---|---|
| `postOffer` signature bundle | Seller bundle (agreement A + open endorsement) | Buyer bundle (agreement A + USDC commitment) |
| `postOffer` on-chain state change | Offer recorded; agreement openToMatching; cert untouched | Offer recorded; agreement openToMatching; USDC pulled into holding escrow |
| `acceptOffer` signature bundle | Buyer bundle (agreement B + USDC approval) | Seller bundle (agreement B + open endorsement) |
| `acceptOffer` on-chain state change | Agreement finalized; cert endorsed via pre-signed signature; trade escrow opens; awaiting buyer deposit | Agreement finalized; cert endorsed via signature signed at acceptance; trade escrow opens in `PAID` state |
| Buyer payment deposit | Separate step after `acceptOffer` (§10.4) | Already deposited at `postOffer`; migrated at `acceptOffer` |
| Side of `restrictions` filter | Counterparty (buyer) eligibility — accredited, QP, non‑US, Soulbound badge, explicit allowlist | Counterparty (seller) eligibility — most typical case is open to any registered owner with no extra filter (any holder of ≥ `units` of the named SPV can fill); for targeted bids, `restrictions.explicitAllowlist` selects specific sellers; niche filters (non‑affiliate, syndicate badge held) reuse existing `restrictions` fields or ride on `additionalTerms`. The existing `CounterpartyRestrictions` struct serves both sides without extension. |
| Cancel-before-acceptance | Releases endorsement intent; no funds movement | Refunds bid commitment from holding escrow |
| Counterparty visibility filter (UI/indexer, §4.8) | Surface to eligible buyers | Surface to eligible registered owners |

Everything below the dashed line of `acceptOffer` is shared code: same `ICondition` set, same `TimeSettlementPeriodCondition`, same keeper, same `IssuanceManager.executeSecondaryTransfer`, same FIX receipt emission, same fee split. The unified settlement pathway in §3 and §8 is side-agnostic by construction.

**Webapp implications.** §10.1 distinguishes "Post Sell Offer" and "Post Bid" entry points but shares the underlying form components (`AssetInput`, `EmbeddedAgreement`, `CounterpartyRestrictionsInput`). §10.3 (acceptance view) similarly renders both directions; the only visible difference is which side's reps appear in the buyer-bundle vs seller-bundle review and whether the acceptor's "Sign and Accept" prompts for a payment approval (sell-offer acceptance) or an endorsement signature (bid acceptance). §10.4 (deposit + settlement view) is degenerate for bid-initiated trades — the escrow is already in `PAID` state at acceptance, so the view skips the buyer deposit step and goes straight to the conditions / settlement timer.

**Bid-commitment yield: none.** The bidder's payment tokens sit in the `LexScroWLite` holding escrow as principal-only, idle. The protocol does not deposit them into yield-bearing venues during the bid's pendency, and the bidder does not earn yield while their commitment is outstanding. This keeps the holding-escrow mechanics simple, avoids exposing bidder principal to DeFi venue risk, and avoids tax-character complications (yield earned on funds posted as a §4(a)(7) trade commitment is awkward to classify). Bidders should size their commitments and `validUntil` durations accordingly.

**Holding-escrow lifecycle — questions to finalize before building.** §4.5 specifies that bid commitments live in a `LexScroWLite` holding escrow keyed by `offerId` and refund on cancel/expiry, but several implementation choices are not yet pinned. Resolve these before writing the OfferRegistry contract:

1. **Expiry alignment.** Does the holding escrow inherit `validUntil` from the offer as its expiry, or does it carry a separate (longer or shorter) expiry? Recommend: inherits `validUntil` exactly; the offer and the funds commitment expire together.
2. **Refund permissions.** Who can call the refund function on the holding escrow? Permissionless once expired? Bidder-only? BorgAuth-gated? Recommend: permissionless on expiry; bidder-only before expiry via `cancelOffer`.
3. **Partial bid acceptance.** Can a seller fill 150 of a 200-unit bid? If yes, how does the holding escrow split — pro rata (150/200 of the principal migrates into the trade settlement escrow, 50/200 remains in the holding escrow as a residual claim on further partial fills)? Or do partial fills require the bidder to re-post a new bid for the residual after each fill? Recommend: pro rata split, with the offer's `unitsAccepted` and `status` (PARTIALLY_ACCEPTED vs FULLY_ACCEPTED) tracking the cumulative fill state, and the holding escrow holding the residual principal until further fills, cancel, or expiry.
4. **Multiple sellers filling one bid.** Naturally handled if (3) supports pro rata. Each filling seller signs an `acceptOffer` for their slice; each acceptance migrates that slice's principal from the holding escrow into a separate trade settlement escrow. Confirm: yes, allowed by construction.
5. **Concurrency / first-mover semantics on bid acceptance.** Two sellers race to fill the same bid units; whichever transaction lands first wins. The loser's transaction reverts (insufficient remaining `unitsOffered - unitsAccepted`). No queue, no priority. Confirm: yes, standard.
6. **Holding-escrow contract: extend `LexScroWLite` or new contract?** Options: (a) reuse `LexScroWLite` with a single-asset escrow holding only payment tokens, status flowing from `PENDING` to `MIGRATED` (instead of `PAID`) on partial fills, to `VOIDED` on cancel/expiry; (b) new lightweight `BidCommitmentEscrow` contract with simpler state machine. Recommend: option (a), reuse `LexScroWLite`, because the existing escrow primitives (`expiry`, `voidAndRefund`, `handleCounterPartyPayment`) cover most of what's needed; option (b) only if extending `LexScroWLite` proves invasive.
7. **`OfferRegistry` ↔ holding escrow trust path.** When `acceptOffer` migrates funds from the holding escrow into the trade settlement escrow, what authorizes the migration? Recommend: `LexScroWLite` exposes a `migrateTo(targetEscrowId, amount)` function callable only by the `OfferRegistry` (BorgAuth-gated), with a hash-commitment from `postOffer` (offerId → holdingEscrowId) that `acceptOffer` re-verifies.

Decisions on each of these go into the OfferRegistry's storage layout and the `LexScroWLite` extension. The defaults above are conservative; deviations should be documented when chosen.

### 4.6 Contract-formation model

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

### 4.7 QMS mode — deferred enhancement

The model in §4.1–§4.6 is fast: one bundle from each party (whichever side initiates), 24-hour `TimeSettlementPeriod`, settlement. It does **not** preserve the Qualified Matching Service safe harbor under Treas. Reg. §1.7704-1(g), which requires (i) no binding agreement entered into during the first 15 calendar days after listing and (ii) no closing within 45 calendar days of listing. Under the binding-offer model, acceptance forms a binding agreement on day 0, which is incompatible with the 15-day rule.

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

Until and unless QMS mode is built, the initial deployment runs purely in the binding-offer mode of §4.1–§4.6. The spec's §11.1B should be updated to reflect this stance: the platform relies on the private-placement safe harbor for 3(c)(1) funds and on facts-and-circumstances for 3(c)(7) funds in the initial deployment, with QMS held as a configurable future enhancement when a deployment's risk profile demands it.

### 4.8 Visibility lives at the UI layer; compliance lives at settlement

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

## 5. Conditions — reuse what exists, add what's missing

The codebase has `src/interfaces/ICondition.sol`:

```solidity
interface ICondition {
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data)
        external view returns (bool);
}
```

`data` is the encoded agreement ID; custom conditions read agreement parameters back through `DealManager` and `CyberAgreementRegistry`. The prior draft of this section listed twenty new condition contracts to build; second-pass review of `src/libs/conditions/` and `src/creds/` shows that a meaningful portion already exists and the new work is smaller than first stated.

### 5.0 Existing primitives to reuse (verified)

| Existing file | What it does | cyberTRADE use |
|---|---|---|
| `src/libs/conditions/baseCondition.sol` | Abstract `BaseCondition` base class | All new conditions extend this |
| `src/libs/conditions/OrCondition.sol` | Logical-OR combinator over multiple conditions | Composability primitive; reuse as-is |
| `src/libs/conditions/lexchexCondition.sol` | Checks `ILexChex.hasValidLexCheX(counterparty)` (generic "valid accreditation") | Foundation for type-specific accreditation conditions; parameterize by `investorType` filter on `Accreditation` |
| `src/libs/conditions/NonUSNationalityCondition.sol` | zkPassport-verified non-US person check with OFAC blacklist and manager-controlled founder override | Reuse directly as the §4.1.4 / §6.5 spec "`NonUSPersonCondition`" — do not build new |
| `src/libs/conditions/IssuerApprovalRecertificationCondition.sol` | Per-investor, per-cert approval gate (currently gates scrip-to-cert conversion) | Pattern foundation for `GPLPApprovalCondition`; generalize to gate per `dealId` rather than per `(certAddress, investor)` |
| `src/creds/lexchex.sol` | LeXcheX core: ERC721Enumerable soulbound (ERC5484), `Accreditation` struct carrying `investorName`, `investorType`, `investorJurisdiction`, `expiryDate`, `voided`, `agreementId`; `hasValidLexCheX`, `isValid`, `getAccreditationByOwner`, `getTokenIdsByOwner` | Read directly via `ILexChex` from new conditions; **no `LeXcheXAdapter` needed**. The previously-proposed `LeXcheXNameLookup` reduces to `lexchex.accreditations(lexchex.getAccreditationByOwner(addr)).investorName` — no new contract |
| `src/creds/lexchexMinter.sol` | Oracle-pattern minter; admin-EIP712-authorized issuance; creates `CyberAgreementRegistry` agreement alongside each accreditation; renewal flow | Reuse for the Legion-operator credentialing layer; deploy a Legion-controlled instance of LeXcheX + minter alongside the existing MetaLeX instance |
| `src/interfaces/IZKPassportVerifier.sol`, `script/deploy-non-us-zkpassport-condition.s.sol` | zkPassport verifier interface + deploy script | Already wired into `NonUSNationalityCondition` |

### 5.1 Conditions that genuinely need new code

The remaining new conditions are narrower than the prior draft suggested:

```
src/conditions/HolderCapCondition.sol                    // ICA 3(c)(1) / 3(c)(7) cap check at finalize
src/conditions/HoldingPeriodCondition.sol                // Rule 144 / Reg S hold from FundInterestExtension.acquisitionDate
src/conditions/AccreditedInvestorCondition.sol           // ≅ LexChexCondition + filter Accreditation.investorType == ACCREDITED
src/conditions/QualifiedPurchaserCondition.sol           // ≅ LexChexCondition + filter for QP
src/conditions/QualifiedInstitutionalBuyerCondition.sol  // ≅ LexChexCondition + filter for QIB
src/conditions/KYCAMLCondition.sol                       // Asserts both parties have valid LeXcheX; thin wrapper
src/conditions/Section4a7DisclosureCondition.sol         // Checks SPV disclosure URI freshness + agreement acknowledgment
src/conditions/Rule144DisclosureCondition.sol            // Checks Rule 144(c)(2) info package URI freshness
src/conditions/AgreementSignedCondition.sol              // Checks CyberAgreementRegistry.isFinalized(agreementId)
src/conditions/ERISACondition.sol                        // Reads ERISA negative attestation from agreement party values
src/conditions/RegSDistributionComplianceCondition.sol   // Composes NonUSNationalityCondition + Reg S compliance-period elapsed
src/conditions/LegalOpinionCondition.sol                 // Checks recorded GP/counsel sign-off or formal opinion (per-SPV configurable)
src/conditions/CFIUSCondition.sol                        // Buyer-jurisdiction check; deployed only for non-fund-exception SPVs
src/conditions/TaxInfoCondition.sol                      // Checks W-9/W-8BEN on file in agreement or auxiliary registry
src/conditions/PriceAnomalyCondition.sol                 // Optional; checks trade price vs. GP-configured floor / NAV range
src/conditions/GPLPApprovalCondition.sol                 // ≅ IssuerApprovalRecertificationCondition generalized to deal-level approval
src/conditions/LegionSoulboundCondition.sol              // Filters Accreditation by category — see §5.4 below
src/conditions/GlobalKillCondition.sol                   // Bilateral admin; protocol-wide; see §5.2
src/conditions/TimeSettlementPeriodCondition.sol         // Per-deal time delay; see §5.3
```

Most are 20–80 line contracts. The ones marked "≅" are parameterizations of existing primitives rather than new logic.

### 5.2 `HoldingPeriodCondition`

Reads `FundInterestExtension.acquisitionDate` (and `tackedFromAcquisitionDate` if non‑zero) from the seller's cert via `CyberCertPrinter.getCertificate(tokenId).extensionData`, decodes via `FundInterestExtension`, applies the earlier date when tacking is asserted, and compares against the rule's required hold (one year for non‑reporting issuers under Rule 144; the Reg S compliance period derived from `regSCategory`). Pure on‑chain check, no oracle.

### 5.3 `GlobalKillCondition` (§12B.5)

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

### 5.4 `TimeSettlementPeriodCondition` (§12B.6)

```solidity
struct DealClock {
    uint64 startedAt;     // set on the trigger event
    uint8  trigger;       // 0=proposal, 1=both deposits, 2=agreement countersigned
}
mapping(bytes32 dealId => DealClock) clocks;

uint64 delaySeconds; // default 86400
```

Started by a hook on `DealManager` when the trigger condition first occurs. `checkCondition` returns `block.timestamp >= clock.startedAt + delaySeconds` and `clock.startedAt != 0`.

### 5.5 `LegionSoulboundCondition`

The "Legion Soulbound NFT" of spec §4.1.3A is implemented as a **second LeXcheX deployment under Legion's operator key** — the existing `src/creds/lexchex.sol` is already soulbound (ERC5484, `BurnAuth.OwnerOnly`) and already has the `Accreditation` struct with `investorType`, `investorJurisdiction`, and other category fields. A Legion-operated instance issues Legion-specific accreditations (SPV-X whitelist, syndicate-circle badges, accredited-tier distinctions) without disturbing the canonical MetaLeX LeXcheX deployment.

`LegionSoulboundCondition` is configured with: (a) the address of the Legion-operated LeXcheX contract, (b) the required `investorType` (or a custom category, if the `Accreditation` struct is extended with a `bytes32 category` field). At check time it calls `ILexChex(legionLexchex).getAccreditationByOwner(counterparty)` and asserts the returned `Accreditation` has `voided == ""`, `expiryDate >= block.timestamp`, and matches the required category.

No separate "LegionSoulboundAdapter" is needed; the `ILexChex` interface is the adapter. If `Accreditation` needs a new field for fine-grained SPV-specific badges (the spec hints at "any number of categories" in §4.1.3A), it would be a forward-compatible extension to the existing storage struct via the existing namespaced-storage pattern.

**Implication for the impl doc's earlier framing.** The previously-proposed `LeXcheXAdapter`, `LegionSoulboundAdapter`, and `LeXcheXNameLookup` are all unnecessary as new contracts: the canonical `ILexChex` interface plus a parallel Legion-operated deployment of the existing LeXcheX contract is the cleanest implementation. The "Legion-controlled custom credentialing layer" of spec §4.1.3A is realized by deploying LeXcheX + LeXcheXMinter with Legion's keys as the BorgAuth admin, not by writing new contracts.

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

The template registration follows the existing pattern in `script/template.s.sol`, `script/templatev2.s.sol`, and `script/add-spa-plus-templates.s.sol`. The new cyberTRADE templates land as `script/RegisterTradeAgreementTemplates.s.sol` modeled on these existing scripts. Per-trade population happens inside `OfferRegistry.postOffer` (which knows the seller, the exemption pathway, and the `globalValues` from the offer + the SPV's stored disclosure URIs) and inside `OfferRegistry.acceptOffer` (which fills in `partyBValues` and finalizes).

**Existing templates directory.** The repo's `templates/` directory carries an extensive set of cyberSAFE / cyberSAFTE / cyberSAFT / cyberTokenWarrant variants in both Reg D and Reg S forms (`mlx_safe_reg_d_v1_3.md`, `mlx_safe_reg_s_v1_3.md`, `mlx_saft_reg_d_v1_3.md`, etc.) plus jurisdictionally-neutral variants and the MetaLeX LeXcheX Agreement. **There is no existing fund-interest subscription template and no secondary-trade template.** All five cyberTRADE trade-agreement templates are new drafting work for MetaLeX Pro. Naming convention is mixed in the existing set (`v 1.0` vs `v1_3`); the cyberTRADE templates should pick one and stick to it — recommend the `v1_3`-style file-system-friendly naming for the markdown sources, with the registered onchain `Template.title` carrying the human-readable version label.

**Delegation is already in place.** `CyberAgreementRegistry.Delegation` plus the `useCyberAgreementRegistryDelegations` hook in the webapp already support a party delegating signing authority to another address with an expiry. Fund administrators or attorneys-in-fact signing on behalf of LPs is supported through this mechanism today; no additional protocol work is needed for the §4.1.6 spec language about delegation support.

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

   For Administered Custody, the endorser slot may instead be filled with the ledger administrator multisig as the operational executor, with the seller's signature still attached as `signatureHash` — preserving the seller's pre-signed authorization as the legal anchor while reflecting that the multisig is the holder of record. The choice is the `endorserOfRecord` per-SPV configuration knob enumerated in §3.4. Default is `SELLER`.

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

The webapp has two distinct existing precedents that cyberTRADE inherits from for different parts of its flow:

- **cyberSign** (`/cybersign/create`, `/cybersign/[chainId]/[agreementId]`) is the precedent for templated trade-agreement creation and per-party EIP-712 signing. cyberSign uses `CyberAgreementRegistry` directly, parses `globalFields` / `partyFields` from the registered template, supports delegation, and renders condition-status. **The Offer Builder and Acceptance view inherit from cyberSign**, not from CyTE.
- **CyTE / LeXscroW** (`/lexscrow/propose`, `/lexscrow/double-token-lexscrow-agreement/[agreementAddress]`) is the precedent for **escrow deposit and settlement** — `LexScroWLite`-based two-party asset locks with finalize/void semantics. The Deposit + Settlement view inherits from CyTE's `ExecuteLexscrowAgreement`. CyTE renders a static IPFS document and is **not** a templated-agreement flow; it should not be the model for the trade-agreement creation step.

The prior framing of CyTE as the "closest precedent" for the agreement step was a misreading: CyTE's `legalAgreementURI` is a single IPFS link with no globalFields/partyFields parsing, while cyberSign already implements exactly the per-party templated EIP-712 signing surface cyberTRADE needs. The correction matters because the wrong choice would force re-implementing field parsing, delegation, and per-party signature tracking that cyberSign already does.

Other reusable infrastructure (verified in second-pass review):

- **`useFormSession` / `FormStepsLayout` multi-step form pattern.** Used by cyberRAISE round creation. Manages step state via Jotai atoms, persists to localStorage, integrates with TanStack Form validation. The Offer Builder should reuse this for a structure→terms→review→sign flow rather than be a single-page form.
- **`useDealsForX` hook family** (`useDealsForInvestor`, `useDealsForFounder`, `useDealsForCyberCorp`, `useDealById`, `useDealForCyberCert`, `useOpenDealsForInvestor`, `useExpiredDealsForInvestor`). These are direct precedents for cyberTRADE's `useOffersFor*` family.
- **`useNotifications`** (`apps/cybercorps-web/src/features/notifications/hooks/useNotifications.ts`). Already aggregates pending EOIs, allocations, rejections, expirations, open deals, and finalized deals with 14-day auto-expiry. **cyberTRADE notifications plug into this; no new notification UI.** The existing pattern already avoids "specific opportunity for you" framing, which aligns with the Covered UI Provider §11.1A constraint.
- **`useUploadPdfToPinata`** (`apps/cybercorps-web/src/features/api/upload/useUploadPdfToPinata.ts`). **Pinata is the IPFS provider.** Trade-agreement templates, disclosure packages, and any other IPFS-hosted assets go through this hook.
- **`useCyberAgreementRegistryAgreementSummary` / `useCyberAgreementRegistryContractDetails` / `useCyberAgreementRegistryDelegations`** in `apps/web/src/features/cyber-agreement-registry/hooks/`. These already parse template field structures and read agreement / delegation state. Reused unchanged.
- **`PublicRoundsList`** (`apps/cybercorps-web/src/app/(frame-layout)/cyberraise/public-rounds/`). The existing rounds-discovery page is the structural precedent for offer discovery under Covered UI Provider §11.5 — sortable, filterable, paginated, no recommendation labels. cyberTRADE's discover page should extend this component's pattern.

### 10.1 Offer Builder (post sell / post bid)

Modeled on cyberSign's `CreateAgreementForm` (`apps/web/src/app/(frame-layout)/cybersign/create/`) combined with cyberRAISE's `CreateRoundForm` (`apps/cybercorps-web/src/features/rounds/forms/CreateRoundForm.tsx`) — both of which already do templated-agreement creation against `CyberAgreementRegistry`. The Offer Builder is a `useFormSession`-driven multi-step flow: (1) structure & exemption pathway, (2) units & consideration, (3) counterparty restrictions, (4) review & sign.

Concrete reuses:

- **From cyberSign**: the template-id selector, the global/party field parsing via `useCyberAgreementRegistryContractDetails`, the EIP-712 typed-data signing prompt that handles per-party values, the delegation hook (`useCyberAgreementRegistryDelegations`) for fund-admin-signs-on-behalf cases.
- **From cyberRAISE's round form**: the `useFormSession` multi-step pattern, the asset selectors, the `requiresLexChex` and condition-attachment pattern.
- **From CyTE's design-system forms**: `AssetInput`, `AssetValueLabel`, `EmbeddedAgreement` (for IPFS preview of the template's `legalContractUri`), `DateInputField` for `validUntil`, `FormSelectField` for the exemption pathway dropdown, `TransactionActionButton` for the signing action.

Per the binding-offer model (§4.6) and the symmetric framework (§4.5), the offeror's signing step at posting produces **two EIP‑712 signatures presented in a single typed‑data payload**, with the contents determined by side:

- **Post Sell Offer** (offeror = seller): (a) the signature on the partially-populated trade agreement (party A = seller fields), and (b) the open-endorsement signature on the seller's cert (§4.3, authorizing transfer of the offered units to whichever qualifying counterparty accepts). No payment movement at posting.
- **Post Bid** (offeror = buyer): (a) the signature on the partially-populated trade agreement (party A = buyer fields, including accreditation, ERISA negative attestation, info-package acknowledgment, tax-info covenant), and (b) an ERC-20 approval that lets `OfferRegistry.postOffer` pull `consideration` of `paymentToken` into a `LexScroWLite` holding escrow keyed by the new `offerId`.

The wallet shows both signatures in one bundled EIP‑712 prompt; the user experiences it as one signing action. The offeror will not be asked to sign again at any later step (until cancel or void, which produce their own self-contained signatures).

What neither cyberSign nor cyberRAISE has and must be added: a "Counterparty restrictions" sub‑form (accredited‑only, QP‑only, non‑US‑person, required Soulbound category/tier, explicit allowlist). This is a small new component under `packages/design-system/forms/components/CounterpartyRestrictionsInput.tsx`.

Sell‑side specifics: an entry-token picker (the LP's existing `cyberCert` rows under the SPV's printer, served from the Ponder indexer's `cyberCert` table — the same data source as the existing `CertsTable.tsx` on the mainframe). The picker surfaces, per cert: `unitsRepresented`, `acquisitionDate`, `certLegend`, holding‑period status (derived from `acquisitionDate` and the fund's category).

### 10.2 Offer Discovery (browse)

Extends the existing `PublicRoundsList` pattern (`apps/cybercorps-web/src/app/(frame-layout)/cyberraise/public-rounds/`), which is already a Covered UI Provider–compliant listings page (sort/filter only, no recommendation labels, paginated, search-by-name). New page under `apps/web/src/app/(frame-layout)/cybertrade/discover/page.tsx`. Server component pulls from `/api/offers` (new indexer route, §11), pre‑filtered by:

- session user's LeXcheX credentials (`useLexchexForAddress`),
- session user's Legion Soulbound badge (the LeXcheX schema already supports investor-type fields; an extended `Accreditation.category` or a separate Legion-operator LeXcheX deployment carries the SPV-specific badge — see §5),
- session user's per‑SPV whitelist entitlements (server‑side, queried from a new `user_spv_entitlements` table in the webapp DB — administered by Legion ops, not on chain),
- session user's seasoning timestamp (set when the user finishes onboarding; gate at 30 days per §11.1B of the spec).

The list view is a thin wrapper around the indexer's denormalized response, mirroring `PublicRoundsList`'s structure. Sort/filter is user‑driven, no recommendations or "best price" labels — this is the Covered UI Provider constraint (§11.5).

### 10.3 Acceptance view

Modeled on cyberSign's `SignAgreementForm` (`apps/web/src/app/(frame-layout)/cybersign/[chainId]/[agreementId]/`). cyberSign already implements:

- reading the agreement record, displaying party A's filled values and signature,
- rendering party B's blank fields for the connected acceptor to fill,
- signing as a designated party, a delegate, or an unassigned party slot,
- displaying condition pass/fail status before signing,
- per-party `signedAt` tracking.

For cyberTRADE, the route is `apps/web/src/app/(frame-layout)/cybertrade/offer/[offerId]/page.tsx`. It extends cyberSign's flow with:

- a compliance checklist (KYC valid, accreditation valid, non‑US valid, QP valid, Soulbound held, ERISA negative, Reg S distribution compliance, tax info) — each item rendered via existing condition-status hooks (e.g., `useRoundConditionsState` pattern in `apps/cybercorps-web/src/features/conditions/hooks/`, parameterized for cyberTRADE's condition set instead of round conditions),
- a 4(a)(7) information‑package acknowledgment modal that the acceptor must click‑through before the "Sign and Accept" button activates,
- a single "Sign and Accept" action that signs an EIP-712 typed-data bundle covering the acceptor's contribution to the trade (§4.5 for the full symmetric model). The bundle contents depend on which side the user is accepting:
  - **Accepting a sell offer** (acceptor = buyer): (a) agreement-buyer-side signature; (b) ERC-20 approval allowing the trade's settlement escrow to pull `consideration` of `paymentToken` (collected on the deposit screen immediately afterward, §10.4).
  - **Accepting a bid** (acceptor = seller): (a) agreement-seller-side signature; (b) open-endorsement signature on the seller's cert (the same `OpenEndorsement` typed structure used in sell-offer posting, but signed by the acceptor at acceptance time because the seller is the acceptor here).

  The single transaction hits `OfferRegistry.acceptOffer`, which (a) attaches and signs the open agreement via `CyberAgreementRegistry.attachAndSignAsPartyB`, finalizing the contract; (b) materializes the seller's endorsement on the seller's cert via `IssuanceManager.attachOpenEndorsement`; (c) opens (or migrates from a holding escrow, for bid acceptance) the trade settlement escrow on `DealManager.proposeSecondaryDeal`. There is no separate countersign step — the offeror's posting signature already covered party A.

### 10.4 Deposit + Settlement view

Closely modeled on `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/ExecuteLexscrowAgreement.tsx`. CyTE's `ExecuteLexscrowAgreement` already handles the deposit + finalize sequence under `LexScroWLite`. cyberTRADE simplifies it considerably under the unified pathway (§3); the exact shape of the view depends on how the trade was initiated:

- **Trade initiated from a sell offer (sell-side post → buy-side accept).** The buyer (acceptor) has a payment-deposit step here, after signing acceptance. The seller has no deposit step at all — there is no NFT escrow in the unified pathway, and the seller's open-endorsement was already materialized on the cert at `acceptOffer` (§4.4).
- **Trade initiated from a bid (buy-side post → sell-side accept).** Neither party has a deposit step on this view. The buyer's payment was already deposited into the holding escrow at `postOffer` and migrated into the trade settlement escrow at `acceptOffer` (§4.5). The seller's open-endorsement was signed and applied at `acceptOffer`. The escrow is already `PAID` on entry to this view; the user lands directly on the conditions / settlement timer.
- The status dashboard shows: agreement finalized (✓ at acceptance), endorsement‑lock active on seller's cert (✓ at acceptance), buyer payment deposited (pending → ✓ for sell-offer trades; ✓ on entry for bid-initiated trades), all conditions passing (live evaluation), `TimeSettlementPeriod` elapsed (countdown timer, default 24 hours), ready to finalize.
- The "Settle" action is **hidden by default**: the keeper service (§10.4 of the spec) calls `signAndFinalizeDeal` once `TimeSettlementPeriodCondition` clears. A "Settle manually" affordance is shown if the keeper hasn't fired within a configurable grace period; this preserves user agency without putting the keeper in the trust path.
- **Per‑SPV `settlementMode = NFT_ESCROW` rendering (deferred).** If a future SPV elects the legacy NFT-escrow mode (§3.4), the deposit view conditionally renders the seller's "approve and deposit Ledger Entry Token" step for Direct Custody sellers. This is a UI branch behind a feature flag; not built in the initial deployment because no SPV has been configured with `NFT_ESCROW`.

### 10.5 GP Monitoring view

Closely modeled on `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx`. Same columns plus: active offers for the SPV (joined from the indexer's `offer` table), passing/failing condition counts per open trade, holder count vs. ICA cap with color‑coded headroom, transfer‑restriction‑hook deployment status. No "approve trade" button — the spec is explicit that GPs do not approve individual trades.

### 10.6 Admin panel (Pathway F + Officer / BorgAuth management)

This subsection covers a meaningful gap surfaced in the second-pass review: the webapp has **no admin UI for officer management or BorgAuth role assignment today**. The indexer tracks `OfficerAdded` / `OfficerRemoved` events on `CyberCorp` and `RoleUpdated` events on `BorgAuth`, and the `officer` and `role` tables are populated, but role management today is script-only (`script/upgrade-lexchex-minter-admin.s.sol`, etc.). cyberTRADE requires a real admin UI for two reasons: (a) the Pathway F admin actions enumerated below have no current home; (b) BorgAuth role rotation becomes operationally critical with the new `SECONDARY_TRANSFER_ROLE` granted to each SPV's DealManager (§8.1).

The admin route lives under `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/admin/` and is **not** part of the trading UI — this separation keeps the Covered UI Provider scope (§11.5) clean by isolating issuer-administrator functions from the user-facing trading surface.

Admin-panel responsibilities for the cyberTRADE workstream:

1. **Officer management.** Add / remove officers on the SPV's cyberCORP. Surfaces the existing indexed `officer` table; new mutations call `CyberCorp.addOfficer` / `removeOfficer`. Tracks signing officers used by `CertPrinter.CertificateDetails.signingOfficerName` / `signingOfficerTitle`.
2. **BorgAuth role assignment.** Grant and rotate the SPV's roles: GP admin, ledger administrator multisig, `SECONDARY_TRANSFER_ROLE` on the DealManager, optional `LegionSoulboundCondition` admin, optional `GPLPApprovalCondition` approver, etc. Surfaces the indexed `role` table; new mutations call `BorgAuth.updateRole`.
3. **Pathway F operations.** Void / force-transfer / `voidCert` on specific certs, with documentation of the underlying basis (Compromised Credential Transfer voidness, court order, etc.). Each action requires a written justification field and an attached document (filed in the SPV's records via Pinata + the per-cyberCORP documents tab proposed in §10.7).
4. **Global Kill governance.** `raiseKill()` (unilateral by either MetaLeX or Legion admin), `proposeLower()` and `confirmLower()` for the bilateral 48-hour quorum (§5.3 of this doc).
5. **Per-SPV configuration flags.** Set / read `settlementMode`, `qmsMode`, `endorserOfRecord` (§3.4). For SPVs that need to migrate flags mid-life, the flag setters are BorgAuth-gated.
6. **Restriction-hook configuration.** Deploy / swap / update the SPV's `globalRestrictionHook` and per-token `restrictionHooksById` (§3.6). Surfaces the existing `WhitelistTransferHook` / `ToggleTransferHook` patterns for configuration.

### 10.7 Per-cyberCORP documents tab (new)

Spec §4.3.1 (Rule 144(c)(2) disclosure maintenance and Section 4(a)(7) information delivery) requires the GP to publish and periodically refresh the SPV's information package, financial statements, GP underlying-asset provenance attestation (§4.1.0 of spec), and other disclosure documents. The current webapp has no per-cyberCORP documents tab; the legacy `documents` system at `apps/web/src/data/queries/documents.ts` is Borg-only and is not reusable as-is.

cyberTRADE depends on this tab existing because:

- The OfferRegistry's `registerSPV` check should verify the SPV's disclosure URIs are non-empty and freshly-dated.
- The `Section4a7DisclosureCondition` and `Rule144DisclosureCondition` (§5.1) read the SPV's disclosure URI from the cyberCORP and check timestamp freshness against per-condition staleness windows.
- The trade-agreement templates' `gpUnderlyingProvenanceAttestationHash` field (§7) must be populatable from the cyberCORP record.

New work for the cyberTRADE webapp:

- Per-cyberCORP documents page modeled on the legacy `documents` system but writing to a `cyberCorpDocuments` table (chain-indexed if URIs are stored on chain, server-side if not).
- Upload via `useUploadPdfToPinata` to Pinata; URI written to the cyberCORP's metadata (PPM, financial statements, GP attestation, etc.).
- Annual / quarterly refresh prompts surfaced via `useNotifications` for the GP.
- Public-facing read of these URIs from the offer detail view (Section 4(a)(7) information delivery acknowledgment is recorded as a buyer-side party value at acceptance).

---

## 11. Indexer Additions

The webapp uses Ponder (`apps/cybercorps-indexer/`). Schema in `ponder.schema.ts`. **Existing tables verified by second-pass review:** `cyberCorp`, `officer`, `role`, `certPrinter`, `cyberCert` (with endorsements stored as JSONB), `cyberScripBalance`, `deal`, `dealCerts`, `round`, `eoi`, `pumpWrappedToken`. **Existing event handlers (~39 total)** cover CyberCorp lifecycle, BorgAuth role updates, IssuanceManager (cert creation, scrip deployment, scripification), DealManager (deal proposed/finalized/voided), RoundManager (round/EOI lifecycle), and ERC-721 transfers/endorsements/voids on CyberCert.

**Critical gap surfaced in second-pass review:** `CyberAgreementRegistry` events are **not currently indexed**. There are no Ponder handlers for `AgreementCreated`, `AgreementSigned`, `AgreementFinalized`, or `AgreementVoided`. Agreement state lives only on chain and is reachable only via direct contract reads (`useCyberAgreementRegistryAgreementSummary`, etc.). cyberTRADE's offer discovery and acceptance views cannot function without indexed agreement state — listing every offer's agreement-finalized status, condition-pass status, party-B signed-at timestamp, etc., requires a queryable indexer table. **Add agreement events to the Ponder config as a discrete step (§14).**

cyberTRADE additions:

```ts
// new tables
agreement:            {id, templateId, parties, signedAt (per-party JSONB), finalized, voided,
                       openToMatching, legalContractUri, globalValues, partyValues, expiry,
                       createdAt, finalizedAt, voidedAt}
                       // ↑ critical missing primitive — see note above
offer:                {id, spvCyberCorp, offeror, side, tokenId, units, paymentToken, consideration,
                       exemptionPathway, validUntil, restrictionsBlob, additionalTermsBlob,
                       integrator, agreementId, offerorEndorsementSignature, bidCommitmentEscrowId,
                       status, unitsAccepted, postedAt, cancelledAt, expiredAt}
offer_acceptance:     {id, offerId, acceptor, units, dealId, acceptedAt}
fix_trade_receipt:    {id (=execID), dealId, offerId, fixID, tradeDate, lastPx, lastQty,
                       currency, partyBuyer, partySeller, partyGP, exemptionBasis}
endorsement:          {id, cyberCert, endorser, endorsee, registry, agreementId, timestamp,
                       signatureHash, voidedAt}
                       // ↑ optional but recommended — denormalize from cyberCert.endorsements JSONB
                       // for "all endorsements made by address X" / "all endorsements on cert Y"
                       // / "all endorsements with agreementId Z" query patterns
user_spv_entitlement: {userId, spvCyberCorp, whitelistTier, addedAt, addedBy}  // off-chain only
user_seasoning:       {userId, onboardingCompletedAt, seasoningUnlockAt}        // off-chain only

// extensions to existing tables
deal:                 + offerId, sellerAddress, tradeType, feeDestination, integratorFeePaid, platformFeePaid
cyberCert:            + fundInterestData (decoded), lastTrade (decoded FIX), custodyMode
```

API routes mirror the existing patterns in `apps/cybercorps-indexer/src/api/rounds/rounds-routes.ts` and `deals/deals-routes.ts`:

```
GET /api/agreements              // new — agreement-state queries
GET /api/agreements/:agreementId
GET /api/offers                  // filtered list, eligibility-aware via session
GET /api/offers/:offerId
GET /api/spvs/:cyberCorp/offers  // per-SPV
GET /api/users/:address/offers   // mine
GET /api/users/:address/deals    // mine (extends existing)
GET /api/spvs/:cyberCorp/fix-receipts
```

Eligibility filtering for `/api/offers` is server‑side: the route joins `user_spv_entitlement`, `user_seasoning`, and the user's LeXcheX credential cache; it never returns an offer the user is ineligible to see. This is the implementation of the spec's "UI‑level visibility gating" (§4.4, §11.1B).

**IPFS storage.** The webapp uses Pinata via `apps/cybercorps-web/src/features/api/upload/useUploadPdfToPinata.ts`. Trade-agreement templates, disclosure packages, and the GP underlying-asset provenance attestation document all live on Pinata. The indexer does not pin IPFS content directly; URIs are recorded as fields on the agreement / cyberCorp / cyberCert records and resolved at render time. Operationally, Pinata API key management lives in the webapp's environment configuration; pricing scales with the volume of cyberTRADE templates and per-SPV disclosure packages.

A keeper component (separate Node process, deployed alongside the indexer) does two things:

1. **Auto-finalize ready deals.** Subscribes to `DealProposed`, `BuyerDeposit`, `SellerDeposit` and calls `DealManager.signAndFinalizeDeal` once both required deposits are in and `TimeSettlementPeriodCondition` clears, per §10.4 of the spec.
2. **Auto-void stuck deals on expiry.** Subscribes to deal `expiry` timestamps and, when an open deal passes its `expiry` without reaching finalize, calls `DealManager.voidExpiredDeal` (or the equivalent void function on `LexScroWLite`) to release escrowed assets back to their owners. Includes both trade-settlement escrows (refund buyer payment, release any seller endorsement-lock via void endorsement on the seller's cert) and bid-commitment holding escrows (refund bidder principal). This eliminates the failure mode where escrowed funds sit indefinitely after expiry because no party manually called void.

Both auto-finalize and auto-void are convenience layers, not trust layers: either party can call the underlying functions directly at any time. The keeper exists so users don't have to.

---

## 12. Out of Scope (Future‑Enhancement Markers)

Items the spec lists as future enhancements that are not in this implementation detail:

- **Scrip Token layer (§13).** No `CyberScrip` changes proposed for cyberTRADE. Note: `src/CyberScrip.sol` already exists in the codebase with compliance flags (`canForceTransfer`, `canForceBurn`, `canFreeze`), transfer-hook integration, and `_update` overrides — more than the spec's "future enhancement" framing implies. If/when scrip is adopted as a trading instrument for fund interests, the foundation is in place; the new work is scrip-to-cert conversion semantics for the fund context and any tax/PTP accommodations.
- **AMM liquidity for scrip (§13A).** Out of scope for cyberTRADE. Note: `src/hooks/uniswap/MetalexIssuerFeeHook.sol` already exists as a Uniswap v4 hook skeleton in the codebase — the §13A AMM is partially scaffolded at the protocol layer, not greenfield. If §13A is adopted in the future, this hook is the natural starting point.
- **Tag‑along / drag‑along / ROFR.** Not assumed for the initial SPVs (Addendum B).
- **Manual per‑trade GP consent.** Generalized into `GPLPApprovalCondition` (§5), deployed only on SPVs whose governing documents require it (Addendum C). The condition exists in the protocol layer; no UI work beyond a "GP approval pending" status row in the trade detail view.
- **QMS mode (§4.7).** Architected for via the `qmsMode` flag on offers, `qmsListedAt` timestamp, and the cool-off behavior on `AgreementSignedCondition` and `TimeSettlementPeriodCondition`. Not built in the initial deployment. The initial deployment relies on the §1.7704‑1(h) private-placement safe harbor for 3(c)(1) funds and on facts-and-circumstances analysis for 3(c)(7) funds. Build QMS mode when (i) a 3(c)(7) deployment with high turnover lands, or (ii) counsel for a particular SPV requires the belt-and-suspenders treatment.

---

## 13. Spec ↔ Codebase Discrepancies (verified)

Items in v2.04 that should be corrected or refined when the spec is next revised:

1. **§7.4 / §12B.1 routing description.** The spec says `LexScroWLite.finalizeEscrow` routes "buyer assets to `companyPayable` and corp assets to `counterParty`" — verified correct. The implication for cyberTRADE is that "secondary trade mode" must redirect `buyerAssets` to a per‑deal seller address. The spec already captures this in §12B.1; no change needed there, but cross‑reference the seller‑address storage requirement (§3.2 above).
2. **§12B.2 per‑token restriction hooks.** Spec says the block in `_update` is "commented out" — verified correct (around lines 257–264 of the current `CyberCertPrinter.sol`). The `restrictionHooksById` storage and setter functions exist; only the read in `_update` is dormant. Spec is accurate.
3. **§4.2 `safeMint` vs `safeMintAndAssign`.** Spec correctly identifies that `safeMint` leaves `OwnerDetails.name` empty — verified. Implementation must use `safeMintAndAssign` everywhere, including the secondary‑settlement mint. The spec calls this out in §7.5; reinforce in implementation reviews.
4. **§7.6 / §12B.7 FIX field location.** Spec is ambivalent about whether FIX fields live on the core `CertificateDetails` or on `FundInterestExtension`. This detail document recommends extension (§1.4), to minimize the blast radius of the change and stay consistent with the existing pattern where security‑class‑specific data lives in the extension.
5. **§8 reference to CyTE — partially wrong as a precedent.** Spec states CyTE is at "`app.metalex.tech/lexscrow/propose`" and acts as the closest precedent for the agreement-and-escrow steps — URL verified correct. CyTE is the right precedent for the **escrow + deposit + settlement** half of cyberTRADE (`LexScroWLite`-based two-party locks with finalize/void). It is the wrong precedent for the **trade-agreement creation** half: CyTE renders a single static IPFS `legalAgreementURI` and does not use the `CyberAgreementRegistry` template-with-globalFields/partyFields machinery that cyberTRADE needs. The correct webapp precedent for cyberTRADE's agreement creation and signing is **cyberSign** (routes `/cybersign/create` and `/cybersign/[chainId]/[agreementId]`), which already implements templated-agreement creation, per-party value population, EIP-712 typed-data signing, delegation, and condition-status display. The impl doc's §10 reflects this corrected mapping. The spec's §8 reference should similarly be updated to point at cyberSign as the agreement-creation precedent and CyTE as the escrow-deposit-settlement precedent — they are different precedents for different halves of the flow.
6. **§4.2.2 `acquisitionDate` placement.** Spec proposes adding to `CertificateDetails` "preferable" — this detail document recommends the extension (§1 above). Both are workable; placement in the extension is lower‑risk for the cyberTRADE workstream because it doesn't touch shared core storage.
7. **§12 reference to `OfferRegistry`.** Spec correctly notes none exists. New file `src/OfferRegistry.sol` proposed in §4 above.
8. **§10 reference to `CertsTable`.** The webapp already has a serviceable cap‑table view (`apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx`); the GP monitoring view extends this rather than building new.
9. **§7.3 contract-formation model — binding-offer adoption.** The spec's §7.3 describes a sequential "seller proposes, buyer countersigns" agreement flow that, in conjunction with the §11.1B QMS timing constraints (15-day no-binding-agreement period), implies two seller signatures. This detail document adopts **Architecture B (binding-offer model, §4.6)** for the initial deployment: the offeror's `postOffer` signature is the legally operative offer on a partially-populated trade agreement, and the acceptor's `acceptOffer` signature attaches to and finalizes the same agreement in one transaction. Conditions are conditions precedent to performance, not to formation. This collapses the trade-formation flow to one signature per side, at the cost of forgoing QMS safe-harbor qualification. The trade-off is acceptable because (i) the initial pipeline is 3(c)(1) funds where the private-placement safe harbor handles §7704 by construction and (ii) QMS mode is preserved as a configurable future enhancement (§4.7). When the spec is next revised, §7.3 should be reframed to describe the binding-offer flow as the default and QMS as the opt-in. Spec §11.1B's QMS treatment should be re-titled "Future Enhancement: QMS Mode" rather than the primary regulatory posture.
10. **`CyberAgreementRegistry.createOpenAgreement` / `attachAndSignAsPartyB` (§7.1).** The current `CyberAgreementRegistry` requires both parties' addresses at `createContract` time. The binding-offer model requires the ability to create an agreement signed by party A while leaving party B open until any qualifying counterparty attaches. This is a small additive change to the registry and does not alter the existing primary-issuance flow (which continues to use `createContract`).
11. **§7.4A pathway taxonomy — unified pathway adoption.** The spec's §7.4A enumerates six settlement pathways (A: escrow + transfer, B: endorsement + transfer, C: scrip intermediation, D: void + mint, E: metadata mutation, F: admin force transfer) and recommends Pathway A/B+A for Direct Custody and Pathway E for Administered Custody. This detail document adopts a **unified settlement pathway (§3, §8)** that effectively merges Pathway B (the seller's pre‑signed open endorsement) with Pathway D/E (void‑or‑decrement + fresh mint by IssuanceManager) for both custody modes. The motivation is structural symmetry: the cyberCORPs Bylaws and spec §2 both state that metadata mutation is the legally operative act and the ERC‑721 transfer is bookkeeping; the unified pathway treats them that way universally. Pathway A is retained as the per‑SPV `settlementMode = NFT_ESCROW` opt‑in (§3.4) for deployments whose counsel specifically wants on‑chain NFT escrow. Pathway F remains the off‑trade admin escape hatch. Spec §7.4A's pathway table should be revised in the next edit to lead with the unified pathway and treat A/B/C as alternative configurations rather than custody‑mode defaults.
12. **Pre‑signed open endorsement at `postOffer`.** The cyberCORPs `Endorsement` struct (`src/CyberCertPrinter.sol`) requires `endorsee` to be a known address. The binding-offer + unified-pathway architecture requires the seller to authorize transfer at posting, when the endorsee is not yet known. This detail document introduces the **open endorsement** pattern (§4.3): the seller signs an EIP-712 `OpenEndorsement` typed structure that omits the endorsee but binds the authorization to a specific `offerId`; at `acceptOffer`, the IssuanceManager combines the seller's pre-signed `signatureHash` with the now-known buyer's address and name to materialize the full `Endorsement` struct on the cert. This mirrors negotiable-instruments-law "indorsement in blank" and preserves the seller as the legal endorser of record, even though the writing of the endorsement to the cert is performed by the IssuanceManager under BorgAuth. No change to the on-chain `Endorsement` struct is required; only the `IssuanceManager.attachOpenEndorsement` entry point and the OfferRegistry's storage of the pre-signed signature. The cyberCORPs Bylaws may want a small drafting update to acknowledge that endorsements may be pre-signed in open form when authorizing transfer through the OfferRegistry/DealManager flow.

13. **Buy-side parity and bid commitments (§4.5).** The OfferRegistry surface supports both sell-initiated and buy-initiated trades. The mechanics are symmetric: each side contributes a two-signature EIP-712 bundle (agreement-side signature + side-specific commitment), and whichever side posts signs at `postOffer` while the other side signs at `acceptOffer`. The downstream flow from `acceptOffer` through finalize is identical regardless of initiation direction. The asymmetric commitment artifact is: for sell offers, the seller's open-endorsement is the pre-signed commitment; for bids, the buyer's payment deposited into a `LexScroWLite` holding escrow is the commitment, custodied by the protocol from posting until acceptance, void, or expiry. The cyberCORPs Bylaws (and the spec's discussion of the offer registry in §7.1 / §4.4) should be updated to recognize bid-side initiation as a first-class flow on equal footing with sell offers, with the holding-escrow commitment as the buy-side analog of the seller's open endorsement.

14. **`endorsementRequired = true` precondition for SPVs using cyberTRADE.** The endorsement-lock that protects a Direct Custody seller's cert during pendency (§4.4) depends on `CyberCertPrinter._update` enforcing the `endorsementRequired` check. SPVs whose cert printers were initialized with `endorsementRequired = false` would silently lack this protection — the materialized endorsement at `acceptOffer` would be recorded but not enforced as a transfer lock, allowing the seller to move the cert mid-pendency. The OfferRegistry's `registerSPV` function therefore enforces `CyberCertPrinter.endorsementRequired() == true` and reverts otherwise. SPVs that wish to use cyberTRADE for secondary trading must enable this flag at cert-printer initialization (preferable) or via the printer's setter (if available) before SPV registration. The spec's §4.4 / §9 should reflect this precondition in the SPV-onboarding checklist.

15. **Spec assumes embedded / MPC wallet infrastructure exists; it does not.** Spec §4.2.2 says LPs who elect Administered Custody "do not need wallets; their ownership is recorded in Ledger Entry Token metadata and they interact through a conventional web interface." This implies a Legion-provisioned MPC wallet that signs on the LP's behalf after web authentication. **No such infrastructure exists in the webapp today** — the EVM provider stack is ConnectKit + wagmi (`apps/cybercorps-web/src/features/providers/EvmProviders.tsx`), which requires the user to bring their own self-custodial wallet. Building MPC integration (Privy, Web3Auth, Magic, Turnkey, or equivalent) is a multi-week dependency for cyberTRADE that the spec treats as a given. The Covered UI Provider statement (§11.5) requires the wallet to be "self-custodial," which MPC patterns can satisfy if the user controls one key shard via their authentication provider — but the integration choice and operational model need to be made. The spec should explicitly call this out as an onboarding-infrastructure dependency.

16. **Spec assumes cap-table import infrastructure exists.** Phase 2 Option C (§4.2.3) describes existing funds migrating to the protocol via bulk minting of Ledger Entry Tokens with historical `acquisitionDate` per LP. **No bulk-import flow exists in the webapp.** The current cert-minting pattern is event-driven (via `IssuanceManager:CertificateCreated`), one cert at a time, in the context of a `RoundManager.allocateEOIs` call. A new bulk-import workflow is required: GP uploads CSV/JSON of LP records (name, wallet, units, original acquisition date, capital contribution), webapp invokes a batched mint via `IssuanceManager.safeMintAndAssign` per row, with `FundInterestExtension.acquisitionDate` populated from the imported data. The spec should call this out as a build item under Phase 2 Option C.

17. **Spec assumes per-cyberCORP disclosure-document infrastructure exists.** Spec §4.3.1 (Rule 144(c)(2) and Section 4(a)(7) information delivery) requires the GP to maintain a current information package — business description, GP names, outstanding units, financial statements, GP underlying-asset provenance attestation. **The current webapp has no per-cyberCORP documents tab**; the legacy `documents` system (`apps/web/src/data/queries/documents.ts`) is Borg-only. The cyberTRADE workstream depends on this being built (§10.7 of this doc). The spec should explicitly flag this as a build dependency, not assume it.

18. **Spec references "existing FIX integration on the issuer side" (§12B.7) — no such integration found.** Second-pass review of `metalex-tech/cybercorps-contracts` and `metalex-tech/metalex-webapp` found no existing FIX protocol integration anywhere. This appears to be either (a) aspirational drafting language, (b) a reference to a planned-but-unbuilt component, or (c) an error in the spec. The cyberTRADE workstream introduces the first FIX-format metadata anywhere in the stack, with `FundInterestExtension.lastTrade` (§1.4) and the `FIXTradeReceipt` event (§9). The spec language should be updated to reflect that the FIX integration is being introduced by cyberTRADE, not extending an existing one.

19. **`CyberShares.sol` exists as a partial implementation in the codebase.** `src/CyberShares.sol` (340 lines) is a hybrid ERC20 + ERC721-like share-class layer with `formCertificateFromShares` / `voidToShares` interfaces, currently incomplete (`certificateTokenURI` returns empty string, key logic stubbed). It is not referenced in the spec or in this impl doc. Decision point before committing to the `FundInterestExtension` build path of §1: (a) does the project want to complete `CyberShares.sol` and use it as the foundation for fund-interest shares (fungible LP units with an optional per-LP cert layer)? (b) or treat fund interests as pure cert-with-extension on the existing `CyberCertPrinter`? This document assumes (b); option (a) would be a meaningfully different architecture and should be confirmed-or-rejected before the FundInterestExtension work starts.

20. **Storage namespacing discipline as a quasi-spec requirement.** Every stateful contract in the codebase uses `keccak256("metalex.<contract>.storage.v<N>")` as a namespaced storage slot via a dedicated `*Storage.sol` library (see `src/storage/`). This pattern enables non-breaking upgrades and is enforced by the upgrade migration scripts (`script/upgrade-legacy-*.s.sol`). All new contracts in the cyberTRADE workstream (`OfferRegistry`, `FundInterestExtension`, every new `ICondition`, the bid holding escrow extension) must follow this pattern. The spec should reference this as the protocol's upgrade discipline so it's not silently dropped by new contributors.

---

## 14. Sequenced Delivery Plan

A pragmatic order of work that lets each step ship independently. Three workstreams run in parallel: protocol-layer (contracts), application-layer (webapp), and operational-infrastructure (indexer, keeper, ops tooling).

**Protocol-layer (cybercorps-contracts).**

1. **`FundInterestExtension`** + encoding helpers in webapp. Mergeable; immediately unblocks primary issuance of fund interests through cyberRAISE. *Decision gate: confirm-or-reject the `CyberShares.sol` alternative path (§13 item 19) before starting.*
2. **`acquisitionDate` / `tackedFromAcquisitionDate` plumbing** in the extension and the round‑close flow (cyberRAISE side). Tested by minting fund certs and asserting the date is the round close date, not the mint date.
3. **Activate per‑token restriction hooks** in `CyberCertPrinter._update`. Behind a printer-level feature flag if needed to avoid disturbing existing deployments.
4. **`GlobalKillCondition` + `TimeSettlementPeriodCondition`**. Deployed and attached‑by‑default by `DealManagerFactory`. No behavioral effect on primary issuance because they pass when not raised / once delay elapses.
5. **`DealManagerFactory` integrator whitelist + per‑deal `feeDestination`**. No behavioral change to existing deployments because `defaultIntegrator == 0` and `feeDestination == 0` keep the legacy flow.
6. **`DealManager` secondary trade mode** (`tradeType`, `sellerAddress`, `xferIntent`, payment-only escrow, payment routing to seller, fee split — §3.2). `corpAssets` empty for secondary trades; no NFT deposit step.
7. **`IssuanceManager.executeSecondaryTransfer`** entry point (§8). BorgAuth‑gated to the SPV's DealManager via `SECONDARY_TRANSFER_ROLE`. Implements the unified mutate‑and‑mint with endorsement‑lock and FIX stamping. The `attachOpenEndorsement` helper that `OfferRegistry.acceptOffer` calls also lives in `IssuanceManager`.
8. **`CyberAgreementRegistry` additive surface** (`createOpenAgreement`, `attachAndSignAsPartyB`, `openToMatching` flag — §7.1). No change to existing `createContract` flow; primary issuance unaffected.
9. **Trade agreement templates** registered in `CyberAgreementRegistry` via a new `script/RegisterTradeAgreementTemplates.s.sol` modeled on `script/template.s.sol` / `templatev2.s.sol`. Markdown sources land in `templates/`.
10. **New `ICondition` implementations** (§5.1). Smaller list than the prior draft enumerated: extend `LexChexCondition` for accredited / QP / QIB; reuse `NonUSNationalityCondition` and `IssuerApprovalRecertificationCondition`. New code: `HolderCapCondition`, `HoldingPeriodCondition`, `KYCAMLCondition`, `Section4a7DisclosureCondition`, `Rule144DisclosureCondition`, `AgreementSignedCondition`, `ERISACondition`, `RegSDistributionComplianceCondition`, `LegalOpinionCondition`, `CFIUSCondition`, `TaxInfoCondition`, `PriceAnomalyCondition`, `GPLPApprovalCondition`, `LegionSoulboundCondition`. All follow the existing storage-namespacing discipline (§13 item 20).
11. **`OfferRegistry`** contract (§4), including: the pre‑signed open‑endorsement signature storage and `acceptOffer` → `attachOpenEndorsement` + `attachAndSignAsPartyB` + `proposeSecondaryDeal` orchestration for sell-side initiation; the bid-commitment holding escrow opened at `postOffer` and migrated into the trade settlement escrow at `acceptOffer` for buy-side initiation (§4.5). Both sides share the same `Offer` storage struct, the same agreement-template registry, the same condition set, and the same downstream settlement code. SPV registration enforces `CyberCertPrinter.endorsementRequired() == true` (§13 item 14).
12. **`FundSPVFactory`** extending `PumpCorpFactory` (§13 item 20 architecture; details in §15). Bundles SPV-specific subscription template + cyberCORP + IssuanceManager + DealManager + RoundManager into a single EIP-712-bundled deployment.

**Operational-infrastructure (indexer / keeper / ops).**

13. **Indexer schema additions and CyberAgreementRegistry event handlers** (Ponder). Adds the `agreement`, `offer`, `offer_acceptance`, `fix_trade_receipt`, optional `endorsement` denormalized table, plus off-chain `user_spv_entitlement` and `user_seasoning`. **CyberAgreementRegistry event handlers are net-new — they are not in the current Ponder config and are a prerequisite for cyberTRADE's UI to function** (§13 item 18 of this doc, §11 of impl doc).
14. **Keeper service.** Auto-finalize on ready conditions + auto-void on expiry (both trade settlement escrows and bid-commitment holding escrows). Convenience layer, not trust layer.
15. **MPC / embedded-wallet integration.** Privy, Web3Auth, Magic, Turnkey, or equivalent. Multi-week dependency that the spec implicitly assumes. Must satisfy the Covered UI Provider statement's "self-custodial wallet" condition (user controls at least one key shard via auth provider). Required for any LP/buyer who does not bring their own wallet.

**Application-layer (metalex-webapp).**

16. **`useUploadPdfToPinata` reuse and Pinata API key allocation.** Trade-agreement templates and disclosure packages all flow through this. Existing infrastructure; only ops setup required.
17. **Per-cyberCORP documents tab** (§10.7). Build the disclosure-document management UI required by spec §4.3.1 — no current equivalent for cyberCORP (legacy `documents` system is Borg-only).
18. **Cap-table import workflow.** Bulk-mint UI for migrating offchain LP records to onchain certs with historical `acquisitionDate` capture (Phase 2 Option C of spec; §13 item 16 of this doc).
19. **Officer / BorgAuth admin UI.** Surfaces the indexed `officer` and `role` tables; CRUD operations call the corresponding contract functions. Prerequisite for the admin panel (§10.6) and for cyberTRADE's BorgAuth role rotation (e.g., `SECONDARY_TRANSFER_ROLE`).
20. **Per-SPV settings / config panel.** Renders and mutates `settlementMode`, `qmsMode`, `endorserOfRecord`, plus existing flags (`requiresLexChex`, etc.). Lives under the cyberCORP admin route.
21. **Webapp UI for cyberTRADE itself.**
    - **Offer Builder** modeled on cyberSign's `CreateAgreementForm` + cyberRAISE's `CreateRoundForm` (using `useFormSession` multi-step pattern); CyTE design-system components for asset / date / select inputs (§10.1).
    - **Discovery view** extending `PublicRoundsList` (§10.2).
    - **Acceptance view** modeled on cyberSign's `SignAgreementForm` (§10.3).
    - **Deposit + Settlement view** modeled on CyTE's `ExecuteLexscrowAgreement` (§10.4).
    - **GP Monitoring** extending `CertsTable` (§10.5).
22. **Notifications integration.** Plug cyberTRADE state changes (offer posted, accepted, ready to deposit, ready to settle, expired) into the existing `useNotifications` aggregator (`apps/cybercorps-web/src/features/notifications/`).
23. **Pathway F admin panel** for void / force transfer / Global Kill governance (§10.6).

**Sequencing notes.**

- Items 1–4 are protocol upgrades with no functional change to existing flows; they can land on `main` without coordinating with the webapp.
- Item 5 is the first change that requires coordinated webapp release (the integrator address must be supplied somewhere).
- Items 6–12 are the secondary‑trade protocol core; items 13–15 are operational infrastructure; items 16–23 are application layer.
- Items 15 (MPC wallets) and 17 (disclosure documents) are large dependencies that the spec assumes exist; they need to land before any cyberTRADE flow is end-to-end functional.
- The legacy NFT‑escrow opt-in (§3.4) and QMS mode (§4.7) are deferred enhancements that ride on top of this sequence and are not built in the initial deployment.

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
- `src/hooks/uniswap/MetalexIssuerFeeHook.sol` — Uniswap v4 hook skeleton; deferred §13A scrip-AMM groundwork.
- `src/libs/auth.sol`, `src/storage/BorgAuthStorage.sol` — BorgAuth role wiring.
- `src/libs/conditions/{baseCondition,lexchexCondition,OrCondition,NonUSNationalityCondition,IssuerApprovalRecertificationCondition}.sol` — **existing condition primitives to extend, not duplicate** (§5.0).
- `src/creds/lexchex.sol`, `src/creds/lexchexMinter.sol`, `src/creds/storage/lexchexStorage.sol` — LeXcheX core; `Accreditation` struct already carries `investorName` / `investorType` / `investorJurisdiction` / `expiryDate`; soulbound (ERC5484); LeXcheXMinter is the oracle pattern. No `LeXcheXAdapter` / `LegionSoulboundAdapter` / `LeXcheXNameLookup` needed; use `ILexChex` directly. Legion's custom credentialing layer is a parallel LeXcheX deployment.
- `src/interfaces/{ILexChex,IZKPassportVerifier,ICondition,ITransferRestrictionHook,ICertificateConverter}.sol` — already-defined interfaces.
- `src/PumpCorpFactory.sol`, `src/CyberCorpFactory.sol`, `src/CyberCorpSingleFactory.sol`, `src/MetaDAOFactory.sol`, `src/ParentCoFactory.sol` — factory landscape. `FundSPVFactory` extends `PumpCorpFactory` (closest existing analog to a fund-SPV factory).
- `src/CyberShares.sol`, `src/storage/CyberSharesStorage.sol` — partial implementation; decision gate before FundInterestExtension build (§13 item 19).
- `src/CyberScrip.sol`, `src/storage/CyberScripStorage.sol` — existing scrip implementation with compliance flags; foundation for any future scrip-trading layer.
- `src/converters/SafeCertificateConverter.sol` — converter pattern reference.
- `src/{CyberCorp,DealManager,IssuanceManager}WithMigration.sol`, `src/helpers/RoundManagerUpgradeHelper.sol` — migration pattern for upgrading existing deployments; cyberTRADE protocol changes land as new `*WithMigrationV2` contracts via this pattern.
- `script/{template,templatev2,add-spa-plus-templates}.s.sol` — existing template-registration script pattern; new cyberTRADE templates follow this. `script/deploy-non-us-zkpassport-condition.s.sol` shows how to deploy a condition. `script/upgrade-legacy-*.s.sol` files are the migration playbook.
- `templates/` — existing markdown sources for cyberSAFE/cyberSAFTE/cyberSAFT/cyberTokenWarrant Reg D/Reg S variants; cyberTRADE templates land here under a consistent naming convention.

Webapp (`metalex-tech/metalex-webapp`):

**cyberSign — primary precedent for trade-agreement creation and signing (§10.1, §10.3):**
- `apps/web/src/app/(frame-layout)/cybersign/create/` — `CreateAgreementForm` (templated agreement creation).
- `apps/web/src/app/(frame-layout)/cybersign/[chainId]/[agreementId]/` — `SignAgreementForm` (per-party EIP-712 signing, delegation, condition-status display).
- `apps/web/src/features/cyber-agreement-registry/hooks/useCyberAgreementRegistry.ts` — `useCyberAgreementRegistryAgreementSummary`, `useCyberAgreementRegistryContractDetails`, `useCyberAgreementRegistryDelegations`.

**CyTE / LeXscroW — precedent for escrow deposit and settlement (§10.4):**
- `apps/web/src/app/(frame-layout)/lexscrow/propose/_forms/ProposeLexscrowAgreement.tsx` — escrow proposal form (not the agreement-templating precedent).
- `apps/web/src/app/(frame-layout)/lexscrow/double-token-lexscrow-agreement/[agreementAddress]/_forms/ExecuteLexscrowAgreement.tsx` — escrow deposit + finalize flow.
- `apps/web/src/app/(frame-layout)/lexscrow/_hooks/{useFeeBasisPoints,useEscrowBalance,useLexscrowsForAddress,useAgreementDetails,useSignedAgreement,useReadFees}.ts` — escrow read-side hooks.

**Design-system components (reusable across cyberSign and CyTE):**
- `packages/design-system/forms/components/` — `AssetInput`, `AssetValueLabel`, `PartyHeader`, `EmbeddedAgreement`, `TransactionActionButton`, `ExpiryCard`, `SummaryBox`.
- `packages/design-system/forms/fields/{DateInputField,FormSelectField,FormSelectOrInputField}.tsx`.

**cyberRAISE — multi-step form pattern and extension-data encoding:**
- `apps/cybercorps-web/src/features/rounds/forms/CreateRoundForm.tsx` — round configuration; multi-step form precedent.
- `apps/cybercorps-web/src/features/rounds/hooks/{useSubmitEOI,useAllocate,useCloseRoundNow}.ts` — flow patterns and Wagmi usage.
- `apps/cybercorps-web/src/features/forms/session/useFormSession.ts`, `FormStepsLayout`, `useFormSessionRouter` — **reusable multi-step form pattern with Jotai-atom state and localStorage persistence**; basis for cyberTRADE's Offer Builder.
- `apps/cybercorps-web/src/features/forms/form-builder/helpers/extensionData.ts` — extension encoder dispatch; add `encodeFundInterestExtensionData`.

**Listings / discovery (precedent for §10.2):**
- `apps/cybercorps-web/src/app/(frame-layout)/cyberraise/public-rounds/` — `PublicRoundsList`; sortable/filterable/paginated Covered-UI-Provider-compliant listings page.

**Hooks for cyberTRADE to extend:**
- `apps/cybercorps-web/src/features/api/lexchex/useLexchexForAddress.ts` — credential check via `ILexChex.hasValidLexCheX`. Read other accreditation fields directly via `ILexChex.getAccreditationByOwner` + `accreditations(tokenId)` — no new adapter hook needed.
- `apps/cybercorps-web/src/features/api/upload/useUploadPdfToPinata.ts` — **Pinata is the IPFS provider**. Trade-agreement templates, disclosure packages, and GP attestation documents flow through this hook.
- The `useDealsForX` family (`useDealsForInvestor`, `useDealsForFounder`, `useDealsForCyberCorp`, `useDealById`, `useDealForCyberCert`, `useOpenDealsForInvestor`, `useExpiredDealsForInvestor`) — precedent for `useOffersFor*` family.
- `apps/cybercorps-web/src/features/conditions/hooks/useRoundConditionsState.ts` — condition-status hook pattern; parameterize for cyberTRADE's condition set.

**Notifications (existing aggregator to plug into, §10.x):**
- `apps/cybercorps-web/src/features/notifications/hooks/useNotifications.ts` — aggregates EOI, deal, and round state changes with 14-day auto-expiry. cyberTRADE state changes plug into this; **no new notification UI needed**.

**GP / admin / cap table:**
- `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/mainframe/_components/CertsTable.tsx` — GP cap-table view; basis for GP monitoring (§10.5).
- `apps/cybercorps-web/src/app/(frame-layout)/cybercorps/admin/` — existing admin route; basis for the expanded admin panel (§10.6) and SPV settings panel.

**Indexer (Ponder):**
- `apps/cybercorps-indexer/ponder.schema.ts` — indexer schema; new `agreement`, `offer`, `offer_acceptance`, `fix_trade_receipt`, optional `endorsement` tables go here. Existing tables: `cyberCorp`, `officer`, `role`, `certPrinter`, `cyberCert`, `cyberScripBalance`, `deal`, `dealCerts`, `round`, `eoi`, `pumpWrappedToken`.
- `apps/cybercorps-indexer/ponder.config.ts` — event-handler registration; **add `CyberAgreementRegistry` handlers** (gap surfaced in second-pass review, §13 item 18).
- `apps/cybercorps-indexer/src/api/{rounds,deals,cybercerts,cybercorps}/...-routes.ts` — REST route patterns; new `offers-routes.ts` and `agreements-routes.ts` follow them.

**EVM provider stack (relevant to MPC integration §14 step 15):**
- `apps/cybercorps-web/src/features/providers/EvmProviders.tsx` — current ConnectKit + wagmi stack; **no MPC / embedded-wallet integration exists yet**.

These pointers, plus the structural changes in §3–§11, are the bridge from the v2.04 spec to a working implementation that fits the cybercorps protocol and the metalex webapp as they exist today.

---

## Appendix A — End-to-End Worked Trades (Unified Pathway)

Reference walkthroughs through the architecture in §3–§9. The intent is to give an implementer a concrete step-by-step trace they can match against the protocol code as they build. Legal/regulatory framing lives in the body sections above and is not repeated here.

### A.0 Setup (shared by both walkthroughs)

**SPV X.** Delaware LLC, 3(c)(1), 100-holder cap, USDC on Arbitrum. Onboarded with defaults: `settlementMode = UNIFIED`, `qmsMode = false`, `endorserOfRecord = SELLER`. `CyberCertPrinter.endorsementRequired = true` (precondition for OfferRegistry registration, §4.2). Disclosure package URI current; GP underlying-asset provenance attestation hash recorded.

**Contracts deployed for SPV X.** `cyberCorp`, `IssuanceManager`, `CyberCertPrinter` (with `FundInterestExtension` bound), `DealManager`, `CyberAgreementRegistry`, plus the per-SPV conditions (`HolderCapCondition`, `LegionSoulboundCondition`, etc.). The `DealManager` holds the `SECONDARY_TRANSFER_ROLE` on the SPV's BorgAuth, granting it the authority to call `IssuanceManager.executeSecondaryTransfer`.

**Shared infrastructure.** Single `OfferRegistry` deployed protocol-wide. Single `GlobalKillCondition` (bilateral MetaLeX/Legion admins). `TimeSettlementPeriodCondition` with default 24h. `DealManagerFactory` with Legion whitelisted as an integrator at 40% fee share.

**Trade-agreement templates.** `TEMPLATE_4A7` registered in `CyberAgreementRegistry`, IPFS-hosted.

**Cast of characters.**

| Party | Role | Custody | Wallet | LeXcheX state |
|---|---|---|---|---|
| Alice | Existing LP in SPV X, holds cert #42 = 1000 units, `acquisitionDate = 2024-01-15` | Administered (cert in ledger administrator multisig; `OwnerDetails = {Alice Doe, 0xAlice}`) | `0xAlice` (Legion-provisioned MPC wallet) | KYC + accredited, current |
| Bob | Prospective buyer, whitelisted on Legion's UI for SPV X, seasoned 30+ days | Direct (cert will be minted to his wallet) | `0xBob` (Legion-provisioned MPC wallet) | KYC + accredited + Legion-SPV-X Soulbound, current |
| Carol | Prospective buyer | Direct | `0xCarol` | KYC + accredited + Legion-SPV-X Soulbound, current |
| Dave | Existing LP in SPV X, holds cert #87 = 500 units, `acquisitionDate = 2024-06-01` | Administered | `0xDave` | KYC + accredited, current |

---

### A.1 Sell-Initiated Trade (Alice posts; Bob accepts)

Alice wants to sell 200 of her 1000 units for 50,000 USDC under Section 4(a)(7).

#### Phase 1 — Alice posts the offer

Alice opens her SPV X holder dashboard, sees cert #42, clicks "Post Offer to Sell." Offer Builder loads with cert #42 pre-selected and her 4(a)(7) template rendered.

She fills in: side = SELL, units = 200, consideration = 50,000 USDC, exemption = 4(a)(7), validUntil = now + 30d, counterparty restrictions = {accredited, Legion-SPV-X Soulbound}.

She clicks "Sign and Post Offer." Her wallet prompts her once with a bundled EIP-712 typed-data payload containing:
- **Agreement signature**: party-A-as-seller signature on TEMPLATE_4A7 with her partyAValues populated (her affiliate-status disclosure, governing-document references, etc.).
- **Open-endorsement signature**: signature on `OpenEndorsement{offerId, spvCyberCorp = SPV X, certId = 42, units = 200, agreementId, exemptionBasis = "4A7", validUntil}`.

The transaction lands. `OfferRegistry.postOffer`:
1. Validates Alice is `OwnerDetails.ownerAddress[42]` (she is). ✓
2. SPV X is registered, Legion is an approved integrator, USDC is on SPV X's allowlist, the cert printer has `endorsementRequired = true`. ✓
3. Calls `CyberAgreementRegistry.createOpenAgreement(TEMPLATE_4A7, partyA = Alice, partyAValues, partyASignature, validUntil, openToMatching = true)`. Agreement record created, `agreementId` returned.
4. Stores the `Offer` struct: `{side: SELL, offeror: Alice, certId: 42, units: 200, consideration: 50_000e6, exemptionPathway: SECTION_4A7, validUntil, restrictions, integrator: Legion, agreementId, offerorEndorsementSignature, bidCommitmentEscrowId: 0, status: LIVE}`.
5. Emits `OfferPosted(offerId, ...)`.

**State after Phase 1:** Offer is LIVE. Agreement is partially signed (Alice as A; openToMatching = true). Cert #42 is untouched in the multisig. No funds have moved.

#### Phase 2 — Bob discovers and accepts

The Ponder indexer ingests `OfferPosted` and writes a row to the `offer` table. `/api/offers` is called by Bob's authenticated session and returns Alice's offer (Bob passes the eligibility filter: accredited, Soulbound, seasoned).

Bob clicks the offer, lands on the Acceptance view. The view runs his side of the compliance checklist (KYC ✓, accreditation ✓, Soulbound ✓, ERISA negative attestation needed, tax info on file ✓). Bob clicks the ERISA checkbox and the 4(a)(7) information-package acknowledgment modal (records his acknowledgment in `partyBValues`).

Bob clicks "Sign and Accept." His wallet prompts him once with an EIP-712 typed-data payload containing:
- **Agreement signature**: party-B-as-buyer signature on the same TEMPLATE_4A7 with his `partyBValues` populated (accredited rep, ERISA negative attestation, information-package acknowledgment, tax-info covenant).
- **USDC approval** (implicit, runs as part of the transaction bundle): `USDC.approve(DealManager, 50_000e6)`.

The transaction lands. `OfferRegistry.acceptOffer(offerId, units = 200, partyBValues, acceptorAgreementSignature, acceptorEndorsementSignature = empty)`:
1. Validates offer LIVE, within validUntil, units within range. ✓
2. Validates Bob satisfies `restrictions` via LeXcheX. ✓
3. Calls `CyberAgreementRegistry.attachAndSignAsPartyB(agreementId, partyB = Bob, partyBValues, partyBSignature)`. Agreement → `finalized = true`, `openToMatching = false`. `AgreementSignedCondition` now passes.
4. Calls `IssuanceManager.attachOpenEndorsement(certId = 42, units = 200, endorsee = Bob, endorseeName = "Bob Smith" from LeXcheX)`. The IssuanceManager assembles the `Endorsement` struct: `{endorser: Alice (per endorserOfRecord = SELLER), timestamp: now, signatureHash: offer.offerorEndorsementSignature, registry: CyberAgreementRegistry, agreementId, endorsee: Bob, endorseeName: "Bob Smith"}` and calls `CyberCertPrinter.addEndorsement(42, ...)`. The cert now has an endorsement-lock; any transfer of #42 to anyone other than Bob will fail in `_update`.
5. Calls `DealManager.proposeSecondaryDeal(seller = Alice, buyer = Bob, paymentToken = USDC, paymentAmount = 50_000e6, sellerCertId = 42, units = 200, isFullSale = false, agreementId, conditions = [4(a)(7) condition set], expiry = now + 7d, feeDestination = Legion, offerId, exemptionBasis = "4A7")`. Creates the escrow with `tradeType = SECONDARY_TRADE`, `corpAssets = []`, `buyerAssets = [{USDC, 50_000e6, isFee: true}]`, `sellerAddress = Alice`, `counterParty = Bob`, `xferIntent = {sellerCertId: 42, units: 200, buyer: Bob, isFullSale: false, agreementId, exemptionBasis: "4A7"}`.
6. Emits `OfferAccepted(offerId, dealId, ...)` and `DealProposed(dealId, ...)`. Sets offer status = FULLY_ACCEPTED.

**State after Phase 2:** Contract formed. Endorsement-lock active on cert #42. Escrow in `PENDING` state awaiting Bob's payment deposit.

#### Phase 3 — Bob deposits payment

The webapp routes Bob to the Deposit + Settlement view. Only the buyer deposit row is shown (Alice has no deposit step). Bob clicks "Deposit Payment" → `DealManager.depositPayment(dealId)` (or the LexScroWLite equivalent). 50,000 USDC pulled from `0xBob` into the escrow. Status → `PAID`. Emits `BuyerDeposit`. `TimeSettlementPeriodCondition` clock starts.

#### Phase 4 — 24-hour window + conditions

24 hours pass. All conditions evaluate continuously:
- `AccreditedInvestorCondition`: Bob accredited in LeXcheX. ✓
- `KYCAMLCondition`: both parties' KYC current. ✓
- `Section4a7DisclosureCondition`: SPV X's disclosure URI fresh + Bob's acknowledgment recorded in agreement. ✓
- `ERISACondition`: Bob's negative attestation in agreement. ✓
- `HolderCapCondition`: SPV X currently at 87 holders; adding Bob → 88; ≤ 100. ✓
- `TaxInfoCondition`: Bob's W-9 on file. ✓
- `AgreementSignedCondition`: agreement finalized. ✓
- `LegionSoulboundCondition`: Bob holds the SPV-X badge. ✓
- `GlobalKillCondition`: kill flag low. ✓
- `TimeSettlementPeriodCondition`: 24h elapsed since `BuyerDeposit`. ✓ (after 24h)

#### Phase 5 — Finalization (keeper)

Keeper detects the ready state and calls `DealManager.signAndFinalizeDeal(dealId)`. Inside:

1. Re-evaluate all conditions. All pass.
2. Compute fee split. Protocol fee = 50,000 × 50 bps = 250 USDC. Integrator share = 250 × 40% = 100 USDC to Legion. MetaLeX share = 150 USDC. Net to Alice = 49,750 USDC.
3. Branch on `tradeType` and seller's custody: SECONDARY_TRADE + Administered → call `IssuanceManager.executeSecondaryTransfer(xferIntent, buyer = Bob, buyerName = "Bob Smith", buyerCustodyMode = DIRECT, ledgerAdministratorMultisig = N/A)`.
4. `executeSecondaryTransfer` (BorgAuth-gated to DealManager via SECONDARY_TRANSFER_ROLE):
   - Confirms the endorsement on cert #42 matching `agreementId` is present (it is — added at Phase 2 step 4). Leaves it in place as the chain-of-title record.
   - `CertPrinter.updateCertificateDetails(42, ...)`: decrement `unitsRepresented` from 1000 to 800; update `FundInterestExtension.lastTrade` to record the FIX trade fields.
   - `CertPrinter.safeMintAndAssign(to = 0xBob, name = "Bob Smith", ownerAddress = 0xBob, ...)`. New cert tokenId = 87 (next sequential). Cert data: `unitsRepresented = 200`, `OwnerDetails = {Bob Smith, 0xBob}`, `extensionData` encoded with `FundInterestData{acquisitionDate = now, tackedFromAcquisitionDate = 0, exemptionBasis = "4A7", custodyMode = DIRECT, lastTrade = <full FIX record>, ...}`, applicable 4(a)(7) restriction legends.
   - `CertPrinter.addEndorsement(87, ...)`: mirror endorsement on the new cert: `{endorser: Alice, signatureHash: offer.offerorEndorsementSignature, registry, agreementId, endorsee: Bob, endorseeName: "Bob Smith", timestamp: now}`.
5. Route USDC: 49,750 to `0xAlice`, 100 to Legion, 150 to MetaLeX `platformPayable`.
6. Emit `DealFinalized(dealId)`, `FeePaid(dealId, Legion, 100, 150)`, `FIXTradeReceipt(dealId, offerId, fixID, ...)`, `SecondaryTransferExecuted(...)`. Plus the ERC-721 `Transfer(0x0 → 0xBob, 87)` mint event, `CertificateAssigned(87, ...)`, `CertificateDetailsUpdated(42)`, `EndorsementAdded(42)`, `EndorsementAdded(87)`.
7. Escrow status → `FINALIZED`.

#### Phase 6 — Post-settlement state

- Cert #42 in administrator multisig: `OwnerDetails = {Alice}`, 800 units, original `acquisitionDate = 2024-01-15`, endorsement array now has one entry recording the 200-unit transfer to Bob under `agreementId`.
- Cert #87 in Bob's wallet `0xBob`: `OwnerDetails = {Bob Smith, 0xBob}`, 200 units, `acquisitionDate = today`. Bob holds the ERC-721 directly.
- SPV X holder count: 87 → 88.
- Alice's webapp dashboard shows 800 units. Bob's wallet shows the new cert and the webapp dashboard shows him as a SPV X holder with 200 units.

---

### A.2 Bid-Initiated Trade (Carol posts; Dave accepts)

Carol wants to buy 500 units of SPV X for 125,000 USDC. She posts a bid. Dave is a Direct-Custody-less LP whose 500 units (cert #87, `acquisitionDate = 2024-06-01`) match the bid and decides to fill it.

#### Phase 1 — Carol posts the bid

Carol opens the Bid Builder. Fills in: side = BUY, units = 500, consideration = 125,000 USDC, exemption = 4(a)(7), validUntil = now + 14d, counterparty restrictions = empty (any registered owner of SPV X eligible).

She clicks "Sign and Post Bid." Her wallet prompts her with an EIP-712 bundle:
- **Agreement signature**: party-A-as-buyer signature on TEMPLATE_4A7 with her `partyAValues` (accredited rep, ERISA negative attestation, information-package acknowledgment, tax-info covenant, etc.).
- **USDC approval**: `USDC.approve(OfferRegistry, 125_000e6)`.

The transaction lands. `OfferRegistry.postOffer(side = BUY, tokenIdOrZero = 0, units = 500, ..., offerorEndorsementSignature = empty)`:
1. Validates BUY-side conditions: Carol has approved `OfferRegistry` for 125_000e6 USDC, SPV X registered, Legion approved integrator, USDC on allowlist.
2. Calls `CyberAgreementRegistry.createOpenAgreement(TEMPLATE_4A7, partyA = Carol, partyAValues, partyASignature, validUntil = now + 14d, openToMatching = true)`. Returns `agreementId`.
3. Opens a `LexScroWLite` holding escrow keyed by the new `offerId` and pulls 125,000 USDC from Carol into it. Returns `bidCommitmentEscrowId`.
4. Stores the `Offer` struct with `side: BUY, offerorEndorsementSignature: empty, bidCommitmentEscrowId, agreementId, status: LIVE`.
5. Emits `OfferPosted(offerId, side: BUY, bidCommitmentEscrowId, ...)`.

**State after Phase 1:** Bid is LIVE. Carol's 125,000 USDC is custodied by `LexScroWLite` keyed to this bid. Agreement is partially signed (Carol as A; openToMatching = true). No cert has moved.

#### Phase 2 — Discovery and Dave accepts

The indexer surfaces the bid to registered owners of SPV X with ≥500 units. Dave's session pulls `/api/offers` and the bid appears. He reviews — 125,000 USDC for his 500 units is a price he likes.

Dave clicks "Accept Bid." The acceptance view runs his side of the compliance checklist (KYC ✓, holding period elapsed (under 1 year, but this is a 4(a)(7) trade — the seller-side requirement is the SPV's 90-day-outstanding check, not Rule 144 hold), affiliate disclosure (he's not an affiliate), Reg-S distribution-compliance N/A, tax info on file ✓).

Dave clicks "Sign and Accept Bid." His wallet prompts him once with an EIP-712 bundle:
- **Agreement signature**: party-B-as-seller signature on the same TEMPLATE_4A7 with his `partyBValues` (affiliate-status disclosure, governing-document references).
- **Open-endorsement signature**: signature on `OpenEndorsement{offerId, spvCyberCorp = SPV X, certId = 87, units = 500, agreementId, exemptionBasis = "4A7", validUntil}`.

The transaction lands. `OfferRegistry.acceptOffer(offerId, units = 500, partyBValues, acceptorAgreementSignature, acceptorEndorsementSignature)`:
1. Validates bid LIVE, within validUntil, units = 500 ≤ unitsOffered.
2. Validates Dave is a registered owner of cert #87 with ≥500 units. ✓ (And he satisfies any counterparty restrictions — empty in this bid.)
3. Calls `CyberAgreementRegistry.attachAndSignAsPartyB(agreementId, partyB = Dave, partyBValues, partyBSignature)`. Agreement → finalized.
4. Calls `IssuanceManager.attachOpenEndorsement(certId = 87, units = 500, endorsee = Carol, endorseeName = "Carol Jones")`. Constructs the `Endorsement`: `{endorser: Dave, timestamp: now, signatureHash: acceptorEndorsementSignature, registry, agreementId, endorsee: Carol, endorseeName: "Carol Jones"}`. Adds to cert #87. Endorsement-lock active.
5. **Migrates the holding escrow into the trade settlement escrow.** Calls `LexScroWLite.migrateTo(bidCommitmentEscrowId, 125_000e6, newTradeEscrowId)`. Carol's 125,000 USDC moves from the holding escrow into the trade's settlement escrow, which opens in `PAID` state immediately.
6. Calls `DealManager.proposeSecondaryDeal(seller = Dave, buyer = Carol, sellerCertId = 87, units = 500, isFullSale = true, ...)`. Records `tradeType = SECONDARY_TRADE`, `sellerAddress = Dave`, `counterParty = Carol`, `xferIntent`.
7. Emits `OfferAccepted`, `DealProposed`. Offer status = FULLY_ACCEPTED.

**State after Phase 2:** Contract formed. Endorsement-lock active on cert #87. Trade settlement escrow already in `PAID` state — no buyer deposit step needed. `TimeSettlementPeriodCondition` clock starts.

#### Phase 3 — (skipped: no buyer deposit needed)

#### Phase 4 — 24-hour window + conditions

Same as Phase 4 of A.1, with the relevant condition set evaluated against Dave (seller) and Carol (buyer).

#### Phase 5 — Finalization

Keeper calls `signAndFinalizeDeal`. `executeSecondaryTransfer` runs:
- Cert #87 is voided (isFullSale = true): `CertPrinter.voidCert(87)`. SecurityStatus → Void. Endorsement array retained as historical record.
- New cert minted to Carol via `safeMintAndAssign(to = 0xCarol, name = "Carol Jones", ownerAddress = 0xCarol, ...)`. New tokenId = 88. `unitsRepresented = 500`, `acquisitionDate = today`, custody mode = DIRECT (Carol's election), full 4(a)(7) FIX record.
- Mirror endorsement appended on cert #88.
- Payment routed: 125,000 × 50bps = 625 protocol fee; 250 to Legion, 375 to MetaLeX, 124,375 to Dave.

#### Phase 6 — Post-settlement state

- Cert #87: Voided. Sits in administrator multisig with endorsement and `SecurityStatus.Void`. Historical record only.
- Cert #88: Lives in Carol's wallet `0xCarol`. 500 units of SPV X. `OwnerDetails = {Carol Jones, 0xCarol}`. Carol now appears as an SPV X holder in the webapp and on chain.
- SPV X holder count: Dave departed (-1, since #87 was his only cert) + Carol joined (+1) = net zero. Still 87.

---

### A.3 Variants

The walkthroughs above cover (A.1) Administered seller → Direct buyer via sell offer, and (A.2) Direct buyer → Administered seller via bid. Other combinations differ in only one or two lines each:

| Variant | Difference vs. A.1/A.2 |
|---|---|
| Both Administered (sell offer) | At Phase 5 mint, `safeMintAndAssign(to = ledgerAdministratorMultisig, name = buyerName, ownerAddress = buyer)`. New cert lives in the multisig with the buyer as registered owner. Otherwise identical. |
| Both Direct (sell offer) | At Phase 1, the seller's cert is in their own wallet; the endorsement-lock at Phase 2 step 4 prevents transfer to anyone other than the buyer. At Phase 5 mint, new cert goes to buyer's wallet. |
| Sell offer, Direct seller | Same as both-Direct above; the endorsement-lock is the structural protection during pendency. |
| Bid, Administered bidder | At Phase 1, Carol's funds still flow into the holding escrow; Carol's custody mode affects only where her new cert lands at Phase 5. |
| Partial sale (full sale's analog under bid) | At Phase 5, instead of `voidCert(87)`, call `updateCertificateDetails(87, ...)` to decrement `unitsRepresented`. Mint a new cert for the sold portion. The unsold remainder stays with the original holder. |
| QMS mode (per-SPV opt-in, deferred build) | Phase 2 step 3 attaches party B but does not finalize; agreement enters `qmsCoolOff` until day 15. Phase 5 keeper waits 45 days from `qmsListedAt`. |
| NFT_ESCROW mode (per-SPV opt-in, deferred build) | Phase 2 / 3 adds a seller deposit step: the seller approves and deposits the cert into LexScroWLite. At Phase 5, the cert transfers from escrow to the buyer's wallet (or to the multisig). |
| `endorserOfRecord = LEDGER_ADMINISTRATOR` | The `Endorsement.endorser` field on both certs is the administrator multisig; `signatureHash` remains the seller's signature. Everything else identical. |

---
