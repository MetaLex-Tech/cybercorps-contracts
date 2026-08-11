---
description: Install transfer-restriction hooks and compliance powers on cyberSCRIP
---

# Restrict cyberSCRIP transfers

cyberSCRIP is an ERC-20. You can restrict it with transfer-restriction hooks,
and a cyberCORP can hold (and later renounce) compliance powers.

## Transfer-restriction hooks

Hooks implement `ITransferRestrictionHook`; CyberScrip runs every installed
hook on each transfer. See [Hooks](../reference/hooks.md).

Hooks are set initially when the scrip is deployed (`typeRestrictionHooks`
argument of `deployCyberScrip`) and can be replaced afterward through the
IssuanceManager:

```solidity
// at deploy time
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    /* ...remaining args... */
);

// later (BorgAuth admin) — replaces the whole hook set
IIssuanceManager(issuanceManager).setScripRestrictionHooks(certAddress, newHooks);
```

The cert printer (`LedgerEntryToken`) has its own hooks for cyberCERT
transfers, set on the printer itself by the IssuanceManager or a BorgAuth
admin: `setRestrictionHook(id, hook)` (per token) and
`setGlobalRestrictionHook(hook)`.

Implementations in
[`src/hooks/transfer/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/transfer):
`WhitelistTransferHook` (allow only whitelisted addresses) and
`ToggleTransferHook` (per-token on/off). Consult each contract's source for
its admin functions.

## Compliance powers

A CyberScrip is deployed with three optional powers — the last three
booleans of `deployCyberScrip`:

```solidity
    /* ... */ true /*enableForceTransfer*/, true /*enableForceBurn*/, true /*enableFreeze*/
```

There is **no blocklist** — only force transfer, force burn, and freeze.

The underlying CyberScrip functions are `onlyIssuanceManager`; you exercise
them through the IssuanceManager's wrappers (BorgAuth admin):

| Power | Exercised via (on IssuanceManager) |
|---|---|
| Force transfer | `forceScripTransfer(certAddress, from, to, amount)` |
| Force burn | `forceScripBurn(certAddress, account, amount)` |
| Freeze | `setScripFrozen(certAddress, account, isFrozen)` |

## Permanently disabling a power

Each power has a one-way disable, driven through the IssuanceManager
(`onlyOwner`): `disableScripForceTransfer(certAddress)`,
`disableScripForceBurn(certAddress)`, `disableScripFreeze(certAddress)`.
Once disabled, a power cannot be re-enabled; exercising it afterward reverts
`ComplianceFeatureDisabled`.

## Holder cap

`CyberScrip` enforces `maxHolderCount` (`0` = unlimited); transfers that
would exceed it revert `HolderLimitExceeded`.

{% hint style="warning" %}
The setter (`setMaxHolderCount`) is `onlyIssuanceManager` and the
IssuanceManager currently exposes **no wrapper** for it — so on production
deployments the cap stays at its default `0` (unlimited) and cannot be
relied on for compliance until the wiring ships.
{% endhint %}

For holder-count limits on
secondary trades, see `HolderCapCondition` in
[`src/libs/conditions/secondary/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/libs/conditions/secondary).

## Related

* [CyberScrip](../reference/contracts/CyberScrip.md), [Hooks](../reference/hooks.md).
