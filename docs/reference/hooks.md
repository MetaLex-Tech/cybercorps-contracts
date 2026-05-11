# Hooks

Hooks are pluggable contracts attached at well-defined extension points. The
protocol exposes two families:

* **Transfer hooks** — consulted by `CyberScrip` on every transfer.
* **Uniswap v4 hooks** — used by LiquiLeX pools.

## Transfer hooks

### `BaseTransferHook`

Abstract base class. Override `_check(from, to, amount)` to enforce a rule.

### `WhitelistTransferHook`

Restricts `cyberSCRIP` transfers to whitelisted addresses. The cyberCORP's
officers manage the set:

```solidity
function setWhitelisted(address account, bool ok) external; // OFFICER_AUTHORITY
function isWhitelisted(address account) external view returns (bool);
```

Use for closed-circle compliance models or to whitelist a single LiquiLeX
pool.

### `ToggleTransferHook`

Per-cyberCERT transfer toggling by the issuer with a configurable default.
Useful for time-limited freezes or per-class transferability switches.

## Uniswap v4 hooks

### `MetalexIssuerFeeHook`

Fee router for LiquiLeX. Splits Uniswap v4 swap fees between MetaLeX and the
issuer at configured BPS, enabling cyberSCRIP / stablecoin pools that pay
the issuer onchain on every trade.

```solidity
constructor(
    address metalexTreasury,
    address issuerTreasury,
    uint256 metalexBps,
    uint256 issuerBps
);
```

Address-suffix mining is required to deploy at a Uniswap-v4-compliant
address; use the standard `HookMiner` salt-mining flow.

## See also

* [How-to: Restrict cyberSCRIP transfers](../how-to/restrict-transfers.md)
* [How-to: Deploy a LiquiLeX pool](../how-to/deploy-liquilex-pool.md)
