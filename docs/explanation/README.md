---
description: >-
  Why the protocol is designed as it is, what it relies on in law, and how
  far MetaLeX's control over a deployed company reaches.
---

# How cyberCORPs works

These pages explain the design and its legal grounding for lawyers,
investors and integrators deciding whether the model fits. They argue why a
company's onchain records can be its legal record, why each security has two
token forms, where compliance runs, and what MetaLeX can and cannot do once a
company is deployed. To build on the protocol, start with the
[guides](../how-to/README.md), which also list the contracts each product
uses, and the [reference](../reference/README.md).

* [Constitutive vs. pointer tokenization](constitutive-vs-pointer.md) is the
  thesis: where a company's governing documents designate the onchain
  records as its securities ledger, changing onchain state is the legal
  change.
* [Ledger Entry Tokens and scrip](lets-and-scrip.md) shows how a Ledger
  Entry Token (LET) records a holding on the register while scrip, its
  fungible counterpart, trades without moving it.
* [Legal mappings across jurisdictions](legal-mappings.md) sets out the
  statutes and governing documents that anchor the register for Delaware
  corporations and LLCs, Cayman and BVI entities, English companies and
  funds.
* [Compliance architecture](compliance-architecture.md) covers condition
  contracts, credentials, and the choice of where in the scrip lifecycle the
  strictest gate sits.
* [Composability and DeFi](composability.md) weighs what scrip can do in AMMs
  and lending markets against what its restrictions cost.
* [Upgrades and what MetaLeX controls](upgrades-and-control.md) explains
  opt-in upgrades, fees and templates, and the owner role the deploying
  factory keeps.
* [Regulatory context](regulatory-context.md) maps the US exemptions and SEC
  staff statements the protocol is built around.
