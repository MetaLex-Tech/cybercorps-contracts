# cyberTRADE — Engineering TODO

Synthesized from spec v3.53 (§12, §12A, §12B, §13, §13A, §15, §16, Addenda A–E) and Diagram 5 of the regulation map.
Items are grouped by layer then by roadmap phase.

**Roadmap key:**

- `v1` — required at launch; spec treats as a prerequisite for cyberTRADE to function
- `v1.x` — post-launch planned; spec explicitly marks as intended next milestone
- `C` — conditional on external trigger (e.g., 3(c)(7) fund onboarding, counsel call)
- `future` — architecturally available but explicitly deferred
- `[NOT LAUNCH]` — spec explicitly blocks at launch; noted for completeness

---

## Protocol Layer (Solidity)

### Core contract additions

| #   | Item                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Roadmap | Spec ref           |
|-----|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|--------------------|
| P-1 | **FundInterestExtension** — `ICertificateExtension` impl for fund-specific metadata: interest class, acquisition date, tacked-from acquisition date, fund entity type, relied-on ICA exception, transfer-restriction-hook override, distribution waterfall position, governing-doc URIs, Security Identification fields                                                                                                                                                                                                         | v1      | §12 item 1         |
| P-2 | **`acquisitionDate` + `tackedFromAcquisitionDate` fields** — add to core `CertificateDetails` struct (recommended) or to FundInterestExtension; requires storage migration (append-safe under ERC-7201)                                                                                                                                                                                                                                                                                                                         | v1      | §12B.3, §12 item 2 |
| P-3 | **IssuanceManager: secondary-transfer entry point** — BorgAuth-gated via new secondary-transfer role; implements unified mutate-and-mint (void/decrement seller token, mint buyer token per hosting mode, consume unit reservation, attach open-endorsement chain-of-title); companion open-endorsement attachment helper called by DealManager acceptance                                                                                                                                                                      | v1      | §12 item 5, §7.4A  |
| P-4 | **CyberAgreementRegistry: open-agreement surface** — open-slot mechanics already exist (`address(0)` in parties array, `getFirstOpenPartyIndex`, `fillUnallocated` on `signContract`); new work: (1) `isOpenToMatching` flag on `AgreementData`; (2) named `createOpenAgreement` entry point (create + party-A sign atomically); (3) BorgAuth-gated `attachPartyB` for DealManager to fill party B during offer acceptance; (4) distinct event for open→fully-signed transition for indexer; no change to primary-issuance flow | v1      | §12 item 4         |

### DealManager extensions

| #   | Item                                                                                                                                                                                                                                                                                                                                       | Roadmap | Spec ref           |
|-----|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|--------------------|
| P-5 | **DealManager: secondary trade mode** — add trade-type discriminator to `Escrow` struct; seller-address payment destination; fee-destination field; offer-id back-link; `finalizeEscrow` branch: compute+split fee, pay seller, call IssuanceManager secondary-transfer, skip `corpAssets` transfer block; primary-issuance path unchanged | v1      | §12B.1, §12 item 6 |
| P-6 | **DealManager: offer/acceptance primitives** — `postOffer`, `cancelOffer`, `acceptOffer`, SPV registration; no separate OfferRegistry; unit-reservation semantics at posting (calls CyberCertPrinter reserve entry point); holding escrow for bid commitments (LexScroWLite instance per bid)                                              | v1      | §12B.8, §12 item 3 |
| P-7 | **DealManager: partial fill support** — price-per-unit field on offer; acceptor can fill a sub-range; minimum-fill check applies the per-SPV threshold (P-8)                                                                                                                                                                               | v1      | §12 item 7         |
| P-8 | **DealManager: per-SPV minimum trade threshold** — stored per-SPV (units denominated, optional consideration-denominated threshold); checked at offer posting, partial-fill acceptance, direct-deal proposal; BorgAuth-admin setter; emits event with prior/new value                                                                      | v1      | §12B.1A            |
| P-9 | **DealManagerFactory: integrator whitelist + fee split** — add approved-integrators mapping + per-integrator fee-share to `DealManagerFactoryStorage`; per-DealManager default-integrator slot; per-deal fee-destination override on escrow; fee-split at finalization (integrator share + MetaLeX share, same payment token); audit event | v1      | §12B.4, §12 item 8 |

