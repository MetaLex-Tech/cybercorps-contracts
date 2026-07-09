# Audit Scope v2 — Funds-Critical Surface

Expanded from the previous audit scope (RoundManager / DealManager / LexScroWLite / factories, ~1k SLOC) to cover every path that can move, custody, or release user funds and the securities delivered against them, as of `b4e7014` (2026-07-07).

**Total scope: ~7,750 SLOC** (comment- and license-header-stripped). All SLOC figures below are measured, not estimated. Scripification / CyberScrip / recertification are deferred to a later audit (see "Deferred" section).

## Contracts in scope

### 1. Primary deal & round escrow (direct token custody) — 2,014 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/DealManager.sol | 339 | Entry points, reentrancy guards, escrow receiver hooks, fee resolution, UUPS upgrade gate |
| src/storage/DealManagerStorage.sol | 222 | Actual deal logic (delegatecall-linked): propose/sign/pay/finalize/void/refund |
| src/storage/LexScrowStorage.sol | 244 | Escrow engine (formerly LexScroWLite): pulls, holds, refunds, and pays out ERC20/721/1155; fee split |
| src/RoundManager.sol | 400 | Round entry points: EOI submit/allocate/reject/recall, fee resolution |
| src/storage/RoundManagerStorage.sol | 382 | Actual round logic (delegatecall-linked): createRound, submitEOI (pulls ERC20, optional LexChex mint payment), allocate (partial refund + finalize) |
| src/libs/RoundLib.sol | 99 | Round struct + pricing/validation helpers used by allocation math |
| src/DealManagerFactory.sol | 77 | Fee ratio, platform payable, integrator whitelist + fee shares, reference implementation (upgrade gate) |
| src/storage/DealManagerFactoryStorage.sol | 45 | Storage for the above (BASIS_POINTS, fee params) |
| src/RoundManagerFactory.sol | 87 | Same role for RoundManager |
| src/storage/RoundManagerFactoryStorage.sol | 43 | Storage for the above |
| src/libs/EIP712Lib.sol | 76 | EIP-712 signature verification used by RoundManager/RoundManagerStorage for EOI signatures |

### 2. Secondary trading (new; direct token custody) — 699 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/storage/SecondaryTradeStorage.sol | 539 | Offer/bid custody, partial fills + pro-rata consideration, settlement escrow, seller payout, integrator/platform fee split, void/refund paths, EIP-712 relayer auth |
| src/interfaces/ISecondaryTradeStorage.sol | 160 | Offer/SecondaryEscrow structs, statuses, events/errors (accounting invariants live in these types) |

### 3. Agreement registry (gates every escrow release) — 922 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/CyberAgreementRegistry.sol | 922 | EIP-712 signature verification, delegation, signContractFor / signContractWithEscrow, finalizeContract, voidContractFor — finalize/void here directly triggers payouts and refunds in the managers |

### 4. Securities layer (the assets escrow delivers) — 1,889 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/IssuanceManager.sol | 486 | Only authorized caller of printers: cert creation/assignment, secondaryTransfer, unit reservation. (Excludes ~262 SLOC of scripify/scrip-admin/recertification entry points — deferred) |
| src/storage/IssuanceManagerStorage.sol | 634 | The execute* bodies: executeSecondaryTransfer, cert creation/assignment, reserved-units enforcement. (Excludes ~698 SLOC of scrip vault/exec logic and recert approvals — deferred) |
| src/CyberCertPrinter.sol | 338 | Certificate ERC721: escrow-aware `_update`, legal-owner tracking/indexes, unitsReserved, endorsements, void/unvoid/burn |
| src/storage/CyberCertPrinterStorage.sol | 431 | Cert details, legal owner index maintenance/backfill, restrictive legends, transfer restriction plumbing |

### 5. Conditions gating fund movement — 1,351 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/libs/conditions/secondary/* (18 files) | 1,120 | Threshold + closing conditions evaluated at postOffer / acceptOffer / finalize; includes GlobalKillCondition (kill switch), HolderCapCondition, TimeSettlementPeriodCondition, KYC/AML, Reg S, Rule 144, CFIUS, ERISA, etc. |
| src/libs/conditions/BaseSecondaryTradingCondition.sol | 23 | ISecondaryTradingCondition interface (ERC-165-checked at config time) |
| src/libs/conditions/NonUSNationalityCondition.sol | 144 | ZK-passport-based primary-escrow condition |
| src/libs/conditions/lexchexCondition.sol | 30 | LexChex credential gate on primary escrow |
| src/libs/conditions/OrCondition.sol | 24 | Condition combinator |
| src/libs/conditions/baseCondition.sol | 10 | Base condition |

