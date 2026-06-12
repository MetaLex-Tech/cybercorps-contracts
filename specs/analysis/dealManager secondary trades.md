# DealManager Secondary Trade — Full Lifecycle State Machine

Two parallel state machines run concurrently: the **Offer** (one per `postOffer()`) and one or more **Settlement Escrows
** (one per `acceptOffer()`).

---

## 1. Offer State Machine

```mermaid
stateDiagram-v2
    [*] --> LIVE: postOffer()
    LIVE --> CANCELLED: cancelOffer()
    PARTIALLY_ACCEPTED --> CANCELLED: cancelOffer()
    FULLY_ACCEPTED --> CANCELLED: cancelOffer()
    LIVE --> PARTIALLY_ACCEPTED: acceptOffer() partial fill
    LIVE --> FULLY_ACCEPTED: acceptOffer() full fill
    PARTIALLY_ACCEPTED --> FULLY_ACCEPTED: acceptOffer() completes fill
    PARTIALLY_ACCEPTED --> LIVE: settlement voided, unitsAccepted back to 0
    FULLY_ACCEPTED --> LIVE: settlement voided, unitsAccepted back to 0
    FULLY_ACCEPTED --> PARTIALLY_ACCEPTED: settlement voided, unitsAccepted still gt 0
    FULLY_ACCEPTED --> FINALIZED: last lot finalized, unitsFinalized == units
    CANCELLED --> [*]
    FINALIZED --> [*]
    note right of LIVE
        SELL: reserves units on cert at postOffer
        BUY: pulls full consideration into contract at postOffer
    end note
    note right of CANCELLED
        SELL releases uncommitted units (units - unitsAccepted) immediately.
        BUY: refunds uncommitted consideration (consideration - paymentAccepted) immediately.
        By default (voidOutstandingSettlements=true) cancelOffer also voids
        all outstanding PAID settlements atomically, keeping Offer and
        settlement agreement status in sync; each voided lot is released
        (SELL) / refunded (BUY) along with the free pool.
    end note
    note right of FINALIZED
        Terminal: all offered units consumed by finalized settlements.
        CANCELLED is sticky — a cancelled offer whose last in-flight lot
        finalizes stays CANCELLED.
        Only the terminal states (FINALIZED, CANCELLED) are not cancellable.
    end note
    note right of FULLY_ACCEPTED
        Accepted does not mean settled, parties can still void in-flight settlements.
        EXPIRED is logical only, no status field change.
        Enforced at acceptOffer() when block.timestamp > validUntil,
        and at finalizeDeal() when block.timestamp > secEscrow.expiry.
    end note
```

### Offer status transitions

| From                 | Event                                         | To                   | Notes                                                                                                |
|----------------------|-----------------------------------------------|----------------------|------------------------------------------------------------------------------------------------------|
| *(none)*             | `postOffer()`                                 | `LIVE`               | SELL: reserves units on cert; BUY: pulls full consideration into contract                            |
| any non-terminal     | `cancelOffer()`                               | `CANCELLED`          | Releases/refunds the free pool; by default also voids all outstanding PAID settlements atomically    |
| `LIVE`               | `acceptOffer()` — partial fill                | `PARTIALLY_ACCEPTED` | `unitsAccepted < units`                                                                              |
| `LIVE`               | `acceptOffer()` — full fill                   | `FULLY_ACCEPTED`     | `unitsAccepted == units`                                                                             |
| `PARTIALLY_ACCEPTED` | `acceptOffer()` — completes fill              | `FULLY_ACCEPTED`     |                                                                                                      |
| `PARTIALLY_ACCEPTED` | settlement voided                             | `LIVE`               | `unitsAccepted` decrements; if back to 0 and not terminal                                            |
| `FULLY_ACCEPTED`     | settlement voided, `unitsAccepted` drops to 0 | `LIVE`               | Same logic as `PARTIALLY_ACCEPTED`: status set purely by `unitsAccepted == 0` check                  |
| `FULLY_ACCEPTED`     | settlement voided, `unitsAccepted` still > 0  | `PARTIALLY_ACCEPTED` | `unitsAccepted` decrements but offer not empty yet                                                   |
| `FULLY_ACCEPTED`     | last settlement finalized                     | `FINALIZED`          | `unitsFinalized == units`; terminal and immutable. CANCELLED stays sticky if the offer was cancelled |
| any                  | `block.timestamp > validUntil`                | `EXPIRED` (logical)  | No status field change; enforced at `acceptOffer()` and at `finalizeDeal()` (settlement expiry)      |

