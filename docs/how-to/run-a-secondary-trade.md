---
description: Post, accept, and finalize a secondary offer under an elected exemption pathway
---

# Run a secondary trade

Secondary trades settle through a cyberCORP's **`DealManager`**, which since
the deal-manager secondary-trading upgrade has a dedicated offer flow:
**post an offer → accept it → finalize the settlement**. Each acceptance
creates a fully-signed settlement agreement in the `CyberAgreementRegistry`
(a `bytes32` id), and the DealManager holds the escrow internally.

Offers have two sides (`OfferSide.SELL` / `OfferSide.BUY`), support partial
fills, and every settlement is pinned to a securities-law **exemption
pathway** (`ExemptionPathway`: `RULE_144`, `SECTION_4A7`, `SECTION_4A1HALF`,
`RULE_144A`, `REGULATION_S`) elected by the buyer. Structs are in
[`ISecondaryTradeStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ISecondaryTradeStorage.sol).

```mermaid
sequenceDiagram
    participant S as Seller
    participant DM as DealManager
    participant B as Buyer
    participant IM as IssuanceManager
    S->>DM: postOffer (SELL)
    Note over DM: units reserved on the seller's cert
    B->>DM: acceptOffer (full or partial)
    Note over DM: buyer elects exemption pathway ·<br/>pathway + SPV conditions checked ·<br/>payment escrowed · settlement agreement fully signed
    B->>DM: finalizeSecondaryTradeAgreement
    Note over DM: SPV + pathway + closing conditions<br/>re-checked at settlement
    DM-->>S: seller proceeds paid · fees distributed
    DM->>IM: secondaryTransfer
    IM-->>B: units onto the buyer's cert
```

## 0. One-time configuration (owner/admin)

Before any offer can settle, the cyberCORP configures its trading policy on
the DealManager:

```solidity
// enable a pathway and set its exemption-specific conditions
dealManager.setPathwayThresholdConditions(ExemptionPathway.RULE_144, conds, true);
dealManager.setSpvThresholdConditions(fundConds);    // apply to every offer
dealManager.setClosingConditions(closingConds);      // checked at finalize only
dealManager.setMinTradeThreshold(minUnits, minConsideration);
dealManager.setSettlementWindow(window);             // seconds from acceptance
dealManager.setDefaultIntegrator(integrator);        // optional fee-split partner
```

A pathway that is not enabled can be neither pinned nor elected.

The platform fee on a settlement is not set here. It comes from the
DealManagerFactory's **secondary** rate (`getSecondaryFeeRatio()`, which
MetaLeX can override per DealManager), separate from the primary rate used
for deals and rounds; a whitelisted integrator's share is carved out of
that fee. See the fee notes in
[DealManager](../reference/contracts/DealManager.md).

## 1. Post the offer

```solidity
import {PostOfferParams, OfferSide, ExemptionPathway, HostingMode}
    from "src/interfaces/ISecondaryTradeStorage.sol";

bytes32 offerId = dealManager.postOffer(PostOfferParams({
    side:                     OfferSide.SELL,
    certPrinter:              certPrinter,   // the security being sold
    tokenId:                  tokenId,       // seller's cert (0 for BUY offers)
    units:                    10_000e18,     // 10,000 shares (units are 18-decimal)
    paymentToken:             USDC,
    consideration:            200_000e6,     // total for all offered units
    exemptionPathway:         ExemptionPathway.NONE, // NONE = each buyer elects
    validUntil:               block.timestamp + 30 days,
    counterpartyRestrictions: "",
    additionalTerms:          "",
    integrator:               address(0),    // 0 = default integrator
    templateId:               templateId,    // agreement template
    salt:                     salt,
    globalValues:             globalValues,
    offerorPartyValues:       sellerValues,
    offerorAgreementSig:      sellerAgreementSig, // EIP-712 over the agreement
    openEndorsementSig:       openEndorsementSig, // seller's pre-signed endorsement
    buyerName:                "",            // BUY offers only
    buyerHostingMode:         HostingMode.DIRECT,
    adminMultisig:            address(0)
}));
```

{% hint style="warning" %}
`units` is **18-decimal fixed point** (one share = `1e18`), while
`consideration` is denominated in the payment token's own decimals
(USDC = 6). Mixing these up misprices the offer by orders of magnitude.
{% endhint %}

* **SELL** offers require the caller to be the cert's registered owner and
  the cert not to be void (`CertificateVoided`); the offered units are
  reserved on the cert (they cannot be scripified or reassigned while
  reserved).
* **BUY** offers pull the full `consideration` into DealManager custody up
  front, and must pin an exemption pathway.
* `HostingMode.ADMINISTERED` delivers the buyer's lot to `adminMultisig`,
  so it needs a nonzero address there (`MissingAdminMultisig` otherwise),
  on a buy offer at posting and on a sell offer at acceptance.
* `offerorAgreementSig` is stored with the offer and attached to each
  settlement agreement through `signContractWithEscrow`. Neither the
  DealManager nor the registry verifies it; the offeror's commitment rests
  on its own `postOffer` transaction (or its relayer authorization), and
  the stored signature is the record of what it signed.

## 2. Accept the offer

Any counterparty (fully or partially) accepts:

```solidity
import {AcceptOfferParams} from "src/interfaces/ISecondaryTradeStorage.sol";

bytes32 settlementAgreementId = dealManager.acceptOffer(AcceptOfferParams({
    offerId:             offerId,
    units:               4_000e18,                   // 4,000 shares — partial fills allowed
    exemptionPathway:    ExemptionPathway.RULE_144,  // buyer's election (sell offers)
    buyerName:           "Bob Buyer",
    buyerHostingMode:    HostingMode.DIRECT,
    adminMultisig:       address(0),
    sellerTokenId:       0,                          // BUY-offer acceptances only
    acceptorPartyValues: buyerValues,
    acceptorAgreementSig: buyerAgreementSig,         // EIP-712, registry-verified
    openEndorsementSig:  ""                          // BUY-offer acceptances only
}));
```

Acceptance creates the settlement agreement in the registry (signed by both
sides), funds the escrow (the buyer pays here on a sell offer), and re-runs
the SPV and elected-pathway conditions against the concrete buyer. A failed
condition reverts the whole acceptance, as does a seller cert that has
been voided since the offer was posted.

`acceptorAgreementSig` is verified by the registry, so the acceptor signs
`SignatureData` (with `signer` = the acceptor) for the settlement
agreement's id, before the agreement exists. On the current registry that
id is

```solidity
keccak256(abi.encode(
    offer.templateId,
    uint256(keccak256(abi.encodePacked(offer.salt, n))), // n = earlier acceptances of this offer
    offer.globalValues,
    [offeror, acceptor],
    bytes32(0),        // no secret
    dealManager        // the DealManager is the finalizer
))
```

The settlement expiry is not part of the id. `n` counts every earlier
acceptance, including voided ones, so a competing acceptance mined first
changes the id and invalidates the signature (see
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md#data-model)).

Each lot is priced from the offer's running total:
`consideration × (unitsAccepted + units) / units − paymentAccepted`, so
the lot that exhausts the offer pays whatever remains and rounding does not
accumulate across fills. A priced lot that rounds to zero reverts
`ZeroConsiderationFill`. The minimum-trade threshold applies to a partial
lot and to the remainder it leaves; the lot that exhausts the offer is
exempt, so raising the threshold never strands an existing tail.

## 3. Finalize

After acceptance — and within the settlement window — anyone can finalize:

```solidity
dealManager.finalizeSecondaryTradeAgreement(settlementAgreementId);
```

Finalization re-checks the pathway, threshold, and closing conditions
(eligibility must hold at settlement, not just at acceptance), pays the
seller net of the secondary fee (from which any integrator share is paid),
releases the unit reservation,
and executes the ownership change through
`IssuanceManager.secondaryTransfer` — decrementing the seller's cert and
minting the buyer's cert with the seller's endorsement attached.

## Cancelling and voiding

* `cancelOffer(offerId)` — offeror cancels a live offer; only the
  uncommitted units/consideration are released, in-flight settlements
  resolve on their own.
* `voidSecondaryTradeAgreement(agreementId, signer, signature)` — records a
  party's void request; the settlement voids once **both** parties request
  it (or it expires).
* `voidExpiredSecondaryTradeAgreement(agreementId, signer, signature)` —
  unwinds a settlement past its expiry.
* `syncVoidedSecondaryTradeAgreement(agreementId)` — syncs a settlement that
  was voided directly in the registry.

## Relayer support

`postOffer`, `cancelOffer`, and `acceptOffer` each have a relayed overload
`(…, address forAddr, uint256 nonce, bytes sig)` where `sig` is `forAddr`'s
EIP-712 authorization over the call parameters and nonce — so end users can
trade gaslessly. `voidSecondaryTradeAgreement`'s relayed overload is
different: `(agreementId, signer, voidSignature, nonce, authSig)` — the
registry void signature plus a separate relayer-authorization signature,
with `signer` as the authorized party.

## Bespoke deals

The generic deal flow still exists alongside the offer flow, for primary
issuances and negotiated bilateral deals:
`proposeDeal(...)` / `proposeAndSignDeal(...)` (both return
`(bytes32 agreementId, uint256[] certIds)`), then
`signDealAndPay(signer, agreementId, signature, partyValues,
fillUnallocated, name, secret)`, then `finalizeDeal(agreementId)` — with
`voidExpiredDeal` / `revokeDeal` / `signToVoid` for unwinding.

## Note on escrow

Escrow of payment and certs is internal to the DealManager in both flows —
there is no separate escrow contract to call. See
[LeXscroWLite](../reference/contracts/LeXscroWLite.md).

## Related

* [DealManager](../reference/contracts/DealManager.md),
  [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).
* [Gate state transitions with conditions](gate-with-conditions.md).