### 6. Payment-adjacent periphery — 322 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/CyberCorp.sol | 194 | `companyPayable` (destination of every primary payout) and escrowed officer signatures consumed by escrow endorsement |
| src/libs/auth.sol | 109 | BorgAuth / BorgAuthACL: the access control gating every privileged fund action (onlyOwner/onlyAdmin) |
| src/storage/BorgAuthStorage.sol | 19 | Storage for the above |

### 7. Deployment & wiring trust root — 551 SLOC

| File | SLOC | Why |
| --- | --- | --- |
| src/CyberCorpFactory.sol | 462 | Deploys and wires the whole corp stack in one transaction: sets `companyPayable`, initializes DealManager / RoundManager / IssuanceManager with each other's addresses, grants the new RoundManager OWNER in LeXcheX auth, and can atomically create the first offer/round. A wiring bug here misroutes every downstream payout |
| src/IssuanceManagerFactory.sol | 74 | Reference implementations for IssuanceManager, CyberCertPrinter, and CyberScrip — the upgrade gate for the entire securities layer (same trust role as the manager factories) |
| src/storage/IssuanceManagerFactoryStorage.sol | 15 | Storage for the above |

### Deferred to a later audit (scripification / recertification) — 1,314 SLOC saved

Not live at launch. Note the reserved-units accounting itself stays in scope (it is shared with secondary trading), as does `_selectFirstLegalOwnedToken` (shared by recert and secondary transfers).

| Item | SLOC |
| --- | --- |
| src/CyberScrip.sol (entire file) | 257 |
| src/storage/CyberScripStorage.sol (entire file) | 22 |
| src/IssuanceManager.sol — scrip/recert entry points (deployCyberScrip, scripifyCert, convertScripToCert, forceScripTransfer/Burn, freeze, scrip ratio/minimum/whitelist admin, recertification approvals) | 262 |
| src/storage/IssuanceManagerStorage.sol — scrip/recert bodies (executeDeployCyberScrip, executeScripifyCert, executeConvertScripToCert, scrip unit-vault helpers, scrip state getters, recert approval storage) | 698 |
| src/libs/conditions/IssuerApprovalRecertificationCondition.sol | 75 |

### Deliberately out of scope

- `MetalexIssuerFeeHook.sol` (325 SLOC) — Uniswap v4 fee hook on CyberScrip pools; not currently used.
- `src/hooks/transfer/*` — BaseTransferHook, ToggleTransferHook, WhitelistTransferHook (105 SLOC).
- `lexchexMinter.sol` (327 SLOC) and the lexchex/lexchexBadge credential NFTs — credential mint-fee payments; not currently used.
- `CyberShares.sol` / `CyberSharesStorage.sol` (490 SLOC) — not referenced by any other src contract; appears unwired.
- Variant factories that only deploy/wire alternative stacks (PumpCorpFactory, ParentCoFactory, MetaDAOFactory, CyberCorpSingleFactory), URI/image builders, certificate extensions (metadata only), and interfaces other than ISecondaryTradeStorage.

## Core scope — fund-moving functions

