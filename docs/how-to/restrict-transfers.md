# Restrict cyberSCRIP transfers

cyberSCRIP is an ERC-20, so by default it moves freely. The protocol gives you
several knobs to restrict transfers when the underlying security requires it
(Reg D / Reg S secondary restrictions, an unaccredited-holder cap, a private
whitelist, etc.).

## Options

| Mechanism | Use when |
|---|---|
| `WhitelistTransferHook` | Closed circle of pre-approved counterparties. |
| `ToggleTransferHook` | Per-cert switch; useful for time-limited freezes. |
| Compliance powers (force transfer / burn, freeze, blocklist) | Reg-driven incident response, with **independent, permanent disable toggles** per power. |
| Max-holder cap on `CyberCertPrinter` | Stay below 12(g) (or analogue) thresholds. |

See [Hooks reference](../reference/hooks.md).

## Install a whitelist hook

### 1. Deploy the hook

```solidity
WhitelistTransferHook hook = new WhitelistTransferHook(cyberCorpAddr);
```

### 2. Register it on the cyberSCRIP

From an account with the `OFFICER_AUTHORITY` role:

```solidity
cyberScrip.setTransferHook(address(hook));
```

### 3. Whitelist counterparties

```solidity
hook.setWhitelisted(alice, true);
hook.setWhitelisted(bob, true);
```

Any `transfer` involving an address not in the set will revert. AMM pool
addresses (e.g., a LiquiLeX Uniswap v4 pool) can be whitelisted too.

## Permanently disable a compliance power

Force-transfer, force-burn, freeze and blocklist on cyberSCRIP each have
**independent, irreversible disable toggles**. Once an issuer renounces a
power, no party — including MetaLeX — can restore it.

```solidity
// Permanently renounce force-transfer.
cyberScrip.permanentlyDisableForceTransfer();
```

This is a one-way operation. Use it to harden the cyberSCRIP toward the
"open" end of the compliance spectrum once you no longer need a given power.

## Related

* Explanation: [Composability and DeFi](../explanation/composability.md)
* Reference: [`CyberScrip`](../reference/contracts/CyberScrip.md),
  [Hooks](../reference/hooks.md).
