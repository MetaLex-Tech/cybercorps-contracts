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
de-scripification, deal close, round acceptance, secondary-trade posting and
settlement — accepts a condition contract (`ICondition`, or its strongly
typed secondary-trading variant). The condition is evaluated at the moment
of state change.

This means you can express:

* "This investor must hold a valid LeXcheX accreditation credential."
* "This buyer must have a zkPassport proof that they are non-US."
* "This recipient must hold a soulbound club-membership NFT."
* "This transaction must occur after our SEC Form D filing block."

…and any composition of the above.

Secondary trades get the most developed treatment: a buyer elects an
**exemption pathway** (Rule 144, §4(a)(7), §4(a)(1½), Rule 144A, or Reg S)
when accepting an offer, and the trade runs the condition set wired to that
pathway — holding-period, disclosure, distribution-compliance,
eligibility, holder-cap, state-of-residence, and CFIUS-style
blocked-jurisdiction checks all live in this family — alongside any
issuer-wide conditions. An unconfigured pathway blocks trades rather than
admitting them unchecked.

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
checked by `LexChexCondition` (`hasValidLexCheX`) anywhere in the protocol.

The second-generation registry, `LeXcheXBadge`, unifies all credentialing
into one soulbound contract: KYC/AML, accredited-investor,
qualified-purchaser, and QIB status, non-US status, investor jurisdiction
and US state of residence, entity beneficial-owner counts for look-through
accounting, and per-issuer whitelist and syndicate entitlements. Badge
credentials are immutable once minted — facts change by minting a newer
credential and revocation is void-only, so every credential remains onchain
for audit — and every read returns the credential's expiry alongside its
value. The secondary-trading conditions read this registry.

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

On the scrip side, `CyberScrip.setMaxHolderCount(n)` enforces a hard cap on
every transfer, with an onchain `holderCount` for monitoring. On the
register side, `HolderCapCondition` gates secondary trades against
Investment Company Act §3(c)(1) / §3(c)(7)-style limits, counting
credentialed beneficial owners look-through rather than wallets — an
unattested acquirer conservatively counts as US. The cert register's
holder-count views also support 12(g) threshold monitoring (US) and its
analogues, and the Mainframe UI surfaces these alongside the holder lists
for proactive management.

## See also

* [Conditions](../reference/conditions.md)
* [`LexChex`](../reference/contracts/LexChex.md)
* [How-to: Gate state transitions with conditions](../how-to/gate-with-conditions.md)
* [Composability and DeFi](composability.md)
