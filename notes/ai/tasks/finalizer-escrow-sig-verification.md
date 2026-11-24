# Task: Registry checks the party's signature on escrow signing

- **Status:** Active (implemented and unit-tested locally; not committed, not reviewed)
- **Updated:** 2026-11-23
- **Owner:** Claude Code session, for the owner
- **Collaborators / boundaries:** Registry, RoundManager, DealManager secondary trade,
  ParentCoFactory and MetaDAOFactory. No deployment, upgrade, webapp change or audit was started.
- **Objective:** `signContractWithEscrow` records a party only with a signature that the party gave
  in the calling finalizer's own EIP-712 domain. A finalizer that the agreement creator chose can
  no longer record a party who never signed for it (the escrow signature forgery).
- **Out of scope:** New prefixed escrow types and the agreement-body hash for rounds (MTLX1-24
  stays Acknowledged). Finalizer-only mutation, the notary design, derived expiry.
- **Canonical plan / sources:** Discussion summary artifact "Registry as notary"; option B in the
  "Escrow Signature Binding" report; [attestation binding rule](../../../specs/analysis/attestation%20binding%20rule.md).
  Owner choices on 2026-11-23: reuse today's officer types; secondary trade gets a new offeror type.
- **Repository / branch:** cybercorps-contracts; branch `feat/finalizer-escrow-sig-verification`
  (no upstream)
- **Verified base / code head:** base 13418fb5; first part committed as 1f4fff96 (wip). Latest tests ran on 1f4fff96 plus the uncommitted restore and fork-test changes
- **PR / artifact:** not yet created

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

## Webapp follow-up after merge

Checked against `../metalex-webapp` on 2026-11-24.

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
- MTLX1-30 (Low, Acknowledged): claimable agreement IDs. Unchanged.
- MTLX1-37 (Low, Fixed): delegate replay. Escrow path accepts no delegates.
- MTLX1-41 (High, Fixed) and MTLX1-3 (Medium, Fixed): the domain binds the finalizer address only;
  the existing bindings in the round flow are unchanged.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --nmc '(ForkTest\|AdhocTest)'`; base 13418fb5 + working tree | 1597 passed, 0 failed |
| Sizes | `forge build ... --sizes` | Registry 23,266 B; RoundManager 24,451 B (125 B margin); DealManager 22,248 B |
| Fork tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 -vvv --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`; same tree | 228 passed, 0 failed, 1 skipped. The three tests that ran deployed callers now upgrade them first (FCFS: RoundManager ref implementation; v5 upgrade: registry starts on the Base implementation, then registry and RoundManager upgrade; ParentCo: a ParentCo officer upgrades the live Umia factory, whose live officer signature passes) |

## Next action and handoff

Owner reviews the diff and decides on commit. Independent review is required before merge.
