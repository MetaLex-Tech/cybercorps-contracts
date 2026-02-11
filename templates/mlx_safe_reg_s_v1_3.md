# Data Overview

id: bytes32(bytes("mlx_safe_reg_s_v1_3"))
idHex: 0x6d6c785f736166655f7265675f735f76315f3300000000000000000000000000
title: mlx_safe_reg_s_v1_3

legalURI:
safeURI: IPFS://bafybeieh7jn553jmrjmwee3dsvwf5hkedomey2vhubc3mumlewfpumvlae

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeieh7jn553jmrjmwee3dsvwf5hkedomey2vhubc3mumlewfpumvlae
SAFE alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeigkcbocfq3p7rscojjej24jajyrhqk6mukgetmlsmyo4f6cp6iqry

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
