# The cyberCORPs application stack

CyberCORPs is the **protocol**; the **cyberCORPs app** is the
issuer-facing app surface. Several products run on top of the same contract
suite. Each is independently usable. Each has a reference implementation
in the [`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp)
monorepo.

## cyberRAISE

**What it is.** Onchain primary fundraising. Issuers configure rounds with
raise caps, ticket sizes, pricing, payment tokens (typically USDC), security
types (SAFE, SAFT, SAFTE, equity rounds), and round modes (first-come or
founder-approved). Investors submit EIP-712-signed Expressions of Interest,
funds are held by the LeXscroW escrow logic embedded in the round and deal
managers, and close mints the corresponding cyberCERTs.

**Contracts:** [`RoundManager`](../reference/contracts/RoundManager.md),
[`DealManager`](../reference/contracts/DealManager.md),
[`LeXscroWLite`](../reference/contracts/LeXscroWLite.md).

**Reference UI:** the `/cyberraise` route in
[`apps/cybercorps-web/src/app/(frame-layout)/cyberraise`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cyberraise).
MetaLeX's prior SAFE rounds were run through this UI; the resulting SAFE
certificates are visible onchain as cyberCERTs.

## cyberTRADE

**What it is.** Post-negotiation settlement for secondary trades of fund
interests, LLC membership interests, LP units, private company stock, and
other private securities, across US and non-US jurisdictions. Counterparty
discovery and bilateral negotiation happen wherever they happen; cyberTRADE
handles compliance verification, agreement execution, escrow, and atomic
settlement.

**Two settlement paths:**

* **Register path** — the DealManager's offer flow. At settlement the
  seller's cyberCERT is reduced (or used up) and a new cyberCERT carrying
  the seller's endorsement is minted to the buyer. The buyer elects an
  exemption pathway (Rule 144, §4(a)(7), §4(a)(1½), Rule 144A, or Reg S),
  and the trade is gated by that pathway's conditions plus the issuer's
  own conditions: holder caps, accreditation, qualified-purchaser status,
  holding periods, jurisdiction screens, and, where the issuer installs
  one, a per-deal approval condition. Settlements pay the DealManager's
  secondary fee, which is set separately from the primary fee on rounds and
  deals.
* **Scrip path** — settlement at the cyberSCRIP layer with deferred
  de-scripification, including the AMM-native variant powered by LiquiLeX.

**Contracts:** [`DealManager`](../reference/contracts/DealManager.md),
[`LeXscroWLite`](../reference/contracts/LeXscroWLite.md),
[`IssuanceManager`](../reference/contracts/IssuanceManager.md),
[`CyberScrip`](../reference/contracts/CyberScrip.md).

## ACE (Asset Conversion to Equity)

**What it is.** A structured Reg-S-compliant offering with zkPassport-based
jurisdictional gating that lets a token community convert into equity
stakeholders of an issuing corporation. Live at
[ace.metalex.tech](https://ace.metalex.tech).

**Contracts:**
[`PumpCorpFactory`](../reference/factories.md#specialised-factories),
[`ACESAFEExtension`](../reference/extensions.md).

**Reference UI:** the `/ace` route in
[`apps/cybercorps-web/src/app/ace`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/ace),
with Solana bridge integrations (`/ace/bridge-to-solana`,
`/ace/bridge-from-solana`).

## LiquiLeX

**What it is.** AMM-native secondary liquidity for cyberSCRIPs. Uniswap v4
pools paired against stablecoins, with the
[`MetalexIssuerFeeHook`](../reference/hooks.md#metalexissuerfeehook)
routing swap fees to MetaLeX and the issuer.

**Two compliance models:** whitelisted pool (full credential check on every
swap) and open pool (compliance gated at de-scripification, optionally with
a lighter zkPassport gate at the swap layer).

## cyberSign

**What it is.** Cybernetic legal-agreement execution. Templates registered
in `CyberAgreementRegistry` — registration is permissionless, and standalone
agreements create their templates just-in-time — parties countersign onchain
via EIP-712, and execution is anchored to cyberCERTs and deal records.
Unbundled from cyberRAISE: usable as a standalone signing layer for any
legal instrument.

**Contracts:**
[`CyberAgreementRegistry`](../reference/contracts/CyberAgreementRegistry.md).

**Reference UI:** the `/cybersign` route in
[`apps/web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/web/src/app/%28frame-layout%29/cybersign);
the cyberCORPs app's **cyberSign** sidebar entry opens it.

## The cyberCORPs app

The issuer-facing app. Once a company is selected, its sidebar holds these
sections (labels as the app shows them):

| Section | What it covers |
|---|---|
| **mission control** | The company dashboard: what needs action now and what changed. |
| **Incorporation Hub** | Company identity, formation progress, and the public company record. |
| **Documents** | The company's documents and its signing workflows. |
| **boardRoom** | Officers, governance documents, and the board multisig. |
| **capTable** | Tokenized and untokenized positions in one cap table. |
| **grants** | Equity awards (options, RSUs, restricted stock) with onchain vesting. |
| **cyberRaise** | The company's raises, or a new one (see cyberRAISE above). |
| **Tokenization Hub** | Configure, issue, and manage tokenized securities: security classes and their cert printers, issuance, scripification, transfer controls, and cert and scrip holder lists. Formerly called the Mainframe. |
| **cyberSign** | Opens cyberSign to sign and countersign the company's agreements. |

The app talks to v4 and v5 companies side by side and chooses each call's
shape from the targeted contract's `DEPLOY_VERSION`; see
[Integrate from a frontend](../how-to/integrate-from-frontend.md#abis-and-versions).

**Reference UI:** the `/cybercorps` route in
[`apps/cybercorps-web/src/app/(frame-layout)/cybercorps`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cybercorps).

## MetaDAO

Futarchy-governed Cayman SPC structure. Each portfolio (SegCo) has its own
futarchy oracle.

**Contracts:**
[`MetaDAOFactory`](../reference/factories.md#specialised-factories).

**Reference UI:** the `/metadao` route in
[`apps/cybercorps-web/src/app/(frame-layout)/metadao`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/metadao).

## LeXcheX

Onchain accreditation / KYC-AML credentials. Soulbound, wallet-bound NFT
certificates, now joined by the unified `LeXcheXBadge` credential registry
(LeXcheX v2) covering accreditation, qualified-purchaser and QIB status,
jurisdiction and beneficial-owner attestations, and per-issuer whitelists.

**Contracts:**
[`LexChex / LexChexMinter`](../reference/contracts/LexChex.md).

**Reference UI:**
[`apps/lexchex-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-web)
at lexchex.metalex.tech, with an oracle service at
[`apps/lexchex-oracle`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-oracle).

The monorepo also contains the landing page (`apps/landing`) and the
supporting services these apps run on. Those services are operational
infrastructure for the apps; the contracts do not depend on them.

## Build your own

The contracts are the public surface. None of the apps above are required.
Any front end can interact with the protocol; see
[How-to: Integrate from a frontend](../how-to/integrate-from-frontend.md)
for the recommended stack and patterns.
