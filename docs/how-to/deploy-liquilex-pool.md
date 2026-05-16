# Deploy a LiquiLeX pool

**LiquiLeX** provides AMM-native secondary liquidity for cyberSCRIP via
Uniswap v4 pools paired against a stablecoin, with the
`MetalexIssuerFeeHook` routing swap fees to MetaLeX and the issuer at
configured rates.

## Prerequisites

* A cyberCORP with a deployed `CyberScrip` for the class you want to make
  liquid.
* You have decided on a compliance model:
  * **Whitelisted pool** — every swap checks LeXcheX credentials.
  * **Open pool** — swaps are unrestricted; compliance is enforced at the
    de-scripification boundary, optionally with a lighter zkPassport gate at
    swap for sanctions and Reg S screening.

## Steps

### 1. Deploy the fee hook

```solidity
MetalexIssuerFeeHook hook = new MetalexIssuerFeeHook(
    METALEX_TREASURY,
    issuerTreasury,
    metalexBps,     // e.g., 10  (0.10%)
    issuerBps       // e.g., 20  (0.20%)
);
```

Uniswap v4 hooks have address-suffix requirements. Use `HookMiner` or the
standard salt-mining flow to deploy at a compliant address.

### 2. Initialise the pool

Create a Uniswap v4 pool with:

* `currency0 = cyberScrip`
* `currency1 = USDC` (or your chosen stablecoin)
* `fee = poolFee` (the protocol fee; separate from the issuer/MetaLeX hook fee)
* `hooks = address(hook)`

### 3. Seed liquidity

A founder, treasury, or scripified position provides initial liquidity. If the
cyberSCRIP has a `WhitelistTransferHook`, whitelist the pool address.

### 4. (Optional) Add a zkPassport gate

For open pools used for Reg S issuances, attach a `NonUSNationalityCondition`
to the swap path through a custom router hook.

## Compliance summary

| Model | Per-swap check | De-scripification check |
|---|---|---|
| Whitelisted pool | Full LeXcheX | None additional |
| Open pool | Optional zkPassport (sanctions, Reg S) | Full issuer approval + credential |

## Related

* Reference: [`MetalexIssuerFeeHook`](../reference/hooks.md#metalexissuerfeehook),
  [`CyberScrip`](../reference/contracts/CyberScrip.md).
* Explanation: [Composability and DeFi](../explanation/composability.md).
