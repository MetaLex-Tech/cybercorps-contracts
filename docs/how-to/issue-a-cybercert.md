---
description: Create a security-class printer and issue certificates under it
---

# Issue a cyberCERT

This is how you mint a new register entry on a cyberCORP — stock, a SAFE, an
option, or any [supported security type](../reference/security-types.md).

## Prerequisites

* A cyberCORP and its `issuanceManager` address.
* A cert printer (a `LedgerEntryToken` instance, formerly `CyberCertPrinter`)
  for the security class (create one with `createCertPrinter` if needed).

## 1. (If needed) create the certificate printer

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
    ""                             // seriesData — extension-encoded
                                   // series-scope payload; "" if none
);
```

## 2. Build the `CertificateDetails`

From [`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol):

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
`unitsRepresented`, `investmentAmountUSD`, and
`issuerUSDValuationAtTimeOfInvestment` are all **18-decimal fixed point**:
one share (or one dollar) = `1e18`.
{% endhint %}

## 3. Mint

| Function | Use when |
|---|---|
| `createCert(certAddress, to, details)` | Mint without setting a registered owner. |
| `createCertAndAssign(certAddress, investor, details)` | Mint and record the registered owner. |
| `createCertAndAssignWithName(certAddress, investor, details, investorName, endorsementSignature, timestamp)` | As above, plus a holder name, an endorsement signature, and its timestamp. |
| `createCertSignAndAssign(certAddress, investor, details, endorsementSignature, registry, agreementId, investorName)` | As above, plus a registry/agreement reference. |

```solidity
uint256 tokenId = IIssuanceManager(issuanceManager).createCertAndAssign(
    printer, investor, details
);
```

## Other operations

Cert-level operations were moved off the IssuanceManager onto the cert
printer itself (`LedgerEntryToken`), callable by the IssuanceManager or a
BorgAuth admin:

* **Endorse:** `endorseCertificate(tokenId, endorser, signature, agreementId)`
  on the printer (assembles the endorsement onchain); the registered owner
  can also call `addEndorsement(tokenId, endorsement)` directly.
* **Issuer signature:** `addIssuerSignature(tokenId, signature)`.
* **Void / unvoid:** `voidCert(tokenId)` / `unvoidCert(tokenId)`.

## Related

* [IssuanceManager](../reference/contracts/IssuanceManager.md),
  [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md).
