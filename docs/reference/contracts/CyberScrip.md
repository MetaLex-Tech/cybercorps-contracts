# CyberScrip

A fungible ERC-20 token that tracks the units of one LET contract's Ledger
Entry Tokens (LETs) in a fixed ratio (`setScripRatio` on the
IssuanceManager). Holders convert LET units into scrip and back through
the IssuanceManager. The IssuanceManager deploys the scrip with
`deployCyberScrip`, at most one per
[LedgerEntryToken](LedgerEntryToken.md) contract. Scrip's rights come from
the company's governing documents and the scrip's terms; under
MetaLeX-form bylaws scrip is not stock and confers no stockholder rights
on its own.

* **Source:** [`src/CyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberScrip.sol)
  / interface [`ICyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberScrip.sol)
* **Inherits:** `ERC20Upgradeable`, `BorgAuthACL`, `ICyberScrip`
* **Pattern:** beacon proxy; the IssuanceManager owns the beacon
* **`DEPLOY_VERSION`:** `"5"`; the scrip of a company that has not
  upgraded reports `"4"` or lower

The IssuanceManager drives scripification and de-scripification, so `mint`
and `burnFrom` are `onlyIssuanceManager`. The compliance controls other
than force burn are `onlyIssuanceManagerOrAdmin`, so a cyberCORP admin
(BorgAuth level 98 or above) calls them on the scrip directly.

## Mint and burn

```solidity
function mint(address to, uint256 amount) external onlyIssuanceManager;
function burnFrom(address account, uint256 amount) external onlyIssuanceManager;
```

## Compliance powers

CyberScrip has **three** compliance powers and **no blocklist**.

| Power          | Function                          | Gate             | Enabled at deploy by  | Disable (one-way)        |
|----------------|-----------------------------------|------------------|-----------------------|--------------------------|
| Force transfer | `forceTransfer(from, to, amount)` | manager or admin | `enableForceTransfer` | `disableForceTransfer()` |
| Force burn     | `forceBurn(account, amount)`      | manager only     | `enableForceBurn`     | `disableForceBurn()`     |
| Freeze         | `setFrozen(account, isFrozen)`    | manager or admin | `enableFreeze`        | `disableFreeze()`        |

Each `disable*` function is `onlyIssuanceManagerOrAdmin` and irreversible:
a disabled power cannot be re-enabled. A power works only while its `can*`
flag is true; otherwise the call reverts `ComplianceFeatureDisabled`.

Force burn is manager-only because it must also withdraw the matching
backing units from the LET contract's scrip vault. An admin exercises it
through `IssuanceManager.forceScripBurn` (see
[IssuanceManager](IssuanceManager.md)). Force transfer and force burn
bypass the transfer hooks and the freeze.

A frozen account cannot send or receive scrip. While freezing is enabled,
the IssuanceManager also refuses to let a frozen account scripify a LET or
convert scrip back into a LET (`AccountFrozen`).

## Transfer restrictions

`setRestrictionHook(ITransferRestrictionHook[])`
(`onlyIssuanceManagerOrAdmin`) replaces the whole array of
[transfer hooks](../hooks.md). Every transfer **and mint** (any move to a
nonzero address) runs each hook's `checkTransferRestriction`, and a
`false` result reverts `RestrictedTransfer(reason)`. Burns skip the hooks.
Frozen accounts (when `canFreeze`) revert `AccountFrozen`.

## Holder cap

`setMaxHolderCount(uint256)` (`onlyIssuanceManagerOrAdmin`) sets a maximum
holder count (`0` = unlimited, the default) and emits
`MaxHolderCountUpdated`. A transfer that would exceed it reverts
`HolderLimitExceeded`.

On a v4 company the holder cap cannot be set: the v4 scrip's setter is
`onlyIssuanceManager`, and the v4 IssuanceManager has no function that
calls it.

## Views

`certPrinter`, `issuanceManager`, `transferRestrictionHooks(i)`,
`transferRestrictionHooksLength`, `canForceTransfer`, `canForceBurn`,
`canFreeze`, `frozen(account)`, `holderCount` / `currentHolderCount`,
`maxHolderCount`, `remainingSlots`, `canTransfer(from, to, amount)`,
`willCreateNewHolder(to, amount)`.

## Events

`ForceTransfer`, `ForceBurn`, `FreezeStatusUpdated`,
`ComplianceFeatureDisabledEvent`, `MaxHolderCountUpdated`.

## Errors

`RestrictedTransfer`, `NotIssuanceManager`, `ComplianceFeatureDisabled`,
`AccountFrozen`, `HolderLimitExceeded`.
