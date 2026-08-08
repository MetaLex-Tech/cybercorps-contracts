# RoundManager

Runs multi-investor primary fundraising rounds for a cyberCORP. Rounds are
identified by a `bytes32 roundId`; each Expression of Interest becomes an
agreement identified by a `bytes32 agreementId`.

* **Source:** [`src/RoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/RoundManager.sol)
  / interface [`IRoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IRoundManager.sol)
* **Pattern:** UUPS proxy; round state in the `RoundManagerStorage` library,
  escrow state in the shared `LexScrowStorage` library (see
  [LeXscroWLite](LeXscroWLite.md)).
* **`DEPLOY_VERSION`:** `"4"`

## Functions

```solidity
function createRound(Round roundDraft, CyberCertData[] certData)
    external returns (bytes32 roundId);                          // onlyOwner

function submitEOI(bytes32 roundId, EOI eoi, string[] globalValues,
    string[] partyValues, bytes signature, uint256 salt,
    address[] conditions, bytes32 secretHash)
    external returns (bytes32 agreementId, uint256 tokenId);

function allocate(bytes32 agreementId, uint256 allocatedAmount)
    external returns (uint256 tokenId);                          // onlyOwnerOrSelf
function reject(bytes32 agreementId) external;                   // onlyOwner
function reject(bytes32 agreementId, bool isVoidAgreement) external; // onlyOwner
function recallEOI(bytes32 agreementId) external;
function recallEOI(bytes32 agreementId, bool isVoidAgreement) external;

function setRoundEndTime(bytes32 roundId, uint256 newEndTime) external;      // onlyOwner
function closeRoundNow(bytes32 roundId) external;                            // onlyOwner
function setRoundPricePerShare(bytes32 roundId, uint256 price, uint8 priceDecimals) external; // onlyOwner
function setPrimarySecurity(bytes32 roundId, SecurityClass cls, SecuritySeries series) external; // onlyOwner
```

## Views

`getRound(roundId)`, `roundExists`, `getRoundPriceInfo`,
`getPrimarySecurity`, `computeFee(size)`, `getPlatformPayable`,
`getLexChex` / `setLexChex`, `issuanceManager`,
`getEscrowDetails(agreementId)`, `conditionCheck(agreementId)`,
`DEPLOY_VERSION`.

## How it works

* `createRound` takes a `Round` draft (built with the `RoundLib` helper —
  series, round type FCFS/FounderApproved, public/private, ticket sizing,
  raise cap, price per unit, valuation, start/end time, payment token,
  agreement template, conditions, `allowTimedOffers`,
  `restrictEndTimeReduction`) plus per-series `CyberCertData`. The `roundId`
  is derived from the round's economic terms plus the corp address, and
  duplicate rounds revert `RoundAlreadyExists`.
* The draft must carry an **escrowed officer signature**: `createRound`
  verifies `roundDraft.escrowedSignature` as the `authorityOfficer`'s
  EIP-712 signature over the round's terms (`InvalidEscrowedSignature`
  otherwise). The signature is reused throughout the round — to countersign
  each EOI agreement on the officer's behalf
  (`CyberAgreementRegistry.signContractWithEscrow`), and as the issuer
  signature and endorsement on each minted cyberCERT.
* Investors `submitEOI` with a min/max amount inside the round's ticket
  bounds; payment is escrowed immediately. In an **FCFS** round the EOI is
  auto-allocated in the same transaction; in a **FounderApproved** round the
  issuer `allocate`s accepted EOIs (or `reject`s them).
* If `allowTimedOffers` is true each EOI carries its own expiry; otherwise
  EOI expiries are ignored and the round's end time bounds every offer.
* `allocate` clamps the allocation to the escrowed amount and the remaining
  raise cap, enforces the effective minimum ticket, checks the agreement's
  conditions, finalizes the agreement in the registry, mints the
  cyberCERT(s) through the IssuanceManager, refunds rounding dust, and
  releases the escrow (less the platform fee).
* `reject` refunds the investor and voids the agreement; `recallEOI` lets
  the investor reclaim an expired, unallocated EOI. Both take an optional
  `isVoidAgreement=false` for the edge case where the agreement was already
  voided directly in the registry.
* `closeRoundNow` / `setRoundEndTime` close or extend a round —
  unless the round was created with `restrictEndTimeReduction`, which
  blocks any end-time reduction (`EndTimeReductionRestricted`).
* `computeFee` / `getPlatformPayable` cover the platform fee on a round
  (fee ratio and payable set on the RoundManagerFactory).
* `initialize` wires a default LeXcheX credential configuration (credential
  contract, condition, and minter addresses); `setLexChex` / `getLexChex`
  manage the credential contract used by rounds. An EOI carries
  `lexchexDetails` so that, at allocation, an investor without a valid
  LeXcheX is auto-credentialed through the LeXcheXMinter when the invested
  amount qualifies (≥ $200k for a natural person, ≥ $1M for an entity, paid
  in a factory-whitelisted token).

## Events

`RoundCreated`, `RoundEndTimeUpdated`, `RoundClosed`, `EOISubmitted`,
`AllocationMade`, `EOIRejected`, `EOIRecalled`.

> `RoundSnapshotSet`, `RoundingPolicySet`, and `PMVCSubseriesLabelSet` are
> declared in the ABI but not emitted by any function in the current source
> (the cap-table snapshot / rounding-policy setters they belonged to are not
> present).

## Upgrades

`_authorizeUpgrade` is `onlyOwner` and only accepts the
RoundManagerFactory's current reference implementation
(`NotRefImplementation` otherwise).
