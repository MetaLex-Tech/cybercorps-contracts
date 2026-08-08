# The dual-token model

The protocol's defining architectural innovation is a dual-token model that
resolves the tension between **legal fidelity** and **DeFi composability**.

## The two tokens

### cyberCERT (ERC-721) — the register

Each cyberCERT is a single entry on the cyberCORP's onchain register of
holders — minted by the `LedgerEntryToken` contract (formerly
`CyberCertPrinter`) — encoding everything that the relevant governing law
requires: holder name, unit count, class / series, restriction legends,
endorsement history, authorized signatures, acquisition price, and the
governing agreement URI.

Crucially, **NFT transfer alone does not change registered ownership.**
The register tracks a legal owner of record distinct from the ERC-721
possessor, and only the holder of record (or the `IssuanceManager` acting
as registrar on the owner's signature) can endorse a certificate over —
possession alone never carries endorsement authority. This maintains the
distinction between *token possession* and *registered ownership* that
corporate, LLC, partnership, and fund law require.

### cyberSCRIP (ERC-20) — the trading form

cyberSCRIPs are fungible tokens generated from cyberCERTs via
`scripifyCert()` and convertible back via `convertScripToCert()`. They are
the DeFi composable layer: usable in AMMs (including LiquiLeX pools),
lending protocols, vesting contracts, and as collateral.

The critical claim: **cyberSCRIPs are not wrappers or derivatives.** They
are *securities in scrip form*. Under DGCL §155 (in the Delaware corp case)
or the analogous contractual or statutory authority under the entity's
governing law, scrip is itself an authorised form of the security. Every
circulating cyberSCRIP traces, through the protocol's own logic, to a
specific cyberCERT on the authoritative register.

## The plain-English version

* A **cyberCERT** is your interest in the entity as it lives in the official
  records (a share of stock, an LLC membership interest, an LP unit, a fund
  interest).
* A **cyberSCRIP** is what you can trade or post as collateral when you do
  not need to be registered as a holder of record at that moment.
* Both are the same security in different forms, with bidirectional
  conversion always available.

## Why this works

### Composability without losing the register

A cyberSCRIP can sit in a Uniswap v4 pool and trade in size all day. The
register does not move. When a long-term holder wants to be the holder of
record, they de-scripify — and at that moment, and only at that moment, the
full issuer-approval / accreditation gate runs.

### Compliance at the boundary

This is what lets a LiquiLeX pool be either *whitelisted* (compliance on
every swap) or *open* (compliance at de-scripification, with optional
light-touch zkPassport screening at swap). The boundary is the only place
that matters legally, because that is where the register changes.

### Partial scripification

A holder of 1,000,000 shares can scripify 250,000 to trade and keep 750,000
on the cert. The cert remains active with the reduced unit count. An
ERC-4626-style pool inside the `IssuanceManager` tracks each certificate's
scripified units as vault positions, so that de-scripification withdraws
proportionally against the pool.

## What it isn't

* Not a wrapped-token model. The scrip is the security; the wrap-and-unwrap
  framing is wrong.
* Not a derivative model. There is no contract for difference, no
  shadow-asset, no offchain leg.
* Not a synthetic. A cyberSCRIP is not a claim on a cyberCERT; it is the
  same security in a different form.

## See also

* [Tutorial 3: Scripify and settle](../tutorials/scripify-and-settle.md)
* [`IssuanceManager`](../reference/contracts/IssuanceManager.md),
  [`CyberScrip`](../reference/contracts/CyberScrip.md)
* [Composability and DeFi](composability.md)