| File | Function | Brief explanation |
| --- | --- | --- |
| src/storage/RoundManagerStorage.sol | submitEOI(...) | Create agreement + escrow; pull ERC20 from investor; attach conditions |
| src/storage/RoundManagerStorage.sol | allocate(bytes32, uint256) | Allocate amount, refund difference, finalize escrow (fee split), update raised |
| src/RoundManager.sol | reject(bytes32, bool) | Owner rejects paid EOI; full refund; void escrow/agreement |
| src/RoundManager.sol | recallEOI(bytes32, bool) | Investor recall after expiry; full refund; void escrow/agreement |
| src/RoundManager.sol | computeFee / getPlatformPayable | Fee ratio + destination read from RoundManagerFactory |
| src/storage/DealManagerStorage.sol | proposeDeal(...) | Create agreement, certs, and escrow with buyer/corp assets |
| src/storage/DealManagerStorage.sol | signDealAndPay(...) | Sign, update escrow, pull ERC20 into escrow |
| src/storage/DealManagerStorage.sol | signAndFinalizeDeal(...) | Sign, pull payment, check conditions, finalize |
| src/storage/DealManagerStorage.sol | finalizeDeal(bytes32) | Validate signatures/conditions and finalize escrow |
| src/storage/DealManagerStorage.sol | voidExpiredDeal / signToVoid / revokeDeal / refundVoidedDeal | Void paths; refund buyer assets when paid |
| src/DealManager.sol | setDealRegistry / setCorp / computeFee / getPlatformPayable | Fund-routing configuration |
| src/storage/LexScrowStorage.sol | createEscrow / updateEscrow | Initialize escrow; endorse corp ERC721 certs |
| src/storage/LexScrowStorage.sol | handleCounterPartyPayment(bytes32) | Pull ERC20/721/1155 from buyer; mark PAID |
| src/storage/LexScrowStorage.sol | finalizeEscrow(bytes32) | Pay companyPayable minus fee (callback into manager for fee math), pay platform fee, deliver corp assets |
| src/storage/LexScrowStorage.sol | voidAndRefund / voidEscrow / conditionCheck | Refund buyer assets; verify conditions |
| src/storage/SecondaryTradeStorage.sol | postOffer(params[, forAddr, nonce, sig]) | BID: pull consideration into custody; SELL: reserve seller units; snapshot conditions; relayer EIP-712 auth |
| src/storage/SecondaryTradeStorage.sol | acceptOffer(params[, forAddr, nonce, sig]) | Partial-fill accounting + pro-rata consideration; create fully-signed settlement; SELL: pull buyer payment |
| src/storage/SecondaryTradeStorage.sol | cancelOffer(offerId[, forAddr, nonce, sig]) | Refund/release only the uncommitted pool |
| src/storage/SecondaryTradeStorage.sol | finalizeSecondaryTradeAgreement(bytes32) | Re-check threshold + closing conditions, pay seller, integrator/platform fee split, release reservation, execute cert ownership change |
| src/storage/SecondaryTradeStorage.sol | voidExpiredSecondaryTradeAgreement / voidSecondaryTradeAgreement / syncVoidedSecondaryTradeAgreement | Refund buyer, restore offer accounting, release/retain reservations per side |
| src/CyberAgreementRegistry.sol | signContractFor / signContractWithEscrow | EIP-712 signature verification that authorizes escrow payment |
| src/CyberAgreementRegistry.sol | finalizeContract / voidContractFor / isVoided | The gates managers rely on before paying out or refunding |
| src/IssuanceManager.sol + IssuanceManagerStorage.sol | secondaryTransfer / executeSecondaryTransfer | Void/decrement seller cert, mint buyer cert against settlement metadata |
| src/IssuanceManager.sol + IssuanceManagerStorage.sol | increaseUnitsReserved / decreaseUnitsReserved | Reservation accounting shared by secondary trades and scripify |
| src/CyberCertPrinter.sol | _update / legalOwnerOf / endorseAndTransfer / increase-decreaseUnitsReserved / burn / voidCert | Legal-vs-token ownership, escrow-aware transfer, reservation enforcement |
| src/DealManagerFactory.sol | setDefaultFeeRatio / setPlatformPayable / setIntegrator / setRefImplementation | Fee parameters and upgrade gate trusted by every DealManager |
| src/CyberCorpFactory.sol | deployCyberCorp / deployCyberCorpAndCreateOffer / deployCyberCorpAndCreateRound / deployAndInitializeRoundManager | Wires companyPayable, manager addresses, and auth grants that every subsequent fund flow trusts |

## SLOC summary

| Group | SLOC |
| --- | --- |
| 1. Primary deal & round escrow | 2,014 |
| 2. Secondary trading | 699 |
| 3. Agreement registry | 922 |
| 4. Securities layer | 1,889 |
| 5. Conditions | 1,351 |
| 6. Payment-adjacent periphery | 322 |
| 7. Deployment & wiring trust root | 551 |
| **Core total** | **7,748** |
| Deferred: scripification / recertification | −1,314 |

If the budget needs further trimming toward 7k, the best remaining cuts are the long tail of secondary conditions beyond GlobalKill / HolderCap / TimeSettlementPeriod / AgreementSigned (−~900) or group 7 if deployment wiring is considered operationally verified (−551). We recommend keeping groups 1–4 intact — they are a single connected custody system and the delegatecall-linked library structure means vulnerabilities compose across file boundaries.
