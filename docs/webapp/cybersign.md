---
description: Propose, review, sign and countersign agreements in MetaLeX's standalone signing app
---

# cyberSign — sign agreements

**cyberSign** is MetaLeX's standalone signing app, part of the main
MetaLeX app at `app.metalex.tech/cybersign`. Anyone with a wallet can
propose an agreement around a PDF and collect signatures from the other
parties, and each signature is recorded onchain in the
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).
The [cyberCORPs app](mainframe.md) opens cyberSign from its sidebar
(**cyberSign**), and the board consents and governance documents created
in the [boardRoom](boardroom.md) give each remaining signer a cyberSign
link.

cyberSign has three pages:

| Page | Address | What you do there |
|---|---|---|
| **New agreement** | `app.metalex.tech/cybersign/create` | Propose an agreement. Opening `/cybersign` lands here. |
| **Agreement page** | `app.metalex.tech/cybersign/<chain id>/<agreement id>` | Review the document and its terms, and sign. This is the link you share. |
| **Contract Library** | `app.metalex.tech/cybersign/library` | Find the agreements and documents tied to your wallet. |

---

## Signing an agreement you were sent

Open the link. The agreement's onchain terms are on the left under
**Agreement Details**; the document is on the right, with a signing bar
beneath it. If no wallet is connected, the bar offers **Connect Wallet**.

### Reviewing the terms

The left pane shows, top to bottom:

* **Network** is the chain the agreement lives on. You sign on that
  network, and your wallet is asked to switch to it if needed.
* **Agreement expiry** is the deadline for signatures, shown as a date
  with an **ends in** countdown, or as **No expiry** when the agreement
  has no deadline. The row disappears once the agreement is complete or
  voided.
* **Contract Details** lists the agreement's global fields: name/value
  pairs the proposer chose to record onchain, such as key business
  terms.
* **Party #1 Details**, **Party #2 Details** and so on give each party's
  wallet address in full (so you can check every character), the
  **MetaLeX profile** behind that wallet when it has one, and the
  party's own fields, by default a name and a contract role.

The document opens in your browser's built-in PDF viewer. If the
proposer password-protected the PDF, the viewer asks for the password;
the proposer gives it to you outside cyberSign, and MetaLeX never has
it.

### Signing: a free signature, then one transaction

