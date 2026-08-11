# Hooks

The protocol uses two kinds of hook: **transfer-restriction hooks** consulted
on token transfers, and a **Uniswap v4 hook** used by LiquiLeX pools.

## Transfer-restriction hooks

### `ITransferRestrictionHook`

```solidity
interface ITransferRestrictionHook {
    function checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,   // token id for cyberCERTs; amount for cyberSCRIP
        bytes memory data
    ) external view returns (bool allowed, string memory reason);
}
```

Both `LedgerEntryToken` (the cert printer, formerly `CyberCertPrinter`) and
`CyberScrip` consult these hooks on transfer:

* `CyberScrip` holds an **array** of hooks (`setRestrictionHook`); every
  hook must allow the transfer or it reverts `RestrictedTransfer(reason)`.
* `LedgerEntryToken` holds per-id hooks (`setRestrictionHook(id, hook)`)
  and a `globalRestrictionHook` (`setGlobalRestrictionHook`).

### Implementations

In [`src/hooks/transfer/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/transfer):

| Hook | Purpose |
|---|---|
| `BaseTransferHook` | Common base for transfer-restriction hooks. |
| `WhitelistTransferHook` | Allows transfers only between whitelisted addresses. |
| `ToggleTransferHook` | Per-token transfer on/off switch, with a configurable default. |

> These three implement `ITransferRestrictionHook`. Consult each contract's
> source for its admin functions (whitelist management, toggle setters).

## Uniswap v4 hook

### `MetalexIssuerFeeHook`

In [`src/hooks/uniswap/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/uniswap).
A Uniswap v4 hook for **LiquiLeX** AMM pools that splits swap fees between
MetaLeX and the issuer, so a cyberSCRIP / stablecoin pool pays the issuer
onchain on every trade.

* Per-pool configuration via `setPoolConfig` (`onlyAdmin`): a
  `PoolFeeConfig` with the MetaLeX and issuer recipients, `metalexFeeBps` /
  `issuerFeeBps` (their sum capped at 10 000 bps), and an `enabled` flag.
* Registers `beforeSwap`/`afterSwap` permissions with return deltas and
  handles **all four swap flows**: exact-input swaps are charged in
  `beforeSwap`, exact-output swaps in `afterSwap`, in both directions
  (`zeroForOne` and `oneForZero`).

See the source for the hook-address requirements Uniswap v4 imposes.
