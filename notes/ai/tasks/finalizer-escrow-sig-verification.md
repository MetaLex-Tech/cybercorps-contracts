# Task: Registry checks the party's signature on escrow signing

- **Status:** Active (issue #218 fix `DealManager.signDeal` in 6745777e; version bump committed after it; not reviewed)
- **Updated:** 2026-11-27
- **Owner:** Claude Code session, for the owner
- **Collaborators / boundaries:** Registry, RoundManager, DealManager secondary trade,
  ParentCoFactory and MetaDAOFactory. No deployment, upgrade, webapp change or audit was started.
- **Objective:** `signContractWithEscrow` records a party only with a signature that the party gave
  in the calling finalizer's own EIP-712 domain. A finalizer that the agreement creator chose can
  no longer record a party who never signed for it (the escrow signature forgery).
- **Out of scope:** New prefixed escrow types and the agreement-body hash for rounds (MTLX1-24
  stays Acknowledged). The notary design, derived expiry. Finalizer-only signing was added on
  2026-11-24 (owner request); other finalizer-only mutation stays out of scope.
- **Canonical plan / sources:** Discussion summary artifact "Registry as notary"; option B in the
  "Escrow Signature Binding" report; [attestation binding rule](../../../specs/analysis/attestation%20binding%20rule.md).
  Owner choices on 2026-11-23: reuse today's officer types; secondary trade gets a new offeror type.
- **Repository / branch:** cybercorps-contracts; branch `feat/finalizer-escrow-sig-verification`
  (no upstream)
- **Verified base / code head:** base 13418fb5; first part committed as 1f4fff96 (wip). Latest tests ran on 1f4fff96 plus the uncommitted restore and fork-test changes
- **PR / artifact:** PR #216 (`feat/finalizer-escrow-sig-verification`); issue #218 (compatibility review); PR #219 (issuer regression tests, targets this branch)

## Change

- **Registry:** `signContractWithEscrow` takes `EscrowAttestation(domainName, domainVersion,
  structHash, signature)` instead of raw signature bytes. It builds the domain with `msg.sender`
  (the finalizer) as the verifying contract and reverts `SignatureVerificationFailed` unless the
  signature recovers to the escrow signer. ECDSA only, no delegates. The old selector is removed.
- **RoundManager:** passes the officer's existing `EscrowedSignatureData` signature at FCFS
  `submitEOI` and at `allocate`. The owner can change `endTime` after the officer signs, so the
  first `setRoundEndTime` or `closeRoundNow` keeps the signed value in the appended
  `signedEndTime` mapping.
- **ParentCoFactory:** passes the officer's existing `EscrowAuthorization(name, contact)` signature.
- **MetaDAOFactory:** today it stores `metaDAOSignatureHash` and verifies nothing. It now uses the
  ParentCo type in its own `"MetaDAOFactory"` domain and adds `escrowAuthorizationHash`.
- **Registry, finalizer-only signing (2026-11-24):** when an agreement has a finalizer,
  `signContractFor` (and so `signContract`) accepts only `msg.sender == finalizer`. The signer can no
  longer submit directly. Commit 24386429 (Oct 2025, audit item 3.3) added the signer exception for
  "open deal" agreements. Evidence that no use case still needs it: every contract caller is the
  finalizer; every webapp direct registry sign uses finalizer `address(0)`; a trace of all 1,564
  mainnet `AgreementSigned` events (Base, Ethereum, Arbitrum, Robinhood; 1,459 with a finalizer)
  found the finalizer as caller in every case. Testnets were not scanned.
- **Secondary trade:** new `OfferorAgreement` type in the DealManager domain (offeror, economics,
  template, salt, global and offeror party values). `postOffer` reverts
  `InvalidOfferorAgreementSignature` unless `offerorAgreementSig` is the offeror's signature over
  the stored offer. `acceptOffer` passes it to the registry.

## Acceptance and current state

- Forged escrow sign by a creator-chosen finalizer reverts: verified (registry unit tests).
- Signature for another finalizer domain, or over other terms, reverts: verified.
- RoundManager FCFS and allocation flows record the officer, including after an end time change: verified.
- ParentCo flows record the officer with today's signature: verified (existing ParentCo tests).
- Secondary post rejects a wrong or stale offeror signature; accept records the offeror: verified.
- Signer or third party submit on a finalizer agreement reverts `NotFinalizer`; the finalizer submit
  records the party: verified (`test_RevertIf_signContractForFinalizerAgreementNotFromFinalizer`,
  fails on HEAD). `testPOC_Allocate_CanMarkOfficerSignedWithNonAgreementSignature` now submits as the
  RoundManager to keep `SignatureVerificationFailed`, plus an officer-direct `NotFinalizer` check. The
  two zero-expiry void tests now use no finalizer and one unsigned party (owner choice).
  Fork tests (owner choice): `testCreateContract` has the finalizer submit the open-slot fill;
  `testDelegateSigningDeal` passes the delegate signature only to `signAndFinalizeDeal`, as the webapp
  does; `testDelegateSigningWithExpiry` submits through `signAndFinalizeDeal` and still expects
  `SignatureVerificationFailed`.
- MetaDAOFactory: not tested. Its test file was emptied in beccbb7c.
- Fork tests: pass. Owner chose to upgrade the caller in each test that ran a deployed caller (2026-11-23).

## Upgrade effects

- Each deployed RoundManager, DealManager, ParentCoFactory and MetaDAOFactory must upgrade before
  its next escrow sign after the registry upgrade. Until then that call reverts.
- MetaDAO owner must set a new `metaDAOSignatureHash`: the officer's `EscrowAuthorization` signature.
- Live secondary offers posted before the upgrade have no valid offeror signature. They cannot be
  accepted; the offeror must cancel and post again. The webapp must ask for the new signature.
- A round whose end time changed before the RoundManager upgrade has no `signedEndTime`. Its
  `allocate` reverts at the registry until the owner calls `restoreSignedEndTime(roundId, endTime)`
  with the end time from `RoundCreated`. The call checks the officer's signature, so only the signed
  value is accepted. Scan live rounds for `RoundEndTimeUpdated` to find them.
- Scan pre-upgrade agreements whose finalizer no known factory deployed (forged records stay).

- After the registry upgrade, `DealManagerStorage.signAndFinalizeDeal`'s "already signed in registry"
  branch is reachable only when a DealManager path signed that party first, and no test covers it
  now. Not changed; a trace of every DealManager path is the next step before any deletion.

## Webapp follow-up after merge

Checked against `../metalex-webapp` on 2026-11-24.

0. Primary escrow: `EscrowedDealPanel.tsx` / `buildSignContractCall` must call
   `DealManager.signDeal(signer, agreementId, partyValues, signature, secret)` instead of the registry.
1. Secondary post: `secondaryOfferCall.ts` sends `offerorAgreementSig: "0x"`, and
   `secondaryOfferAuthorization.ts` pins it to `z.literal("0x")`. The seller must sign
   `OfferorAgreement` (domain `"DealManager"`, `"1"`, the DealManager address) before the post or the
   relayer `PostOfferAuth` signature.
2. MetaDAO escrowed-signature page (`useEscrowMetaDaoSignature.ts`, `escrowSignatureData.ts`) signs
   the registry's `EscrowSignatureData`. It must sign `EscrowAuthorization(name, contact)` in the
   `"MetaDAOFactory"` domain. `packPreflight.ts` must check the stored bytes against that type.
3. Upgrade page: upgrade order is registry first, then each finalizer. Add `restoreSignedEndTime`
   for rounds whose end time changed before the RoundManager upgrade.
4. ABIs: regenerate the registry, DealManager, RoundManager and MetaDAOFactory ABIs in
   `packages/abis` and `apps/cybercorps-indexer/abis`. Map the new errors.
5. Stale offers: offers posted before the upgrade cannot be accepted. Show them as "post again".

No change: Umia (ParentCo) escrow page, RoundManager officer signature, round close calls, indexer events.

## Decisions and evidence

Related findings (Hexens report in `audits/`):

- MTLX1-24 (Low, Acknowledged): officer signature does not cover the agreement body. Unchanged.
- MTLX1-26 (Low, Fixed): round signature reuse through a weaker factory. Type unchanged, still holds.
- MTLX1-30 (Low, Acknowledged): claimable agreement IDs. Closed in code on 2026-11-27 (owner
  request, branch `feat/registry-attestation-cleanup`): `createContract` reverts `NotFinalizer`
  unless `msg.sender == finalizer`. Not deployed. The recorded audit response is unchanged.
- MTLX1-39 (Medium, Acknowledged): standalone signature moved to a squatted ID. Closed in code on
  2026-11-27 (owner request): the same check refuses `finalizer = address(0)`, and
  `createStandaloneContractAndSign(For)` are removed. Agreements with no finalizer use only the bound
  path. Blocker for the registry upgrade: the webapp still creates agreements with no finalizer
  (`emailSigning.ts`, `privateDocumentEnvelope.ts`, governance documents, GAIBE and cyberSign
  standalone). The `docs/` pages still describe the deployed standalone path.
- MTLX1-37 (Low, Fixed): delegate replay. Escrow path accepts no delegates.
- MTLX1-41 (High, Fixed) and MTLX1-3 (Medium, Fixed): the domain binds the finalizer address only;
  the existing bindings in the round flow are unchanged.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --nmc '(ForkTest\|AdhocTest)'`; base 13418fb5 + working tree | 1597 passed, 0 failed |
| Sizes | `forge build ... --sizes` | Registry 23,266 B; RoundManager 24,451 B (125 B margin); DealManager 22,248 B |
| Fork tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`; same tree | 228 passed, 0 failed, 1 skipped. The three tests that ran deployed callers now upgrade them first (FCFS: RoundManager ref implementation; v5 upgrade: registry starts on the Base implementation, then registry and RoundManager upgrade; ParentCo: a ParentCo officer upgrades the live Umia factory, whose live officer signature passes) |

Finalizer-only signing, 2026-11-24, on 0dcf8dd8 plus the uncommitted registry and test changes:

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --nmc '(ForkTest\|AdhocTest)'` | 1598 passed, 0 failed |
| Fork tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --mc ForkTest --nmc AdhocTest --threads 1 --cups 10` | 228 passed, 0 failed, 1 skipped. A first run had one DNS failure in `MulticallFormationFeeForkTest` setUp; the rerun passed |
| Sizes | `forge build ... --sizes` | Registry 23,240 B (26 B smaller than 0dcf8dd8). The `onlyFinalizerIfSet` modifier form was 26,204 B and was not used |

## Issue #218 dispositions (2026-11-25)

Owner decisions on 2026-11-25:

- Case 1 (removed 6-argument `signContractWithEscrow`): hard cutover. Every manager must upgrade
  before it uses the new registry. No legacy overload, no allowlist. PR #219 fork tests confirm the
  revert for live Base v4 and v5.1 RoundManagers and a v5 DealManager after a registry-only upgrade.
- Case 3 (`proposeDeal`, company signs after the investor pays): fixed by `DealManager.signDeal`
  (first party only; relays allowed). The registry finalizer-only rule is unchanged.
  `signAndFinalizeDeal` is not an alternative after payment (`DealNotPending`). The production UI does
  not send `DealManager.proposeDeal`; only `EscrowedDealPanel` signs such a deal, through the registry.
- Case 4 (EOA/Safe finalizer service agreements): no fix. No mainnet use; MetaVesT service template
  registration is commented out.
- Case 5 (MetaVesT grantee): no break.
- Umia `ParentCoFactory` (Ethereum, customer-owned, upgrade not pinned) and `MetaDAOFactory` (Base,
  deployer-owned auth) also call the removed selector and must upgrade with the cutover.

Tests: `test/DealManagerSignDealTest.t.sol` (6 tests, real registry, factories and company).

Version bump (2026-11-25): `RoundManager.DEPLOY_VERSION` is `"5.2"` and `DealManager.DEPLOY_VERSION`
is `"5.1"`. The live Base 5.1 `RoundManager` and v5 `DealManager` report the old strings, so the webapp
can find un-upgraded managers with `DEPLOY_VERSION()`. Gabriel accepted the hard cutover with an in-app
upgrade prompt. `UpgradeRoundManagerV51ScriptForkTest` is removed: the 5.1 upgrade is live, and the
script now builds 5.2.

## Next action and handoff

Owner reviews the diff and decides on commit. Independent review is required before merge.
