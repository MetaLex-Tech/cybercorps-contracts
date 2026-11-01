# Base to Robinhood agreement template synchronization

- Owner: current Codex chat; deployment-tool preparation and fork testing only.
- Date: 2026-10-30. Branch: `codex/robinhood-intermediate-20261028`.
- Source base: `b59269beea86f7ccb14c516361140519c8da8f2c`.
- Status: implemented and locally validated; operator deployment remains separate.
- Later live-state acceptance: user reports registration completed; fresh block
  102202000 confirms all 86 selected definitions. See the superseding
  [fixture-free lifecycle acceptance](robinhood-live-template-acceptance-20261030.md).
- User request: make a script to deploy all matching templates from Base.
- Context: [post-upgrade acceptance](robinhood-post-v5-acceptance-20261030.md)
  reproduced missing standard SAFE template 32 on Robinhood.
- Preserve existing dirty operator files and prior task additions. No authority
  to broadcast, sign real transactions, merge, or start an external audit.

## Invariants and acceptance criteria before implementation

Follow-up signing change, requested by the user: the Forge entrypoint loads
`PRIVATE_KEY_MAIN` from the environment and uses `vm.broadcast(deployerPrivateKey)`
after full preflight. The user explicitly instructed **not to test or insert a
key**, superseding the initially proposed toy-key validation. No tests, key reads,
key insertion or environment edits were performed for this change. The runbook
now uses the environment variable without keystore/CLI key arguments. Earlier
17-test evidence predates this signing change and does not validate it. This
grants no live broadcast.

1. Discover all `TemplateCreated` IDs emitted by the canonical Base registry
   through a pinned source block, not a list of presumed numeric IDs. Account
   for templates created inline by the bound agreement API as well as scripts.
   Export exact current title, legal URI, ordered global fields and signer fields.
2. Preserve template IDs and bytes, including URI casing and field order. Never
   rewrite Base definitions for Robinhood, invent templates absent on Base, copy
   agreements/signatures, or alter implementation/auth/proxy/fee configuration.
3. Deploy only to chain 4663's canonical registry. Validate the full manifest and
   all destination IDs before any registration: exact existing definitions skip;
   conflicting definitions, malformed/duplicate IDs or unexpected RPC reverts fail.
   Allow safe reruns after a partially completed operator broadcast.
4. Provide a pinned, reviewable manifest and straightforward Forge dry-run and
   operator broadcast commands. No private key is required by preparation tools;
   the deployer selects their wallet using standard Foundry options.
5. Test exact bytes/field-order parity, first deployment, idempotent rerun,
   preexisting conflict (with no earlier writes), wrong chain and malformed input.
   Run all real exported definitions against the actual Robinhood registry on a
   local fork, then exercise SAFE issuance using the imported standard template.
6. Keep local fork sign/simulate results distinct from real test-environment
   sign/simulate/submit and independent external-model review/release gates.

## Export and destination plan

Refreshed develop reference remains `7ce4e1c`; no merge or source upgrade performed.
Complete Base Blockscout indexed query, from genesis through **53290002**, returned
**87 creation events / 87 distinct IDs**, below its response cap. Direct explorer
HTTP requests encountered Cloudflare, so the public JSON was read through the
in-app browser. The checked-in [event inventory](../../../script/res/base-template-events.json)
records that query. Its IDs were independently verified by reading **all 87 exact
definitions** from Base RPC at the pinned block, hash
`0x7a72032036f4b0f098ea91b49ec04baedd1447325b3d22f814cb839b259ed54b`.
No private code or credentials were sent to an explorer. The exporter reads only
allowlisted RPC/API configuration and never a signing key.

Follow-up: the user-supplied Base endpoint is now saved as `RPC_URL_BASE` in the
ignored local `.env`. Read-only checks confirmed chain 8453 and the exact pinned
source block hash. Its provider plan also limits historical log ranges to 10
blocks; the completed indexed event inventory remains the reproduction input.
No endpoint credential was added to shared records or deployment manifests.

[Full Base snapshot](../../../script/res/base-templates.json), SHA-256
`bf3d3f20d0a45661977fb085920b6d5e143e3c466b87e0da53eb801a32917832`,
includes legacy, bespoke and test templates as requested by "all". The actual
Base ACE Reg D ID is **`ace_safe_regd_v1`**, distinct from the existing repository
helper's `ace_safe_reg_d_v1`. The export preserves the actual registered ID.

