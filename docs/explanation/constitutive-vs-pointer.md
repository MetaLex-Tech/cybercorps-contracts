---
description: >-
  Why a cyberCORP's onchain records can be its legal securities ledger, and
  what the company's governing documents must say for that to be true.
---

# Constitutive vs. pointer tokenization

Most tokenized securities are pointer tokens. The record that legally
controls who owns what sits with a transfer agent, on Carta or in a law
firm's files, and the token refers to it. Moving a pointer token asks
whoever keeps that record to update it, and the issuer or its agents may
decline. Take the chain away and the legal position does not change.

cyberCORPs is built for constitutive tokenization, in which the onchain
records are the securities ledger and changing onchain state is the legal
change itself. For the securities this covers, the chain and the legal
record cannot drift apart, because there is no offchain copy of the register
to reconcile and no transfer agent to instruct.

## The governing documents decide which record is the ledger

Whether the chain is a company's securities ledger is settled by its
governing documents: the certificate of incorporation and bylaws, an
operating agreement, articles of association, a partnership agreement, or a
fund's constitutional documents. They can designate the protocol's contracts
as the official register for some or all of the company's securities.
Tokenized units and onchain data do not settle the question on their own.
Without a designation, Ledger Entry Tokens (LETs) record the same facts, but
the legal record is wherever the documents put it. A company brought onchain
from Carta, Pulley or a spreadsheet usually keeps its securities ledger where
it was, and the app's [cap table](../webapp/captable.md) tracks it.

The MetaLeX-form bylaws of Delaware corporations formed through the
cyberCORPs app show what a designation looks like. Shares are uncertificated
unless the board decides otherwise. The board designates which classes or
series are Tokenized Shares, and the smart contracts that record them, with
their state and event logs, become the stock ledger for those shares. Any other shares stay on an offchain
stock ledger, and the two parts together form the corporation's stock ledger
under DGCL §§219 and 224. Record ownership of a Tokenized Share changes only
through an operation of the onchain system: editing a LET's metadata,
minting or voiding a LET, or minting or burning scrip tied to a LET. Moving
a token from one address to another changes nothing by itself.

## Corporate law permits the designation

Delaware has the most fully worked-out basis. DGCL §224 lets a corporation
keep its records, the stock ledger included, on electronic networks or
databases, distributed ones among them, provided the records can be
converted into clearly legible paper form and carry the information other
sections require. §158 permits uncertificated shares, §202 governs how
transfer restrictions are noted, §155 authorizes scrip, and §219 draws the
stockholder list from the stock ledger. The
[legal mappings](legal-mappings.md) page sets out each provision against the
protocol object that uses it.

Delaware LLC law, Cayman corporate and SPC regimes, BVI corporate law,
English company law and partnership and fund statutes reach the same result
through comparable provisions or through the entity's own contracts. The
protocol assumes no particular statute. It needs only a governing law that
lets the entity's documents designate the onchain register as authoritative,
and the `CyberCorp` contract records the entity type and jurisdiction as
configuration.

## A LET is the holder's entry in the official record

Where the designation exists, a LET is the holder's interest as the
company's official records show it, and the register for those securities
can be read straight from the chain. An auditor, a regulator or a court can
ask the chain who the holders of record are and get the legal answer. Scrip,
the fungible form, relates to that register differently, and
[Ledger Entry Tokens and scrip](lets-and-scrip.md) explains how.

## Further reading

* MetaLeX, ["What Is Slop Tokenization and Why Is It Bad?"](https://metalex.substack.com/)
* MetaLeX, ["5 Ways of Tokenizing Securities (& One Which Is Best)"](https://x.com/lex_node/status/2030322576208068616)
* SEC staff, [statement on tokenized securities](https://www.sec.gov/newsroom/speeches-statements/corp-fin-statement-tokenized-securities-012826) (January 2026)
