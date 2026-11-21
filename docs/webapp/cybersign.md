---
description: Send a document for signature by wallet or email, choose how the signatures are recorded, and track the evidence each request produces
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

## Send a document for signature

Open **Create** in cyberSign, or choose **New agreement** in the
**Contract Library** or the inbox. If the page asks you to sign in or to
connect a wallet linked to your profile, use the button it shows or the
account button at the top right.

The page **Send a document for signature** is one column with these
sections, in this order:

1. **Document.** Choose the exact PDF to sign (up to 2 MiB), or write or
   import a document and review its final PDF. Enter the **Document title**.
2. **Signers.** **I am also signing this document** makes your wallet the
   first signer. Each signer has one field for an email or wallet address
   and a **Signing capacity**. The app reads the kind of signer from the
   value: an address with `@` is an email signer, and `0x` followed by 40
   hexadecimal characters is a wallet signer. ENS names are not accepted.
   **More** on a signer holds only the options that apply to that signer,
   such as a passport requirement, a name, an approval role or onchain
   recording. **Add a signer** adds a row, up to eight signers.
3. **How people sign.** Choose one answer:
   - **Wallets, recorded onchain** is preselected. Each signature is
     recorded in the agreement registry on the network shown under the
     answer, for example "Network: Base", with **Change** to choose
     another network.
   - **Email or wallet, no blockchain.** MetaLeX keeps the signatures,
     their evidence and a signing certificate. An email signer needs no
     wallet, gas or network.

   **What this means** states the consequences of the selected answer,
   including what is public onchain.
4. **Sign by.** One deadline. A request recorded onchain allows up to 30
   days less five minutes, and at least one day when the request collects
   email signatures or passport proofs. A request with no blockchain allows one hour to 30
   days.
5. **Options**, closed by default. Its summary line names what is in
   effect, for example "From my account · Private PDF". Inside are
   **Send as** and the options of the selected answer. For an onchain
   record: a private PDF or a public PDF on IPFS (with an optional password), open
   slots for a public PDF, and company sponsorship. With no blockchain:
   onchain recording by some signers (mixed execution) and approval
   routing.

Choose **Review**. The review shows the exact PDF and its SHA-256
fingerprint, the title, the signers, the answer to **How people sign**,
the network, the cost, the deadline, the options and the consents that
the answer requires. For a request with no blockchain it also has
**Email the invitations when I send this request**. Choose
**Send for signature** to create the request. The answer cannot change
on the review: choose **Back to editing** to change it or any other
input. A change after the review discards the review.

### Send as a company

**Create a signing request in cyberSign** in a company workspace opens
the page with that company as the sender, on the company's network, for
both answers. **Email or wallet, no blockchain** can be chosen where
cyberSign offers company requests with no blockchain on that network;
elsewhere it is shown disabled, with the reason under it. **Send as**
also offers your own account and another company you own, entered by its
contract address.

Your connected wallet must hold the company's current owner role on that
network, or creation is refused. Choosing a company as the sender does
not make it a signing party or prove a signer's authority to represent
it. Network availability, sponsorship and email delivery are checked
separately. An option that is absent or refused is not enabled because
the other answer supports it.

### Other ways to create a request

- **Correct and send a new version** on an open request with no
  blockchain opens the same form on the request page, with the request's
  parties and policy. Every party signs the new version again.
- **Prepare in cyberSign** in a company's formation packets opens packet
  preparation. See [Formation packets](formation-packets.md).
- [boardRoom](boardroom.md) governance documents use their own form with
  named governance signers.

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

New public requests use creator-bound creation when every party is named
and distinct and the registry is reviewed for that method. A request with
an open slot still uses ordinary standalone creation. Existing agreements
keep their original creation method and identifier.

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
signatures. Parties use **Verified email** (a one-time code or, for a
Gmail address, a Google sign-in) or an external-wallet message signature. Email parties do not need a wallet or gas. The request
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
Current creator-bound agreements use registry
[signer conditions](../reference/contracts/SignerConditions.md). A gated
party supplies its proof together with an evidence-bound signature. The
last required signature finalizes the agreement automatically. The older
[ZKPassportFinalizer](../reference/contracts/ZKPassportFinalizer.md) is a
historical integration, removed from current contract source. A passport
check is not a substitute for reviewing the agreement or proving authority
to sign for a company.

The current app refuses requests stored under the retired finalizer flow.
An unfinished request needs a new signing request; it cannot be completed
by opening its old app link. Already completed agreements remain recorded
onchain with their original identities.

## How a request is created onchain

A public PDF, chosen under **Options**, goes to IPFS after you accept the
publication acknowledgment on the review. Protect a sensitive public PDF
with a password, or keep the PDF private. The form takes an uploaded or
composed PDF, not a link, so signers review a fixed version.

Review the full request before the first signature. The public wallet
path uses `createBoundContractAndSignFor` for qualifying named, distinct
parties on a compatible registry, or `createStandaloneContractAndSignFor`
for an ordinary request such as one with open slots. Managed requests can
prepare an unsigned agreement first; eligible formation packets also use
creator-bound creation. Passport-gated requests batch creator-bound
registration and evidence signing as described above. Each path preserves
its own request identity,
correction rules and registration status. A draft edit must not silently
change the document another party has signed.

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
[dated source review](../reference/documentation-status.md) identifies
the app revision reviewed and features whose publication or enablement needs
separate verification.
