# Data Overview

id: bytes32(uint256(35))

legalURI:
saftURI: ipfs://bafybeighy3fgweoeivmxnp62ryrckn7xgtjerrsefrkxrruea6tq2q6gyi


combined doc: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeidquzma24o53tiys7kvspvx5izc7iru5n5dfgfwmxefi3qd67ou2y](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeibwrz3rttteguo5ccoh5x7ndwdu6hyhy7i3iraii5c5ml4pfv73t4)

SAFT alone: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeieqiarv2kqdbkmvrf2o6powu375hayji54gauqhqpz2kfmypao6nm](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeighy3fgweoeivmxnp62ryrckn7xgtjerrsefrkxrruea6tq2q6gyi)


## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount      |       e.g. "1000.00"              |
| protocolValuationCap       |          |
| governingJurisdiction       |          |
| disputeResolution   |         |
| unlockStartTimeType |"agreementStartTime" \|"tgeTime" \| "setTime"        |
| unlockStartTime       | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod       | Duration in `unlockingInvervalType` units  |
| unlockingCliffPeriod       | Duration in `unlockingIntervalType`, first tokens unlocked at `unlockingStartTime` + `unlockingCliffPeriod`  |
| unlockingCliffPercentage       | e.g. "10.5%" |
| unlockingIntervalType       |  "secondly", "hourly", "daily", "monthly", "blockly". Note that this affects both `unlockingPeriod` and `unlockingCliffPeriod`   |
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

name: SAFTExtension
```solidity
struct SAFTData {
    UnlockStartTimeType unlockStartTimeType;    // enum of different types, can be agreementStartTime, tgeTime, or setTime
    uint256 agreementExecutionTime;                
    uint256 unlockingPeriod;
    uint256 unlockingCliffPeriod;
    uint256 unlockingCliffPercentage;
    UnlockingIntervalType unlockingIntervalType; - // blockly, secondly, daily, weekly, monthly
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

Restrictive Legends

[1] ria compliance legend.

RIA COMPLIANCE LEGEND. THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFT WITHOUT THE PRIOR CONSENT OF THE COMPANY.

[2] restricted securities legend.

RESTRICTED SECURITIES LEGEND. THIS INSTRUMENT, THE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144.

[3] unregistered securities legend.

UNREGISTERED SECURITIES LEGEND. THIS INSTRUMENT, THE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFT AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.

[4] contentious hardfork legend.

CONTENTIOUS HARDFORK LEGEND. IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.
