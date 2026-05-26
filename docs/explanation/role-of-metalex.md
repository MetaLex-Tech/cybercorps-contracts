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
* Maintains agreement templates.
* Operates LeXcheX (an oracle), so MetaLeX or a delegate signs accreditation
  attestations into the credential registry.
* Runs the reference UIs (the cyberCORPs Mainframe, ACE, LeXcheX onboarding,
  the landing page) — *as one possible front end*. Anyone can build their
  own.

## What MetaLeX does *not* do

* Hold issuer custody. Funds in flight are in `LeXscroWLite`, which has no
  admin keys. MetaLeX cannot move them.
* Hold issuer admin keys. Each cyberCORP's BorgAuth roles are owned by the
  issuer's governance addresses (board / officer multisigs). MetaLeX is not
  on the list.
* Force upgrades. The co-approval upgrade model requires the issuer's
  `UPGRADE_AUTHORITY` to opt in. MetaLeX cannot push an upgrade. (See
  [co-approval upgradeability](co-approval-upgradeability.md).)
* Approve trades. The issuer's `OFFICER_AUTHORITY` approves deals; MetaLeX
  is not in that loop.
* Maintain a separate offchain register. There is no offchain register.

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
