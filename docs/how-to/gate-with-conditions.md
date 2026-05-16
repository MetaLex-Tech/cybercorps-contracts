# Gate state transitions with conditions

Any state transition in the protocol — issuance, scripification,
de-scripification, deal close, round acceptance, secondary trade — can be
gated by an arbitrary onchain check via the `ICondition` interface.

## Built-in conditions

| Condition | Effect |
|---|---|
| `lexchexCondition` | Requires a valid LeXcheX credential (KYC/AML, accreditation, qualified-purchaser). |
| `NonUSNationalityCondition` | zkPassport-based check that the address is held by a non-US person (Reg S). |
| `IssuerApprovalRecertificationCondition` | Requires explicit issuer approval before a non-registered scrip holder can present scrip for de-scripification. |
| `OrCondition` | Composes multiple conditions with disjunctive logic. |

See [Conditions reference](../reference/conditions.md).

## Attach a condition to a round

```solidity
ICondition lexCond = ICondition(LEXCHEX_CONDITION_ADDR);

roundManager.createRound(RoundConfig({
    // ...
    conditions: lexCond
}));
```

Now no EOI can be accepted unless the investor's address has the credential.

## Attach a condition to scripification

```solidity
issuanceManager.setScripifyCondition(SHARE_CLASS_COMMON, lexCond);
```

A cert holder will be unable to scripify unless they pass the check.

## Compose conditions

Use `OrCondition` (or a custom composer) for unions:

```solidity
OrCondition or = new OrCondition();
or.add(lexchexCondition);
or.add(nonUsCondition);
issuanceManager.setDescripifyCondition(SHARE_CLASS_COMMON, or);
```

## Write a custom condition

Implement `ICondition`:

```solidity
interface ICondition {
    function check(address subject, bytes calldata context) external view returns (bool);
}
```

Deploy and register it like any other. Anything expressible onchain — a token
balance threshold, a Snapshot vote outcome, a UMA assertion, a Soulbound
credential — can become a precondition for a state transition on your
cyberCORP.

## Related

* Reference: [Conditions](../reference/conditions.md)
* Explanation:
  [Compliance architecture](../explanation/compliance-architecture.md)
