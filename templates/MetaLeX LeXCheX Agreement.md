# Data Overview

id: bytes32(uint256(100))

legalURI:
safeURI: IFPS://bafybeieoahzrvqk3vggrv6zyljlgkrqn2ls5wgpbgp4w4ylenr2r2ftugm

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| expiryDate      |       unix timestamp              |




## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
| investorName | |
|investorType | | 
|investorJurisdiction | |
|investorContact | |



## Certificate Extension

name: TokenWarrantExtension
```solidity
struct Accreditation {
    uint256 uuid;
    bytes32 agreementId;
    address registryAddress;
    string investorName;
    string investorType;
    string investorJurisdiction;
    string investorContact;
    uint256 issuanceDate;
    uint256 expiryDate;
    string voided;
    bytes signature;
}

```


```

