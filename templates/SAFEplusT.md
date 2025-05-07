# Data Overview

id:

legalURI:

## Global Fields

/*      string[] memory globalFieldsSafe = new string[](17);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";
        globalFieldsSafe[5] = "exercisePriceMethod";
        globalFieldsSafe[6] = "exercisePrice";
        globalFieldsSafe[7] = "unlockStartTimeType";
        globalFieldsSafe[8] = "unlockStartTime";
        globalFieldsSafe[9] = "unlockingPeriod";
        globalFieldsSafe[10] = "latestExpirationTime";
        globalFieldsSafe[11] = "unlockingCliffPeriod";
        globalFieldsSafe[12] = "unlockingCliffPercentage";
        globalFieldsSafe[13] = "unlockingIntervalType";
        globalFieldsSafe[14] = "tokenCalculationMethod";
        globalFieldsSafe[15] = "minCompanyReserve";
        globalFieldsSafe[16] = "tokenPremiumMultiplier";


        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "name";
        partyFieldsSafe[1] = "evmAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "investorType";
        partyFieldsSafe[4] = "investorJurisdiction";

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount       |       e.g. "1000.00"              |
| postMoneyValuationCap       |          |
| expirationTime       |         |
| governingJurisdiction       |          |
| disputeResolution       |         |
| exercisePriceMethod       |           |
| exercisePrice       |          |
| unlockStartTimeType       |           |
| unlockStartTime       |           |
| unlockingPeriod       |           |
| latestExpirationTime       |          |
| unlockingCliffPeriod       |           |
| unlockingCliffPercentage       |         |
| unlockingIntervalType       |           |
| tokenCalculationMethod       |          |
| minCompanyReserve       |           |
| tokenPremiumMultiplier       |          |



## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
| name       | Name of the individual or organization  |
| evmAddress       |   |
| contactDetails       |   |
| investorType       |   |
| investorJurisdiction       |   |



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
    tokenWarrentTime,
    tgeTime,
    setTime
}

enum UnlockingIntervalType {
    blockly,
    secondly,
    hourly,
    daily,
    monthly
}

```

## Potential wording for storing floating point as uints (suggested by AI)

**"Value Representation"**: All fractional values are represented as unsigned integers (`uint`) by scaling the value up by a factor of \(10^18\), thereby preserving 18 decimal places of precision. The actual value is derived by dividing the stored integer by \(10^18\).


Restrictive Legends:

[1] investment advisor certificate custody legend

THE SAFE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFE WITHOUT THE PRIOR CONSENT OF THE COMPANY. 

[2] restricted security legend

THIS SAFE, THE SAFE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS SAFE, THE SAFE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.  

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE SAFE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY), NO COPY OF THE SAFE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH  BLOCKCHAIN SYSTEM (AND WHICH SAFE CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE SAFE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED).  IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ITS CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH CONTENTIOUS HARFORK, MUTATIS MUTANDIS.