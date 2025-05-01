# Data Overview

id:

legalURI: 

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| test                |                                    | 


## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
| name               | Name of the individual or organization  |


## Certificate Extension

name: TokenWarrentExtension
```
struct TokenWarrantData {
    ExercisePriceType exercisePriceType;
    uint256 exercisePrice;
    ConversionType conversionType;
    uint256 reservePercent;
    uint256 networkPremiumMultiplier;
    LockupStartType lockupStartType;
    uint256 lockupLength;
    uint256 lockupCliffInMonths;
    LockupIntervalType lockupIntervalType;
    uint256 latestExpirationTime;
}
```