At Robinhood **101773759**, **86 IDs are missing**, **0 match**, and **1 conflicts**.
Legacy SAFE ID **1** already exists with a different IPFS document. Its fields
and title match, but the URI CIDs differ:

- Base: `bafybeig6hszt562xsvcyumiph4kz5u5stgecpusbjw6hiycgxth42afezq`.
- Preserved Robinhood: `bafybeih5wvr7zfw76plnb66teaa66rtgoikhhcqh55oecuoxtuw5c3dooi`.

Existing registry templates have no overwrite operation. Preserve ID 1 without
upgrading the registry, substituting a new ID or changing existing agreements.
The [destination deployment plan](../../../script/res/robinhood-base-templates.json)
therefore selects the other **86** exact Base definitions and records both ID-1
definitions in `destinationAudit.conflicts`. Its SHA-256 is
`c463a163df85afcf2671733182fcd1020e130b5fdedbbaa3beb3571871dba403`.
This is an explicit exclusion in a reviewable deployment input, not a runtime
"ignore all conflicts" flag. Any unexpected conflict within the selected IDs
still refuses before registration. The full 87-entry Base snapshot remains intact.

## Implementation and validation

- [Exporter](../../../script/export-base-templates.py): complete indexed inventory
  or bounded historical-RPC discovery, pinned getter reads, source-block reorg
  check and atomic output. Current Alchemy free log queries are limited to 10
  blocks; the Etherscan API plan excludes Base. The supplied event inventory
  avoids those limitations when reproducing this exact snapshot. Public RPC
  accepted recent bounded queries but refused older log ranges; no partial
  scan was accepted as a complete inventory.
- [Destination planner](../../../script/prepare-robinhood-templates.py): pinned
  read-only comparison, exact missing-error handling, all known differences
  recorded/excluded, atomic target-plan output. No signing key is read.
- [Forge entrypoint](../../../script/sync-base-templates.s.sol): validates source
  and target metadata, runs entire list preflight before `vm.broadcast()`, skips
  exact matches, refuses unknown conflicts/duplicate/malformed entries, and reads
  back every registration. The later user-requested signer change reads
  `PRIVATE_KEY_MAIN` from the environment; it was not tested, per explicit user
  instruction. No Safe, proxy, AUTH, implementation, fee or payment-token operation.
- **13 unit safeguards passed**. Initial complete-snapshot fork rehearsal refused
  the real immutable ID-1 conflict as designed; the destination plan was then
  prepared with that explicit preserved-ID exclusion. The strict full-snapshot
  refusal remains a separate fork regression.
- **Final suite: 17 passed, 0 failed, 0 skipped** (13 unit safeguards and 4 actual
  Robinhood fork scenarios). All 86 selected definitions register and pass exact
  hash checks. The production entrypoint rerun registers 0 and skips 86. Legacy
  ID 1 and the registry implementation slot remain unchanged. The strict full
  87-entry snapshot correctly refuses its legacy collision before any registration.
  Full signed USDG SAFE investment/allocation/LET issuance and rendered JSON/SVG
  checks pass using the imported template. Unauthorized creation/allocation,
  invalid investor signatures and early recall refuse; expiry recall refunds.
  The unchanged as-deployed missing-template refusal is reproduced separately.
  [Verification evidence](robinhood-base-template-sync-verification-20261030.json)
  records blocks, file hashes, commands and individual test results. Full cold-cache
  fork run took approximately 294 seconds. Existing compiler warnings remain.
- All production `src/` files remain unchanged.
  The existing lifecycle helper was marked `virtual` solely to reuse its assertions
  with the actual complete import script rather than its one-template fixture.

## Operator handoff

[Runbook](../../../script/res/base-template-sync.md) provides the dry run,
operator-selected wallet/broadcast and post-receipt rerun. Registering template
data requires no source verification. The task has not signed/submitted a live
transaction. Independent external-model review and real test-environment
sign/simulate/submit integration gates remain separate. Operator dirty files and
prior task records/outputs are preserved. New files are local working-tree
additions until deliberately committed/shared; nothing has been pushed.
