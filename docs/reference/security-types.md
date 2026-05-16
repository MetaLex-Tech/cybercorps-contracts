# Security types

The protocol natively issues and manages the lifecycle of the following
instrument types. Each maps to a registered
[Certificate extension](extensions.md) on the cyberCORP's
`CyberCertPrinter`.

## Equity

* **Common Stock** — `ShareExtension`.
* **Preferred Stock**, Pre-Seed through Series F —
  `ShareExtension` with the appropriate series identifier and NVCA-aligned
  parameters.
* **Stock Options** — `ShareExtension` (option variant) with reservation
  accounting in `CyberShares`.
* **Restricted Stock Purchase Agreements** — `ShareExtension` plus an
  unlock / vesting condition.
* **Restricted Stock Units (RSUs)** — `ShareExtension` (RSU variant).

## SAFE family

* **SAFEs** — `SAFEExtension`. YC post-money or jurisdiction-neutral
  template (see [Templates](templates.md)).
* **ACE SAFEs** — `ACESAFEExtension`. Used by
  [PumpCorpFactory](factories.md#pumpcorpfactory).

## SAFT family

* **SAFTs** — `SAFTExtension` / `SAFTExtensionV2`.
* **SAFTEs** — `SAFTEExtension` / `SAFTEExtensionV2` (tokens or equity, with
  trigger-first conversion).

## Token instruments

* **Token Warrants** — `TokenWarrantExtension` / `TokenWarrantExtensionV2`
  (a16z-derived, jurisdiction-neutral, and Reg S variants).
* **Token Purchase Agreements** — issuable via `SAFTExtension` with
  appropriate parameters.
* **Restricted Token Purchase Agreements** — `SAFTExtension` + vesting
  condition.
* **Restricted Token Units** — `SAFTEExtension` (RTU variant).

## Convertible Notes

Issuable via `SAFEExtension` configured as a debt instrument with maturity,
interest, and conversion terms. (Convention; the extension is intentionally
flexible.)

## LLC / partnership / fund

LLC membership interests, LP interests, and fund interests flow through
`ShareExtension` with the appropriate `entityType` on the parent cyberCORP
and jurisdiction-appropriate legends. The protocol makes no assumption
about the underlying corporate or partnership statute.
