# Data Overview

id: bytes32(uint256([____]))

legalURI: 
SAFTE URI: ipfs://bafybeid4xxgesjbxpdwx3dmcxlupzscurpnh6c3k7lukhzt2fsfkbxjr34

combined doc: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay)

SAFTE alone: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeid4xxgesjbxpdwx3dmcxlupzscurpnh6c3k7lukhzt2fsfkbxjr34](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeid4xxgesjbxpdwx3dmcxlupzscurpnh6c3k7lukhzt2fsfkbxjr34)

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount      |       e.g. "1000.00"              |
| postMoneyValuationCap  |     post-money equity valuation of the company  |
| expirationTime      |    time at which offer to sign agreement (purchasing the SAFTE) expires     |
| governingJurisdiction       |     jurisdiction of incorporation and also jurisdiction of governing law for the agreement     |
| disputeResolution   |       method of dispute resolution   |
| unlockStartTimeType |"tokenWarrantTime" \|"tgeTime" \| "setTime"        |
| unlockStartTime       | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod       | Duration in `unlockingIntervalType` units  |
| unlockingCliffPeriod       | Duration in `unlockingIntervalType`, first tokens unlocked at `unlockStartTime` + `unlockingCliffPeriod`  |
| unlockingCliffPercentage       | e.g. "10.5%" |
| unlockingIntervalType       |  "secondly", "hourly", "daily", "monthly", "blockly". Note that this affects both `unlockingPeriod` and `unlockingCliffPeriod`   |
| tokenCalculationMethod       |  `equityProRataToTokenSupply` or `equityProRataToCompanyReserve` or `dollarProRataToProtocolVal` |
| minCompanyReserve       | This is a number of tokens   |
| tokenPremiumMultiplier  | A number. If used with equityProRataToTokenSupply method, then if SAFTE is worth 30% of company fully diluted equity, and premium multiplier is 2, the investor will be entitled 15% of total supply.       |
| protocolUSDValuationAtTimeofInvestment    |  valuation of the "network" or "protocol" (i.e., FDV of all tokens)  |
| customProvisions  | an arbitrary string intended to insert any custom provision the parties agree upon |


## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
| name       | Name of the individual or organization  |
| evmAddress       |   |
| contactDetails       |   |
| investorType       |   |
| investorJurisdiction       |   |


## Certificate Extension

name: SAFTEExtension
```solidity
struct SAFTEData {
    UnlockStartTimeType unlockStartTimeType;    
    uint256 unlockStartTime;                
    uint256 unlockingPeriod; 
    uint256 unlockingCliffPeriod; 
    uint256 unlockingCliffPercentage; 
    UnlockingIntervalType unlockingIntervalType;
    TokenCalculationMethod tokenCalculationMethod; 
    uint256 minCompanyReserve;
    uint256 tokenPremiumMultiplier;
    uint256 protocolUSDValuationAtTimeofInvestment;
    string customProvisions; // an arbitrary string intended to insert any custom provision the parties agree upon
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
enum TokenCalculationMethod {
    equityProRataToCompanyReserve,
    equityProRataToTokenSupply,
    dollarProRataToProtocolVal
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

[1] investment advisor certificate custody legend

THE SAFTE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFTE WITHOUT THE PRIOR CONSENT OF THE COMPANY. 

[2] restricted security legend

THIS SAFTE, THE SAFTE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS SAFTE, THE SAFTE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFTE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.  

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE SAFTE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY), NO COPY OF THE SAFTE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH  BLOCKCHAIN SYSTEM (AND WHICH SAFTE CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE SAFTE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED).  IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ITS CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH CONTENTIOUS HARFORK, MUTATIS MUTANDIS.
