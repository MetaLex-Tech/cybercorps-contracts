# Audit Scope v2 — Funds-Critical Surface

Expanded from the previous audit scope (RoundManager / DealManager / LexScroWLite / factories, ~1k SLOC) to cover every
path that can move, custody, or release user funds and the securities delivered against them, as of `d0f0ae9` (
2026-07-10, includes PR #117 issuance/acquisition timestamps and PR #118 CyberCertPrinter auth refactor).

**Total scope: ~9,100 SLOC** (comment- and license-header-stripped). All SLOC figures below are measured, not estimated.
Includes scripification / CyberScrip / recertification.

## Contracts in scope

### 1. Primary deal & round escrow (direct token custody) — 2,011 SLOC

| File                                       | SLOC | Why                                                                                                                                                 |
|--------------------------------------------|------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| src/DealManager.sol                        | 339  | Entry points, reentrancy guards, escrow receiver hooks, fee resolution, UUPS upgrade gate                                                           |
| src/storage/DealManagerStorage.sol         | 221  | Actual deal logic (delegatecall-linked): propose/sign/pay/finalize/void/refund                                                                      |
| src/storage/LexScrowStorage.sol            | 244  | Escrow engine (formerly LexScroWLite): pulls, holds, refunds, and pays out ERC20/721/1155; fee split                                                |
| src/RoundManager.sol                       | 400  | Round entry points: EOI submit/allocate/reject/recall, fee resolution                                                                               |
| src/storage/RoundManagerStorage.sol        | 380  | Actual round logic (delegatecall-linked): createRound, submitEOI (pulls ERC20, optional LexChex mint payment), allocate (partial refund + finalize) |
| src/libs/RoundLib.sol                      | 99   | Round struct + pricing/validation helpers used by allocation math                                                                                   |
| src/DealManagerFactory.sol                 | 77   | Fee ratio, platform payable, integrator whitelist + fee shares, reference implementation (upgrade gate)                                             |
| src/storage/DealManagerFactoryStorage.sol  | 45   | Storage for the above (BASIS_POINTS, fee params)                                                                                                    |
| src/RoundManagerFactory.sol                | 87   | Same role for RoundManager                                                                                                                          |
| src/storage/RoundManagerFactoryStorage.sol | 43   | Storage for the above                                                                                                                               |
| src/libs/EIP712Lib.sol                     | 76   | EIP-712 signature verification used by RoundManager/RoundManagerStorage for EOI signatures                                                          |

### 2. Secondary trading (new; direct token custody) — 699 SLOC

| File                                      | SLOC | Why                                                                                                                                                                 |
|-------------------------------------------|------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| src/storage/SecondaryTradeStorage.sol     | 539  | Offer/bid custody, partial fills + pro-rata consideration, settlement escrow, seller payout, integrator/platform fee split, void/refund paths, EIP-712 relayer auth |
| src/interfaces/ISecondaryTradeStorage.sol | 160  | Offer/SecondaryEscrow structs, statuses, events/errors (accounting invariants live in these types)                                                                  |

### 3. Agreement registry (gates every escrow release) — 922 SLOC

| File                           | SLOC | Why                                                                                                                                                                                                |
|--------------------------------|------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| src/CyberAgreementRegistry.sol | 922  | EIP-712 signature verification, delegation, signContractFor / signContractWithEscrow, finalizeContract, voidContractFor — finalize/void here directly triggers payouts and refunds in the managers |

### 4. Securities layer (the assets escrow delivers; incl. scripification & recertification) — 3,194 SLOC

Note: PR #118 moved most cert-admin logic (legends, void/unvoid, transferability, units reserved, timestamps) from
IssuanceManager into CyberCertPrinter/CyberCertPrinterStorage behind a new `onlyIssuanceManagerOrAdmin` auth flow — the
logic shifted between rows below but stays fully in scope. PR #117 added issuance/acquisition timestamps (Rule 144
holding-period inputs) and the look-through holder tally.

