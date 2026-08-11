# CyberScrip

The ERC-20 fungible form of a cyberCORP security. One CyberScrip is deployed
per [LedgerEntryToken](LedgerEntryToken.md) printer, via
`IssuanceManager.deployCyberScrip`.

* **Source:** [`src/CyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberScrip.sol)
* **Inherits:** `ERC20Upgradeable`, `BorgAuthACL`
* **Pattern:** beacon proxy
* **`DEPLOY_VERSION`:** `"4"`

Every state-changing function carries `onlyIssuanceManager` — the caller must
be the IssuanceManager. Scripification and de-scripification are driven
through the IssuanceManager.

## Mint / burn

```solidity
function mint(address to, uint256 amount) external onlyIssuanceManager;
function burnFrom(address account, uint256 amount) external onlyIssuanceManager;
```

## Compliance powers

CyberScrip supports **three** compliance powers. There is **no blocklist**.

| Power | Function | Enabled at deploy by | Disable (one-way) |
|---|---|---|---|
| Force transfer | `forceTransfer(from, to, amount)` | `enableForceTransfer` | `disableForceTransfer()` |
| Force burn | `forceBurn(account, amount)` | `enableForceBurn` | `disableForceBurn()` |
| Freeze | `setFrozen(account, isFrozen)` | `enableFreeze` | `disableFreeze()` |

Each `disable*` function is irreversible — once a power is disabled it cannot
be re-enabled. A power can only be exercised while its `can*` flag is true;
otherwise the call reverts `ComplianceFeatureDisabled`.

Since every one of these functions is `onlyIssuanceManager`, officers and
admins exercise them through the IssuanceManager's wrappers
(`forceScripTransfer`, `forceScripBurn`, `setScripFrozen`,
`setScripRestrictionHooks`, `disableScripForceTransfer` /
`disableScripForceBurn` / `disableScripFreeze`) — see
[IssuanceManager](IssuanceManager.md).

## Transfer restrictions

`setRestrictionHook(ITransferRestrictionHook[])` installs an array of
[transfer hooks](../hooks.md). Every transfer runs each hook's
`checkTransferRestriction`; a `false` result reverts `RestrictedTransfer`.
Frozen accounts (when `canFreeze`) revert `AccountFrozen`.

## Holder cap

`setMaxHolderCount(uint256)` sets a maximum holder count (`0` = unlimited).
Transfers that would exceed it revert `HolderLimitExceeded`.

{% hint style="warning" %}
The setter is `onlyIssuanceManager`, and the IssuanceManager currently
exposes no wrapper that calls it — so on production deployments the cap
remains at its default `0` (unlimited).
{% endhint %}

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