---

## 2. Settlement Escrow State Machine (one per `acceptOffer()`)

```mermaid
stateDiagram-v2
    [*] --> PAID: acceptOffer()
    PAID --> FINALIZED: finalizeDeal()
    PAID --> VOIDED: voidSecondaryAgreement()
    PAID --> VOIDED: syncVoidedSettlement()
    PAID --> VOIDED: voidExpiredDeal()
    PAID --> VOIDED: cancelOffer() with voidOutstandingSettlements
    note left of PAID
        SELL: safeTransferFrom buyer, then escrow written as PAID.
        BUY: funds already in contract from postOffer(), escrow written as PAID directly.
    end note
    note right of FINALIZED
        Pays seller minus fee.
        Splits fee to integrator and platform.
        Calls IssuanceManager.secondaryTransfer()
        to mint buyer cert and void/decrement seller cert,
        consuming this lot's reserved units as part of the cert mutation.
    end note
    note right of VOIDED
        voidSecondaryAgreement: party only.
        syncVoidedSettlement: anyone if either party already voided through registry.
        voidExpiredDeal: past secEscrow.expiry.
        Acceptor's asset always returned immediately: SELL refunds the buyer's payment, BUY releases the seller's unit reservation.
        Offeror's asset stays in custody for the next fill, returned only if the offer has been cancelled:
        SELL: corresponding units are freed up for the next fill; released if the offer has been cancelled
        BUY: corresponding funds are freed up for the next fill; refunded if the offer has been cancelled
    end note
```

### Settlement escrow status transitions

| From     | Event                                                 | To          | Notes                                                                                                                                                                                                                        |
|----------|-------------------------------------------------------|-------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| *(none)* | `acceptOffer()` — SELL offer                          | `PAID`      | `safeTransferFrom` buyer pulls payment; escrow written directly as PAID                                                                                                                                                      |
| *(none)* | `acceptOffer()` — BUY offer                           | `PAID`      | Funds already in contract from `postOffer()`; escrow written directly as PAID                                                                                                                                                |
| `PAID`   | `finalizeDeal()` — conditions met, before expiry      | `FINALIZED` | Reverts past `secEscrow.expiry`; pays seller (minus fee), splits fee to integrator/platform, calls `IssuanceManager.secondaryTransfer` to mint buyer cert and void/decrement seller cert, consuming the lot's reserved units |
| `PAID`   | `voidSecondaryAgreement()` — party requests void      | `VOIDED`    | Either party (offeror or counterparty) only                                                                                                                                                                                  |
| `PAID`   | `syncVoidedSettlement()` — registry voided externally | `VOIDED`    | Callable by anyone; guards via `isVoided()` check                                                                                                                                                                            |
| `PAID`   | `voidExpiredDeal()` — past `secEscrow.expiry`         | `VOIDED`    | Callable past expiry only                                                                                                                                                                                                    |
| `PAID`   | `cancelOffer(voidOutstandingSettlements=true)`        | `VOIDED`    | Offeror cancels the offer and atomically voids every outstanding PAID lot (default); DealManager is the settlement's finalizer so the registry void request needs no signature                                               |

All `VOIDED` paths share the same asset handling, symmetric between sides. The acceptor's asset is returned
immediately: SELL refunds the buyer's payment (pulled per settlement at `acceptOffer()`), BUY releases the seller's
per-settlement unit reservation. The offeror's asset (SELL: reserved units; BUY: consideration) returns to the offer's
free pool and stays in custody, available for the next fill — it is released/refunded only if the offer is `CANCELLED`,
since the lot can never be re-accepted.

---

## 3. End-to-End Flow

### 3A. SELL Offer (seller posts, buyer accepts)

