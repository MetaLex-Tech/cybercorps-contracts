# Data Overview

id:

legalURI:

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| exercisePrice       | e.g. "1000.00"                     |
| exercisePrice       | e.g. "1000.00"                     |


## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
| investorType       | Name of the individual or organization  |
| investorName       | Name of the individual or organization  |


## Certificate Extension

name: TokenWarrentExtension
```solidity
struct TokenWarrantData {
    ExercisePriceMethod exercisePriceMethod  // per token or per warrant
    uint256 exercisePrice;                   // 18 decimals
    ConversionType conversionType;
    uint256 reservePercent;
    uint256 networkPremiumMultiplier;
    LockupStartType unlockStartTimeType;     // enum of different types
    uint256 unlockStartTime;                 // seconds (relative unless type is fixed)
    uint256 lockupLength; // TODO: DO WE NEED THIS?

    //
    uint256 unlockingCliffPeriod; // seconds
    uint256 unlockingCliffPercentage; // what precision??
    UnlockingIntervalType unlockingIntervalType; // block, second, daily, weekly, monthly

    TokenCaclulationMethod tokenCalculationMethod;
    // TODO: fields for token calc price
    uint256 latestExpirationTime;            // Unix timesatamp (seconds)
}
```

## CertificateDetails Struct (for reference)

```solidity
struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmount;
    uint256 issuerUSDValuationAtTimeofInvestment;
    uint256 unitsRepresented;
    string legalDetails;
}
```

## Potential wording for storing floating point as uints (suggested by AI)

**"Value Representation"**: All fractional values are represented as unsigned integers (`uint`) by scaling the value up by a factor of \(10^18\), thereby preserving 18 decimal places of precision. The actual value is derived by dividing the stored integer by \(10^18\).
