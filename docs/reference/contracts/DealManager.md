# DealManager

**DealManager** is the deal-lifecycle and escrow contract used by cyberTRADE
and by `RoundManager` when closing rounds.

* **Source:** [`src/DealManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/DealManager.sol)
* **Proxy pattern:** UUPS (v3)

## Responsibilities

* Propose deals (`proposeDeal`).
* Manage counterparty signatures (EIP-712).
* Escrow assets (ERC-20 / ERC-721) via `LeXscroWLite`.
* Evaluate `ICondition` sets and release atomically on satisfaction.
* Endorse the affected cyberCERT(s) on close.

## Selected public interface

```solidity
function proposeDeal(DealParams calldata) external returns (uint256 dealId);
function signDeal(uint256 dealId, bytes calldata signature) external;
function approveDeal(uint256 dealId) external;         // OFFICER_AUTHORITY (issuer side)
function deposit(uint256 dealId) external;
function close(uint256 dealId) external;
function cancel(uint256 dealId) external;
```

## Settlement modes

* `EDIT_CERT` — mutate the seller's existing cert's holder / units fields
  in place under issuer approval.
* `BURN_AND_MINT` — burn the seller's cert and mint a fresh one to the buyer
  with new metadata.
* `SCRIP` — settle in cyberSCRIP; the seller may scripify as part of close,
  the buyer may de-scripify later or never.

## See also

* [`LeXscroWLite`](LeXscroWLite.md), [`RoundManager`](RoundManager.md)
* [Conditions](../conditions.md)
