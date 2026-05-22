# Gate state transitions with conditions

A **condition** is a contract implementing `ICondition`. Conditions gate
state transitions on arbitrary onchain checks.

## The interface

```solidity
interface ICondition {
    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool);
}
```

See [Conditions](../reference/conditions.md) for the built-in conditions
(`lexchexCondition`, `NonUSNationalityCondition`,
`IssuerApprovalRecertificationCondition`, `OrCondition`).

## Where conditions are attached

Conditions are passed as `address[]` (or `ICondition[]`) into the call that
creates the gated thing:

**Scripification / de-scripification** — set when the scrip is deployed:

```solidity
IIssuanceManager(issuanceManager).deployCyberScrip(
    certAddress,
    typeRestrictionHooks,
    certToScripConditions,   // ICondition[] gating scripifyCert
    scripToCertConditions,   // ICondition[] gating convertScripToCert
    /* ...remaining args... */
);
```

**A fundraising round** — in the `Round` built via `RoundLib.setAgreement`
(`roundConditions`), and per-EOI in `submitEOI(..., conditions, ...)`.

**A deal** — the `conditions` argument of `DealManager.proposeDeal`.

## Writing a custom condition

Implement `ICondition`. Because `checkCondition` receives the calling
contract, the selector, and arbitrary `data`, you can encode any onchain
check:

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

Deploy it and pass its address wherever the protocol accepts a condition
list.

## Related

* [Conditions reference](../reference/conditions.md)
