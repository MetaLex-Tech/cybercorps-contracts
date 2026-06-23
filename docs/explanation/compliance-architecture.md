# Compliance architecture

The protocol does not bake any specific compliance regime into the
contracts. Instead, it exposes a small number of **extension points** —
conditions, credentials, and the de-scripification boundary — and lets
issuers compose them to satisfy whatever rules apply to them (Reg D, Reg S,
local private-placement regimes, qualified-purchaser rules, sanctions
screening, etc.).

## The two big extension points

### 1. `ICondition` everywhere

Every state transition that matters legally — issuance, scripification,
de-scripification, deal close, round acceptance — accepts an `ICondition`.
The condition is evaluated at the moment of state change.

This means you can express:

* "This investor must hold a valid LeXcheX accreditation credential."
* "This buyer must have a zkPassport proof that they are non-US."
* "This recipient must hold a soulbound club-membership NFT."
* "This transaction must occur after our SEC Form D filing block."

…and any composition of the above.

### 2. The de-scripification boundary

The critical insight: **compliance at the register boundary, freedom in
between**. cyberSCRIP can flow freely (or under light gates); when someone
wants to become the holder of record, the full gate runs.

This pattern lets you:

* Have a globally tradable AMM market on private equity.
* Avoid having to KYC every counterparty in that market.
* Still maintain a fully compliant register at the level that matters
  legally.

For regulated instruments where even the swap layer must be gated, the
whitelisted-pool model checks credentials on every swap. Both models live in
the same contract suite.

## Credentials: LeXcheX

LeXcheX is the protocol's accreditation and KYC-AML credential layer (see
[`LexChex`](../reference/contracts/LexChex.md)). Credentials are soulbound
NFTs minted to a wallet after the holder completes onboarding (questionnaire,
portfolio valuation, agreement countersigning). The credentials can be
checked by `lexchexCondition` anywhere in the protocol.

For onchain wealth-based accreditation ("my $5M ETH portfolio makes me
qualified"), see the reference UI at
[`apps/lexchex-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-web)
in `metalex-webapp`.

## Credentials: zkPassport

For Reg S and sanctions-screening purposes, `NonUSNationalityCondition`
integrates a zkPassport proof that the address is held by a non-US person.
Unlike LeXcheX, zkPassport is zero-knowledge: the address proves
nationality status without revealing identity. Useful at the swap layer of
open LiquiLeX pools.

## Reg D vs. Reg S

| Regime | Typical pattern |
|---|---|
| Reg D (US) | LeXcheX accreditation + KYC required on all primary investors and on de-scripification. Whitelisted LiquiLeX pool. |
| Reg S (non-US) | zkPassport non-US proof at primary, optional light zkPassport gate at swap, full credential on de-scripification. |
| Combined | `OrCondition` allowing either path; cyberCORP serves both audiences with two issuance flows. |

## Holder caps

`CyberCertPrinter.setMaxHolders(n)` and `CyberScrip.setMaxHolders(n)` let
you monitor and enforce 12(g) thresholds (US) and their analogues. The
Mainframe UI surfaces these alongside the holder lists for proactive
management.

## See also

* [Conditions](../reference/conditions.md)
* [`LexChex`](../reference/contracts/LexChex.md)
* [How-to: Gate state transitions with conditions](../how-to/gate-with-conditions.md)
* [Composability and DeFi](composability.md)
