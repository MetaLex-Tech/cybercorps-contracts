# CyberScrip

The ERC-20 fungible form of a cyberCORP security. One CyberScrip is deployed
per [LedgerEntryToken](LedgerEntryToken.md) printer, via
`IssuanceManager.deployCyberScrip`.

* **Source:** [`src/CyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberScrip.sol)
  / interface [`ICyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberScrip.sol)
* **Inherits:** `ERC20Upgradeable`, `BorgAuthACL`, `ICyberScrip`
* **Pattern:** beacon proxy (beacon owned by the IssuanceManager)
* **`DEPLOY_VERSION`:** `"5"` in the current source; scrip of companies that
  have not upgraded reports `"4"` or earlier.

Scripification and de-scripification are driven through the IssuanceManager,
so `mint` / `burnFrom` are `onlyIssuanceManager`. The compliance controls,
except force burn, are `onlyIssuanceManagerOrAdmin`, so a cyberCORP admin
(BorgAuth level 98 or above) calls them on the scrip directly.

## Mint / burn

```solidity
function mint(address to, uint256 amount) external onlyIssuanceManager;
function burnFrom(address account, uint256 amount) external onlyIssuanceManager;
```

## Compliance powers

CyberScrip supports **three** compliance powers. There is **no blocklist**.

| Power          | Function                          | Gate             | Enabled at deploy by  | Disable (one-way)        |
|----------------|-----------------------------------|------------------|-----------------------|--------------------------|
| Force transfer | `forceTransfer(from, to, amount)` | manager or admin | `enableForceTransfer` | `disableForceTransfer()` |
| Force burn     | `forceBurn(account, amount)`      | manager only     | `enableForceBurn`     | `disableForceBurn()`     |
| Freeze         | `setFrozen(account, isFrozen)`    | manager or admin | `enableFreeze`        | `disableFreeze()`        |

Each `disable*` function is `onlyIssuanceManagerOrAdmin` and irreversible —
once a power is disabled it cannot be re-enabled. A power can only be
exercised while its `can*` flag is true; otherwise the call reverts
`ComplianceFeatureDisabled`.

Force burn is manager-only because it must also withdraw the matching
backing units from the printer's scrip vault; an admin exercises it through
`IssuanceManager.forceScripBurn` (see [IssuanceManager](IssuanceManager.md)).
Force transfer and force burn bypass the transfer hooks and the freeze.

A frozen account cannot send or receive scrip. While freezing is enabled,
the IssuanceManager also refuses to let a frozen account scripify a lot or
convert scrip back into a certificate (`AccountFrozen`).

## Transfer restrictions

`setRestrictionHook(ITransferRestrictionHook[])`
(`onlyIssuanceManagerOrAdmin`) replaces the whole array of
[transfer hooks](../hooks.md). Every transfer **and mint** (any move to a
nonzero address) runs each hook's `checkTransferRestriction`; a `false`
result reverts `RestrictedTransfer(reason)`. Burns skip the hooks. Frozen
accounts (when `canFreeze`) revert `AccountFrozen`.

## Holder cap

`setMaxHolderCount(uint256)` (`onlyIssuanceManagerOrAdmin`) sets a maximum
holder count (`0` = unlimited, the default) and emits
`MaxHolderCountUpdated`. Transfers that would exceed it revert
`HolderLimitExceeded`.

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
