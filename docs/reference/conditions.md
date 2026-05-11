# Conditions

The `ICondition` interface is the universal precondition primitive. Any
state transition in the protocol — issuance, scripification, de-scripification,
deal close, round acceptance, secondary trade settlement — can be gated on
any check expressible onchain.

## `ICondition`

```solidity
interface ICondition {
    function check(address subject, bytes calldata context)
        external view returns (bool);
}
```

## Built-in conditions

### `lexchexCondition`

Requires a valid LeXcheX credential at check time. Variants for
`hasAccreditation`, `hasKyc`, `isQualifiedPurchaser`, and combined checks.
See [`LexChex`](contracts/LexChex.md).

### `NonUSNationalityCondition`

zkPassport-based check that the subject address is held by a non-US person.
For Regulation S issuances. The reference UI flow lives in
[`features/zkpassport`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/features/zkpassport)
in `cybercorps-web`.

### `IssuerApprovalRecertificationCondition`

Requires explicit issuer approval before a non-registered scrip holder can
present scrip for de-scripification into a fresh cyberCERT. Implements the
*new-holder path* of recertification (see
[Tutorial 3](../tutorials/scripify-and-settle.md)).

### `OrCondition`

Composes multiple conditions with disjunctive logic:

```solidity
or.add(lexchexCondition);
or.add(nonUsCondition);
// passes if either is true
```

## Writing a custom condition

Anything expressible onchain is fair game: a token-balance threshold, a
Snapshot vote outcome, a UMA assertion, a Soulbound credential, a Chainlink
oracle reading.

```solidity
contract MinHoldingCondition is ICondition {
    IERC20 immutable token;
    uint256 immutable minimum;
    constructor(IERC20 t, uint256 m) { token = t; minimum = m; }
    function check(address subject, bytes calldata) external view returns (bool) {
        return token.balanceOf(subject) >= minimum;
    }
}
```

Register it on the cyberCORP wherever you need it (e.g.,
`roundManager.createRound(...)`, `issuanceManager.setScripifyCondition(...)`).
