# DealManager Secondary Trade — Full Lifecycle State Machine

Two parallel state machines run concurrently: the **Offer** (one per `postOffer()`) and one or more **Settlement Escrows
** (one per `acceptOffer()`).

---

## 1. Offer State Machine

```mermaid
stateDiagram-v2
    [*] --> LIVE: postOffer()
    LIVE --> CANCELLED: cancelOffer()
    LIVE --> PARTIALLY_ACCEPTED: acceptOffer() partial fill
    LIVE --> FULLY_ACCEPTED: acceptOffer() full fill
    PARTIALLY_ACCEPTED --> FULLY_ACCEPTED: acceptOffer() completes fill
    PARTIALLY_ACCEPTED --> LIVE: settlement voided, unitsAccepted back to 0
    FULLY_ACCEPTED --> LIVE: settlement voided, unitsAccepted back to 0
    FULLY_ACCEPTED --> PARTIALLY_ACCEPTED: settlement voided, unitsAccepted still gt 0
    note right of LIVE
        SELL: reserves units on cert at postOffer
        BUY: pulls full consideration into contract at postOffer
    end note
    note right of CANCELLED
        SELL: releases reservation immediately if no active settlements; otherwise, release it until last settlement settles
        BUY: refunds uncommitted consideration
    end note
    note right of FULLY_ACCEPTED
        EXPIRED is logical only, no status field change.
        Enforced at acceptOffer() when block.timestamp > validUntil.
    end note
```

### Offer status transitions

| From                 | Event                                         | To                   | Notes                                                                                 |
|----------------------|-----------------------------------------------|----------------------|---------------------------------------------------------------------------------------|
| *(none)*             | `postOffer()`                                 | `LIVE`               | SELL: reserves units on cert; BUY: pulls full consideration into contract             |
| `LIVE`               | `cancelOffer()`                               | `CANCELLED`          | SELL: releases reservation if no active settlements; BUY: refunds uncommitted portion |
| `LIVE`               | `acceptOffer()` — partial fill                | `PARTIALLY_ACCEPTED` | `unitsAccepted < units`                                                               |
| `LIVE`               | `acceptOffer()` — full fill                   | `FULLY_ACCEPTED`     | `unitsAccepted == units`                                                              |
| `PARTIALLY_ACCEPTED` | `acceptOffer()` — completes fill              | `FULLY_ACCEPTED`     |                                                                                       |
| `PARTIALLY_ACCEPTED` | settlement voided                             | `LIVE`               | `unitsAccepted` decrements; if back to 0 and not CANCELLED                            |
| `FULLY_ACCEPTED`     | settlement voided, `unitsAccepted` drops to 0 | `LIVE`               | Same logic as `PARTIALLY_ACCEPTED`: status set purely by `unitsAccepted == 0` check   |
| `FULLY_ACCEPTED`     | settlement voided, `unitsAccepted` still > 0  | `PARTIALLY_ACCEPTED` | `unitsAccepted` decrements but offer not empty yet                                    |
| any                  | `block.timestamp > validUntil`                | `EXPIRED` (logical)  | No status field change; enforced at `acceptOffer()`                                   |

---

## 2. Settlement Escrow State Machine (one per `acceptOffer()`)

```mermaid
stateDiagram-v2
    [*] --> PAID: acceptOffer()
    PAID --> FINALIZED: finalizeDeal()
    PAID --> VOIDED: voidSecondaryAgreement()
    PAID --> VOIDED: syncVoidedSettlement()
    PAID --> VOIDED: voidExpiredDeal()
    note left of PAID
        SELL: safeTransferFrom buyer, then escrow written as PAID.
        BUY: funds already in contract from postOffer(), escrow written as PAID directly.
    end note
    note right of FINALIZED
        Pays seller minus fee.
        Splits fee to integrator and platform.
        Calls IssuanceManager.secondaryTransfer()
        to mint buyer cert and void/decrement seller cert.
    end note
    note right of VOIDED
        voidSecondaryAgreement: party only.
        syncVoidedSettlement: anyone if either party already voided through registry.
        voidExpiredDeal: past secEscrow.expiry.
        All paths refund buyer.
        SELL: shared reservation released only when paymentAccepted == 0 AND offer is CANCELLED.
        FULLY_ACCEPTED is not safe here: void can roll it back to LIVE, so only CANCELLED is terminal.
        BUY: per-settlement reservation released immediately.
    end note
```

### Settlement escrow status transitions

