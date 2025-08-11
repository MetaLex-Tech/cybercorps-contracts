# Data Overview

id: bytes32(uint256(TODO))

combined doc: TODO

SAFT alone: TODO

Github: TODO


## Global Fields

| **globalFieldName**   | **description**                                                                                         |
|:----------------------|:--------------------------------------------------------------------------------------------------------|
| metavestType          | "Vesting", (WIP)"TokenOption", (WIP)"RestrictedTokenAward"                                              |
| grantee               | Address of the signer                                                                                   |
| recipient             | Address to receive unlocked tokens                                                                      |
| tokenContract         | Address of the token                                                                                    |
| tokenStreamTotal      | Total amount to tokens subject to linear vesting (includes cliff credits but not each 'milestoneAward') |
| vestingCliffCredit    | Amount vested at vestingStartTime                                                                       |
| unlockingCliffCredit  | Amount unlocked at unlockStartTime                                                                      |
| vestingRate           | Amount vested per seconds                                                                               |
| vestingStartTime      | Epoch time in seconds                                                                                   |
| unlockRate            | Amount unlocked per seconds                                                                             |
| unlockStartTime       | Epoch time in seconds                                                                                   |


## Party Fields

| **partyFieldName**   | **description**                        |
|:---------------------|:---------------------------------------|
| name                 | Name of the individual or organization |
| evmAddress           |                                        |
| contactDetails       |                                        |
| investorType         |                                        |


## MetaVesT Deal

```solidity
struct DealData {
    bytes32 agreementId;
    metavestType _metavestType;
    address grantee;
    address recipient;
    BaseAllocation.Allocation allocation;
    BaseAllocation.Milestone[] milestones;
}

struct Allocation {
    uint256 tokenStreamTotal; // total number of tokens subject to linear vesting/restriction removal (includes cliff credits but not each 'milestoneAward')
    uint128 vestingCliffCredit; // lump sum of tokens which become vested at 'startTime' and will be added to '_linearVested'
    uint128 unlockingCliffCredit; // lump sum of tokens which become unlocked at 'startTime' and will be added to '_linearUnlocked'
    uint160 vestingRate; // tokens per second that become vested; if RESTRICTED this amount corresponds to 'lapse rate' for tokens that become non-repurchasable
    uint48 vestingStartTime; // if RESTRICTED this amount corresponds to 'lapse start time'
    uint160 unlockRate; // tokens per second that become unlocked;
    uint48 unlockStartTime; // start of the linear unlock
    address tokenContract; // contract address of the ERC20 token included in the MetaVesT
}

struct Milestone {
    uint256 milestoneAward; // per-milestone indexed lump sums of tokens vested upon corresponding milestone completion
    bool unlockOnCompletion; // whether the 'milestoneAward' is to be unlocked upon completion
    bool complete; // whether the Milestone is satisfied and the 'milestoneAward' is to be released
    address[] conditionContracts; // array of contract addresses corresponding to condition(s) that must satisfied for this Milestone to be 'complete'
}
```
