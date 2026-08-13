# 🔐 Security Review — cybercorps-contracts

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | Default (full repo, `src/`)                            |
| **Files reviewed**               | 89 in-scope `.sol` files (~25.2k LoC) across `src/`, `src/storage/`, `src/storage/extensions/`, `src/libs/conditions/`, `src/hooks/`, `src/creds/`, `src/converters/` |
| **Confidence threshold (1-100)** | 75                                                     |
| **Agents**                       | 12/12 completed (Fable)                                |

---

## Findings

**[85] 1. Permissionless corp/round deployment grants OWNER on the shared credential registry → forged accreditation credentials**

`CyberCorpFactory.deployAndInitializeRoundManager` · Confidence: 85 · [agents: 1]

**Description**
`deployCyberCorp` / `deployAndInitializeRoundManager` are `public` with no caller guard, and as their last step call `BorgAuth(lexchexAuth).updateRole(newRoundManager, OWNER_ROLE)` on the *shared, protocol-wide* `lexchexAuth` (default `0xeAdeaD…01c2`); because `BorgAuth.onlyRole` uses `userRoles[user] >= role` and `OWNER_ROLE(99) >= ADMIN_ROLE(98)`, the attacker-provisioned RoundManager becomes ADMIN of the global `LeXcheXMinter`, whose `requestMintFor` is `onlyAdmin` and (unlike the sibling `requestMint`) skips `_verifyAuthoritySignature` — so an attacker can drive their own round's `allocate` path to mint arbitrary KYC/accreditation credentials to any address, bypassing the authority-signature gate. Verify manually before remediation given the length of the chain.

**Fix**

```diff
- if (lexchexAuth != address(0)) BorgAuth(lexchexAuth).updateRole(roundManagerAddress, BorgAuth(lexchexAuth).OWNER_ROLE());
+ // grant a narrowly-scoped minter role on a per-corp auth, never OWNER on the shared lexchexAuth
+ if (lexchexAuth != address(0)) BorgAuth(lexchexAuth).updateRole(roundManagerAddress, MINTER_ROLE);
```

Additionally gate `deployAndInitializeRoundManager` (make it `internal` as `PumpCorpFactory` does), and have `requestMintFor` bind the minted subject to the round's actual paying counterparty rather than an attacker-supplied `request.owner`.

---

**[80] 2. Unbounded `O(totalSupply)` loop permanently bricks the final scrip redemption**

`IssuanceManagerStorage._zeroAllVaultNominals` · Confidence: 80 · [agents: 3]

**Description**
When a scrip conversion drives `pool.totalAssetsWad` to exactly 0, `_zeroAllVaultNominals` loops `for i in 0..certificate.totalSupply()` doing an SLOAD (`tokenByIndex`) + SSTORE per token, and `totalSupply` grows monotonically because `executeSecondaryTransfer` fresh-mints a Ledger Entry Token per settled lot and voids-but-never-burns the seller token — so once a printer accumulates enough certs the vault-emptying conversion exceeds the block gas limit and reverts permanently, locking the last tranche of scrip and its underlying units. Converged independently across the economic-security, numerical-gap, and flow-gap agents.

**Fix**

```diff
- function _zeroAllVaultNominals(address certAddress) internal {
-     ICertificate certificate = ICertificate(certAddress);
-     uint256 supply = certificate.totalSupply();
-     for (uint256 i = 0; i < supply; i++) {
-         getCertScripState(certAddress, certificate.tokenByIndex(i)).vaultNominalShares = 0;
-     }
- }
+ // Track vault participants in an explicit enumerable set and iterate only certs with
+ // vaultNominalShares > 0 — or drop the eager zero-out and treat pool.totalNominalShares == 0
+ // as authoritative, reading vaultNominalShares lazily as 0 when the pool is empty (O(1)).
```

---

**[78] 3. `processTransfer` reassigns legal ownership to a stale endorsee when custody returns to the owner**

`CyberCertPrinterStorage.processTransfer` · Confidence: 78 · [agents: 1]

**Description**
In the `from != ownerAddress` branch, the guard `if (endorsement.endorsee != to && ownerAddress != to) revert` passes whenever custody is returned to the legal owner (`to == ownerAddress`), and then unconditionally runs `_setLegalOwner(..., endorsement.endorsee, ...)` — so on a partially-sold token carrying a live `endorsee = buyer` endorsement, a custodian returning the NFT to the seller silently re-registers the seller's remaining units to the buyer (who paid nothing), and if the last endorsement came from `endorseCertificate` (endorsee `address(0)`) it wipes the holder of record entirely.

