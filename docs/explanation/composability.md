---
description: >-
  What scrip can do in AMMs, lending markets and vesting contracts, and what
  its transfer restrictions and compliance powers cost in integrations.
---

# Composability and DeFi

A Ledger Entry Token (LET) names its holder and carries restriction legends,
so DeFi protocols built for interchangeable ERC-20 units cannot use it. Scrip
is the form they can use.

## Scrip can sit in pools, lending markets and vesting contracts

A LiquiLeX pool on Uniswap v4 quotes scrip against USDC continuously, and
its `MetalexIssuerFeeHook` splits swap fees between the issuer and MetaLeX,
so the company earns a share of every swap in its own scrip. Like USDC,
scrip is an ERC-20 with optional compliance powers, so lending protocols
that accept such tokens can list it as collateral. A standard ERC-20
vesting or streaming contract handles scrip as long as the scrip's transfer
hooks admit it, and buybacks
and other payments to holders can be made in scrip or settled against it.
What a scrip holder is owed on the shares behind the scrip, dividends
included, depends on the scrip's terms (see
[Ledger Entry Tokens and scrip](lets-and-scrip.md)).

## Each compliance choice narrows where scrip can go

### A transfer hook limits the venues

Scrip with a `WhitelistTransferHook` moves only between whitelisted
addresses, and many integrations, permissionless ones especially, reject
it. A company chooses between an open model (no transfer hook, compliance at
conversion into a LET) and accepting that its scrip flows only through
whitelisted venues.

### Compliance powers show even when unused

Force transfer, force burn and per-account freeze are opt-in powers chosen
when the scrip is deployed, and the company's admins exercise them. Their
presence is visible onchain whether or not anyone uses them, and some
lending protocols decline to list any ERC-20 that has them. The scrip's
one-way switches (`disableForceTransfer`, `disableForceBurn`,
`disableFreeze`) let a company commit, irreversibly and verifiably, to an
open posture.

### Registered ownership lives on the LET

A LET's holder of record is the registered owner of its units, and holding
scrip registers no one. An integration that needs registered ownership, for
voting, dividends to record holders or a DGCL §219 stockholder list, has to
read the LET layer.

## Whitelisted and open LiquiLeX pools

| | Whitelisted pool | Open pool |
|---|---|---|
| Check on each swap | Transfer-hook whitelist (credentialed addresses only) | Optional zkPassport (sanctions, Reg S) |
| Who can hold LP positions | Whitelisted addresses only | Anyone |
| Effect of trades on the register | None | None |
| Gate at conversion into a LET | Standard | Standard, and the main compliance point |
| Suited to | High-touch private credit and Reg D issuers | Reg S issuances and widely traded scrip |

## See also

* [Deploy a LiquiLeX pool](../how-to/deploy-liquilex-pool.md)
* [Compliance architecture](compliance-architecture.md)
* [Hooks](../reference/hooks.md)
