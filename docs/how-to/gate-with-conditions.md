---
description: Attach condition contracts to scripification, rounds, deals and secondary settlement, and write a custom condition
---

# Gate state transitions with conditions

A condition is a contract implementing `ICondition`. Attaching conditions
lets a company require any onchain check before scrip is minted or
redeemed, an investor joins a round, a deal proceeds or a secondary trade
settles.

```solidity
interface ICondition {
    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool);
}
```

[Conditions](../reference/conditions.md) documents the built-in conditions
(`lexchexCondition`, `NonUSNationalityCondition`,
`IssuerApprovalRecertificationCondition`, `OrCondition`). The
secondary-trading conditions live in
[`src/libs/conditions/secondary/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/src/libs/conditions/secondary)
and cover eligibility, holding periods, holder caps, Reg S distribution
compliance, Rule 144 and Section 4(a)(7) disclosure, CFIUS, a kill switch
and more.

## Attach conditions where the protocol accepts them

Pass conditions as an `address[]` (or `ICondition[]`) to the call that
creates the gated thing. Secondary trades are the exception: the
DealManager keeps their conditions as standing lists.

### Scripification and de-scripification

Set both lists when you deploy the scrip:

```solidity
IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,
    certToScripConditions,   // ICondition[] gating scripifyCert
    scripToCertConditions,   // ICondition[] gating convertScripToCert
    /* ...remaining args... */
);
```

### Fundraising rounds

Round-wide conditions go in the `Round` built with `RoundLib.setAgreement`
(`roundConditions`). Per-EOI conditions go in
`submitEOI(..., conditions, ...)`.

### Deals

Pass them as the `conditions` argument of `DealManager.proposeDeal`.

### Secondary trades

The company sets these lists once on the DealManager, and the DealManager
evaluates them at post, accept and finalize:

```solidity
// exemption-pathway conditions (also enables/disables the pathway)
dealManager.setPathwayThresholdConditions(pathway, conditions, enabled);
// fund-specific conditions applying to every offer
dealManager.setSpvThresholdConditions(conditions);
// conditions evaluated only at finalization
dealManager.setClosingConditions(conditions);
```

These lists accept only contracts implementing the typed
`ISecondaryTradingCondition`, and the setters check for it through ERC-165.
[Run a secondary trade](run-a-secondary-trade.md) shows the lists in use.

## Write a custom condition

`checkCondition` receives the calling contract, the function selector and
arbitrary `data`, so a condition can encode any onchain check:

```solidity
contract MinBalanceCondition is ICondition {
    IERC20  immutable token;
    uint256 immutable minimum;
    constructor(IERC20 t, uint256 m) { token = t; minimum = m; }

    function checkCondition(address, bytes4, bytes memory data)
        external view returns (bool)
    {
        address subject = abi.decode(data, (address));
        return token.balanceOf(subject) >= minimum;
    }
}
```

Deploy it and pass its address in any `ICondition` list on this page.