```mermaid
sequenceDiagram
    actor Seller
    participant DM as DealManager
    participant Cert as CertPrinter
    participant Registry as AgreementRegistry
    participant IM as IssuanceManager
    actor Buyer
    Seller ->> DM: postOffer(SELL, units, consideration)
    DM ->> Cert: reserveUnits(tokenId, units)
    Note over DM: Offer: LIVE
    Buyer ->> DM: acceptOffer(offerId, units, buyer)
    DM ->> Registry: createContract(templateId, settlementSalt, parties)
    DM ->> Registry: signContractWithEscrow(offeror, settlementAgreementId)
    DM ->> Registry: signContractFor(acceptor, settlementAgreementId)
    DM ->> IM: attachOpenEndorsement(certPrinter, tokenId)
    Buyer ->> DM: safeTransferFrom(filledConsideration)
    Note over DM: Settlement: PAID
    Note over DM: Offer: PARTIALLY_ACCEPTED or FULLY_ACCEPTED
    Buyer ->> DM: finalizeDeal(settlementAgreementId)
    DM ->> Registry: finalizeContract(settlementAgreementId)
    DM ->> Seller: safeTransfer(paymentToken, toSeller)
    DM ->> DM: distribute fee to integrator and platform
    DM ->> IM: secondaryTransfer(dealMetadata)
    IM ->> Cert: mint new cert to Buyer
    IM ->> Cert: void or decrement seller cert, consuming the lot's reserved units
    Note over DM: Settlement: FINALIZED
```

### 3B. BUY Offer (buyer posts, seller accepts)

```mermaid
sequenceDiagram
    actor Buyer
    participant DM as DealManager
    participant Cert as CertPrinter
    participant Registry as AgreementRegistry
    participant IM as IssuanceManager
    actor Seller
    Buyer ->> DM: postOffer(BUY, units, consideration)
    Buyer ->> DM: safeTransferFrom(consideration)
    Note over DM: Offer: LIVE, funds in contract custody
    Seller ->> DM: acceptOffer(offerId, units, sellerTokenId)
    DM ->> Registry: createContract(templateId, settlementSalt, parties)
    DM ->> Registry: signContractWithEscrow(offeror, settlementAgreementId)
    DM ->> Registry: signContractFor(acceptor, settlementAgreementId)
    DM ->> Cert: reserveUnits(sellerTokenId, units)
    DM ->> IM: attachOpenEndorsement(certPrinter, sellerTokenId)
    Note over DM: Settlement: PAID, no token movement, funds already in contract
    Note over DM: Offer: PARTIALLY_ACCEPTED or FULLY_ACCEPTED
    Seller ->> DM: finalizeDeal(settlementAgreementId)
    DM ->> Registry: finalizeContract(settlementAgreementId)
    DM ->> Seller: safeTransfer(paymentToken, toSeller)
    DM ->> DM: distribute fee to integrator and platform
    DM ->> IM: secondaryTransfer(dealMetadata)
    IM ->> Cert: mint new cert to Buyer
    IM ->> Cert: void or decrement seller cert, consuming the lot's reserved units
    Note over DM: Settlement: FINALIZED
```

---

## 4. Partial Fill State Sequence (SELL offer, two acceptors)

```mermaid
sequenceDiagram
    actor Seller
    participant DM as DealManager
    participant Cert as CertPrinter
    actor Alice
    actor Bob
    Seller ->> DM: postOffer(SELL, units=1000, consideration=P)
    DM ->> Cert: reserveUnits(tokenId, 1000)
    Note over DM: Offer: LIVE, unitsAccepted=0, paymentAccepted=0
    Alice ->> DM: acceptOffer(units=400)
    Alice ->> DM: safeTransferFrom(400 x P/1000)
    Note over DM: Escrow_A: PAID, units=400, payment=400P/1000
    Note over DM: Offer: PARTIALLY_ACCEPTED, unitsAccepted=400
    Bob ->> DM: acceptOffer(units=600)
    Bob ->> DM: safeTransferFrom(600 x P/1000)
    Note over DM: Escrow_B: PAID, units=600, payment=600P/1000
    Note over DM: Offer: FULLY_ACCEPTED, unitsAccepted=1000
    Alice ->> DM: finalizeDeal(settlementAgreementId_A)
    DM ->> Seller: safeTransfer(400P/1000 - fee)
    DM ->> IM: secondaryTransfer(dealMetadata_A)
    IM ->> Cert: mint new cert to Alice (400 units)
    IM ->> Cert: decrement seller cert by 400 units, consuming 400 reserved units
    Note over DM: Escrow_A: FINALIZED
    Note over DM: 600 units still reserved for Escrow_B
    Bob ->> DM: finalizeDeal(settlementAgreementId_B)
    DM ->> Seller: safeTransfer(600P/1000 - fee)
    DM ->> IM: secondaryTransfer(dealMetadata_B)
    IM ->> Cert: mint new cert to Bob (600 units)
    IM ->> Cert: void seller cert (0 units remaining), consuming 600 reserved units
    Note over DM: Escrow_B: FINALIZED, no reserved units remain
```