| File                                             | SLOC  | Why                                                                                                                                                                                                                                                                             |
|--------------------------------------------------|-------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| src/IssuanceManager.sol                          | 580   | Only authorized caller of printers/scrips: cert creation/assignment, secondaryTransfer, beacon upgrades, scripify entry points (deployCyberScrip, scripifyCert, convertScripToCert), force transfer/burn/freeze, scrip ratio/minimum/whitelist admin, recertification approvals |
| src/storage/IssuanceManagerStorage.sol           | 1,198 | The execute* bodies: executeSecondaryTransfer, cert creation/assignment, executeDeployCyberScrip, executeScripifyCert, executeConvertScripToCert, scrip unit-vault accounting (deposit/redeem/withdraw), recert approval storage                                                |
| src/CyberCertPrinter.sol                         | 361   | Certificate ERC721: escrow-aware `_update`, legal-owner tracking/indexes, endorsements, new `onlyIssuanceManagerOrAdmin` auth surface                                                                                                                                           |
| src/storage/CyberCertPrinterStorage.sol          | 610   | Cert details, legal owner index maintenance/backfill, unitsReserved enforcement, issue/acquisition timestamps (+ backfill), look-through holder tally, restrictive legends, `requireManagerOrAdmin` auth check                                                                  |
| src/CyberScrip.sol                               | 257   | Fractionalized security ERC20: restriction hooks, holder caps, freeze, forceTransfer/forceBurn                                                                                                                                                                                  |
| src/storage/CyberScripStorage.sol                | 22    | Storage for the above                                                                                                                                                                                                                                                           |
| src/storage/extensions/FundInterestExtension.sol | 61    | FUND_INTEREST cert extension: encodes/decodes `FundInterestData` (acquisitionDate / tackedFromAcquisitionDate) that HoldingPeriodCondition reads to enforce Rule 144 holding periods on secondary settlements                                                                   |
| src/hooks/transfer/BaseTransferHook.sol          | 32    | Transfer-restriction hook base consulted by CyberScrip `_update` / `canTransfer`                                                                                                                                                                                                |
| src/hooks/transfer/ToggleTransferHook.sol        | 43    | Global on/off transfer gate for scrip transfers                                                                                                                                                                                                                                 |
| src/hooks/transfer/WhitelistTransferHook.sol     | 30    | Whitelist gating of scrip transfers                                                                                                                                                                                                                                             |

### 5. Conditions gating fund movement — 1,398 SLOC

