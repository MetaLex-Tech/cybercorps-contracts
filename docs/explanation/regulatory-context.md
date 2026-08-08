# Regulatory context

This page is a brief, non-exhaustive map of the regulatory backdrop the
protocol is designed for. It is **not legal advice**. Issuers must consult
their own counsel.

## US securities laws

### Reg D (private placements to US investors)

The standard exemption for unregistered US private placements. Imposes
accreditation requirements (Rule 506(b)/(c)) and limits on general
solicitation. The protocol supports Reg D via:

* `LexChexCondition` accreditation-credential checks (`hasValidLexCheX`) at
  issuance, deal close, and de-scripification.
* Reg D agreement templates (`MetaLeX cyberSAFE US style Reg D`, etc.).
* Holder caps (scrip-side `setMaxHolderCount` enforcement and onchain
  holder-count views for 12(g) threshold monitoring).

### Reg S (offers to non-US persons)

The extraterritorial-offering exemption. The protocol supports Reg S via:

* `NonUSNationalityCondition` (zkPassport).
* Reg S agreement templates.
* Optional whitelisted-pool or open-pool LiquiLeX models with the
  appropriate gate.

### Secondary resales

Secondary trades settle under an exemption pathway elected by the buyer at
acceptance — Rule 144, §4(a)(7), §4(a)(1½), Rule 144A, or Reg S — each
wired to its own condition set (holding periods, disclosure, distribution
compliance, buyer eligibility, and jurisdictional screens). Issuers enable
only the pathways they support; an unconfigured pathway blocks trades.

### Tokenized securities — SEC January 2026 Joint Staff Statement

In January 2026 the SEC's Division of Corporation Finance issued a joint
staff statement clarifying that the agency's traditional analytical
framework for securities laws applies to tokenized securities. The cyberCORPs
protocol is designed to be compatible with that framework: a tokenized
security is a security, treated as such, and the chain is the medium not
the escape.

See:
[corp-fin-statement-tokenized-securities-012826](https://www.sec.gov/newsroom/speeches-statements/corp-fin-statement-tokenized-securities-012826).

### Covered User Interface Providers — SEC April 2026 Staff Statement

In April 2026 the SEC issued staff guidance on "covered user interface
providers" (File No. 4-894). The statement creates a safe harbour for
front-end operators that meet specified conditions, relevant to operators of
cyberTRADE and LiquiLeX front ends. The contract architecture stays neutral
to front-end legal status: whichever harbour a UI operator chooses to
rely on, the chain-side primitives do not change.

## Delaware General Corporation Law

The most fully worked-out statutory reference for the protocol. See
[Legal mappings](legal-mappings.md) for the field-by-field hooks (DGCL §§
151, 155, 158, 202, 219, 224).

## Other jurisdictions

Delaware LLC law, Cayman corporate / SPC regimes, BVI corporate law,
English corporate law (Companies Act 2006), and various partnership /
fund statutes all accommodate the protocol's constitutional designation
pattern. See [Legal mappings](legal-mappings.md).

## What is *not* in scope

* Broker-dealer registration analysis for any specific front end. (See SEC
  April 2026 Staff Statement for the UI-provider safe harbour conditions.)
* AIFMD / EU MiCA / specific national private-placement regimes. The
  protocol does not encode these; issuers under those regimes configure
  conditions and agreements to comply.
* Tax. The protocol records what happens; tax treatment of each event is
  an issuer/holder question.

## See also

* [MetaLeX Substack](https://metalex.substack.com/) for the running
  commentary on regulatory developments.
