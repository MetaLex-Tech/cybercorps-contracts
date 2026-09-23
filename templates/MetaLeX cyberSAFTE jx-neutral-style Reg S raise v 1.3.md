# Data Overview

SAFTE Reg S 

id: bytes32(uint256([____]))

legalURI: 
SAFTE URI: ipfs://bafybeihtnhmplfq6xx7pxhovchc4np2akabi4nxr5nmbys6vu4yvhftxrq

combined doc: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeia43r7e566s2jlq4gtaasmtybutujy7fuizhw3fycxtwnstfbkeia](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeia43r7e566s2jlq4gtaasmtybutujy7fuizhw3fycxtwnstfbkeia)

SAFTE alone: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeihtnhmplfq6xx7pxhovchc4np2akabi4nxr5nmbys6vu4yvhftxrq](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeihtnhmplfq6xx7pxhovchc4np2akabi4nxr5nmbys6vu4yvhftxrq)

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

[1] ria complaince legend

RIA COMPLIANCE LEGEND. THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFTE WITHOUT THE PRIOR CONSENT OF THE COMPANY.

[2] regulation s legend

REGULATION S LEGEND. THIS SAFTE AND THE CERTIFICATE TOKEN HAVE NOT BEEN, AND WILL NOT BE, REGISTERED UNDER ANY SECURITIES LAWS, INCLUDING THOSE OF THE UNITED STATES OF AMERICA. THIS SAFTE AND THE CERTIFICATE TOKEN ARE ONLY BEING OFFERED FOR SALE OUTSIDE THE UNITED STATES OF AMERICA TO PERSONS OTHER THAN U.S. PERSONS IN OFFSHORE TRANSACTIONS MEETING THE REQUIREMENTS OF REGULATION S UNDER THE SECURITIES ACT (“REGULATION S”). AS USED HEREIN, THE TERMS “OFFSHORE TRANSACTIONS” AND “U.S. PERSON” HAVE THE MEANINGS GIVEN TO THEM IN REGULATION S. THIS AGREEMENT. THIS SAFTE AND THE CERTIFICATE TOKEN ARE NOT PERMITTED TO BE OFFERED OR SOLD (INCLUDING OPENING A SHORT POSITION IN SUCH SECURITIES) IN THE UNITED STATES OR TO U.S. PERSONS AS DEFINED BY RULE 902(k) ADOPTED UNDER THE ACT, UNLESS THEY ARE REGISTERED UNDER THE SECURITIES ACT OF 1933 (THE “ACT”), OR AN EXEMPTION FROM THE REGISTRATION REQUIREMENTS OF THE ACT IS AVAILABLE. YOU MAY RESELL SUCH SECURITIES ONLY PURSUANT TO AN EXEMPTION FROM REGISTRATION UNDER THE ACT OR OTHERWISE IN ACCORDANCE WITH THE PROVISIONS OF REGULATION S OF THE ACT, OR IN TRANSACTIONS EFFECTED OUTSIDE OF THE UNITED STATES PROVIDED YOU DO NOT SOLICIT (AND NO ONE ACTING ON YOUR BEHALF SOLICITS) PURCHASERS IN THE UNITED STATES OR OTHERWISE ENGAGE(S) IN SELLING EFFORTS IN THE UNITED STATES AND PROVIDED THAT HEDGING TRANSACTIONS INVOLVING THESE SECURITIES MAY NOT BE CONDUCTED UNLESS IN COMPLIANCE WITH THE ACT AND ALL OTHER APPLICABLE SECURITIES LAWS. A HOLDER OF THE SECURITIES WHO IS A DISTRIBUTOR, DEALER, SUB-UNDERWRITER OR OTHER SECURITIES PROFESSIONAL, IN ADDITION, CANNOT RESELL THE SECURITIES TO A U.S. PERSON AS DEFINED BY RULE 902(k) OF REGULATION S UNLESS THE SECURITIES ARE REGISTERED UNDER THE ACT OR AN EXEMPTION FROM REGISTRATION UNDER THE ACT IS AVAILABLE.

[3] contentious hardfork legend

CONTENTIOUS HARDFORK LEGEND. IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.

