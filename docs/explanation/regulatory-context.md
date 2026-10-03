---
description: >-
  The US exemptions and SEC staff statements the protocol is built around,
  and what lies outside it. Not legal advice.
---

# Regulatory context

This page maps, briefly and incompletely, the regulatory backdrop the
protocol is designed for. It is **not legal advice**. Issuers must consult
their own counsel.

## Reg D private placements

Reg D is the standard exemption for unregistered private placements to US
investors, with accreditation requirements under Rule 506(b) and 506(c) and
limits on general solicitation. A company running a Reg D offering on the
protocol checks LeXcheX accreditation credentials with `LexChexCondition`
(`hasValidLexCheX`) at issuance, at deal close and when scrip converts into
a Ledger Entry Token (LET). It signs from Reg D agreement templates such as
`MetaLeX cyberSAFE US style Reg D`. For holder limits it can gate secondary
trades with `HolderCapCondition`, which counts holders on a look-through
basis, watch the onchain holder-count views for the 12(g) threshold, and, on
a v5 company, cap scrip holders on the scrip itself (see
[Restrict scrip transfers](../how-to/restrict-transfers.md)).

## Reg S offerings

Reg S covers offers and sales made outside the United States. The protocol
supports
it through `NonUSNationalityCondition`, which checks a zkPassport proof of
non-US nationality, through Reg S agreement templates, and through LiquiLeX
pools run either whitelisted or open with the matching gate.

## Secondary resales

On a v5 company, a secondary trade settles under an exemption pathway the
buyer elects on accepting the offer: Rule 144, §4(a)(7), §4(a)(1½), Rule
144A or Reg S. Each
pathway has its own conditions for holding periods, disclosure, distribution
compliance, buyer eligibility and jurisdictional screens. Issuers enable only
the pathways they support, and an unconfigured pathway blocks trades.
[Compliance architecture](compliance-architecture.md) describes the
condition sets.

## SEC staff statements

In January 2026 the SEC's Division of Corporation Finance issued a joint
staff statement confirming that the agency's existing framework for
analyzing securities applies to tokenized securities
([statement](https://www.sec.gov/newsroom/speeches-statements/corp-fin-statement-tokenized-securities-012826)).
The protocol is built for that framework, in which a security recorded
onchain is still a security.

In April 2026 SEC staff issued guidance on covered user interface providers
(File No. 4-894), creating a safe harbor for front-end operators that meet
its conditions. It bears on anyone operating a front end that helps
investors find issuers or trade, such as cyberRAISE, cyberTRADE, LiquiLeX or
ACE front ends. The contracts behave the same whichever safe harbor a
front-end operator relies on.

## Corporate law

The protocol depends on corporate and entity law for the designation that
makes the onchain register the legal record. The Delaware General
Corporation Law is the most fully worked-out case. Delaware LLC law, Cayman
corporate and SPC regimes, BVI corporate law, English company law
(Companies Act 2006) and partnership and fund statutes also accommodate the
designation. [Legal mappings](legal-mappings.md) sets out the provisions.

## Outside the protocol's scope

Whether a particular front end needs broker-dealer registration is a
question for its operator, and the April 2026 staff statement sets out the
conditions of its safe harbor. AIFMD, MiCA and national private-placement
regimes are not encoded in the contracts, so issuers subject to them
configure conditions and agreements to comply. Tax treatment is for the
issuer and the holder to work out from the events the protocol records.

## See also

* [MetaLeX on Substack](https://metalex.substack.com/), for commentary on
  regulatory developments.