1. In the signing bar, each party has a signature block labeled with its
   address, and unsigned blocks read **click to sign**. Yours is the
   highlighted one. Click it.
   Your wallet shows the agreement data you are consenting to (see
   [What you sign](#what-you-sign)) and asks for a signature, which
   costs nothing.
2. **Sign Agreement** becomes active. Click it and confirm the
   transaction in your wallet. It records your signature in the registry
   and costs gas on the agreement's network.

If the wallet hasn't accepted the current MetaLeX Terms of Service, a
**Terms of Service** dialog appears before the transaction. **I Accept**
records the acceptance for that wallet (a wallet that isn't signed in is
first asked for a free sign-in signature), and the dialog returns only
when the Terms change.

When the transaction confirms, an **Agreement signed** notice appears and
your block reads **cyberSigned by** with your name. Editing one of your
fields after step 1 discards the signature, because it covers the exact
values; sign again.

### Open slots

A proposer can leave a party's address blank. That party is an open
slot, and any wallet not already named in the agreement can take it by
signing. When you take a slot, its fields are yours to fill in. **Name**
starts from your public MetaLeX profile name, with a note that you can
edit or clear it before signing because it will be recorded onchain. The
values you enter are part of what you sign.

A named party's fields were set by the proposer and can't be edited; you
sign them as they stand.

### Deadlines and closed agreements

Once the deadline passes, the registry refuses new signatures, and any
single party can void the unfinished agreement (see
[Voiding](../how-to/sign-a-cyberagreement.md#voiding)). An agreement with
**No expiry** never lapses this way.

The agreement page doesn't label a voided agreement. If you're unsure,
check its status in your [Contract Library](#your-contract-library). The
registry also refuses a signature on a voided or already complete
agreement, so such a transaction fails and records nothing.

An agreement proposed in cyberSign completes with its last signature:
every block reads **cyberSigned by** and the **Sign Agreement** button
goes away.

---

## Proposing an agreement

Open cyberSign and sign in with **Connect Wallet** at the top right.
Signing in matters here: it fills Party 1 with your wallet, and uploading
a PDF requires it. The form is titled **Agreement Details**; once it has
a document, a preview of the PDF and the signing bar appear beside it.

### Network, title, document and deadline

* **Network** sets where the agreement lives: Ethereum (the default),
  Arbitrum or Base. Every party signs there and pays its own gas.
* **Title of Legal Contract** (for example "Stock Purchase Agreement")
  is recorded onchain.
* **Paste a link to your document, or upload it** takes either a link
  to a PDF or an upload. An upload goes to public IPFS and fills in the
  link.
  * A PDF that already has a password shows **Document password
    protected** and uploads as is.
  * Otherwise the form shows **Document not password protected** and
    offers a **New Password** with **Encrypt with AES-256 and upload**,
    which encrypts the PDF in your browser before uploading it, or
    **Upload without password**, which publishes the readable PDF. Send
    the password to the other parties yourself.
* **Latest Date/Time Agreement Can Be Signed** is the deadline, in your
  local time. It defaults to 30 days out and can't be left empty.

### Parties and fields

Under **Parties to the Legal Contract**, each party has a **blockchain
address** (the wallet that will sign) and optional **Name** and
**Contract Role** fields. An address with a MetaLeX profile shows its
profile chip, so you can confirm who it belongs to. Leave an address
blank and the party becomes an **Open slot** that any wallet can claim
by signing. **+ add party**, **Remove Party**, **+ add additional fields
relating to this Party** and **Remove field** shape the list. Party 1 is
the proposer and needs a real address.

The form warns that everything entered here is recorded onchain. For
privacy, give a party's address alone, or a pseudonym as its name.

**Global Fields** (optional) are name/value pairs about the whole
agreement that every signer attests to: business terms you want readable
without opening the PDF, or values the document text refers to.

### Sign and create

Once the title, document and deadline are set, click **click to sign** on
your block in the signing bar and sign the free message. The button then
reads **Create Agreement**. Click it and confirm the transaction, which
creates the agreement and records your signature in one step. An
**Agreement proposed** notice appears and the app opens the new agreement
page.

Copy that page's address and send it to the other parties yourself. A
one-party agreement is complete as soon as it's created.

Changing anything in the form after you sign the message discards the
signature. The draft survives moving between cyberSign pages in the same
tab (to **← My Contract Library** and back, say), is never written to
browser storage, and is cleared when you reload, sign out or switch
accounts.

If Party 1's wallet has delegated agreement signing to your wallet (see
[Delegation](profile.md#delegation)), you can enter that address as
Party 1 and sign for it; the registry records Party 1 as the signer.

---

## Your Contract Library

The **Contract Library** (`/cybersign/library`, or **← My Contract
Library** on the new-agreement form) lists the agreements and documents
tied to the connected wallet, newest first, with **New agreement** to
start another. Each row has a source tag, the parties, a date and a
status, plus **PDF** (the document) and **Open** (the agreement page)
where they apply.

| Source tag | What it lists | Statuses |
|---|---|---|
| **cyberSign** | Registry agreements that name your wallet as a party, on Ethereum, Arbitrum, Base and zkSync Era | **Pending**, **Signed**, **Expired**, **Voided** |
| **Tokenization Hub** | Certificates your wallet holds. **Open** goes to the agreement the certificate was issued under, when it has one. | **Recorded**, **Voided** |
| **cyberRaise**, **Formation**, **Cap Table** | Files the cyberCORPs and cyberRAISE apps store (pitch decks, formation documents, cap-table grant documents) for companies where your wallet is a founder or investor | **Signature not verified** |

**Recorded** and **Signature not verified** describe what the library
can prove: a certificate record or a stored file is not evidence that
anyone signed. Private cap-table grant documents appear only after you
**Sign in** from the banner at the top. Source chips filter the list
when more than one source has entries, and the search box matches
titles, document types, company names and party names.

---

## What you sign

Every signature in cyberSign is an EIP-712 typed-data message addressed
to the registry: domain `CyberAgreementRegistry`, version `1`, on the
agreement's chain and registry address. The message (`SignatureData`)
contains:

* the agreement id (`contractId`);
* the party you are signing for (`signer`), on registries that include
  it;
* the document link (`legalContractUri`);
* the global field names and values;
* the party field names and your values.

Before your wallet prompts, cyberSign reads the registry's signature
format and builds the matching message. The registry on Ethereum, Base
and Arbitrum includes `signer`; the older zkSync Era registry uses the
format without it. cyberSign refuses a registry whose format it doesn't
recognize. Before sending the transaction it checks that the network,
registry and format still match your signature, and asks you to sign
again if they don't.

> **Under the hood.** Proposing calls `createStandaloneContractAndSignFor`,
> which creates the template (if new) and the agreement, with no
> finalizer, and records your signature in one transaction. Countersigning
> calls `signContract`. On Ethereum, Base and Arbitrum the registry is the
> proxy `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`. Templates, open
> slots, voiding and delegation at the contract level are covered in
> [Sign a cyberAgreement](../how-to/sign-a-cyberagreement.md) and the
> [CyberAgreementRegistry reference](../reference/contracts/CyberAgreementRegistry.md).

## Good to know

* **Agreements are public unless you encrypt the PDF.** An uploaded PDF
  sits on public IPFS, and the title, deadline, party addresses and every
  field value are onchain for anyone to read. Password protection keeps
  the document text private; the onchain fields stay public.
* **Which steps cost gas.** Clicking a signature block is a free message
  signature. **Create Agreement** and **Sign Agreement** are
  transactions.
* **You deliver the links.** cyberSign doesn't email anyone. Parties who
  turned on [Telegram notifications](profile.md#notifications) get a
  message when an agreement naming them is created, signed, fully signed
  or voided, with an **Open agreement** link.
* **There is no void button.** A party requests a void from the registry
  directly; see [Voiding](../how-to/sign-a-cyberagreement.md#voiding).
* **A delegate can propose but not countersign.** A delegate wallet can
  create an agreement for the party that delegated to it, but the
  agreement page can't submit a delegate's signature on an existing
  agreement: the transaction is rejected. Countersign from the party's
  own wallet.
