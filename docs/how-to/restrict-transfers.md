---
description: Install transfer-restriction hooks and compliance powers on cyberSCRIP
---

# Restrict cyberSCRIP transfers

cyberSCRIP is an ERC-20. You can restrict it with transfer-restriction hooks,
and a cyberCORP can hold (and later renounce) compliance powers.

## Transfer-restriction hooks

Hooks implement `ITransferRestrictionHook`; CyberScrip runs every installed
hook's `checkTransferRestriction` on each transfer and on each mint (any move
to a nonzero address), so a scripify to a recipient the hooks reject fails.
Burns skip the hooks. See [Hooks](../reference/hooks.md).

Hooks are set initially when the scrip is deployed (`typeRestrictionHooks`
argument of `deployCyberScrip`) and can be replaced afterward by a BorgAuth
admin, directly on the scrip:

```solidity
// at deploy time
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    /* ...remaining args... */
);

// later (BorgAuth admin) — replaces the whole hook set
ICyberScrip(cyberScrip).setRestrictionHook(newHooks);
```

Implementations in
[`src/hooks/transfer/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/transfer):
`WhitelistTransferHook` allows a transfer when both sender and recipient
are whitelisted, and a mint when the recipient is. Consult its source for
its admin functions. The former `ToggleTransferHook` has been removed.

## cyberCERT restrictions

The cert printer (`LedgerEntryToken`) restricts two events separately, set
on the printer itself by the IssuanceManager or a BorgAuth admin:

* **Delivery** (the token moves between wallets): the printer-wide
  `setGlobalTransferable` and per-lot `setTokenTransferable` switches, plus
  each hook's `checkTransferRestriction`.
* **Registration** (the holder of record changes): the printer-wide
  `setGlobalLegalTransferable` and per-lot `setTokenLegalTransferable`
  switches, plus each hook's `checkLegalTransferRestriction`.

Hooks are installed with `setRestrictionHook(id, hook)` (per token) and
`setGlobalRestrictionHook(hook)`. All four switches start `false` on a new
printer, so certificates issue freely but cannot move, and the register
cannot change, until an admin opens them. See
[LedgerEntryToken](../reference/contracts/LedgerEntryToken.md#delivery-and-registration-gates).

## Compliance powers

A CyberScrip is deployed with three optional powers — the last three
booleans of `deployCyberScrip`:

```solidity
    /* ... */ true /*enableForceTransfer*/, true /*enableForceBurn*/, true /*enableFreeze*/
```

There is **no blocklist** — only force transfer, force burn, and freeze.

| Power          | Exercised via                                       |
|----------------|-----------------------------------------------------|
| Force transfer | `CyberScrip.forceTransfer(from, to, amount)`        |
| Force burn     | `IssuanceManager.forceScripBurn(certAddress, account, amount)` |
| Freeze         | `CyberScrip.setFrozen(account, isFrozen)`           |

An admin calls force transfer and freeze on the scrip directly, since
those functions are `onlyIssuanceManagerOrAdmin`. Force burn is the
exception: it also withdraws the matching backing units from the cert's
vault, so the admin calls it on the IssuanceManager. A frozen account can neither move
scrip nor scripify or convert scrip back into a certificate.

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
