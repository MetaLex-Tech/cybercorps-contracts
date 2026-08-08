# The cyberCORPs application stack

CyberCORPs is the **protocol**; the cyberCORPs **Mainframe** is the
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

* **Registered ledger path** — edits to the existing cyberCERT (or
  burn-and-mint with new metadata) under issuer approval, with the buyer
  electing an exemption pathway (Rule 144, §4(a)(7), §4(a)(1½), Rule 144A,
  or Reg S) and the trade gated by that pathway's conditions — holder caps,
  accreditation, qualified-purchaser status, holding periods, and
  jurisdiction screens.
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
[`PumpCorpFactory`](../reference/factories.md#pumpcorpfactory),
[`ACESAFEExtension`](../reference/extensions.md#acesafeextension).

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

## Mainframe

Issuer-facing hub. Cap table / holder register by class, fundraising round
configuration, deal management, agreement signing, scripification controls,
transfer hook configuration, BorgAuth role management, holder-of-record
reporting, and 12(g) (or jurisdictional analogue) threshold monitoring
across cyberCERT and cyberSCRIP holder bases.

**Reference UI:** the `/cybercorps` route in
[`apps/cybercorps-web/src/app/(frame-layout)/cybercorps`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cybercorps).

## MetaDAO

Futarchy-governed Cayman SPC structure. Each portfolio (SegCo) has its own
futarchy oracle.

**Contracts:**
[`MetaDAOFactory`](../reference/factories.md#metadaofactory).

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

## Supporting services in `metalex-webapp`

* **`apps/cybercorps-indexer`** — ponder-based indexer projecting protocol
  events into a SQL store for fast cap-table queries.
* **`apps/notifier`** — event-driven notifications (round close, deal
  ready, registration approval needed).
* **`apps/snapshot-executor`** — executes Snapshot governance outcomes
  onchain where they affect a cyberCORP's authority.
* **`apps/landing`** — the marketing landing page.

## Build your own

The contracts are the public surface. None of the apps above are required.
Any front end can interact with the protocol; see
[How-to: Integrate from a frontend](../how-to/integrate-from-frontend.md)
for the recommended stack and patterns.
