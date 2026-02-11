# Data Overview

id: bytes32(bytes("mlx_safe_reg_d_v1_3"))
idHex: 0x6d6c785f736166655f7265675f645f76315f3300000000000000000000000000
title: mlx_safe_reg_d_v1_3

legalURI:
safeURI: IPFS://bafybeih7l2kxncjuwrfgv5gnmpcik43dnn4pxpe4it4u7ti2hgfgrlot2a

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeih7l2kxncjuwrfgv5gnmpcik43dnn4pxpe4it4u7ti2hgfgrlot2a
SAFE alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeidq7z4sgbh5tqxfehs5rz3r3il76ony3t7psetwge5ctld6lubi5e

## Global Fields

| **globalFieldName** | **description** |
|:--------------------|:----------------|
| purchaseAmount | e.g. "1000.00" |
| postMoneyValuationCap |  |
| expirationTime |  |
| governingJurisdiction |  |
| disputeResolution |  |

## Party Fields

| **partyFieldName** | **description** |
|:-------------------|:----------------|
| name | Name of the individual or organization |
| evmAddress |  |
| contactDetails |  |
| investorType |  |
| investorJurisdiction |  |

## Certificate Extension

none.

## CertificateDetails Struct (for reference)

```solidity
struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmountUSD;
    uint256 issuerUSDValuationAtTimeOfInvestment;
    uint256 unitsRepresented;
    string legalDetails;
    bytes extensionData;
}
```
