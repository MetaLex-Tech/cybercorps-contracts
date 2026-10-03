---
description: Your identity, wallets, visibility settings, and notifications
---

# Your profile

Your **profile** (`profile.metalex.tech`) is your MetaLeX identity. It
belongs to your MetaLeX account — which can hold **several linked
wallets** — and stays with you when you switch between them, shared
across all the apps: when a founder reviews your Expression of Interest,
or your name appears on a certificate, it comes from here. The cyberCORPs
app, cyberRAISE, cyberSign and LeXcheX all use the same account card and
menu, so you see the same profile and wallets in each.

A profile is **optional but recommended**. You can also stay anonymous.

## Creating your profile (onboarding)

1. Connect a wallet and **Sign in**. Signing in is free (a signature,
   not a transaction) and creates your MetaLeX account and its profile
   record.
2. Pick a profile picture. If you don't have one yet, the preset
   gallery opens on its own (see [Profile pictures](#profile-pictures)).
3. Enter a **Name** (up to 25 characters) and **Continue**.

Prefer not to? **Stay Anon for now** skips the whole step.

![Profile onboarding](../.gitbook/assets/webapp/profile-onboarding.png)

If you were onboarded as a stakeholder through a company's invitation
link, your name pre-fills from the stakeholder record — and starts visible
only to companies you hold with, until you choose to make it public.

## Your profile page

Your profile page (*Account Profile*) is a public-facing card showing your
picture, name, bio, social links, your **LeXcheX accreditation status**,
and your **MetaLeX account addresses** — every wallet linked to the
account, plus any multisigs. If you are a founder, your founder title (e.g. “Founder of …”)
is derived from your cyberCORPs onchain and shown automatically. Your own
profile also shows a public **platform activity** card — your cyberCORPs
and how long you've been cybernetic if you're a founder, your closed
investments if you're an investor.

To edit it, sign in (**auth to edit profile**), then open the edit form:

* **Your PFP**: **Upload picture**, **Choose MetaLeX Pfp** from the
  preset gallery, or **Import Your X Pfp** (**Use X Pfp** once your X
  account is connected).
* **Profile identity**: your **Display Name** (up to 25 characters) and
  bio. Others on MetaLeX see the display name as far as your visibility
  setting allows. A nickname or pseudonym is fine, and it doesn't have to
  match the legal name you use to form a company.
* **Private formation details**: your legal first and last name, phone
  number, country of residence and mailing address, for when you act as
  a company's responsible party. These are owner-only and never shown to
  profile visitors. They are copied into a
  [formation request](mainframe.md#what-the-form-asks-for) only when you
  choose **Reuse profile details** there. If you stay linked as the
  company's first public officer, your legal name also fills that
  officer's onchain record, which is permanently public; you can review
  it before publishing.
* **Accreditation**: shows your LeXcheX status, with a link out to
  [LeXcheX](lexchex.md) to get accredited. Until you are accredited, public
  rounds are not open to you. Once accredited, this section shows a
  validity countdown with **view certificate** and **renew certificate**
  links.
* **Socials**: **Verify X Account** through X's own sign-in, and
  **Verify Telegram Account** through the Telegram login widget. If
  verification fails, the form tells you why, for example that the X
  account is already linked to another MetaLeX account, that X declined
  the authorization, or “X verification isn't available here” when X
  sign-in isn't enabled. This is also where you can **enable Telegram
  notifications** (below).
* **Additional Details**: website and additional info.
* **Privacy**: name, socials, website, and additional info each carry a
  visibility control with four settings: public, private, viewable to all
  founders, or viewable to connected founders only. (Your picture and bio
  are always public.)

Saving your profile is a plain save — no transaction, no gas. The public
profile and the private formation details save separately; if only one
of them saves, the form says which and keeps your edits.

### Profile pictures

The preset gallery (*Pick a PFP that fits your role and style*) has more
than 80 pictures, most of them LeXbot designs (LeXbot is the MetaLeX
mascot), kept together by theme: Ethereum, Solana, Zcash, Bitcoin,
MetaDAO and others. Any account can use any preset; none is reserved
for one person. Clicking a picture opens an enlarged preview. Step
through the gallery with the arrows (or your arrow keys), then choose
**Use this PFP**, or **Keep this PFP** if it is already yours. Closing
the preview returns you to the gallery without changing anything.

## Wallets and your account

Your profile belongs to your account, not to a wallet. The wallet you
have **active** is the one that signs and sends transactions; switching
it never changes which profile you are signed into. The account card in
the header shows both: the signed-in profile, and the active wallet. If
the active wallet isn't linked to your profile, a **!** marker on the
card says so.

Clicking the card opens the account menu: **Profile**, **Wallet
Settings**, the wallets connected in this browser (click one to make it
active), **Link another wallet**, and **Sign out**. In the cyberCORPs
app and cyberRAISE the menu also has **Your Multisigs**, **Delegation
Settings**, **My grants** and **My formation orders**. From cyberSign
and LeXcheX, **Profile** and **Wallet Settings** open the profile app in
a new tab.

### Linking a wallet

**Link another wallet** asks you to connect a wallet and sign a short
authorization message with it. Selecting a connected wallet that isn't
linked yet (**Authorize** on its Wallet Settings row) shows your profile
and the wallets already on it, and **Link wallet** asks for the same
signature. The signature is free, single-use, and expires after a few
minutes; a wallet already authorized for your profile isn't asked again.
Because the wallet itself has to sign, a smart-contract wallet such as a
Safe can't be linked this way. To act for a Safe, use
[Delegation](#delegation).

A wallet that already belongs to a different MetaLeX profile can't be
linked to yours, and profiles are never merged. If your sign-in has
picked up such a wallet, a **Wallet link needs attention** notice explains
that it can't authorize payments or account changes for this account.
If the other profile is yours, unlink the wallet in Wallet Settings,
then use **Sign in with …** to sign in with that wallet and reach that
profile (**Stay on this account** keeps you where you are). If it isn't
yours, or it is the only wallet on the account, contact support.

**Profiles from before MetaLeX accounts.** If a wallet you sign in or
link with carries a profile created before accounts existed, and no
other account has claimed it, that profile is recovered into your
account automatically, and your earlier profile and its history become
available (linking the wallet shows **Profile recovered**). Once you
have unlinked a wallet from your account, this automatic recovery no
longer applies.

Until you dismiss it, an **Authorize your wallets** prompt may point you
to Wallet Settings to choose the wallets for your profile and sign a
fresh authorization for each. **Later** dismisses it; your existing
profiles and their records are unchanged either way.

### Wallet Settings

**Wallet Settings** (in the account menu) lists your **Linked Wallets**,
the active one first, and any **Unlinked Wallets** connected in this
browser, with **Link another wallet** at the bottom. Each row is labeled
with the wallet's type and status, for example *active · profile
linked*. *not connected* marks a linked wallet that isn't connected in
this browser; *login linked · profile unverified* marks a wallet your
sign-in knows about but your profile hasn't authorized, and **Authorize**
adds it; *another profile* marks a wallet that belongs to a different
profile.

A linked wallet can be unlinked only when at least one other linked
wallet remains on the account. An *embedded* wallet created by MetaLeX
as part of your profile can't be unlinked. Unlinking takes effect at
once: the wallet stops giving this account access to company
workspaces, private documents and Safe-owner permissions. If it was the
active wallet, another connected linked wallet becomes active. Linking
it again needs a fresh authorization signature.

When the active wallet is your embedded wallet, Wallet Settings also
shows **Embedded wallet confirmation prompts**: you choose whether
transactions and signatures skip the confirmation popup. The wallet
still signs in your browser with your key; only the popup is hidden.

## Notifications

MetaLeX notifications arrive over **Telegram**. In the profile's Socials
section, **Enable notifications** opens a private chat with the MetaLeX
bot; once started, the bot messages you about your offers, deals, and
investments — offers submitted/accepted/rejected, deals ready to sign or
finalized, certificates assigned or transferred, agreements ready and
fully signed, rounds closing — each with a link straight to the relevant
page. In the chat, `/status` shows your subscription and `/stop` ends it.

Inside the apps, notification counters also appear on the cyberRAISE
sidebar (on **Portfolio** for investors, **Raise** for founders with
pending EOIs).

## Delegation

The **delegation** page is for people who sign on behalf of a **Safe
multisig**. Collecting multisig signatures for every legal agreement is
slow, so delegation lets a Safe grant agreement-signing authority to a
single wallet.

To set it up: pick the chain, enter your Safe address (it must be a
multisig that lists you as an owner), and set an expiry date (it defaults
to about six months out). **Sign delegation** proposes a Safe transaction —
you then complete it from your Safe's own interface, where your co-signers
approve it.

After that, the delegated wallet can sign cyberAgreements on the Safe's
behalf until the delegation expires.

> **Under the hood.** Delegation registers the delegate against the
> protocol's agreement layer, so a signature from the delegate counts as a
> signature from the Safe when executing a cyberAgreement. Background:
> [CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md)
> and [Sign a cyberAgreement](../how-to/sign-a-cyberagreement.md).

## Good to know

* Your profile follows your **account**, not a single wallet: act from
  any of your linked wallets and it's still you. A wallet that isn't
  linked to your account has its own (or no) profile — link it in
  Wallet Settings. (One exception is wallet-bound by design: the LeXcheX
  credential itself lives in the wallet that holds it — see
  [LeXcheX](lexchex.md).)
* **Company access follows your profile too.** If any wallet linked to
  your profile is an owner of a company, you can open and work in that
  company's workspace while another linked wallet is active, or with no
  wallet connected. Signatures and transactions for the company still
  need an authorized wallet on the company's network. When the active
  wallet isn't one, the app says “Your profile has access to this
  company. Company signatures still require an authorized wallet and
  network.”, names the wallets to use, and offers **Switch to …** and
  **Connect signing wallet**. Access is checked against the chain again
  as you work, so it ends when the wallet loses its role or you unlink
  it.
* In cyberSign, the other parties to an agreement see your picture and,
  if it is public, your name; a name visible only to founders stays
  hidden there. cyberSign fills your name into an agreement only from a
  public profile name, and you can edit or clear it before signing.
* Verifying socials and accreditation builds trust with founders reviewing
  your investments — worthwhile if you intend to invest in founder-approval
  rounds. Founder profiles without any verified social carry a “no verified
  socials” warning for investors.