---

## 5. Void / Cancellation Paths

```mermaid
flowchart TD
    subgraph OFFER_LEVEL["Offer level"]
        CO["cancelOffer(voidOutstandingSettlements)<br/>by offeror, any non-terminal status"]
        OC["Offer: CANCELLED"]
        CO --> OC
        CO -->|SELL| RU1["releaseUnits(tokenId, units - unitsAccepted)<br/>uncommitted units first"]
        CO -->|BUY| RF1["refund uncommitted consideration first"]
        CO -->|" voidOutstandingSettlements=true (default) "| VOS["void every outstanding PAID settlement<br/>via the settlement-level VOIDED path below"]
        CO -->|" voidOutstandingSettlements=false "| KEEP["in-flight lots stay PAID<br/>resolve at finalize or void"]
    end

    subgraph SETTLEMENT_LEVEL["Settlement level"]
        VSA["voidSecondaryAgreement()<br/>buyer or offeror only"]
        SVS["syncVoidedSettlement()<br/>anyone, registry already voided"]
        VED["voidExpiredDeal()<br/>past secEscrow.expiry"]
        SV["Settlement: VOIDED"]
        VSA --> SV
        SVS --> SV
        VED --> SV
    end

    SV --> ACC["decrement offer.unitsAccepted and offer.paymentAccepted"]
    ACC -->|SELL, offer CANCELLED| RU2["releaseUnits(tokenId, lot units)"]
    ACC -->|SELL, offer not CANCELLED| POOL["lot returns to offer's free pool<br/>stays reserved, re-acceptable"]
    ACC -->|SELL, always| RF2["refund buyer payment"]
    ACC -->|BUY, always| RU3["releaseUnits(tokenId, lot units)"]
    ACC -->|BUY, offer CANCELLED| RF3["refund offeror payment"]
    ACC -->|BUY, offer not CANCELLED| FPOOL["payment returns to offer's free pool<br/>stays in custody, re-acceptable"]
    ACC --> OS["Restore Offer status"]
    OS -->|offer is terminal CANCELLED or FINALIZED| OS1["stays terminal"]
    OS -->|unitsAccepted = = 0| OS2["LIVE"]
    OS -->|unitsAccepted > 0| OS3["PARTIALLY_ACCEPTED"]
```

---

## 6. Key Invariants

| Invariant                                                                                   | Where enforced                                                                                                                                                                                                                                                               |
|---------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `offerId` never registered in `CyberAgreementRegistry`                                      | `postOffer()` makes no registry call                                                                                                                                                                                                                                         |
| `settlementAgreementId` always fully signed by both parties at creation                     | `acceptOffer()`: `signContractWithEscrow(offeror)` + `signContractFor(acceptor)`                                                                                                                                                                                             |
| Buyer's payment enters contract custody before settlement `PAID` is set                     | SELL: `safeTransferFrom` then status flip in same tx; BUY: custody at `postOffer()`                                                                                                                                                                                          |
| Seller cert units are reserved before any settlement is created                             | SELL: `reserveUnits` at `postOffer()`; BUY: `reserveUnits` at `acceptOffer()` per settlement                                                                                                                                                                                 |
| Each reserved unit is released or consumed exactly once (amount-based reservations, no IDs) | finalize: `secondaryTransfer` consumes the lot; void: BUY releases the lot, SELL releases only if offer `CANCELLED` (else lot returns to free pool); cancel: releases `units - unitsAccepted` first, then each outstanding lot through the void rule when voiding by default |
| Each unit of BUY consideration leaves custody exactly once (payout or refund)               | finalize: paid to seller; void: refunded only if offer `CANCELLED` (else returns to free pool); cancel: refunds `consideration - paymentAccepted` first, then each outstanding lot through the void rule when voiding by default                                             |
| Fee always split: integrator portion + platform portion                                     | `_finalizeSecondaryEscrow`: `integratorFee + platformFee == totalFee`                                                                                                                                                                                                        |
| Conditions checked at `finalizeDeal()`, not at `acceptOffer()`                              | `_finalizeSecondaryEscrow`: `conditionCheck(agreementId)`                                                                                                                                                                                                                    |