### CyberCertPrinter extensions

| #    | Item                                                                                                                                                                                                                                                                                                                                                                | Roadmap | Spec ref              |
|------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|-----------------------|
| P-10 | **CyberCertPrinter: unit-reservation system** — per-token reservation records keyed by reservation ID + running reserved-total; `reserve` entry point (DealManager-only, BorgAuth-gated); `release` entry point (DealManager-only, on cancel/expiry/void); `consume` entry point (IssuanceManager-only at settlement); `_update` rejects movement of reserved units | v1      | §12B.2, §12 item 11   |
| P-11 | **Activate per-token restriction hook in `CyberCertPrinter._update`** — storage (`restrictionHooksById`) and setter exist; read is currently commented out; uncomment and wire; lower priority than P-10 since unified pathway doesn't rely on it at settlement                                                                                                     | v1.x    | §12B.2A, §12 item 12A |

### New condition contracts (ICondition implementations)

| #    | Condition                              | Regulatory rule                | Roadmap | Notes                                                                                                                                                                                                                         |
|------|----------------------------------------|--------------------------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| C-1  | `KYCAMLCondition`                      | BSA / FinCEN                   | v1      | All paths; acceptance stage; both parties                                                                                                                                                                                     |
| C-2  | `AccreditedInvestorCondition`          | §4(a)(7) + Rule 501(a)         | v1      | Parameterizes `LexChexCondition`; redundant on §3(c)(7) funds                                                                                                                                                                 |
| C-3  | `QualifiedPurchaserCondition`          | ICA §3(c)(7) + §2(a)(51)       | v1      | §3(c)(7) funds only; $5M+ individuals / $25M+ institutions; collapses §15 Q3 risk if layered on Rule 144                                                                                                                      |
| C-4  | `QualifiedInstitutionalBuyerCondition` | Rule 144A                      | v1      | Rule 144A path only ($100M+)                                                                                                                                                                                                  |
| C-5  | `USStateOfResidenceCondition`          | State blue sky                 | v1      | Non-§4(a)(7) paths only; NY defaults on without Martin Act registration; consults per-SPV blocked-states list                                                                                                                 |
| C-6  | `TaxInfoCondition`                     | IRC §1446(f) + §6722/§6698     | v1      | All paths; acceptance stage; pre-settlement W-9/W-8BEN gate                                                                                                                                                                   |
| C-7  | `LegionSoulboundCondition`             | Issuer custom gating           | v1      | Queries Legion's credentialing layer within LeXcheX deployment                                                                                                                                                                |
| C-8  | `AgreementSignedCondition`             | EIP-712 bilateral signing      | v1      | All paths; acceptance stage; both parties                                                                                                                                                                                     |
| C-9  | `Section4a7DisclosureCondition`        | §4(a)(7)(d)(3)                 | v1      | §4(a)(7) path only; checks disclosure URI freshness from cyberCORP; triggers NSMIA preemption                                                                                                                                 |
| C-10 | `HoldingPeriodCondition`               | Rule 144(b) + 144(d)(3)        | v1      | Rule 144 path only; reads `acquisitionDate` + `tackedFromAcquisitionDate`; 1-year minimum                                                                                                                                     |
| C-11 | `Rule144DisclosureCondition`           | Rule 144(c)(2) + Rule 15c2-11  | v1      | Rule 144 path only; 14-item current-public-info standard; no NSMIA preemption                                                                                                                                                 |
| C-12 | `LegalOpinionCondition`                | §4(a)(1½)                      | v1      | §4(a)(1½) path only; legal opinion or GP sign-off must precede contract formation                                                                                                                                             |
| C-13 | `HolderCapCondition` — §3(c)(1)        | ICA §3(c)(1) + §3(c)(1)(A)     | v1      | 100-cap + entity look-through arithmetic; maintains §1.7704-1(h) safe harbor by construction                                                                                                                                  |
| C-14 | `HolderCapCondition` — §3(c)(1)(C)     | ICA §3(c)(1)(C)                | v1      | 250-cap QVCF variant; §1.7704-1(h) unavailable above 100 partners — `QMSModeCondition` required for QVCF funds above that threshold                                                                                           |
| C-15 | `CFIUSCondition`                       | FIRRMA + 31 CFR §800.307       | v1      | Non-fund-exception SPVs only (foreign LP buyers without U.S. GP + passive LP structure)                                                                                                                                       |
| C-16 | `ERISACondition`                       | ERISA plan assets              | v1      | Closing stage; negative attestation from buyer at finalization                                                                                                                                                                |
| C-17 | `GPLPApprovalCondition`                | Governing documents            | v1      | Optional per-SPV; generalizes `IssuerApprovalRecertificationCondition`                                                                                                                                                        |
| C-18 | `GlobalKillCondition`                  | Bilateral admin authority      | v1      | Two admin slots (MetaLeX + Legion); unilateral raise / bilateral lower; closing stage; factory attaches to every DealManager                                                                                                  | see §12B.5 |
| C-19 | `TimeSettlementPeriodCondition`        | UCC §8-303 intervention window | v1      | 24h default delay; configurable start-trigger (acceptance / buyer deposit / both); closing stage; reparameterized to 45-day gate for QMS-mode SPVs                                                                            | see §12B.6 |
| C-20 | `NonUSNationalityCondition`            | Reg S Rule 902(k)              | v1.x    | Reg S path; already exists (`NonUSNationalityCondition`) — reuse directly as NonUSPersonCondition                                                                                                                             |
| C-21 | `RegSDistributionComplianceCondition`  | Reg S Rule 903                 | v1.x    | Reg S path; distribution compliance period (category 1/2/3)                                                                                                                                                                   |
| C-22 | `HolderCapCondition` — Touche Remnant  | SEC Staff Touche Remnant 1984  | v1.x    | Non-U.S. SPVs only; counts U.S.-resident BOs only; not deployed at launch                                                                                                                                                     |
| C-23 | `GPConsentCondition`                   | Governing documents            | C       | Legacy SPVs / BorgAuth policy; conditional on GP authorization                                                                                                                                                                |
| C-24 | `QMSModeCondition`                     | Treas. Reg. §1.7704-1(g)       | C       | Per-SPV opt-in; 15-day inert period + 30-day frequency cap at acceptance; frequency counter incremented by DealManager after condition passes; 45-day closing gate handled by `TimeSettlementPeriodCondition`; see Addendum E |
| C-25 | *Annual transfer volume tracker*       | Treas. Reg. §1.7704-1(j)       | **GAP** | 2% de minimis PTP safe harbor; spec §2514 notes "requires an additional annual transfer volume tracker" — **no condition stub, no launch marker, no addendum; only PTP defense with no roadmap artifact**                     |

