# Data Overview

id: bytes32(bytes("three_prime_safe_t"))

legalURI:
safeURI: IFPS://bafybeibojsh6f4wxj3gvwjbv7uvvurony7jumyqqi5i6rqsv7wcywdsi44

combined doc: IPFS://bafybeidbzt4y3uvxxouzcli4k6p3zgozh5bp6dqphzhkn5o5adcgs5emja

SAFE alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeifmwe5gzjl4j57qs4hdmytcocp55uaiqgdut5gvibuvejmd7avqja

Warrant alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeibhtpwtgsdbwvqfg2dynotwiorbmbqmluj7ci6vc5wn6mrlh2eawy

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount      |       e.g. "1000.00"              |
| postMoneyValuationCap       |          |
| expirationTime      |         |
| governingJurisdiction       |          |
| disputeResolution   |         |
| exercisePriceMethod | "perToken" or "perWarrant"  |
| exercisePrice       | price, e.g. "1000.00"  |
| unlockStartTimeType |"tokenWarrantTime" \|"tgeTime" \| "setTime"        |
| unlockStartTime       | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod       | Duration in `unlockingInvervalType` units  |
| latestExpirationTime       | Unix timestamp. Will not be prompted for in UI, will be 10 yrs from deal date   |
| unlockingCliffPeriod       | Duration in `unlockingIntervalType`, first tokens unlocked at `unlockingStartTime` + `unlockingCliffPeriod`  |
| unlockingCliffPercentage       | e.g. "10.5%" |
| unlockingIntervalType       |  "secondly", "hourly", "daily", "monthly", "blockly". Note that this affects both `unlockingPeriod` and `unlockingCliffPeriod`   |
| tokenCalculationMethod       |  `equityProRataToTokenSupply` or `equityProRataToCompanyReserve`        |
| minCompanyReserve       | This is a number of tokens   |
| tokenPremiumMultiplier  | A number. If SAFE is worth 30% of company fully diluted equity, and premium multiplier is 2, the investor can buy 15% of total supply.       |



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
    tokenWarrantTime,
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

safe

[1] investment advisor certificate custody legend

THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFE WITHOUT THE PRIOR CONSENT OF THE COMPANY. 

[2] restricted security legend

THIS SAFE, THE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS SAFE, THE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.

token warrant

[1] investment advisor certificate custody legend

THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS TOKEN WARRANT WITHOUT THE PRIOR CONSENT OF THE COMPANY.

[2] restricted security legend

THIS TOKEN WARRANT, THE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS TOKEN WARRANT, THE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS TOKEN WARRANT AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.




