# Data Overview

id: bytes32(uint256(400))

legalURI:
safeURI: 

## Global Fields

| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| expiryDate      |       unix timestamp              |



## Party Fields

| **partyFieldName** | **description**                         |
|:-------------------|:----------------------------------------|
|investorName | |
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