### BorgAuth / role changes

| #   | Item                                                                                                                                                                                      | Roadmap | Spec ref |
|-----|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|
| R-1 | **New secondary-transfer BorgAuth role** — new `uint256` role ID; grant to each SPV's DealManager at SPV onboarding (§4.1.5); required for IssuanceManager secondary-transfer entry point | v1      | §16.3    |
| R-2 | **Unit-reservation roles on CyberCertPrinter** — `reserve` gated to DealManager, `consume` gated to IssuanceManager; granted at SPV onboarding                                            | v1      | §12B.2   |

### SPV configuration / metadata

| #   | Item                                                                                                                                                                                                          | Roadmap | Spec ref            |
|-----|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|---------------------|
| M-1 | **SPV adaptation layer on cyberCORP** — entity type (LLC/LP/non-U.S.), jurisdiction of domicile, relied-on ICA exception, Reg S issuer category (1/2/3), holder-cap configuration, hosting-mode configuration | v1      | §12 item 15         |
| M-2 | **GP underlying-asset provenance attestation** — registry slot or onchain metadata field on cyberCORP for GP's signed attestation hash; GP-refresh workflow; surfaced in per-SPV disclosure UI                | v1      | §12 item 17, §4.1.0 |
| M-3 | **cyberCORP portfolio holdings + SPV-unit-to-underlying ratio** — per-holding records (security type, count); stable vs. subject-to-change flag; UI reads current ratio at view time for unstable SPVs        | v1      | §2                  |

