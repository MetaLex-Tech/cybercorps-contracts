---
description: Pair a company's scrip against a stablecoin in a Uniswap v4 pool with MetalexIssuerFeeHook, under a whitelisted or open compliance model
---

# Deploy a LiquiLeX pool

**LiquiLeX** provides AMM liquidity for a company's scrip in Uniswap v4
pools, with the **`MetalexIssuerFeeHook`** routing swap fees to MetaLeX and
the issuer.

## Choose a compliance model

You need a cyberCORP with a deployed `CyberScrip` for the class you want to
make liquid (see [Scripify and settle a secondary
trade](scripify-and-settle.md)), and one of two compliance models:

* **Whitelisted pool.** A `WhitelistTransferHook` on the scrip, with the
  pool's custody addresses whitelisted. Only whitelisted addresses can send
  or receive the scrip, so credential checks happen when an address is
  added to the whitelist.
* **Open pool.** No transfer hook. Compliance is enforced when scrip
  converts back into a Ledger Entry Token (LET), optionally with a
  zkPassport check at the swap.

## Deploy the hook and the pool

1. Deploy the `MetalexIssuerFeeHook`
   ([`src/hooks/uniswap/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/uniswap))
   and call `initialize(auth, poolManager)`. The hook declares
   `beforeSwap`/`afterSwap` permissions (with return deltas), and Uniswap v4
   requires the hook address to encode those flags, so deploy it at a mined
   address with the standard `HookMiner` salt-mining flow.
2. Initialize a Uniswap v4 pool pairing the `CyberScrip` against a
   stablecoin, with `hooks` set to the deployed fee hook.
3. As a BorgAuth admin, configure the pool's fees with
   `setPoolConfig(key, metalexRecipient, issuerRecipient, metalexFeeBps,
   issuerFeeBps, enabled)`. Both fees are in basis points, and together
   they can be at most `10_000`.
4. Seed liquidity. If the scrip has a `WhitelistTransferHook`, whitelist
   every address the scrip passes through: in Uniswap v4 that is the
   singleton `PoolManager`, which holds every v4 pool's balances, plus any
   router or position manager that takes custody of the scrip in your flow.
   Scrip hooks also run when scrip is minted, so every address that
   receives scrip from `scripifyCert` must be whitelisted as well.

See also [Hooks](../reference/hooks.md),
[CyberScrip](../reference/contracts/CyberScrip.md) and
[Composability](../explanation/composability.md).
