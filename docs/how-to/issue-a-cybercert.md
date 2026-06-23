# Issue a cyberCERT

This is how you mint a new register entry on a cyberCORP — stock, a SAFE, an
option, or any [supported security type](../reference/security-types.md).

## Prerequisites

* A cyberCORP and its `issuanceManager` address.
* A `CyberCertPrinter` for the security class (create one with
  `createCertPrinter` if needed).

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
    SHARE_EXTENSION_ADDR           // certificate extension
);
```

## 2. Build the `CertificateDetails`

From [`CyberCertPrinterStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/CyberCertPrinterStorage.sol):

```solidity
import {CertificateDetails} from "src/storage/CyberCertPrinterStorage.sol";

CertificateDetails memory details = CertificateDetails({
    signingOfficerName:                  "Jane Founder",
    signingOfficerTitle:                 "Chief Executive Officer",
    investmentAmountUSD:                 2_500_000e18,
    issuerUSDValuationAtTimeOfInvestment: 20_000_000e18,
    unitsRepresented:                    1_000_000,
    legalDetails:                        "Series A Preferred",
    extensionData:                       abi.encode(/* per the extension */)
});
```

## 3. Mint

| Function | Use when |
|---|---|
| `createCert(certAddress, to, details)` | Mint without setting a registered owner. |
| `createCertAndAssign(certAddress, investor, details)` | Mint and record the registered owner. |
| `createCertAndAssignWithName(...)` | As above, plus a holder name and an endorsement signature. |
| `createCertSignAndAssign(...)` | As above, plus a registry/agreement reference. |

```solidity
uint256 tokenId = IIssuanceManager(issuanceManager).createCertAndAssign(
    printer, investor, details
);
```

## Other operations

* **Endorse:** `endorseCertificate(certAddress, tokenId, endorser, signature, agreementId)`.
* **Officer signature:** `addOfficerSignature(certAddress, tokenId, signature)`.
* **Void / unvoid:** `voidCertificate` / `unvoidCertificate`.

## Related

* [IssuanceManager](../reference/contracts/IssuanceManager.md),
  [CyberCertPrinter](../reference/contracts/CyberCertPrinter.md).
