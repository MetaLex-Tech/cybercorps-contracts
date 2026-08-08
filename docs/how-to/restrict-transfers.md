# Restrict cyberSCRIP transfers

cyberSCRIP is an ERC-20. You can restrict it with transfer-restriction hooks,
and a cyberCORP can hold (and later renounce) compliance powers.

## Transfer-restriction hooks

Hooks implement `ITransferRestrictionHook`; CyberScrip runs every installed
hook on each transfer. See [Hooks](../reference/hooks.md).

Hooks are set initially when the scrip is deployed (`typeRestrictionHooks`
argument of `deployCyberScrip`) and can be changed afterward through the
IssuanceManager:

```solidity
// at deploy time
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    /* ...remaining args... */
);
```

On the `CyberCertPrinter` itself, the IssuanceManager can also set hooks for
cyberCERT transfers: `setRestrictionHook(certAddress, id, hook)` and
`setGlobalRestrictionHook(certAddress, hook)`.

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

| Power | Exercised via (on CyberScrip) |
|---|---|
| Force transfer | `forceTransfer(from, to, amount)` |
| Force burn | `forceBurn(account, amount)` |
| Freeze | `setFrozen(account, isFrozen)` |

These functions are `onlyIssuanceManager`, so they are driven through the
cyberCORP's IssuanceManager.

## Permanently disabling a power

Each power has a one-way disable on CyberScrip — `disableForceTransfer()`,
`disableForceBurn()`, `disableFreeze()`. Once disabled, a power cannot be
re-enabled; exercising it afterward reverts `ComplianceFeatureDisabled`. Like
the exercise functions, the disables are `onlyIssuanceManager`.

## Holder cap

`IssuanceManager.setScripMaxHolderCount(certAddress, n)` (admin-gated) caps
the scrip's holder count (`0` = unlimited); transfers that would exceed it
revert `HolderLimitExceeded`. The underlying setter,
`CyberScrip.setMaxHolderCount(n)`, is `onlyIssuanceManager` like the other
compliance functions.

## Related

* [CyberScrip](../reference/contracts/CyberScrip.md), [Hooks](../reference/hooks.md).
