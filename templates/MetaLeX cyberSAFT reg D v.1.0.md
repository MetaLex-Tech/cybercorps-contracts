# Data Overview

id: bytes32(uint256(24))

combined doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeif6fqgexescp4g2hbb6fjkk3ifrqpopc2lv2oue5tiq6h3t2pmgc4

SAFT alone: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeif7wf53zdhbrcla6wlvvnj3oie4nlv5ojeqaykwiftas3irpdetme

Github: https://github.com/MetaLex-Tech/publicDocs/blob/main/cyberKs/cyberSAFT/MetaLeX%20cyberSAFT%20reg%20D%20v.1.0.pdf


## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount      |       e.g. "1000.00"              |
| protocolValuationCap       |          |
| governingJurisdiction       |          |
| disputeResolution   |         |
| unlockStartTimeType |"agreementExecutionTime" \|"tgeTime" \| "setTime"        |
| unlockStartTime       | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod       | Duration in `unlockingInvervalType` units  |
| unlockingCliffPeriod       | Duration in `unlockingIntervalType`, first tokens unlocked at `unlockingStartTime` + `unlockingCliffPeriod`  |
| unlockingCliffPercentage       | e.g. "10.5%" |
| unlockingIntervalType       |  "secondly", "hourly", "daily", "monthly", "blockly". Note that this affects both `unlockingPeriod` and `unlockingCliffPeriod`   |


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
struct SAFTData {
    UnlockStartTimeType unlockStartTimeType;    // enum of different types, can be agreementStartTime, tgeTime, or setTime
    uint256 agreementExecutionTime;                
    uint256 unlockingPeriod;
    uint256 unlockingCliffPeriod;
    uint256 unlockingCliffPercentage;
    UnlockingIntervalType unlockingIntervalType; - // blockly, secondly, daily, weekly, monthly
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

Restrictive Legends

[1] ria compliance legend.

RIA COMPLIANCE LEGEND. THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFT WITHOUT THE PRIOR CONSENT OF THE COMPANY.

[2] restricted securities legend.

RESTRICTED SECURITIES LEGEND. THIS INSTRUMENT, THE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144.

[3] unregistered securities legend.

UNREGISTERED SECURITIES LEGEND. THIS INSTRUMENT, THE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFT AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.

[4] contentious hardfork legend.

CONTENTIOUS HARDFORK LEGEND. IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.
