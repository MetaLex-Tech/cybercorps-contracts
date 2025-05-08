# Data Overview

id: bytes32(uint256(2))

legalURI:
safeURI:https://ipfs.io/ipfs/bafybeiacwnkl4oai7ncsomqniu5jwoc3soibnwocrrt2jm2fhpz6c2cczm
tokenWarrantURI:https://ipfs.io/ipfs/bafybeia2kruqmomqbyw37oi5mbodzrfsnk2b3x2d46k2e224u6oinrpudi

## Global Fields

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
    uint256 exercisePrice;    // 18 decimals
    UnlockStartTimeType unlockStartTimeType;    // enum of different types, can be tokenWarrantTime, tgeTime, or setTime
    uint256 unlockStartTime;                
    uint256 unlockingPeriod;
    uint256 latestExpirationTime;
    uint256 unlockingCliffPeriod;
    uint256 unlockingCliffPercentage; 
    UnlockingIntervalType unlockingIntervalType; // blockly, secondly, daily, weekly, monthly
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
    uint256 issuerUSDValuationAtTimeOfInvestment;
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

Restrictive Legends:

[1] investment advisor certificate custody legend

THE SAFE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFE WITHOUT THE PRIOR CONSENT OF THE COMPANY. 

[2] restricted security legend

THIS SAFE, THE SAFE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS SAFE, THE SAFE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.  

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE SAFE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY), NO COPY OF THE SAFE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH  BLOCKCHAIN SYSTEM (AND WHICH SAFE CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE SAFE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED).  IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ITS CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH CONTENTIOUS HARFORK, MUTATIS MUTANDIS.