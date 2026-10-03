---
description: Install transfer-restriction hooks on scrip and LETs, use or permanently disable scrip compliance powers, and cap scrip holders
---

# Restrict scrip and LET transfers

Scrip is an ERC-20 (`CyberScrip`). You restrict it with transfer-restriction
hooks, and the company can hold compliance powers over it and later give
them up. Ledger Entry Tokens (LETs) have their own switches for delivery
and registration.

## Install transfer-restriction hooks on scrip

Hooks implement `ITransferRestrictionHook`. CyberScrip runs every installed
hook's `checkTransferRestriction` on each transfer and on each mint (any
move to a nonzero address), so a scripify to a recipient the hooks reject
fails. Burns skip the hooks. See [Hooks](../reference/hooks.md).

You set the hooks when you deploy the scrip (the `typeRestrictionHooks`
argument of `deployCyberScrip`), and a BorgAuth admin can replace them
later on the scrip itself:

```solidity
// at deploy time
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    /* ...remaining args... */
);

// later, as a BorgAuth admin; replaces the whole hook set
ICyberScrip(cyberScrip).setRestrictionHook(newHooks);
```

The repository's hook implementation is `WhitelistTransferHook` in
[`src/hooks/transfer/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/transfer).
It allows a transfer when both sender and recipient are whitelisted, and a
mint when the recipient is. Its source lists its admin functions.

## Open and close a LET contract's gates

A LET contract (`LedgerEntryToken`) restricts two events separately. The
IssuanceManager or a BorgAuth admin sets both on the LET contract:

* **Delivery** (the token moves between wallets): the contract-wide
  `setGlobalTransferable` and per-lot `setTokenTransferable` switches, plus
  each hook's `checkTransferRestriction`.
* **Registration** (the holder of record changes): the contract-wide
  `setGlobalLegalTransferable` and per-lot `setTokenLegalTransferable`
  switches, plus each hook's `checkLegalTransferRestriction`.

Install hooks with `setRestrictionHook(id, hook)` for one token and
`setGlobalRestrictionHook(hook)` for the whole contract. All four switches
start `false` on a new LET contract, so LETs issue freely but cannot move,
and the holder of record cannot change, until an admin opens them. The
gates are documented in [LedgerEntryToken](../reference/contracts/LedgerEntryToken.md).

## Use the scrip compliance powers

A CyberScrip is deployed with up to three compliance powers, chosen by the
last three booleans of `deployCyberScrip`:

```solidity
    /* ... */ true /*enableForceTransfer*/, true /*enableForceBurn*/, true /*enableFreeze*/
```

The scrip has no blocklist. Force transfer, force burn and freeze are the
only powers.

| Power          | Exercised via                                       |
|----------------|-----------------------------------------------------|
| Force transfer | `CyberScrip.forceTransfer(from, to, amount)`        |
| Force burn     | `IssuanceManager.forceScripBurn(certAddress, account, amount)` |
| Freeze         | `CyberScrip.setFrozen(account, isFrozen)`           |

An admin calls force transfer and freeze on the scrip directly, since those
functions are `onlyIssuanceManagerOrAdmin`. Force burn runs through the
IssuanceManager because it also withdraws the matching backing units from
the scrip pool. A frozen account cannot move scrip, scripify, or convert
scrip back into a LET.

## Disable a power permanently

Each power has a one-way disable on CyberScrip (`disableForceTransfer()`,
`disableForceBurn()`, `disableFreeze()`). A disabled power cannot be
re-enabled, and exercising it reverts `ComplianceFeatureDisabled`. The
disables are `onlyIssuanceManagerOrAdmin`, like the other controls.

## Cap the number of scrip holders

`CyberScrip.setMaxHolderCount(n)` caps the holder count (`0` means
unlimited), and a transfer that would exceed the cap reverts
`HolderLimitExceeded`. The cap is `onlyIssuanceManagerOrAdmin` and can be
changed at any time.

Function-level detail is in
[CyberScrip](../reference/contracts/CyberScrip.md) and
[Hooks](../reference/hooks.md).
