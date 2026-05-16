# LeXscroWLite

**LeXscroWLite** is the atomic deal-closing escrow used by `DealManager` and
`RoundManager`. It escrows ERC-20 and ERC-721 assets against a set of
`ICondition`s and releases atomically when all conditions evaluate true.

## Properties

* No admin keys.
* No partial release.
* Conditions are evaluated at the time of `close`, not at deposit.
* Cancellation paths exist for stale escrows that never reach conditions —
  see the source for `cancel`.

## Selected public interface

```solidity
function depositERC20(address token, uint256 amount) external;
function depositERC721(address token, uint256 tokenId) external;
function setConditions(ICondition[] calldata) external;
function close() external;
function cancel() external;
```
