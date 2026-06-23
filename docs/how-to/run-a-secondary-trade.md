# Run a secondary trade

Secondary trades settle through a cyberCORP's **`DealManager`**. A deal is
built from an agreement template and identified by a `bytes32 agreementId`.

## 1. Propose the deal

```solidity
bytes32 agreementId = IDealManager(dealManager).proposeDeal(
    certPrinters,     // address[] — cert printers involved
    USDC,             // paymentToken
    200_000e6,        // paymentAmount
    templateId,       // bytes32 agreement template
    salt,             // uint256
    globalValues,     // string[]
    parties,          // address[] — the counterparties
    certDetails,      // CertificateDetails[]
    partyValues,      // string[][]
    conditions,       // address[] — ICondition gates
    secretHash,       // bytes32
    expiry            // uint256
);
```

Use `proposeAndSignDeal` to propose and sign in one call.

## 2. Counterparties sign (and pay)

Each party signs the agreement (EIP-712). `signDealAndPay` combines a party's
signature with their payment:

```solidity
IDealManager(dealManager).signDealAndPay(
    signer,
    agreementId,
    signature,        // bytes (EIP-712)
    partyValues,      // string[]
    fillUnallocated,  // bool
    name,             // string
    secret            // string — if the deal is secret-gated
);
```

## 3. Finalise

When all parties have signed and the deal's conditions are satisfied:

```solidity
IDealManager(dealManager).finalizeDeal(agreementId);
```

Finalisation applies the deal's certificate effects (mint / assign /
endorse) through the IssuanceManager. `signAndFinalizeDeal` does the final
signature and finalisation together.

## Cancelling

* `voidExpiredDeal(agreementId, signer, signature)` — clear an expired deal.
* `revokeDeal(agreementId, signer, signature)` — revoke before completion.
* `signToVoid(agreementId, signer, signature)` — sign to void a deal.

## Note on escrow

The escrow of payment and assets is part of this deal flow — there is no
separate escrow contract to call. See
[LeXscroWLite](../reference/contracts/LeXscroWLite.md).

## Related

* [DealManager](../reference/contracts/DealManager.md),
  [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).
