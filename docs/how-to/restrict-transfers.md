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

| Power          | Exercised via (on CyberScrip)     |
|----------------|-----------------------------------|
| Force transfer | `forceTransfer(from, to, amount)` |
| Force burn     | `forceBurn(account, amount)`      |
| Freeze         | `setFrozen(account, isFrozen)`    |

An admin calls the scrip directly — the compliance functions are
`onlyIssuanceManagerOrAdmin`. Force burn is the exception: it also withdraws
the matching backing units from the cert's vault, so it is managed by IssuanceManager.

## Permanently disabling a power

Each power has a one-way disable on CyberScrip — `disableForceTransfer()`,
`disableForceBurn()`, `disableFreeze()`. Once disabled, a power cannot be
re-enabled; exercising it afterward reverts `ComplianceFeatureDisabled`.
Like the other controls, the disables are `onlyIssuanceManagerOrAdmin`.

## Holder cap

`CyberScrip.setMaxHolderCount(n)` caps the holder count (`0` = unlimited);
transfers that would exceed it revert `HolderLimitExceeded`. Like the other
reversible controls it is `onlyIssuanceManagerOrAdmin`.

## Related

* [CyberScrip](../reference/contracts/CyberScrip.md), [Hooks](../reference/hooks.md).
