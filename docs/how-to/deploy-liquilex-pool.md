# Deploy a LiquiLeX pool

**LiquiLeX** provides AMM-native secondary liquidity for cyberSCRIP using
Uniswap v4 pools, with the **`MetalexIssuerFeeHook`** routing swap fees to
MetaLeX and the issuer.

## Prerequisites

* A cyberCORP with a deployed `CyberScrip` for the class you want to make
  liquid (see [Tutorial 3](../tutorials/scripify-and-settle.md)).
* A chosen compliance model:
  * **Whitelisted pool** — a `WhitelistTransferHook` on the cyberSCRIP, with
    the pool's custody addresses whitelisted; only whitelisted addresses can send or
    receive the scrip, so credential checks happen when an address is
    added to the whitelist.
  * **Open pool** — no transfer hook; compliance enforced at the
    de-scripification boundary, optionally with a zkPassport check at swap.

## Approach

1. Deploy the `MetalexIssuerFeeHook`
   ([`src/hooks/uniswap/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/hooks/uniswap))
   and call `initialize(auth, poolManager)`. The hook declares
   `beforeSwap`/`afterSwap` permissions (with return deltas), and Uniswap v4
   requires the hook address to encode those flags — so deploy at a mined
   address (the standard `HookMiner` salt-mining flow).
2. Initialise a Uniswap v4 pool pairing the `CyberScrip` against a
   stablecoin, with `hooks` set to the deployed fee hook.
3. Configure fees for the pool (BorgAuth admin):
   `setPoolConfig(key, metalexRecipient, issuerRecipient, metalexFeeBps,
   issuerFeeBps, enabled)` — both fees in basis points, combined at most
   `10_000`.
4. Seed liquidity. If the cyberSCRIP has a `WhitelistTransferHook`,
   whitelist the addresses the scrip passes through: in Uniswap v4 that is
   the singleton `PoolManager`, which holds every v4 pool's balances, plus
   any router or position manager that takes custody of the scrip in your
   flow. Scrip hooks also run when scrip is minted,
   so every address that receives scrip from `scripifyCert` must be
   whitelisted as well.

## Related

* [Hooks](../reference/hooks.md),
  [CyberScrip](../reference/contracts/CyberScrip.md).
* Explanation: [Composability and DeFi](../explanation/composability.md).