### LeXcheX deployment

| #   | Item                                                                                                                                                                                                                                                                                                                           | Roadmap | Spec ref             |
|-----|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------------------|
| L-1 | **Parallel LeXcheX + LeXcheXMinter deployment under Legion's BorgAuth** — Legion-controlled custom credentialing layer; no new adapter contracts                                                                                                                                                                               | v1      | §12 item 18, §4.1.3A |
| L-2 | **LeXcheX credential extensions** — U.S. state of residence (or state of organization for entities) for investorJurisdiction=US holders; beneficial-owner count for entity holders (used by HolderCapCondition look-through); implementation choice: extend `Accreditation` struct or carry on Legion Soulbound NFT credential | v1      | §12 item 13A         |

### GP transfer restriction hooks

| #   | Item                                                                                                                                                                                                                                                                                                                  | Roadmap | Spec ref            |
|-----|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|---------------------|
| H-1 | **GP transfer restriction hook templates** — composable hook modules (library-of-hooks approach recommended over single configurable hook); covers: valid LeXcheX credentials, existing-LP vs. new-holder policy, minimum transfer size, jurisdiction restrictions, max holder count, required Soulbound NFT category | v1      | §12 item 14, §15 Q2 |

### Trade agreement templates

| #   | Item                                                                                                                                                                                                                                                                         | Roadmap | Spec ref    |
|-----|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|-------------|
| T-1 | **Trade agreement templates for each exemption pathway** — §4(a)(7), §4(a)(1½), Rule 144, Rule 144A, Regulation S; registers in `CyberAgreementRegistry` via deploy script following `template.s.sol` / `templatev2.s.sol` pattern; includes GP affiliation disclosure field | v1      | §12 item 16 |

---

## Application Layer (metalex-webapp)

| #   | Item                                                                                                                                                                                                                                                                                                | Roadmap | Spec ref            |
|-----|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|---------------------|
| A-1 | **cyberTRADE UI — core screens** — Offer Builder (§8.1), Offer Discovery (§8.1A), Acceptance View (§8.2), Deposit + Settlement View (§8.4), Offer and Trade Status (§8.5); inherits from cyberSign (agreement creation/signing) and cyberRAISE (multi-step form patterns, condition-status display) | v1      | §12 item 22, §8     |
| A-2 | **GP Monitoring View** (§8.3) — trade pipeline, condition status, pending expirations, unit reservation ledger                                                                                                                                                                                      | v1      | §8.3                |
| A-3 | **Per-cyberCORP documents tab** — GP publishes/refreshes SPV disclosure package, financial statements, provenance attestation; no current equivalent (legacy documents system is Borg-only); required for `Section4a7DisclosureCondition` and `Rule144DisclosureCondition` freshness checks         | v1      | §12 item 20, §16.1  |
| A-4 | **Officer / BorgAuth admin UI** — add/remove officers, grant/rotate BorgAuth roles (incl. secondary-transfer role); indexer already tracks events; currently script-only; lives under Mainframe admin route                                                                                         | v1      | §12 item 21, §16.1  |
| A-5 | **Per-SPV settings panel** — `requiresLexChex` flag and related per-SPV toggles; Mainframe admin route; (if QMS added) QMS opt-in flag                                                                                                                                                              | v1      | §16.1               |
| A-6 | **Pathway F admin panel** — void / force-transfer on specific tokens; Compromised Credential Transfer determinations; court-order execution; Global Kill governance (raise/lower UI); each invocation requires justification field + attached document (via `useUploadPdfToPinata`)                 | v1      | §8.7, §16.1         |
| A-7 | **UI-level offer visibility gating** — per-SPV user whitelists server-side; joins user credentials, seasoning state, per-SPV whitelist entitlements; never exposes an ineligible offer                                                                                                              | v1      | §12 item 19, §11.1B |

---

## Indexer (Ponder)