| From     | Event                                                 | To          | Notes                                                                                                                                                   |
|----------|-------------------------------------------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| *(none)* | `acceptOffer()` — SELL offer                          | `PAID`      | `safeTransferFrom` buyer pulls payment; escrow written directly as PAID                                                                                 |
| *(none)* | `acceptOffer()` — BUY offer                           | `PAID`      | Funds already in contract from `postOffer()`; escrow written directly as PAID                                                                           |
| `PAID`   | `finalizeDeal()` — conditions met                     | `FINALIZED` | Pays seller (minus fee), splits fee to integrator/platform, calls `IssuanceManager.secondaryTransfer` to mint buyer cert and void/decrement seller cert |
| `PAID`   | `voidSecondaryAgreement()` — party requests void      | `VOIDED`    | Buyer or offeror only; refunds buyer's payment                                                                                                          |
| `PAID`   | `syncVoidedSettlement()` — registry voided externally | `VOIDED`    | Callable by anyone; guards via `isVoided()` check                                                                                                       |
| `PAID`   | `voidExpiredDeal()` — past `secEscrow.expiry`         | `VOIDED`    | Refunds buyer; releases unit reservation                                                                                                                |

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
    DM ->> Cert: reserveUnits(tokenId, offerId, units)
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
    IM ->> Cert: void or decrement seller cert
    Note over DM: Settlement: FINALIZED
    Note over DM: if FULLY_ACCEPTED or CANCELLED, releaseUnits fires
    DM ->> Cert: releaseUnits(offerId)
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
    DM ->> Cert: reserveUnits(sellerTokenId, reservationId, units)
    DM ->> IM: attachOpenEndorsement(certPrinter, sellerTokenId)
    Note over DM: Settlement: PAID, no token movement, funds already in contract
    Note over DM: Offer: PARTIALLY_ACCEPTED or FULLY_ACCEPTED
    Seller ->> DM: finalizeDeal(settlementAgreementId)
    DM ->> Registry: finalizeContract(settlementAgreementId)
    DM ->> Seller: safeTransfer(paymentToken, toSeller)
    DM ->> DM: distribute fee to integrator and platform
    DM ->> IM: secondaryTransfer(dealMetadata)
    IM ->> Cert: mint new cert to Buyer
    IM ->> Cert: void or decrement seller cert
    DM ->> Cert: releaseUnits(reservationId)
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
    DM ->> Cert: reserveUnits(tokenId, offerId, 1000)
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
    IM ->> Cert: decrement seller cert by 400 units
    Note over DM: Escrow_A: FINALIZED
    Note over DM: paymentAccepted still gt 0, reservation held
    Bob ->> DM: finalizeDeal(settlementAgreementId_B)
    DM ->> Seller: safeTransfer(600P/1000 - fee)
    DM ->> IM: secondaryTransfer(dealMetadata_B)
    IM ->> Cert: mint new cert to Bob (600 units)
    IM ->> Cert: void seller cert (0 units remaining)
    Note over DM: Escrow_B: FINALIZED
    Note over DM: paymentAccepted == 0, release shared reservation
    DM ->> Cert: releaseUnits(offerId)
```

---

## 5. Void / Cancellation Paths

```mermaid
flowchart TD
    subgraph OFFER_LEVEL["Offer level"]
        CO["cancelOffer()<br/>by offeror"]
        OC["Offer: CANCELLED"]
        CO --> OC
        CO -->|SELL, unitsAccepted = = 0| RU1["releaseUnits immediately"]
        CO -->|BUY| RF1["refund uncommitted consideration"]
        CO -->|SELL, unitsAccepted > 0| DEFER["defer releaseUnits<br/>until last settlement settles"]
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
    ACC -->|SELL, paymentAccepted = = 0 AND offer CANCELLED| RU2["releaseUnits shared reservation"]
    ACC -->|BUY, always| RU3["releaseUnits per-settlement reservation"]
    ACC -->|escrow was PAID| RF2["refund buyer payment"]
    ACC --> OS["Restore Offer status"]
    OS -->|offer is CANCELLED| OS1["stays CANCELLED"]
    OS -->|unitsAccepted = = 0| OS2["LIVE"]
    OS -->|unitsAccepted > 0| OS3["PARTIALLY_ACCEPTED"]
```

---

## 6. Key Invariants

| Invariant                                                                                                         | Where enforced                                                                                                                                                                  |
|-------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `offerId` never registered in `CyberAgreementRegistry`                                                            | `postOffer()` makes no registry call                                                                                                                                            |
| `settlementAgreementId` always fully signed by both parties at creation                                           | `acceptOffer()`: `signContractWithEscrow(offeror)` + `signContractFor(acceptor)`                                                                                                |
| Settlement escrow status `PAID` is the only state that can be finalized or voided                                 | `finalizeDeal()`, `voidSecondaryAgreement()`, `syncVoidedSettlement()` all guard on `PAID`                                                                                      |
| Buyer's payment enters contract custody before settlement `PAID` is set                                           | SELL: `safeTransferFrom` then status flip in same tx; BUY: custody at `postOffer()`                                                                                             |
| Seller cert units are reserved before any settlement is created                                                   | SELL: `reserveUnits` at `postOffer()`; BUY: `reserveUnits` at `acceptOffer()` per settlement                                                                                    |
| Shared SELL reservation released only when no new acceptances are possible and all in-flight settlements resolved | finalize: `paymentAccepted == 0` + (`FULLY_ACCEPTED` or `CANCELLED`); void: `paymentAccepted == 0` + `CANCELLED` only (`FULLY_ACCEPTED` is unsafe — void can roll it to `LIVE`) |
| Fee always split: integrator portion + platform portion                                                           | `_finalizeSecondaryEscrow`: `integratorFee + platformFee == totalFee`                                                                                                           |
| Conditions checked at `finalizeDeal()`, not at `acceptOffer()`                                                    | `_finalizeSecondaryEscrow`: `conditionCheck(agreementId)`                                                                                                                       |
