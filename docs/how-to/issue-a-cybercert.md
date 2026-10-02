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

The new printer is filed under its `SecurityClass`'s class on the
IssuanceManager (an empty class is created if none exists). Its transfer
switches all start closed: certificates issue freely, but holders cannot
move them and the holder of record cannot change until an admin opens the
printer (`setGlobalTransferable`, `setGlobalLegalTransferable`, or the
per-lot equivalents). See
[LedgerEntryToken](../reference/contracts/LedgerEntryToken.md#delivery-and-registration-gates).

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

Every variant registers a holder of record; they differ in what else they
write.

| Function | Use when |
|---|---|
| `createCert(certAddress, to, details)` | Bare mint: `to` is registered with a blank name, and no endorsement or signature is written. |
| `createCertAndAssign(certAddress, investor, details)` | Mint with an issuance endorsement naming the investor, dated now. |
| `createCertAndAssignWithName(certAddress, investor, details, investorName, endorsementSignature, timestamp)` | As above, plus the holder's legal name, an officer signature, and an endorsement date you choose (a reissue keeps the original date). |
| `createCertSignAndAssign(certAddress, investor, details, endorsementSignature, registry, agreementId, investorName)` | As above, but the endorsement points at an agreement in a registry and is dated now. |

To move an existing lot to a different holder of record (a correction, not
a trade), use `assignCert(certAddress, from, tokenId, investor, details,
investorName)`, where `from` is the current holder of record. It needs the
printer's register to be open.

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
