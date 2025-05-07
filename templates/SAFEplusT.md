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

name: TokenWarrantExtension
```solidity
struct TokenWarrantData {
    ExercisePriceMethod exercisePriceMethod;  // perToken or perWarrant
    uint256 exercisePrice;                   // 18 decimals
    UnlockStartTimeType unlockStartTimeType;     // enum of different types, can be tokenWarrantTime, tgeTime, or setTime
    uint256 unlockStartTime;                 // seconds (relative unless type is fixed)
    uint256 unlockingPeriod;
    uint256 latestExpirationTime; //latest time at which the Warrant can expire (cease to be exercisable)--denominated in seconds
    uint256 unlockingCliffPeriod; // seconds
    uint256 unlockingCliffPercentage; // what precision??
    UnlockingIntervalType unlockingIntervalType; // blockly, seconds, daily, weekly, monthly
    TokenCalculationMethod tokenCalculationMethod; //equityProRataToTokenSupply or equityProRataToCompanyReserve
    uint256 minCompanyReserve; //minimum company reserve within an equityProRataToCompanyReserve method--set to 0 if there is no minimum
    uint256 tokenPremiumMultiplier; //multiplier of network valuation over company equity valuation, to be used within equityProRataToTokenSupply method (set to 0 if no premium)
}
```

## CertificateDetails Struct (for reference)

```solidity
struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmountUSD;
    uint256 issuerUSDValuationAtTimeofInvestment;
    uint256 unitsRepresented;
    string legalDetails;
    bytes extensionData;
}
```

```
enum ExercisePriceMethod {
    perToken,
    perWarrant
}

enum TokenCalculationMethod {
    equityProRataToCompanyReserve,
    equityProRataToTokenSupply 
}

enum UnlockStartTimeType {
    toeknWarrentTime,
    tgeTime,
    setTime
}

enum UnlockingIntervalType {
    byBlock,
    seconds,
    hourly,
    daily,
    monthly,
    quarterly
}

```

## Potential wording for storing floating point as uints (suggested by AI)

**"Value Representation"**: All fractional values are represented as unsigned integers (`uint`) by scaling the value up by a factor of \(10^18\), thereby preserving 18 decimal places of precision. The actual value is derived by dividing the stored integer by \(10^18\).
