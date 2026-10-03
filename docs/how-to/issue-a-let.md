---
description: Create a LET contract for a security class and series and issue Ledger Entry Tokens from it
---

# Issue a LET

A Ledger Entry Token (LET) records one lot of a cyberCORP security: stock, a
SAFE, an option or any other [supported security type](../reference/security-types.md).
This guide issues LETs through the company's `IssuanceManager`.

You need the company's `issuanceManager` address and a LET contract (a
`LedgerEntryToken` deployment) for the security's class and series. Step 1
creates one if the series has none.

## 1. Create the LET contract, if the series has none

```solidity
import {SecurityClass, SecuritySeries} from "src/CyberCorpConstants.sol";

address printer = IIssuanceManager(issuanceManager).createCertPrinter(
    defaultLegend,                 // string[]
    "Acme Series A Preferred",     // name
    "ACME-A",                      // ticker
    "ipfs://acme-cert-art",        // certificate URI
    SecurityClass.PreferredStock,
    SecuritySeries.SeriesA,
    SHARE_EXTENSION_ADDR,          // certificate extension
    ""                             // seriesData, the extension-encoded
                                   // series-scope payload; "" if none
);
```

The IssuanceManager files the new LET contract under its `SecurityClass`,
creating an empty class if none exists. Its transfer switches all start
closed: LETs issue freely, but holders cannot move them and the holder of
record cannot change until an admin opens the contract with
`setGlobalTransferable`, `setGlobalLegalTransferable` or the per-lot
equivalents. [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md)
documents the delivery and registration gates.

## 2. Build the `CertificateDetails`

The struct is defined in
[`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol).

```solidity
import {CertificateDetails} from "src/interfaces/ILedgerEntryToken.sol";

CertificateDetails memory details = CertificateDetails({
    signingOfficerName:                  "Jane Founder",
    signingOfficerTitle:                 "Chief Executive Officer",
    investmentAmountUSD:                 2_500_000e18,
    issuerUSDValuationAtTimeOfInvestment: 20_000_000e18,
    unitsRepresented:                    1_000_000e18, // 1,000,000 shares (18-decimal)
    legalDetails:                        "Series A Preferred",
    extensionData:                       abi.encode(/* per the extension */)
});
```

{% hint style="warning" %}
`unitsRepresented`, `investmentAmountUSD` and
`issuerUSDValuationAtTimeOfInvestment` are all **18-decimal fixed point**:
one share (or one dollar) is `1e18`.
{% endhint %}

## 3. Mint the LET

Every mint function registers a holder of record. They differ in what else
they write.

| Function | Use when |
|---|---|
| `createCert(certAddress, to, details)` | Bare mint: `to` is registered with a blank name, and no endorsement or signature is written. |
| `createCertAndAssign(certAddress, investor, details)` | Mint with an issuance endorsement naming the investor, dated now. |
| `createCertAndAssignWithName(certAddress, investor, details, investorName, endorsementSignature, timestamp)` | As above, plus the holder's legal name, an officer signature, and an endorsement date you choose (a reissue keeps the original date). |
| `createCertSignAndAssign(certAddress, investor, details, endorsementSignature, registry, agreementId, investorName)` | As above, but the endorsement points at an agreement in a registry and is dated now. |

```solidity
uint256 tokenId = IIssuanceManager(issuanceManager).createCertAndAssign(
    printer, investor, details
);
```

To correct the holder of record on an existing lot outside a trade, call
`assignCert(certAddress, from, tokenId, investor, details, investorName)`,
where `from` is the current holder of record. The LET contract's
registration gate must be open.

## 4. Endorse, sign or void an existing LET

These operations live on the LET contract itself, and the IssuanceManager
or a BorgAuth admin can call them:

* **Endorse:** `endorseCertificate(tokenId, endorser, signature, agreementId)`
  assembles the endorsement onchain. The registered owner can also call
  `addEndorsement(tokenId, endorsement)` directly.
* **Issuer signature:** `addIssuerSignature(tokenId, signature)`.
* **Void or unvoid:** `voidCert(tokenId)` and `unvoidCert(tokenId)`.

Function-level detail is in
[IssuanceManager](../reference/contracts/IssuanceManager.md) and
[LedgerEntryToken](../reference/contracts/LedgerEntryToken.md).