**Fix**

```diff
  else if (endorsementCount > 0) {
      Endorsement memory endorsement = s.endorsements[tokenId][endorsementCount - 1];
      if (endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();
-     _setLegalOwner(s, tokenId, endorsement.endorsee, endorsement.endorseeName);
+     if (endorsement.endorsee == to) {
+         _setLegalOwner(s, tokenId, endorsement.endorsee, endorsement.endorseeName);
+     } // else: returning custody to existing owner — leave ownerAddress unchanged
  }
```

---

**[80] 4. `expiry == 0` sentinel confusion lets any single party unilaterally void a perpetual agreement**

`CyberAgreementRegistry.voidContractFor` · Confidence: 80 · [agents: 1]

**Description**
`signContractFor` and `finalizeContract` treat `expiry == 0` as "never expires" (`if (expiry > 0 && expiry < block.timestamp) revert`), but `voidContractFor` omits the `expiry > 0` guard, so `if (agreementData.expiry < block.timestamp)` evaluates `0 < block.timestamp == true` for every no-expiry agreement — taking the "expired ⇒ instant unilateral void" branch on the first void request and bypassing both the unanimous-consent and proposer-only branches. Impact is integrity/liveness of standalone (finalizer=0) agreements; the DealManager/RoundManager paths pass non-zero expiry and are unaffected.

**Fix**

```diff
- if (agreementData.expiry < block.timestamp) {
+ if (agreementData.expiry != 0 && agreementData.expiry < block.timestamp) {
```

---

**[72] 5. `setScripRatio` retroactively reprices already-issued, transferable scrip**

`IssuanceManager.setScripRatio` · Confidence: 72

