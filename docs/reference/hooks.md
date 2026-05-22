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

Both `CyberCertPrinter` and `CyberScrip` consult these hooks on transfer:

* `CyberScrip` holds an **array** of hooks (`setRestrictionHook`); every
  hook must allow the transfer or it reverts `RestrictedTransfer(reason)`.
* `CyberCertPrinter` holds per-id hooks (`setRestrictionHook(id, hook)`) and
  a `globalRestrictionHook` (`setGlobalRestrictionHook`).

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
onchain on every trade. See the source for its exact configuration and the
hook-address requirements Uniswap v4 imposes.
