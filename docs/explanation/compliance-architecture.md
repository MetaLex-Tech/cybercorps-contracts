---
description: >-
  Where compliance runs: condition contracts on every legally significant
  transition, the credentials they read, and the point where scrip becomes a
  Ledger Entry Token again.
---

# Compliance architecture

The contracts carry no compliance regime of their own. Each company builds
its regime (Reg D, Reg S, a local private-placement regime, qualified-purchaser
rules, sanctions screening) out of condition contracts that gate state
changes, credential registries those conditions read, and a choice of where
in the scrip lifecycle to put the strictest gate.

## Conditions gate every transition that changes legal state

Issuance, scripification, conversion of scrip back into a Ledger Entry Token
(LET), deal close, round acceptance, and the posting and settlement of
secondary offers each accept condition contracts (`ICondition`, or its typed
variant for secondary trading). Each condition is evaluated at the moment of
the state change, and conditions compose, so one transition can require
several facts at once. A condition can require that an investor holds a
valid LeXcheX accreditation credential, that a buyer has a zkPassport proof
of non-US nationality, that a recipient holds a soulbound membership NFT, or
that the transaction comes after the block in which the company filed its
Form D.

On a v5 company, secondary trades get the fullest set. A buyer accepting an
offer elects an exemption pathway (Rule 144, §4(a)(7), §4(a)(1½), Rule 144A or
Reg S), and the trade runs the conditions wired to that pathway, alongside
any conditions the issuer applies to every trade. The pathway conditions
cover holding periods, disclosure, distribution compliance, buyer
eligibility, holder caps, state of residence and CFIUS-style blocked
jurisdictions. A pathway the issuer has not configured blocks every trade
under it. [Conditions](../reference/conditions.md) lists the contracts.

## The strictest gate can sit where scrip becomes a LET

Inside the scrip lifecycle, the register changes only when units are
scripified out of a LET or scrip is converted back into one (see
[Ledger Entry Tokens and scrip](lets-and-scrip.md)). A company can therefore
run its full gate at conversion and let scrip move freely, or under a light
gate, everywhere else. That supports a globally tradable AMM market in a
private company's equity without KYC on every counterparty, while every
scrip holder who becomes a holder of record passes the full check. Where
even trading must be gated, a whitelist transfer hook restricts every scrip
transfer, mints included, to whitelisted addresses. Both models use the same
contracts, and [Composability and DeFi](composability.md) compares them as
LiquiLeX pools.

The register keeps its own gate as well. A v5 LET contract consults its
transfer hooks at two points, when a LET moves between addresses
(possession) and when the holder of record changes (registration), and has
a separate stop-transfer switch for each. See [Hooks](../reference/hooks.md).

## Credentials

### LeXcheX

LeXcheX is the protocol's accreditation and KYC/AML credential layer (see
[`LexChex`](../reference/contracts/LexChex.md)). A credential is a soulbound
NFT minted to a wallet once the holder completes onboarding: a
questionnaire, a portfolio valuation and a countersigned agreement.
`LexChexCondition` (`hasValidLexCheX`) checks it anywhere in the protocol.
[LeXcheX](../webapp/lexchex.md) describes the onboarding app, including
accreditation from onchain holdings.

The `LeXcheXBadge` registry keeps every kind of credential in one soulbound
contract: KYC/AML; accredited-investor, qualified-purchaser and QIB status;
non-US status; investor jurisdiction and US state of residence;
beneficial-owner counts for look-through accounting; and per-issuer whitelist
and syndicate entitlements. A badge credential never changes after it is
minted. A changed fact gets a newer credential, and revoking a credential
only voids it, so every credential stays onchain for audit. Every read
returns the credential's expiry with its value. One deployment can serve
several credentialing operators: the registry's admins grant issuing
authority per fact key (`setIssuerKeys`), each credential records the issuer
that minted it, and a reader can accept only the issuers it trusts. The
secondary-trading conditions read this registry.

### zkPassport

`NonUSNationalityCondition` checks a zkPassport proof that the address
belongs to a non-US person, for Reg S and sanctions screening. The proof is
zero-knowledge, so the address shows its nationality status without
revealing who holds it, which suits the swap layer of an open LiquiLeX pool.

## Reg D and Reg S call for different gates

| Regime | Typical pattern |
|---|---|
| Reg D (US) | LeXcheX accreditation and KYC on every primary investor and at conversion into a LET. Whitelisted LiquiLeX pool. |
| Reg S (non-US) | zkPassport non-US proof at primary issuance, an optional light zkPassport gate at swap, and a full credential at conversion into a LET. |
| Both | An `OrCondition` accepting either path, so one company serves both audiences with two issuance flows. |

## Holder caps

On a v5 company, `CyberScrip` can enforce a hard cap on the number of scrip
holders (`maxHolderCount`), checked on every transfer and monitored through
an onchain `holderCount`, and the company's admins set the cap directly on
the scrip. On a v4 company only the IssuanceManager can call the setter, and
the v4 IssuanceManager has no function that does, so the cap cannot be set.

On the register side, `HolderCapCondition` gates secondary trades against
Investment Company Act §3(c)(1) and §3(c)(7) limits. It counts credentialed
beneficial owners on a look-through basis instead of wallets, and counts an
acquirer with no attestation as a US investor. The LET contracts'
holder-count views can feed monitoring of the Exchange Act 12(g) threshold
and its non-US analogues. The cyberCORPs app lists LET and scrip holders in
the [Tokenization Hub](../webapp/tokenization-hub.md) and shows a
stakeholder count on the capTable page, but it does not track 12(g)
thresholds.

## See also

* [Gate state transitions with conditions](../how-to/gate-with-conditions.md)
* [Restrict scrip transfers](../how-to/restrict-transfers.md)
* [Regulatory context](regulatory-context.md)
