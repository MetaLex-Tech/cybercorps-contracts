# Data Overview

id: bytes32(bytes("mlx_saft_reg_s_v1_3"))
idHex: 0x6d6c785f736166745f7265675f735f76315f3300000000000000000000000000
title: mlx_saft_reg_s_v1_3

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeibwrz3rttteguo5ccoh5x7ndwdu6hyhy7i3iraii5c5ml4pfv73t4
SAFT alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeighy3fgweoeivmxnp62ryrckn7xgtjerrsefrkxrruea6tq2q6gyi

## Global Fields

| **globalFieldName** | **description** |
|:--------------------|:----------------|
| purchaseAmount | e.g. "1000.00" |
| protocolValuationCap |  |
| governingJurisdiction |  |
| disputeResolution |  |
| unlockStartTimeType | "agreementExecutionTime" \| "tgeTime" \| "setTime" |
| unlockStartTime | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod | Duration in `unlockingIntervalType` units |
| unlockingCliffPeriod | Duration in `unlockingIntervalType` |
| unlockingCliffPercentage | e.g. "10.5%" |
| unlockingIntervalType | "secondly", "hourly", "daily", "monthly", "blockly" |

## Party Fields

| **partyFieldName** | **description** |
|:-------------------|:----------------|
| name | Name of the individual or organization |
| evmAddress |  |
| contactDetails |  |
| investorType |  |
| investorJurisdiction |  |

## Certificate Extension

name: SAFTEExtension

```solidity
struct SAFTData {
    UnlockStartTimeType unlockStartTimeType;
    uint256 agreementExecutionTime;
    uint256 unlockingPeriod;
    uint256 unlockingCliffPeriod;
    uint256 unlockingCliffPercentage;
    UnlockingIntervalType unlockingIntervalType;
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
