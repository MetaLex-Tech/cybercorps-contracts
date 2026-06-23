# Conditions

A **condition** is a contract implementing `ICondition`. Conditions gate
state transitions — issuance, scripification, de-scripification, deal close,
round acceptance — on arbitrary onchain checks.

* **Interface:** [`ICondition.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICondition.sol)

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

`checkCondition` is given the calling contract, the function selector being
gated, and ABI-encoded context, and returns whether the action may proceed.
Where the protocol accepts conditions — e.g. `IssuanceManager.deployCyberScrip`
(`certToScripConditions`, `scripToCertConditions`),
`DealManager.proposeDeal` (`conditions`), `RoundManager.submitEOI`
(`conditions`) — they are passed as `address[]` / `ICondition[]`.

## Built-in conditions

The protocol ships condition contracts for common compliance checks. By name
(see the source for exact contracts and constructors):

| Condition | Purpose |
|---|---|
| **lexchexCondition** | Requires a valid LeXcheX credential — wraps `ILexChex.hasValidLexCheX`. See [LexChex](contracts/LexChex.md). |
| **NonUSNationalityCondition** | A zkPassport-backed check that the address is held by a non-US person (Regulation S). See `IZKPassportVerifier`. |
| **IssuerApprovalRecertificationCondition** | Requires explicit issuer approval before a non-registered scrip holder can de-scripify into a fresh cyberCERT. |
| **OrCondition** | Composes child conditions with disjunctive (OR) logic. |

## Custom conditions

Any contract implementing `ICondition` works. Because `checkCondition`
receives the calling contract, the selector, and arbitrary `data`, a
condition can encode any onchain check — a token balance, a credential, an
oracle reading, a governance outcome — and be attached wherever the protocol
accepts a condition list.

> The built-in condition contracts live under `src/` (and `src/creds/`).
> This page describes the `ICondition` interface precisely; verify each
> built-in condition's constructor and behaviour against its source.
