---
description: Choose public, private, email, offchain or mixed signing and track the evidence each flow produces
---

# cyberSign

**cyberSign**, at [app.metalex.tech/cybersign](https://app.metalex.tech/cybersign),
creates signing requests, collects signatures and keeps their evidence.
Onchain agreements use the
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).
Fully offchain requests complete without a registry transaction. The
execution policy shown before signing determines which evidence is required.

The creation page, agreement pages, invitation pages and **Contract Library**
serve different parts of that process. Company documents also open cyberSign
from the cyberCORPs app and [boardRoom](boardroom.md). See
[Formation packets](formation-packets.md) for the coordinated founder workflow.

## Choose the signing flow

After authentication, the creation page offers the modes enabled for your
account and network:

| Choice | What it does |
| --- | --- |
| **Public document / email signing** | Creates an ordinary public registry agreement, with wallet or supported email signing. |
| **Signing request · private or public PDF** | Creates a managed request with an explicitly selected document privacy mode and assigned parties. |
| **Offchain signing · no blockchain** | Collects authenticated email acceptance or wallet message signatures without publishing an agreement onchain. This form also offers mixed execution where enabled. |

A company-scoped request uses the company workflow and its owner checks.
Choosing a company as record owner does not make it a signing party or prove
a signer's authority to represent it. Network availability, sponsorship and
email delivery are checked separately. An option that is absent or refused
is not enabled merely because another cyberSign mode supports it.

## Review a request before signing

Open the assigned link and authenticate as the intended recipient. Check the
PDF, title, party list, capacities, field values, deadline, document privacy
and execution policy. For an onchain request, also check the network and the
wallet assigned to your party. A private invitation link gives access only
after the recipient checks succeed; possession of the link is not signing
authority.

Public registry agreement links have the form
`/cybersign/<chain id>/<agreement id>`. Managed requests use request routes;
fully offchain requests use `/cybersign/offchain/<request id>`. Keep the link
the app provides rather than constructing another route from an id.

A password-protected public PDF asks for its password in the viewer. The
sender supplies that password outside the app. A private PDF uses the
request's authenticated viewer. Neither arrangement hides fields published
onchain: wallet addresses and signing capacities can remain public even
when the PDF is private.

## Sign with a wallet

For ordinary onchain signing, select your signature block and approve the
free typed-data signature. Then choose **Sign Agreement** and approve the
transaction. Changing signed field values requires a new signature. A
Terms of Service acceptance or network switch can precede submission.

The registry verifies the EIP-712 signature against the agreement, party,
document URI and field values. The app checks the target registry and its
supported signature format again before submission. Unknown runtimes or a
changed target refuse rather than silently choosing another format.

A supported delegated party can sign through its authorized delegate. The
app checks the delegation and expiry; agreements with a finalizer can also
restrict who submits. Delegated signing is not enabled for the older zkSync
signature format, which cannot bind the signature to its principal in the
same way. See [delegation](profile.md#delegate-signing-for-a-safe).

An ordinary agreement with no finalizer completes when its last party
signs. An agreement with a finalizer can be fully signed while still
awaiting another condition. The app refuses expired, voided or completed
agreements and reports the applicable status.

### Open slots

An ordinary public agreement can leave a party address blank. An eligible
wallet can claim that open slot and enter its own party values. Named party
values are fixed by the request. The app refuses secret-gated open-slot
signing because submitting that secret publicly would expose it.
Creator-bound and passport-gated agreements require named parties.

## Email signing onchain

An email party opens an authenticated invitation and completes the assigned
signing flow. For onchain email signing, the app prepares an embedded wallet
and binds it to the party. This differs from fully offchain email acceptance:
the resulting agreement still requires registry recording.

The sender completes the preparation and creator-signing steps shown in the
request. Collected signatures can still await recording and chain finality.
Follow the request's status rather than treating an accepted invitation or
an offchain signature as a completed onchain agreement. Where sponsorship is
offered, review its credit and gas limits; otherwise the submitting wallet
needs funds for the network fee.

For supported requests, MetaLeX can deliver invitations, reminders and
resends and show delivery status. Delivery depends on the request family
and its configured email service. A copied link remains useful when delivery
is unavailable. Do not assume a message was sent until its delivery status
confirms it. Stakeholder invitations in the cap table are a separate flow.

## Fully offchain and mixed execution

A fully offchain request fixes the document and execution policy before
signatures. Parties use **Email (one-time code)** or an external-wallet
message signature. Email parties do not need a wallet or gas. The request
records evidence and offers a completion certificate and evidence bundle.
A wallet message signature in this mode remains offchain.

For mixed execution, every party signs offchain first. The sender then
registers a separate onchain agreement containing the selected recording
parties. Each recording party uses its own external wallet for a second,
separately consented signature. Completion requires those recordings to
become final within the recording window. Missing that window does not
silently turn the request into a fully offchain completion.

Fully offchain completion, or a mixed agreement containing only the recording
parties, cannot satisfy a protocol flow that requires an onchain agreement
signed by every party, such as an issuance or escrow condition.

Company owners can create and administer company-owned offchain requests,
including mixed execution, through the enabled company selector. Authority
to administer the request is distinct from the capacity in which each party
signs. Offchain invitation delivery has a separate enablement switch from
onchain email delivery.

## Passport requirements

Where available, the sender can require passport evidence for selected
named parties. The app binds the proof to the party, network and agreement.
The [ZKPassportFinalizer](../reference/contracts/ZKPassportFinalizer.md)
requires both signatures and the specified passport evidence before
finalization. A passport check is not a substitute for reviewing the
agreement or proving authority to sign for a company.

## Create and share the document

For an ordinary public agreement, choose the network, title, PDF, deadline,
parties and any global or party fields. Uploaded public PDFs go to IPFS.
Review the publication acknowledgment before upload. Encrypt a sensitive
public PDF before publication, or choose the private-request flow.
A mutable external URL can change its content; an immutable document
reference gives signers a stable version to review.

Review the full request before the first signature. The ordinary wallet
path creates and signs through `createStandaloneContractAndSignFor`;
managed requests can prepare an unsigned agreement first. Eligible formation
packets can use creator-bound creation. Each path preserves its own request
identity, correction rules and registration status. A draft edit must not
silently change the document another party has signed.

## Find records and download evidence

The **Contract Library** combines registry agreements, managed signing
requests, LET-related records and stored company documents. Sign in to see
private records available to your account. Search and source filters help
find the request; use its own page for signer, recording and finality status.

A stored company file or LET record does not prove that its associated
agreement was signed. Completed supported requests offer an evidence bundle
and completion certificate. Where offered, a **conformed executed copy**
combines the document with its signature evidence; it is a generated copy
and does not alter the signed source PDF or registry record.

For contract-level creation, delegation and voiding, see
[Sign a cyberAgreement](../how-to/sign-a-cyberagreement.md). The
[October 27 source review](../reference/documentation-status.md) identifies
the app revision reviewed and features whose publication or enablement needs
separate verification.