| #   | Item                                                                                                                                                                                                                      | Roadmap | Spec ref           |
|-----|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|--------------------|
| I-1 | **CyberAgreementRegistry event handlers** — `AgreementCreated`, `AgreementSigned`, `AgreementFinalized`, `AgreementVoided`, `DelegationSet`; **prerequisite for cyberTRADE UI to function at all**; not currently indexed | v1      | §12 item 23, §16.2 |
| I-2 | **New tables** — `offer`, `offer_acceptance`, `fix_trade_receipt`; optionally a denormalized `endorsement` table                                                                                                          | v1      | §12 item 23, §16.2 |
| I-3 | **New API routes** — `/api/offers`, `/api/agreements`; per-user and per-SPV filtered routes; eligibility filtering is server-side                                                                                         | v1      | §16.2              |

---

## Operational Infrastructure

| #   | Item                                                                                                                                                                                                                                                                                                                                                                                                                                               | Roadmap | Spec ref                  |
|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|---------------------------|
| O-1 | **Keeper service** — auto-finalize deals whose closing conditions are satisfied (`TimeSettlementPeriodCondition` elapsed + `GlobalKillCondition` not raised); auto-void deals past expiry (refund buyer payment, release unit reservation, write void endorsement superseding open endorsement); also auto-void bid-commitment holding escrows (refund bidder principal); convenience layer, not trust layer — finalize/void remain permissionless | v1      | §12 item 24, §10.4, §16.4 |
| O-2 | **Pinata IPFS scaling** — existing `useUploadPdfToPinata` hook already in use; new usage: trade-agreement templates, disclosure packages, provenance attestation; only new ops work is API-key allocation and pricing scaling                                                                                                                                                                                                                      | v1      | §16.4                     |

---

## Future / Deferred

### Scrip Token layer (§13)

- CyberScrip.sol exists with compliance flags (`canForceTransfer`, `canForceBurn`, `canFreeze`, transfer hooks,
  `_update` overrides); MetalexIssuerFeeHook.sol partially scaffolded as Uniswap v4 hook
- New work if adopted: scrip-to-Ledger Entry Token conversion semantics in fund-interest context; de-scripification
  enforcement (voluntary at protocol level, GP can impose mandatory deadlines); UCC classification decision (transfer
  instruction / control agreement / souvenir tokens); §7704 + K-1 + Article 8 accommodations

| #   | Item                                                                                                                                  | Roadmap |
|-----|---------------------------------------------------------------------------------------------------------------------------------------|---------|
| F-1 | Scrip Token trading layer (ERC-20 fungible instruments, CyberScrip.sol foundation)                                                    | future  |
| F-2 | AMM liquidity for Scrip Tokens — whitelisted AMM (Uniswap v4 hook, MetalexIssuerFeeHook.sol) or open AMM with gated de-scripification | future  |

### QMS Mode (Addendum E)

| #   | Item                                                                                                    | Roadmap                       | Trigger                                                      |
|-----|---------------------------------------------------------------------------------------------------------|-------------------------------|--------------------------------------------------------------|
| F-3 | `QMSModeCondition` per-SPV flag + 15-day inert period enforcement at `acceptOffer`                      | C                             | 3(c)(7) fund onboarding where counsel calls for QMS backstop |
| F-4 | `TimeSettlementPeriodCondition` reparameterized to 45-day gate from listing timestamp for QMS-mode SPVs | C                             | Same as F-3                                                  |
| F-5 | Per-SPV QMS opt-in UI in settings panel                                                                 | C                             | Same as F-3                                                  |
| F-6 | Annual transfer volume tracker for §1.7704-1(j) 2% de minimis safe harbor                               | **GAP — no roadmap artifact** | —                                                            |

### Other future enhancements

