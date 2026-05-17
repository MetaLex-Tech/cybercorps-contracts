# ACE — token-community raises

**ACE** (`ace.metalex.tech`) is MetaLeX's fundraising product for token
communities. An ACE raise is a **tokenized SAFE** denominated in a project's
(typically Solana) community token — it lets a token community become equity
holders of the company behind the project.

> **Early access.** The ACE raise area currently sits behind a shared
> access password. This is a launch-phase gate, not an investor check.

## How ACE differs from cyberRAISE

* ACE raises are **always first-come, first-served** and **private** by
  default.
* They are **token-denominated** — priced and funded in a community token,
  not USDC.
* Funding involves bridging that token between Solana and an EVM network.

When you open ACE you choose a role: **Founder** or **Investor**.

## For founders: setting up an ACE raise

1. **SAFE Setup.** Paste your project's **Solana token mint address** — the
   token name, ticker, and image load automatically. Then fill in:
   * **Round terms** — entity valuation, raise cap, min/max investment,
     start date, and an end date (or “open ended”);
   * **Company identity** — company name (pre-filled from the token),
     founder name, contact, company type, jurisdiction, dispute-resolution
     method, current token percentage, and a **payable address** (the EVM
     wallet that receives funds);
   * optional **custom provisions**.
   Drafts are saved automatically and can be shared via a draft link.
2. **Sign.** Sign the agreement preview — two free signatures (one to
   approve the round, one for metadata).
3. **Review the summary** — network, raise cap, ticket range, valuation,
   dates, payable address — then **Confirm & Submit**. This deploys the
   cyberCORP and the round.
4. **Manage the round.** From the round overview you can **invite
   investors** (copy the investor link), **bridge** the token to Solana,
   and — if the round uses non-US gating — **manage zkPassport overrides**.

### zkPassport overrides

If an ACE round restricts investment to non-US persons, founders can
manually approve a verified investor: enter their wallet and add an
override. Each override is an onchain transaction.

## For investors: taking part

1. **Open the round.** The round detail page shows the company, the
   security, the status (open / funded / closed), an elevator pitch, the
   founder's profile, and any resource documents.
2. **Verify eligibility.** If the round is restricted to non-US persons,
   you complete a **zkPassport** verification — a privacy-preserving check
   that proves your eligibility without revealing your identity.
3. **Invest.** The *Invest* flow opens with a notice that you are entering a
   legally binding tokenized SAFE. You provide your name, contact, investor
   type, governing law, and investment amount. Confirming the deal is an
   **onchain transaction**; your funds go into escrow.
4. **Bridge if needed.** ACE rounds are funded in an EVM-wrapped version of
   the Solana token. If your EVM balance is short, an in-page bridge card
   walks you through connecting a **Solana wallet** and bridging — allow
   extra time for the cross-chain confirmations. Standalone
   *bridge to / from Solana* pages are also available.
5. **Track your holdings.** The **My ACE SAFEs** portfolio lists the ACE
   SAFE certificates you hold, across both your wallet and any Safe
   multisig.

## Under the hood

ACE is the cyberCORPs protocol's **ACE / PumpCorp** path. An ACE raise
deploys a cyberCORP configured for a token-to-equity offering and issues
**ACE SAFE** cyberCERTs — a SAFE variant whose security series is `ACE`.
The non-US eligibility check is an onchain **condition** (a zkPassport-backed
`NonUSNationalityCondition`); a founder override writes to that condition
contract.

* Protocol view of the offering type:
  [Deploy a PumpCorp for ACE](../how-to/deploy-pumpcorp-ace.md) and
  [Factories](../reference/factories.md).
* How eligibility gating works:
  [Conditions](../reference/conditions.md) and
  [Compliance architecture](../explanation/compliance-architecture.md).
* What an ACE SAFE is as a security:
  [Security types](../reference/security-types.md).

## Good to know

* **Eligibility is privacy-preserving** — the non-US check proves your
  status without revealing who you are.
* **You're getting a real security** — an ACE SAFE is an actual claim on the
  company, not a points balance or an airdrop.
* **MetaLeX never holds your funds** — the same onchain escrow model as the
  other apps.
* Some ACE features (setting up individual tickets, parts of the bridge UI)
  are still being finished.
