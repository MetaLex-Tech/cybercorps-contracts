# Data Overview

id: bytes32(uint256(30))

legalURI:
safeURI: IPFS://bafybeidq7z4sgbh5tqxfehs5rz3r3il76ony3t7psetwge5ctld6lubi5e

combined doc: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiazn4jdtlu4yz7lqbfhzaxsfhsfuwaq55m4x5mhjdeddbwwrhfufe](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeih7l2kxncjuwrfgv5gnmpcik43dnn4pxpe4it4u7ti2hgfgrlot2a)

SAFE alone: [https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeiafzkynirjta4pd3g365qv6ttlz3pkeqcquhbald7nqqfmm5vpfua](https://beige-just-flyingfish-108.mypinata.cloud/ipfs/bafybeidq7z4sgbh5tqxfehs5rz3r3il76ony3t7psetwge5ctld6lubi5e)

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount       |       e.g. "1000.00"              |
| postMoneyValuationCap       |          |
| expirationTime       |         |
| governingJurisdiction       |          |
| disputeResolution       |         |
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

name: SAFEExtension
```solidity
struct SAFEData {
    string customProvisions; // an arbitrary string intended to insert any custom provision the parties agree upon
}

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

Restrictive Legends:

[1] investment advisor certificate custody legend

THE CERTIFICATE TOKEN MAY NOT BE USED TO EFFECT A TRANSFER OR TO OTHERWISE FACILITATE A CHANGE IN BENEFICIAL OWNERSHIP OF THIS SAFE WITHOUT THE PRIOR CONSENT OF THE COMPANY. 

[2] restricted security legend

THIS SAFE, THE CERTIFICATE TOKEN, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO ARE “RESTRICTED SECURITIES” AS DEFINED IN SEC RULE 144. 

[3] unregistered security legend

THIS SAFE, THE CERTIFICATE TOKEN AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE “SECURITIES ACT”), OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS SAFE AND UNDER THE SECURITIES ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT OR AN EXEMPTION THEREFROM.

[4] hardfork legend

IN THE EVENT THAT THE BLOCKCHAIN SYSTEM ON WHICH THE CERTIFICATE TOKEN WAS ORIGINALLY ISSUED UNDERGOES A PERSISTENT “CONTENTIOUS HARDFORK” (AS COMMONLY UNDERSTOOD IN THE BLOCKCHAIN INDUSTRY, RESULTING IN TWO INDEPENDENT BLOCKCHAIN SYSTEMS THAT ARE BOTH REASONABLY EXPECTED TO HAVE INDEPENDENT PERSISTENT COMMERCIAL VALUE), NO COPY OF THE CERTIFICATE TOKEN MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED UNTIL THE COMPANY HAS DETERMINED, IN ITS SOLE AND ABSOLUTE DISCRETION, WHICH BLOCKCHAIN SYSTEM (AND WHICH CERTIFICATE TOKENS) TO TREAT AS CANONICAL, AND THEN ONLY THE CERTIFICATE TOKEN THUS DETERMINED BY THE COMPANY TO BE CANONICAL MAY BE OFFERED, SOLD, OR OTHERWISE TRANSFERRED, PLEDGED, OR HYPOTHECATED (TO THE EXTENT OTHERWISE PERMITTED). IN THE EVENT THAT THE BLOCKCHAIN SYSTEM DETERMINED BY THE COMPANY TO BE CANONICAL FOLLOWING A CONTENTIOUS HARDFORK ITSELF SUBSEQUENTLY UNDERGOES ANOTHER CONTENTIOUS HARDFORK, THIS RESTRICTIVE LEGEND SHALL LIKEWISE APPLY TO SUCH OTHER CONTENTIOUS HARDFORK, MUTATIS MUTANDIS.

