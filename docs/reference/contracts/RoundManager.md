# RoundManager

Runs multi-investor primary fundraising rounds for a cyberCORP. Rounds are
identified by a `bytes32 roundId`; each Expression of Interest becomes an
agreement identified by a `bytes32 agreementId`.

* **Source:** [`src/RoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/RoundManager.sol)
  / interface [`IRoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IRoundManager.sol)
* **Pattern:** UUPS proxy

## Functions

```solidity
function createRound(Round roundDraft, CyberCertData[] certData)
    external returns (bytes32 roundId);

function submitEOI(bytes32 roundId, EOI eoi, string[] globalValues,
    string[] partyValues, bytes signature, uint256 salt,
    address[] conditions, bytes32 secretHash)
    external returns (bytes32 agreementId, uint256 tokenId);

function allocate(bytes32 agreementId, uint256 allocatedAmount)
    external returns (uint256 tokenId);
function reject(bytes32 agreementId) external;
function reject(bytes32 agreementId, bool isVoidAgreement) external;
function recallEOI(bytes32 agreementId) external;
function recallEOI(bytes32 agreementId, bool isVoidAgreement) external;

function setRoundEndTime(bytes32 roundId, uint256 newEndTime) external;
function closeRoundNow(bytes32 roundId) external;
function setRoundPricePerShare(bytes32 roundId, uint256 price, uint8 priceDecimals) external;
function setPrimarySecurity(bytes32 roundId, SecurityClass cls, SecuritySeries series) external;
```

## Views

`roundExists`, `getRoundPriceInfo`, `getPrimarySecurity`, `computeFee(size)`,
`getPlatformPayable`, `getLexChex` / `setLexChex`, `issuanceManager`,
`DEPLOY_VERSION`.

## How it works

* `createRound` takes a `Round` draft (built with the `RoundLib` helper —
  ticket sizing, raise cap, price, valuation, start/end time, round type,
  public/private, agreement template, conditions) plus per-class
  `CyberCertData`.
* Investors `submitEOI`; the issuer `allocate`s accepted EOIs (or `reject`s
  them); investors may `recallEOI`.
* `closeRoundNow` closes a round; allocations mint the corresponding
  cyberCERTs through the IssuanceManager.
* `computeFee` / `getPlatformPayable` cover the platform fee on a round.

## Events

`RoundCreated`, `RoundSnapshotSet`, `RoundingPolicySet`,
`PMVCSubseriesLabelSet`, `RoundEndTimeUpdated`, `RoundClosed`,
`EOISubmitted`, `AllocationMade`, `EOIRejected`.