| File                                                           | SLOC  | Why                                                                                                                                                                                                                                                                                                                                            |
|----------------------------------------------------------------|-------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| src/libs/conditions/secondary/* (18 files)                     | 1,092 | Threshold + closing conditions evaluated at postOffer / acceptOffer / finalize; includes KillSwitchCondition (kill switch), HolderCapCondition (reworked in PR #117 to use the new look-through tally), HoldingPeriodCondition (now reads acquisition timestamps), TimeSettlementPeriodCondition, KYC/AML, Reg S, Rule 144, CFIUS, ERISA, etc. |
| src/libs/conditions/BaseSecondaryTradingCondition.sol          | 23    | ISecondaryTradingCondition interface (ERC-165-checked at config time)                                                                                                                                                                                                                                                                          |
| src/libs/conditions/NonUSNationalityCondition.sol              | 144   | ZK-passport-based primary-escrow condition                                                                                                                                                                                                                                                                                                     |
| src/libs/conditions/IssuerApprovalRecertificationCondition.sol | 75    | Issuer-approval gate on recertification (scrip → cert conversion)                                                                                                                                                                                                                                                                              |
| src/libs/conditions/lexchexCondition.sol                       | 30    | LexChex credential gate on primary escrow                                                                                                                                                                                                                                                                                                      |
| src/libs/conditions/OrCondition.sol                            | 24    | Condition combinator                                                                                                                                                                                                                                                                                                                           |
| src/libs/conditions/baseCondition.sol                          | 10    | Base condition                                                                                                                                                                                                                                                                                                                                 |

### 6. Payment-adjacent periphery — 322 SLOC

| File                            | SLOC | Why                                                                                                                   |
|---------------------------------|------|-----------------------------------------------------------------------------------------------------------------------|
| src/CyberCorp.sol               | 194  | `companyPayable` (destination of every primary payout) and escrowed officer signatures consumed by escrow endorsement |
| src/libs/auth.sol               | 109  | BorgAuth / BorgAuthACL: the access control gating every privileged fund action (onlyOwner/onlyAdmin)                  |
| src/storage/BorgAuthStorage.sol | 19   | Storage for the above                                                                                                 |

### 7. Deployment & wiring trust root — 551 SLOC

| File                                          | SLOC | Why                                                                                                                                                                                                                                                                                                                             |
|-----------------------------------------------|------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| src/CyberCorpFactory.sol                      | 462  | Deploys and wires the whole corp stack in one transaction: sets `companyPayable`, initializes DealManager / RoundManager / IssuanceManager with each other's addresses, grants the new RoundManager OWNER in LeXcheX auth, and can atomically create the first offer/round. A wiring bug here misroutes every downstream payout |
| src/IssuanceManagerFactory.sol                | 74   | Reference implementations for IssuanceManager, CyberCertPrinter, and CyberScrip — the upgrade gate for the entire securities layer (same trust role as the manager factories)                                                                                                                                                   |
| src/storage/IssuanceManagerFactoryStorage.sol | 15   | Storage for the above                                                                                                                                                                                                                                                                                                           |

### Deliberately out of scope

- `MetalexIssuerFeeHook.sol` (325 SLOC) — Uniswap v4 fee hook on CyberScrip pools; not currently used.
- `lexchexMinter.sol` (327 SLOC) and the lexchex/lexchexBadge credential NFTs — credential mint-fee payments; not
  currently used.
- `CyberShares.sol` / `CyberSharesStorage.sol` (490 SLOC) — not referenced by any other src contract; appears unwired.
- Variant factories that only deploy/wire alternative stacks (PumpCorpFactory, ParentCoFactory, MetaDAOFactory,
  CyberCorpSingleFactory), URI/image builders, certificate extensions (metadata only — except FundInterestExtension, in
  scope in group 4), and interfaces other than ISecondaryTradeStorage.

## Core scope — fund-moving functions

| File                                                   | Function                                                                                                          | Brief explanation                                                                                                                      |
|--------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| src/storage/RoundManagerStorage.sol                    | submitEOI(...)                                                                                                    | Create agreement + escrow; pull ERC20 from investor; attach conditions                                                                 |
| src/storage/RoundManagerStorage.sol                    | allocate(bytes32, uint256)                                                                                        | Allocate amount, refund difference, finalize escrow (fee split), update raised                                                         |
| src/RoundManager.sol                                   | reject(bytes32, bool)                                                                                             | Owner rejects paid EOI; full refund; void escrow/agreement                                                                             |
| src/RoundManager.sol                                   | recallEOI(bytes32, bool)                                                                                          | Investor recall after expiry; full refund; void escrow/agreement                                                                       |
| src/RoundManager.sol                                   | computeFee / getPlatformPayable                                                                                   | Fee ratio + destination read from RoundManagerFactory                                                                                  |
| src/storage/DealManagerStorage.sol                     | proposeDeal(...)                                                                                                  | Create agreement, certs, and escrow with buyer/corp assets                                                                             |
| src/storage/DealManagerStorage.sol                     | signDealAndPay(...)                                                                                               | Sign, update escrow, pull ERC20 into escrow                                                                                            |
| src/storage/DealManagerStorage.sol                     | signAndFinalizeDeal(...)                                                                                          | Sign, pull payment, check conditions, finalize                                                                                         |
| src/storage/DealManagerStorage.sol                     | finalizeDeal(bytes32)                                                                                             | Validate signatures/conditions and finalize escrow                                                                                     |
| src/storage/DealManagerStorage.sol                     | voidExpiredDeal / signToVoid / revokeDeal / refundVoidedDeal                                                      | Void paths; refund buyer assets when paid                                                                                              |
| src/DealManager.sol                                    | setDealRegistry / setCorp / computeFee / getPlatformPayable                                                       | Fund-routing configuration                                                                                                             |
| src/storage/LexScrowStorage.sol                        | createEscrow / updateEscrow                                                                                       | Initialize escrow; endorse corp ERC721 certs                                                                                           |
| src/storage/LexScrowStorage.sol                        | handleCounterPartyPayment(bytes32)                                                                                | Pull ERC20/721/1155 from buyer; mark PAID                                                                                              |
| src/storage/LexScrowStorage.sol                        | finalizeEscrow(bytes32)                                                                                           | Pay companyPayable minus fee (callback into manager for fee math), pay platform fee, deliver corp assets                               |
| src/storage/LexScrowStorage.sol                        | voidAndRefund / voidEscrow / conditionCheck                                                                       | Refund buyer assets; verify conditions                                                                                                 |
| src/storage/SecondaryTradeStorage.sol                  | postOffer(params[, forAddr, nonce, sig])                                                                          | BID: pull consideration into custody; SELL: reserve seller units; snapshot conditions; relayer EIP-712 auth                            |
| src/storage/SecondaryTradeStorage.sol                  | acceptOffer(params[, forAddr, nonce, sig])                                                                        | Partial-fill accounting + pro-rata consideration; create fully-signed settlement; SELL: pull buyer payment                             |
| src/storage/SecondaryTradeStorage.sol                  | cancelOffer(offerId[, forAddr, nonce, sig])                                                                       | Refund/release only the uncommitted pool                                                                                               |
| src/storage/SecondaryTradeStorage.sol                  | finalizeSecondaryTradeAgreement(bytes32)                                                                          | Re-check threshold + closing conditions, pay seller, integrator/platform fee split, release reservation, execute cert ownership change |
| src/storage/SecondaryTradeStorage.sol                  | voidExpiredSecondaryTradeAgreement / voidSecondaryTradeAgreement / syncVoidedSecondaryTradeAgreement              | Refund buyer, restore offer accounting, release/retain reservations per side                                                           |
| src/CyberAgreementRegistry.sol                         | signContractFor / signContractWithEscrow                                                                          | EIP-712 signature verification that authorizes escrow payment                                                                          |
| src/CyberAgreementRegistry.sol                         | finalizeContract / voidContractFor / isVoided                                                                     | The gates managers rely on before paying out or refunding                                                                              |
| src/IssuanceManager.sol + IssuanceManagerStorage.sol   | secondaryTransfer / executeSecondaryTransfer                                                                      | Void/decrement seller cert, mint buyer cert against settlement metadata                                                                |
| src/IssuanceManager.sol + IssuanceManagerStorage.sol   | scripifyCert / convertScripToCert (+ execute*)                                                                    | Cert ↔ scrip vault: deposits, redemptions, unit-vault accounting, scripify whitelist/minimum gates, recert approvals                   |
| src/IssuanceManager.sol                                | forceScripTransfer / forceScripBurn / setScripFrozen                                                              | Privileged movement of user securities                                                                                                 |
| src/CyberScrip.sol                                     | _update / mint / burnFrom / forceTransfer / forceBurn / canTransfer                                               | Scrip transfer restrictions, holder caps, freeze                                                                                       |
| src/CyberCertPrinter.sol + CyberCertPrinterStorage.sol | increaseUnitsReserved / decreaseUnitsReserved (now direct, `onlyIssuanceManagerOrAdmin`)                          | Reservation accounting shared by secondary trades and scripify                                                                         |
| src/CyberCertPrinter.sol                               | _update / legalOwnerOf / endorseAndTransfer / burn / voidCert                                                     | Legal-vs-token ownership, escrow-aware transfer, reservation enforcement                                                               |
| src/storage/CyberCertPrinterStorage.sol                | setIssue/AcquisitionTimestamp / updateTackedFromAcquisitionDate / backfillAcquisitionTimestamp                    | Holding-period inputs consumed by Rule 144 / HoldingPeriod conditions that gate secondary settlements                                  |
| src/storage/CyberCertPrinterStorage.sol                | requireManagerOrAdmin / _countLot / _uncountLot / resyncHolder(s) / backfillLookThroughTally                      | New auth gate for all cert-admin calls; look-through holder tally consumed by HolderCapCondition                                       |
| src/DealManagerFactory.sol                             | setDefaultFeeRatio / setPlatformPayable / setIntegrator / setRefImplementation                                    | Fee parameters and upgrade gate trusted by every DealManager                                                                           |
| src/CyberCorpFactory.sol                               | deployCyberCorp / deployCyberCorpAndCreateOffer / deployCyberCorpAndCreateRound / deployAndInitializeRoundManager | Wires companyPayable, manager addresses, and auth grants that every subsequent fund flow trusts                                        |

## SLOC summary

| Group                                                        | SLOC      |
|--------------------------------------------------------------|-----------|
| 1. Primary deal & round escrow                               | 2,011     |
| 2. Secondary trading                                         | 699       |
| 3. Agreement registry                                        | 922       |
| 4. Securities layer (incl. scripification & recertification) | 3,194     |
| 5. Conditions                                                | 1,398     |
| 6. Payment-adjacent periphery                                | 322       |
| 7. Deployment & wiring trust root                            | 551       |
| **Core total**                                               | **9,097** |

If the budget needs trimming, the best cuts (in order) are: scripification / recertification if it will not be live at
launch (−1,314: CyberScrip + CyberScripStorage, the scrip/recert portions of IssuanceManager and IssuanceManagerStorage,
and IssuerApprovalRecertificationCondition), the long tail of secondary conditions beyond KillSwitch / HolderCap /
TimeSettlementPeriod / AgreementSigned (−~900), or group 7 if deployment wiring is considered operationally verified (
−551). We recommend keeping the escrow/custody core (groups 1–3 plus the cert layer) intact — it is a single connected
custody system and the delegatecall-linked library structure means vulnerabilities compose across file boundaries.
