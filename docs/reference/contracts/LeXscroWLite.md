# LeXscroWLite

> **There is no `LeXscroWLite.sol` in this repository's `src/` tree.**

MetaLeX protocol materials refer to *LeXscroWLite* as the atomic deal-closing
escrow. In `cybercorps-contracts` as it currently stands, the escrow of
payment and assets is **part of the deal and round flow itself**, not a
separate deployed contract in `src/`:

* [`DealManager`](DealManager.md) escrows payment and certificate effects
  across a deal's `proposeDeal` → `signDealAndPay` → `finalizeDeal`
  lifecycle, with `expiry` / `voidExpiredDeal` handling stale deals.
* [`RoundManager`](RoundManager.md) does the equivalent across
  `submitEOI` → `allocate` → `closeRoundNow`.

A standalone LeXscroW escrow engine may be supplied as an external
dependency (see the repository's `dependencies/` directory) or introduced in
a later version. Until a `LeXscroWLite` contract appears in `src/`, treat
the escrow as an aspect of the deal/round managers above.

This page will be replaced with a full contract reference if and when a
standalone escrow contract lands in `src/`.
