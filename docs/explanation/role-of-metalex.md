# The role of MetaLeX

A tokenised-securities system designed badly turns the issuing platform into
a securities intermediary with admin keys over every issuer's stock ledger.
That is bad legally (the platform becomes a transfer agent / clearing
intermediary, subject to the corresponding regulatory burden) and bad
structurally (the issuer's autonomy is fictional).

cyberCORPs is designed so that MetaLeX is **not** an intermediary.

## What MetaLeX does

* Develops the contracts.
* Publishes new implementations to the factories.
* Sets the platform fees on the factories: a primary rate for rounds and
  deals, a separate rate for secondary trades, and optional per-company
  overrides of either.
* Maintains a library of agreement templates — though template creation on
  the `CyberAgreementRegistry` is permissionless: anyone can register a
  template, and standalone agreements create their own templates
  just-in-time. MetaLeX curates; it does not gatekeep.
* Operates LeXcheX (an oracle), so MetaLeX or a delegate signs accreditation
  attestations into the credential registry.
* Runs the reference UIs (the cyberCORPs app, ACE, LeXcheX onboarding,
  the landing page) — *as one possible front end*. Anyone can build their
  own.

## What MetaLeX does *not* do

* Hold issuer custody. Funds in flight sit in the LeXscroW escrow logic
  embedded in each issuer's own `DealManager` / `RoundManager`, and can only
  move along the deal's own signature, finalization, and expiry paths.
  MetaLeX cannot move them.
* Hold issuer admin keys. Each cyberCORP's BorgAuth roles are held by the
  issuer's officers and governance addresses (board / officer multisigs)
  and by the company's own contracts. No MetaLeX wallet is on the list.
  The one MetaLeX-controlled entry is the factory that deployed the
  company (usually `CyberCorpFactory`), which keeps the `OWNER_ROLE`
  BorgAuth gives its deployer; its current code does not use that role
  after deployment, but the factory is upgradeable by MetaLeX (see
  [co-approval upgradeability](co-approval-upgradeability.md)).
* Force upgrades. The co-approval upgrade model requires an account with
  the company's `OWNER_ROLE` to opt in, and no MetaLeX contract in its
  current code exercises that role to push one.
* Approve trades. Deals are proposed and approved by the issuer's own
  BorgAuth owner and its signing officers; MetaLeX is not in that loop.
* Keep a parallel register for onchain securities. Where a company's
  governing documents designate the onchain register, there is no offchain
  copy to reconcile. The cyberCORPs app's cap table can also hold offchain
  entries for untokenized units; those are app records, and which record is
  the company's securities ledger is a question for its governing
  documents.

## Why this matters

If MetaLeX held admin keys over each issuer's cyberCORP, MetaLeX would be
the transfer agent. That has legal consequences (transfer-agent
registration, intermediary liability) and structural ones ("trustless"
is a lie).

By making MetaLeX a *protocol developer and steward* — publishing
implementations and operating a credential oracle, but never holding
issuer-side authority — the protocol stays neutral, and each cyberCORP's
governance is exactly what its constitutional documents say it is.

## The UI provider question

When MetaLeX (or anyone) runs a front end that helps investors find issuers
(cyberRAISE, LiquiLeX, ACE), it may fall under the SEC's April 2026 Staff
Statement on Covered User Interface Providers (File No. 4-894). The contract
architecture is designed so that whatever a UI provider does at the
web layer, the chain-side state-transition system stays neutral. See
[regulatory context](regulatory-context.md).

## See also

* [Co-approval upgradeability](co-approval-upgradeability.md)
* [Constitutive vs. pointer tokenization](constitutive-vs-pointer.md)
* [Regulatory context](regulatory-context.md)