| #    | Item                                                                                                                                                                                 | Roadmap      | Spec ref                                            |
|------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------|-----------------------------------------------------|
| F-7  | Affiliate Rule 144 trading path — volume limits (1% of outstanding per rolling 90 days), manner-of-sale check, Form 144 filing                                                       | [NOT LAUNCH] | Addendum A                                          |
| F-8  | ROFR / tag-along / drag-along enforcement — currently assumes no ROFR; legacy fund onboarding may require; per-SPV opt-in                                                            | future       | Addendum B, §6.3                                    |
| F-9  | Manual per-trade GP consent path (Addendum C) — `GPConsentCondition` + consent-request/response flow                                                                                 | C            | GP policy requirement                               |
| F-10 | Privacy layer — cleartext trade terms and party identities; RAILGUN or ZK proofs (zkPassport) for accreditation/QP status                                                            | future       | §15 Q6                                              |
| F-11 | Cross-chain support — currently all assets must be on same chain                                                                                                                     | future       | §15 Q7                                              |
| F-12 | MPC / embedded wallet integration (Privy, Web3Auth, Magic, Turnkey) — optional; must preserve self-custodial condition per SEC Covered UI Provider statement                         | future       | §16.5, §15 Q22                                      |
| F-13 | Bulk cap-table import workflow — CSV upload, schema validation, batched minting; manual per-LP entry via Mainframe assumed for v1 migration                                          | future       | §16.5                                               |
| F-14 | Cryptographic origination proofs for integrator attribution — originating UI signs with registered key, validated at deal proposal; v1 relies on whitelist + honest self-attribution | future       | §15 Q20                                             |
| F-15 | Tiered Global Kill (soft kill = new deals blocked / hard kill = everything blocked)                                                                                                  | future       | §15 Q16                                             |
| F-16 | Capital call + distribution module — separate from cyberTRADE; architected for composability                                                                                         | future       | §15 Q9                                              |
| F-17 | Touche Remnant HolderCapCondition variant for non-U.S. SPVs (counts U.S.-resident BOs only)                                                                                          | v1.x         | Diagram 5 — `HolderCapCondition` Touche Remnant row |

---

## Open Questions with Engineering Impact (§15)

These are unresolved decisions that block or shape specific items above.

| #    | Question                                                                                                                                                                                                                                                                   | Blocks     | Spec ref |
|------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------|----------|
| Q-1  | Entity type support at launch: Delaware LLCs only, or also LPs? Non-U.S. jurisdictions (Cayman, BVI)? Governs governing-doc rider scope and condition parameterizations                                                                                                    | M-1, T-1   | §15 Q1   |
| Q-2  | Transfer restriction hook design: library of composable modules vs. single parameterized hook                                                                                                                                                                              | H-1        | §15 Q2   |
| Q-3  | `144(c)(2)` disclosure hosting: IPFS, SPV website, or OTC Markets Alternative Reporting? cyberTRADE needs a URI to verify currency                                                                                                                                         | C-11, A-3  | §15 Q4   |
| Q-4  | Hosting election mechanics: election at primary issuance, at minting, or switchable post-issuance? Default (recommendation: Administered)                                                                                                                                  | M-1, A-1   | §15 Q10  |
| Q-5  | Ledger administrator entity structure under hybrid hosting: Legion itself, a Legion affiliate, third-party transfer agent, or GP? Regulatory implications differ                                                                                                           | M-1        | §15 Q11  |
| Q-6  | Affiliate/control person tagging: require positive tagging via `isAffiliateOrControlPerson` flag (automatic disclosure in agreement template), or self-reporting only?                                                                                                     | T-1, H-1   | §15 Q13  |
| Q-7  | Global Kill governance: hard upper bound on kill duration? Key-rotation procedure?                                                                                                                                                                                         | C-18, A-6  | §15 Q16  |
| Q-8  | IssuanceManager preset conditions: mandatory-conditions set (GlobalKill, TimeSettlementPeriod) forced on every Ledger Entry Token, vs. issuer selects                                                                                                                      | C-18, C-19 | §15 Q17  |
| Q-9  | §3(c)(7) + Rule 144 interaction (Open Question §15 Q3): Rule 144 buyer is not required to be a QP — new non-QP BO breaches §3(c)(7) at settlement. Spec posture: facts-and-circumstances non-PTP defense; `QualifiedPurchaserCondition` optional layering on Rule 144 path | C-3, C-10  | §15 Q3   |
| Q-10 | Fee structure: protocol fee ratio (e.g., 25/50/100 bps)? Integrator share (e.g., 30/70 split)? Per-integrator vs. global split ratio?                                                                                                                                      | P-9        | §15 Q5   |
