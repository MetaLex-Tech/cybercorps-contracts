---
description: Multi-investor fundraising rounds with escrowed officer signatures
---

# RoundManager

Runs a cyberCORP's multi-investor primary fundraising rounds. A round is
identified by a `bytes32 roundId`, and each Expression of Interest (EOI)
becomes an agreement identified by a `bytes32 agreementId`.

* **Source:** [`src/RoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/RoundManager.sol)
  / interface [`IRoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IRoundManager.sol)
* **Pattern:** UUPS proxy. Round state lives in the `RoundManagerStorage`
  library and escrow state in the shared `LexScrowStorage` library (see
  [LeXscroWLite](LeXscroWLite.md)).
* **`DEPLOY_VERSION`:** `"5"`; the RoundManager of a company that has not
  upgraded reports `"4"` or lower.

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

## How rounds work

* `createRound` takes a `Round` draft, built with the `RoundLib` helper
  (series, round type FCFS or FounderApproved, public or private, ticket
  sizing, raise cap, price per unit, valuation, start and end time, payment
  token, agreement template, conditions, `allowTimedOffers`,
  `restrictEndTimeReduction`), plus per-series `CyberCertData` (declared in
  `src/CyberCorpConstants.sol`). The v5 struct carries the extension's
  `seriesData` payload, so v4 and v5 `createRound` selectors differ. The
  `roundId` is derived from the round's economic terms plus the corp
  address, and a duplicate round reverts `RoundAlreadyExists`.
* The draft must carry an **escrowed officer signature**: `createRound`
  verifies `roundDraft.escrowedSignature` as the `authorityOfficer`'s
  EIP-712 signature over the round's terms (`InvalidEscrowedSignature`
  otherwise). The round reuses that signature to countersign each EOI
  agreement on the officer's behalf
  (`CyberAgreementRegistry.signContractWithEscrow`) and as the issuer
  signature and endorsement on each Ledger Entry Token (LET) it mints. It
  is checked under the RoundManager's own EIP-712 domain, independent of
  the registry's `SignatureData` type.
* Investors call `submitEOI` with a minimum and maximum amount inside the
  round's ticket bounds, and their payment is escrowed immediately. The
  investor's `signature` is the registry's `SignatureData` signature over
  the EOI agreement (the RoundManager is its finalizer); where the
  registry's type has a `signer` field, it names the investor. In an
  **FCFS** round the EOI is allocated automatically in the same
  transaction. In a **FounderApproved** round the issuer `allocate`s
  accepted EOIs or `reject`s them.
* If `allowTimedOffers` is true, each EOI carries its own expiry.
  Otherwise EOI expiries are ignored and the round's end time bounds every
  offer.
* `allocate` clamps the allocation to the escrowed amount and the
  remaining raise cap, enforces the effective minimum ticket, checks the
  agreement's conditions, finalizes the agreement in the registry, mints
  the LETs through the IssuanceManager, refunds rounding dust, and releases
  the escrow less the platform fee.
* `reject` refunds the investor and voids the agreement; `recallEOI` lets
  the investor reclaim an expired, unallocated EOI. Both take an optional
  `isVoidAgreement=false` for an agreement already voided directly in the
  registry.
* `closeRoundNow` and `setRoundEndTime` close or extend a round. A round
  created with `restrictEndTimeReduction` blocks any end-time reduction
  (`EndTimeReductionRestricted`).
* `computeFee` / `getPlatformPayable` cover the platform fee on a round.
  The fee ratio and payable are set on the RoundManagerFactory, which can
  give one RoundManager its own rate through a per-instance `FeeOverride`.
* `initialize` wires a default LeXcheX credential configuration
  (credential contract, condition and minter addresses), and `setLexChex`
  / `getLexChex` manage the credential contract that rounds use. An EOI
  carries `lexchexDetails` so that, at allocation, an investor without a
  valid LeXcheX is credentialed automatically through the LeXcheXMinter
  when the invested amount qualifies (≥ $200k for a natural person, ≥ $1M
  for an entity, paid in a factory-whitelisted token).

## Events

`RoundCreated`, `RoundEndTimeUpdated`, `RoundClosed`, `EOISubmitted`,
`AllocationMade`, `EOIRejected` (declared in `IRoundManager`);
`EOIRecalled` and `LexChexUpdated(lexChex, oldLexChex)` (emitted by
`setLexChex`) in the contract.

`RoundSnapshotSet`, `RoundingPolicySet` and `PMVCSubseriesLabelSet` are
declared in the ABI but never emitted: RoundManager has no snapshot or
rounding-policy setter.

## Upgrades

`_authorizeUpgrade` is `onlyOwner` and accepts only the
RoundManagerFactory's current reference implementation
(`NotRefImplementation` otherwise).