**Description**
The units↔scrip conversion ratio is a single mutable global (`scripRatios[certAddress]`) read live at both `scripifyCert` (`scrip = amount·num/den`) and `executeConvertScripToCert` (`units = amount·den/num`), with no per-mint snapshot and no guard against changing it while scrip `totalSupply > 0` — so a corp owner can halve the redemption value of scrip already sold to third parties on the secondary market (trace: Alice scripifies 100 units→100 scrip, sells to Bob; owner sets ratio 2:1; Bob converts 100 scrip and receives only 50 units). Below threshold because the actor is the semi-trusted corp owner and this straddles by-design admin config; treat as a design decision to make explicit (snapshot the ratio at scripify time, or forbid `setScripRatio` while scrip supply is nonzero).

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [85] | Permissionless deploy grants OWNER on shared credential registry → forged credentials |
| 2 | [80] | Unbounded `_zeroAllVaultNominals` loop bricks final scrip redemption |
| 3 | [78] | `processTransfer` reassigns legal ownership to stale endorsee on custody return |
| 4 | [80] | `expiry==0` sentinel confusion enables unilateral void of perpetual agreement |
| 5 | [72] | `setScripRatio` retroactively reprices outstanding transferable scrip |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Platform fee on in-flight escrow** — `FactoryStorage.setDefaultFeeRatio` + `LexScrowStorage.finalizeEscrow` / `SecondaryTradeStorage.finalizeSecondaryTradeAgreement` — Code smells: fee ratio and `platformPayable` read *live* at permissionless finalize, not at sign/accept; agents disagreed on whether `setDefaultFeeRatio` is capped at `BASIS_POINTS`. If uncapped, the factory owner can raise the ratio (up to 100%, or >100% to underflow-brick finalize) after counterparties escrow but before finalize, skimming committed value from the corp/seller. Confirm the cap.
- **Admin strands committed settlement** — `SecondaryTradeStorage.finalizeSecondaryTradeAgreement` — Code smells: `pathwayEnabled` / closing conditions are `onlyAdmin`-mutable and read live at finalize; after a buyer has funded an ACCEPTED lot, the SPV admin can flip a condition to force finalize to revert, locking the counterparty's capital until `settlementExpiry`. Griefing/optionality, refundable — no direct theft verified.
- **Socialized vault dilution / stale vault shares** — `IssuanceManagerStorage.executeConvertScripToCert`, `_withdrawVaultAssets` — Code smells: the no-active-cert branch socializes withdrawal via `_withdrawVaultAssets` (dilutes other certs' pro-rata claim); separately, `tokenByIndex` enumerates live tokens only, so a scripified cert that is later *burned* keeps its `vaultNominalShares`, escaping the zero-out and claiming a refilled vault. Burn-path reachability for a scripified cert was unverified.
- **`LeXcheXMinter._verifyAuthoritySignature` signature replay** — `requestMint` / `requestRenewal` — Code smells: no nonce, no `usedSignature` mapping, no deadline on the signature itself; `AuthorityData` omits `msg.sender`. The same admin signature can be resubmitted to re-mint duplicate credentials. Bounded (soulbound, replayer pays `mintPrice`) → spam/griefing, not theft.
- **CyberShares dead-code fund loss** — `CyberShares.formCertificateFromShares` / `voidToShares` — Code smells: `formCertificateFromShares` runs a real `_burn` but the cert `safeMint` is commented out (burn-without-mint, permanent loss); `voidToShares` has no already-voided guard and would re-mint shares each call. Currently unreachable (`safeMint` is a no-op stub; no factory deploys CyberShares) — a ship-blocker only if the contract is ever wired live. Flagged by 4 agents.
- **`SafeCertificateConverter.computeConversion` silent zero-return** — Entire body is commented out inside `/* … */`, returns an all-zero `ConversionPlan` and cannot even fail closed (the `revert MathError()` guard is also commented). Imported by `IssuanceManager` but not called, so no live path — complete it or `revert NotImplemented` before anything wires it as an active converter.
- **`DealManager.signDealAndPay` missing `nonReentrant`** — The one payment-pulling entrypoint lacking the guard its siblings all carry; `paymentToken` is owner-set (not attacker-chosen) so only self-re-entry was reachable. Defense-in-depth gap.
- **Selector-gated condition bypass** — `SecondaryTradeStorage._checkConditions` forwards `msg.sig`; relayer overloads have different selectors than direct calls, so a future condition branching on `msg.sig` could be bypassed by routing through the other entrypoint. No shipped condition currently branches on the selector.
- **Metadata JSON/SVG injection** — `LeXcheX.tokenURI`, `LeXcheXBadgeRender.tokenURI`, `FundInterestExtension._seriesIdentityJson` embed investor string fields without `JsonLib.jsonEscape` (which `ShareExtension` uses correctly). Admin-set fields, off-chain rendering only — low severity.
- **`CyberScrip._update` hook param confusion** — passes transfer `amount` into the hook's `tokenId` parameter; harmless for `WhitelistTransferHook`, but a per-`tokenId` hook (e.g. Toggle-style) mis-wired onto scrip would gate per-amount. Config-dependent.
- **`BorgAuth` role semantics / events** — `onlyRole` uses `>=` so role `200` outranks OWNER (wider privileged set than "OWNER" implies — this is the property finding #1 weaponizes); `acceptOwnership` never downgrades the previous owner and emits `RoleUpdated(address(0), …)` after zeroing `pendingOwner`. Correctness/monitoring smells.
- **`CyberCertPrinter.endorseAndTransfer` authorization bypass** — `external` with no modifier, calls internal `_transfer` which bypasses the ERC-721 `_isAuthorized` check; neutralized today by `addEndorsement`'s gate (caller must be owner or IM) but fragile if that gate changes.
- **`CyberAgreementRegistry.createContract` missing duplicate-party check** — duplicate-party loop commented out; duplicate parties permanently wedge finalization and unanimous-void (each address signs once). Self-inflicted DoS, no attacker profit found.
- **`RoundManager.allocate` min-ticket / decimal boundary** — `minRequired` is checked on the pre-truncation requested amount while `usedAmount` (below `minTicket`) is what gets recorded/raised; and >18-decimal payment tokens coarsen unit granularity to `10^(d-18)`. Dust-bounded and documented as intentional.
- **`IssuanceManagerStorage.executeSecondaryTransfer` orphaned vault position** — a scripified cert whose remaining raw units are fully sold gets `voidCert`'d (not burned), leaving `vaultNominalShares > 0` behind the admin recertification gate; the scripifier can no longer self-redeem their own scrip without an admin `setRecertificationApproval`. Liveness/UX dependency on admin, conservation still holds.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
