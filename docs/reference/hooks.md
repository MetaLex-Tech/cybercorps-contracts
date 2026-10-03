# Hooks

The protocol uses two kinds of hook: **transfer-restriction hooks**,
consulted on token transfers and register changes, and a **Uniswap v4
hook** for LiquiLeX pools.

## Transfer-restriction hooks

### `ITransferRestrictionHook`

```solidity
interface ITransferRestrictionHook {
    // Delivery: may the token move between these addresses?
    function checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,   // token id for LETs; amount for scrip
        bytes memory data
    ) external view returns (bool allowed, string memory reason);

    // Registration: may the holder of record change from `from` to `to`?
    function checkLegalTransferRestriction(
        address from,      // current holder of record (never address(0))
        address to,        // incoming holder of record
        uint256 tokenId,
        bytes memory data
    ) external view returns (bool allowed, string memory reason);
}
```

The two checks answer different questions. `checkTransferRestriction`
governs possession; `checkLegalTransferRestriction` governs the register
and is never called at original issuance. `BaseTransferHook` answers the
registration check with the delivery answer unless a hook overrides it, so
a registration is at least as restricted as a delivery. A hook used by a
v5 LET contract must implement both functions: a hook that implements only
`checkTransferRestriction` reverts when the LET contract asks it about a
registration.

`LedgerEntryToken`, `CyberScrip` and `CyberShares` consult these hooks:

* `CyberScrip` holds an **array** of hooks (`setRestrictionHook` replaces
  the whole list). Every hook must allow the transfer, or it reverts
  `RestrictedTransfer(reason)`. The hooks run on transfers **and mints**
  (any move to a nonzero address), so scripifying to a recipient needs
  that recipient to pass them. Burns skip them.
* `LedgerEntryToken` holds per-LET hooks (`setRestrictionHook(id, hook)`)
  and a `globalRestrictionHook` (`setGlobalRestrictionHook`). It calls
  `checkTransferRestriction` when a token moves between two nonzero
  addresses and `checkLegalTransferRestriction` when the holder of record
  changes after issuance, alongside its own stop-transfer flags (set with
  `setGlobalLegalTransferable` / `setTokenLegalTransferable`). A failing
  hook reverts `TransferRestricted(reason)`.
* `CyberShares` checks its global hook on `transfer` and `transferFrom`.

### Implementations

In [`src/hooks/transfer/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/transfer):

| Hook | Purpose |
|---|---|
| `BaseTransferHook` | Abstract base: an admin `setEnabled` switch (a disabled hook allows everything) and the default registration check. |
| `WhitelistTransferHook` | Allows a transfer when both sender and recipient are whitelisted, and a mint when the recipient is whitelisted. Admin functions `setWhitelisted` / `batchSetWhitelisted`. |

For per-LET switches, use the LET contract's own `setTokenTransferable`
(delivery) and `setTokenLegalTransferable` (registration); see
[LedgerEntryToken](contracts/LedgerEntryToken.md#delivery-and-registration-gates).

## Uniswap v4 hook

### `MetalexIssuerFeeHook`

In [`src/hooks/uniswap/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/uniswap).
A Uniswap v4 hook for **LiquiLeX** AMM pools that splits swap fees between
MetaLeX and the issuer, so a scrip/stablecoin pool pays the issuer onchain
on every trade.

* Per-pool configuration through `setPoolConfig` (`onlyAdmin`): a
  `PoolFeeConfig` with the MetaLeX and issuer recipients, `metalexFeeBps`
  / `issuerFeeBps` (their sum capped at 10 000 bps), and an `enabled`
  flag.
* Registers `beforeSwap` / `afterSwap` permissions with return deltas and
  handles **all four swap flows**: exact-input swaps are charged in
  `beforeSwap` and exact-output swaps in `afterSwap`, in both directions
  (`zeroForOne` and `oneForZero`).

Uniswap v4 also places requirements on the hook's address; the source
documents them.
