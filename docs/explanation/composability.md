# Composability and DeFi

A tokenised security is only as useful as the protocols it can interact
with. cyberSCRIP is the layer where that interaction happens.

## What cyberSCRIP unlocks

* **AMM liquidity.** A LiquiLeX Uniswap v4 pool can quote a cyberSCRIP
  against USDC continuously. The `MetalexIssuerFeeHook` routes a portion of
  swap fees to the issuer (and a portion to MetaLeX), turning the cyberCORP
  into a tiny perpetual fee-receiver on its own scrip.
* **Lending and money markets.** A cyberSCRIP, like USDC, is an ERC-20 with
  optional compliance powers. It can be listed as collateral on lending
  protocols that accept ERC-20s with admin extensions.
* **Vesting and streaming.** Any standard ERC-20 vesting contract works.
* **Programmable distributions.** Dividends, buybacks, or other holder-
  facing flows can be paid in or settled against cyberSCRIP.

## What you trade off

### Restricted ERC-20

A cyberSCRIP with a `WhitelistTransferHook` is not a free-floating ERC-20.
Some integrations (especially permissionless ones) will reject it. Operators
should either pick an open compliance model (no transfer hook, compliance at
the de-scripification boundary) or accept that their scrip will only flow
through whitelisted venues.

### Compliance powers are visible

Force transfer, force burn, and per-account freeze are opt-in powers chosen
when the scrip is deployed, exercisable only through the issuer's
`IssuanceManager`. Even when never invoked, their presence is visible, and
some lending protocols will decline to list any ERC-20 with these powers.
The **one-way disable** functions (`disableScripForceTransfer`,
`disableScripForceBurn`, `disableScripFreeze`) exist for exactly this
reason: an issuer can credibly and irreversibly commit to an open posture.

### Token possession ≠ registered ownership

This is by design (see [the dual-token model](dual-token-model.md)) but it
means naive integrations may make wrong assumptions. The cyberSCRIP holder
is not the holder of record. The cyberCERT holder is. Anywhere registered
ownership matters (voting, dividends to record holders, §219 lists), reads
must go through the cert layer.

## The two LiquiLeX models, side-by-side

| Aspect | Whitelisted pool | Open pool |
|---|---|---|
| Per-swap check | Transfer-hook whitelist (credentialed addresses only) | Optional zkPassport (sanctions / Reg S) |
| Pool address | Only whitelisted addresses can hold LP | Anyone can hold LP |
| Holder of record | Same regardless of trades | Same regardless of trades |
| De-scripification gate | Standard | Standard (this is where compliance lives) |
| Best for | High-touch private credits, Reg D names | Reg S issuances, public-style scrip |

## See also

* [How-to: Deploy a LiquiLeX pool](../how-to/deploy-liquilex-pool.md)
* [Compliance architecture](compliance-architecture.md)
* [Hooks](../reference/hooks.md)
