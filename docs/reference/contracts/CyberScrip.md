# CyberScrip

The ERC-20 fungible form of a cyberCORP security. One CyberScrip is deployed
per CyberCertPrinter, via `IssuanceManager.deployCyberScrip`.

* **Source:** [`src/CyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberScrip.sol)
* **Inherits:** `ERC20Upgradeable`, `BorgAuthACL`
* **Pattern:** beacon proxy
* **`DEPLOY_VERSION`:** `"4"`

Scripification and de-scripification are driven through the IssuanceManager,
so `mint` / `burnFrom` are `onlyIssuanceManager`. The compliance controls are
`onlyIssuanceManagerOrAdmin`, so a cyberCORP admin calls them on the scrip
directly.

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

Each `disable*` function is irreversible — once a power is disabled it cannot
be re-enabled. A power can only be exercised while its `can*` flag is true;
otherwise the call reverts `ComplianceFeatureDisabled`.

## Transfer restrictions

`setRestrictionHook(ITransferRestrictionHook[])` installs an array of
[transfer hooks](../hooks.md). Every transfer runs each hook's
`checkTransferRestriction`; a `false` result reverts `RestrictedTransfer`.
Frozen accounts (when `canFreeze`) revert `AccountFrozen`.

## Holder cap

`setMaxHolderCount(uint256)` sets a maximum holder count (`0` = unlimited).
Transfers that would exceed it revert `HolderLimitExceeded`.

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
