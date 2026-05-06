# Data Overview

id: bytes32(bytes("mlx_safte_reg_d_v1_3"))
idHex: 0x6d6c785f73616674655f7265675f645f76315f33000000000000000000000000
title: mlx_safte_reg_d_v1_3

legalURI:
safeURI: IPFS://bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay
SAFTE alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeid4xxgesjbxpdwx3dmcxlupzscurpnh6c3k7lukhzt2fsfkbxjr34

## Global Fields

| **globalFieldName** | **description** |
|:--------------------|:----------------|
| purchaseAmount | e.g. "1000.00" |
| postMoneyValuationCap |  |
| protocolUSDValuationAtTimeofInvestment |  |
| expirationTime |  |
| governingJurisdiction |  |
| disputeResolution |  |
| unlockStartTimeType | "agreementExecutionTime" \| "tgeTime" \| "setTime" |
| unlockStartTime | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod | Duration in `unlockingIntervalType` units |
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

name: SAFTEExtension

```solidity
struct SAFTEData {
    uint256 protocolUSDValuationAtTimeofInvestment;
    UnlockStartTimeType unlockStartTimeType;
    uint256 unlockStartTime;
    uint256 unlockingPeriod;
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
