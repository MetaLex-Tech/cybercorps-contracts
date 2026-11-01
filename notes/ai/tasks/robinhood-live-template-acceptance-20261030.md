# Robinhood acceptance after live template registration

- Owner: current Codex chat; read-only chain checks and local fork simulation.
- Date: 2026-10-30. Branch: `codex/robinhood-intermediate-20261028`.
- Source base: `b59269beea86f7ccb14c516361140519c8da8f2c` plus the existing local
  lifecycle test/runner additions. Preserve all operator files and prior evidence.
- Status: fresh deployed-state readback and strict local fork acceptance passed.
- User reports template registration completed and requests full CyberCorp
  formation and SAFE LET round creation testing.
- Context: [template deployment preparation](robinhood-base-template-sync-20261030.md)
  and [prior lifecycle acceptance](robinhood-post-v5-acceptance-20261030.md).

## Acceptance criteria before harness changes

1. Pin fresh Robinhood block/hash and read back all 86 selected template definitions
   against the prepared Base manifest; record any missing or conflicting ID.
   Confirm legacy ID 1 remains the recorded Robinhood definition.
2. Strict live-template mode must never register a fixture template, run an upgrade
   or call the deployment script. Missing production configuration must fail.
3. Use deployed factories/registry/SAFE V3 extension and actual USDG on the fork.
   Use generated public test officer/investor keys and local token funding only.
   Never access `PRIVATE_KEY_MAIN`, insert a deployment key or submit live calls.
   This request authorizes lifecycle tests, not testing the key-based deployment
   script that the user previously explicitly excluded from testing.
4. Verify company/component AUTH and officer wiring; SAFE round/printer creation;
   officer and investor typed signatures; escrow funding, partial allocation,
   fee/payout/refund accounting; finalized agreement; investor delivery/legal LET
   ownership; class/series/extension/endorsement and actual JSON/SVG rendering.
5. Include wrong-signature and unauthorized-operation refusals with no issuance
   side effects, plus early-refund refusal and expired-offer refund success.
6. Save exact blocks, commands, result counts and source/artifact hashes. Fork
   signing/simulation is separate from real test-environment submission, app
   acceptance and independent external-model review. No live transaction signed
   or submitted by this task.

## Progress

Fresh readback at Robinhood **102202000** confirms **86/86 exact definitions**,
with no missing, failed or conflicting IDs. Legacy ID 1's definition hash matches
the preserved Robinhood definition. See
[readback evidence](robinhood-live-template-readback-20261030.json).

The new strict live-template harness subclasses the existing lifecycle assertions
and replaces the fixture-install hook with a read-only configuration check. Its
runner selects only this lifecycle test file and excludes the inherited historical
missing-template scenario. No registration or key-based deployment test is run.

## Result

**3 passed, 0 failed, 0 skipped** at block **102202000**, hash
`0x63b16eac4c8f0840393409ea9b1b2fd6bfa9709add81b0e043206c0fdd4467b2`.
The source block hash was checked again after execution and remained canonical.
No template fixture or registration was installed and no deployment/upgrade
script was invoked. This supersedes the earlier missing-template limitation for
the selected 86 IDs and the standard Reg S SAFE ID 32.

- Formation through the deployed factory creates the company, AUTH, issuance,
  deal and round components. Component wiring, officer role, absence of relayer
  authority, payout and v5 versions pass. Existing infrastructure factory role
  99 remains part of deployed formation behavior; this is not exclusive ownership.
- The deployed standard SAFE template 32 is read and its exact URI/title and
  ordered global/signer fields asserted. The actual SAFE V3 extension is used.
- A founder-approved private SeriesSeed SAFE round and LET printer are created
  with an officer EIP-712 round signature. A generated investor signs the actual
  deployed registry's EIP-712 agreement and deposits **10,000 USDG** on the fork.
- Officer allocates **7,500 USDG**: company payout **7,462.50**, platform fee
  **37.50** (50 bps), investor refund **2,500**. Escrow ends empty and finalized;
  round raised equals the allocation; both signatures and finalized agreement
  are recorded. All balances are asserted against the actual USDG contract.
- Investor receives delivery and legal ownership of SAFE LET token **0**, with
  correct SAFE/SeriesSeed classification, 18-decimal investment/valuation/units,
  officer details, endorsement and scoped extension data. Certificate metadata
  parses as JSON; embedded SVG parses and includes the issuer name.
- Unauthorized round creation/allocation and wrong-key investor signatures
  refuse without issuance/payment side effects. Early recall refuses; after a
  local expiry time warp, recall voids the agreement and refunds the offer.

Fork-only company: `0x3F74c0afAf210D31f38f8B7B4c6C6948451CA949`.
Fork-only SAFE LET: `0x0044331a23963bF976fE39fDBe6684a48A51aE77`.
These are simulation addresses, not production deployments by this task.

## Evidence and reproduction

- [Lifecycle evidence](robinhood-live-template-lifecycle-20261030.json): individual
  tests, source revision, exact blocks, command, source/log/artifact hashes and
  explicit fixture/deployment/live-submission flags.
- [Readback evidence](robinhood-live-template-readback-20261030.json): all 86 IDs
  match exact Base manifest definitions; legacy ID 1 remains unchanged.
- [Strict harness](../../../test/RobinhoodLiveTemplateLifecycleTest.t.sol) reuses
  [existing lifecycle assertions](../../../test/RobinhoodPostUpgradeLifecycleTest.t.sol)
  with a read-only template hook. Inherited `ForkTemplateFixture` test names are
  historical names; the strict subclass never installs a template.
- [Runner](../../../script/test-robinhood-live-templates.py):
  `python script/test-robinhood-live-templates.py` checks a fresh head each run.
  It uses Solc 0.8.28, Cancun, optimizer 15/via-IR, one thread, offline compilation
  and explicit OpenZeppelin remappings. Existing compiler warnings were nonfatal.
- Sanitized log, decoded metadata and SVG are local ignored files under
  `out/robinhood-live-templates/`. Source and artifact hashes were checked after
  execution; formatting, Python compilation and diff-whitespace checks passed.

No `PRIVATE_KEY_MAIN` lookup or environment/key mutation was performed. Operator
files, deployment manifests, signing script and protocol `src/` were not changed.
This evidence covers base `b59269b` plus new local test/runner files; nothing
merged or pushed. Records remain local working-tree additions until shared.

This validates contract-level formation and a private founder-approved standard
SAFE flow on a fresh production fork. It does not establish frontend readiness,
actual LeXcheX/passport proof issuance, investor-compliance condition coverage,
real test-environment transaction submission, independent review or live release
approval. No live transaction was signed or submitted by this task.
