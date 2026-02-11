# Data Overview

id: bytes32(bytes("mlx_safe_tw_reg_d_v1_3"))
idHex: 0x6d6c785f736166655f74775f7265675f645f76315f3300000000000000000000
title: mlx_safe_tw_reg_d_v1_3

legalURI:
safeURI: IPFS://bafybeiaw3pwov3ahg4bk2hte2hu4pwv34nndoguxyk3umq6f5su3kod6ay

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiaw3pwov3ahg4bk2hte2hu4pwv34nndoguxyk3umq6f5su3kod6ay
SAFE alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeidq7z4sgbh5tqxfehs5rz3r3il76ony3t7psetwge5ctld6lubi5e
Warrant alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeidmtxc6hveimc43uxdkohbi7ubmtkd57irpday2hmhomuyguxtg7a

## Global Fields

| **globalFieldName** | **description** |
|:--------------------|:----------------|
| purchaseAmount | e.g. "1000.00" |
| postMoneyValuationCap |  |
| expirationTime |  |
| governingJurisdiction |  |
| disputeResolution |  |
| exercisePriceMethod | "perToken" or "perWarrant" |
| exercisePrice | price, e.g. "1000.00" |
| unlockStartTimeType | "tokenWarrantTime" \| "tgeTime" \| "setTime" |
| unlockStartTime | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod | Duration in `unlockingIntervalType` units |
| latestExpirationTime | Unix timestamp |
| unlockingCliffPeriod | Duration in `unlockingIntervalType` |
| unlockingCliffPercentage | e.g. "10.5%" |
| unlockingIntervalType | "secondly", "hourly", "daily", "monthly", "blockly" |
| tokenCalculationMethod | `equityProRataToTokenSupply` or `equityProRataToCompanyReserve` |
| minCompanyReserve | Number of tokens |
| tokenPremiumMultiplier | Premium multiplier |

## Party Fields

| **partyFieldName** | **description** |
|:-------------------|:----------------|
| name | Name of the individual or organization |
| evmAddress |  |
| contactDetails |  |
| investorType |  |
| investorJurisdiction |  |

## Certificate Extension

name: TokenWarrantExtension

```solidity
struct TokenWarrantData {
    ExercisePriceMethod exercisePriceMethod;
    uint256 exercisePrice;
    UnlockStartTimeType unlockStartTimeType;
    uint256 unlockStartTime;
    uint256 unlockingPeriod;
    uint256 latestExpirationTime;
    uint256 unlockingCliffPeriod;
    uint256 unlockingCliffPercentage;
    UnlockingIntervalType unlockingIntervalType;
    TokenCalculationMethod tokenCalculationMethod;
    uint256 minCompanyReserve;
    uint256 tokenPremiumMultiplier;
}
```

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
