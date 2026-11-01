# Robinhood post-v5 comparison and lifecycle acceptance

- Owner: current Codex chat; read-only production comparison and local fork tests.
- Date: 2026-10-30. Branch: `codex/robinhood-intermediate-20261028`.
- Source base: `b59269beea86f7ccb14c516361140519c8da8f2c`.
- Context: user reports the final Safe batch executed. Prior evidence and separate
  review/release gates: [final preparation](robinhood-final-v5-20261030.md).
- Preserve operator edits: `foundry.toml`, final Safe JSON, untracked bootstrap
  Safe JSON and deployment log. No live signing, submission, upgrades or merging.

## Acceptance criteria established before implementation

1. Pin Robinhood and Base read-only snapshots. Compare critical auth/proxy
   addresses, deployed implementations and factory wiring; explain expected
   payment-token differences. Check actual final Safe batch postconditions.
2. Exercise deployed Robinhood factories without upgrading/replacing contracts:
   permissionless company creation, officer ownership, component wiring, SAFE
   round creation, investor EIP-712 signing, payment, allocation and LET issuance.
3. Use public toy signer keys and local token funding only. Attempt production
   templates/extensions first; explicitly disclose any missing production setup
   and any locally installed fixture. Do not turn a fixture pass into readiness.
4. Assert token accounting, fee/payout, agreement finalization, investor LET
   ownership, SAFE classification and metadata. Include unauthorized and invalid
   signature refusal paths with no payment/issuance side effects.
5. Record exact blocks, source revision, commands/results and limitations. Fork
   sign/simulate execution is separate from real test-environment submission,
   independent external-model review and production acceptance.

## Result: upgrade activated; SAFE template registration remains

Read-only snapshots: Robinhood **101773759**, Base **53289424**, with block hashes
in [comparison evidence](robinhood-post-v5-comparison-20261030.json). Refreshed
`origin/develop` remains `7ce4e1c825998de5cf309e620d1e9d8e0d1b543d`.
The current operator final batch contains **22 calls**, not the earlier rehearsal's
23. Its SHA-256 is
`fd682b68fd20367f4299f91ee2b075f95bc00994078fabbdf3b2eba5b934413e`.
All **23 state checks** pass: one per call plus the URI upgrade's nested image
builder initialization. This verifies resulting state, not a Safe execution
receipt; execution itself was reported by the user, without a transaction hash.

- All 22 sampled critical auth/proxy/extension/kill-switch addresses have code on
  both chains. Critical auth and proxy addresses match; 21 sampled runtime hashes
  match exactly. The shared kill switch's runtime differs, but its observed admins
  match (MetaLeX Safe and `0x5ff4…9Abf`) and `killed` is false on both chains.
- Four component factory addresses, core registry/URI/LeXcheX-auth references,
  Safe roles, badge AUTH and badge minter keys agree. Robinhood payment is Global
  Dollar **USDG**, 6 decimals, `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`;
  Base uses USDC. Both payment tokens are whitelisted for the large-investment
  LeXcheX mint path; that mint path itself was not exercised.
- Primary round/deal fees: **50 bps on Robinhood**, **30 bps on Base**. Secondary
  deal fees: **500 bps** on both. No fee change was made.
- Implementation addresses are chain-specific. Eleven of 25 compared runtime
  bodies agree after removing Solidity CBOR metadata and the contract's own
  address. Badge and Share V3 bodies differ only in PUSH20 address operands;
  that observation does not establish equivalence of their dependencies/state.
  Other implementations differ, including registry (22942 vs 24338 bytes) and
  URI builder (21721 vs 21670 bytes). Do not claim implementation/version parity.
  The new signer-condition config getter succeeds on Robinhood with the exact
  production verifier/domain/scope/devMode=false payload in the operator batch;
  the same getter reverts on Base at its pinned block.
- Standard Reg S SAFE template **32** and ACE SAFE IDs `ace_safev1` /
  `ace_safe_reg_d_v1` revert on Robinhood. Base has template 32 and `ace_safev1`;
  its Reg D ACE ID also reverts. This is a check of these specific IDs, not a
  claim that every possible template is absent.

## Deployed-code lifecycle tests

New opt-in [test](../../../test/RobinhoodPostUpgradeLifecycleTest.t.sol) and
[runner](../../../script/test-robinhood-post-upgrade.py) exercise actual deployed
factories, implementations, linked libraries, registry, USDG/USDC and SAFE V3.
They never run UpgradeV5Script, replace code, mock calls or impersonate the Safe.
Local funding uses `deal` on the real token; signer keys derive from public test
labels and are verified to have no on-chain code. All company/LET addresses below
are **fork-only**, not production deployments.

**Robinhood: 3 passed, 0 failed, 0 skipped. Base control: 2 passed, 0 failed,
1 deliberately skipped Robinhood-only missing-template check.**

1. As deployed, permissionless formation succeeds, and a SAFE round/printer can
   be created. Investor submission then reverts `TemplateDoesNotExist` for ID 32;
   investor funds and escrow remain unchanged. This is a reproduced production
   configuration gap: round creation itself does not check template registration.
2. In separate explicit fixture tests, copy the exact template 32 definition
   (URI/title/global/signer fields) from the pinned Base registry into the
   **local Robinhood fork only**, using the permissionless `createTemplate` API.
   Base control uses its existing template with no registration fixture.
3. Formation by an unprivileged relayer grants that caller no role. The officer
   has role 200; the infrastructure CyberCorpFactory retains role 99 in the current
   deployed design. This is not exclusive officer ownership. Company, issuance,
   round manager, shared AUTH, payout and v5 version wiring are asserted.
4. Officer signs round parameters using EIP-712. Investor signs the actual
   registry agreement using EIP-712, deposits **10,000 USDG**, and receives a
   **7,500 USDG** allocation. Company receives **7,462.50**, platform receives
   **37.50**, investor receives a **2,500** refund; escrow ends empty and finalized.
   Base control has the corresponding **22.50 USDC** fee and **7,477.50** payout.
5. Agreement is finalized and both signatures are recorded. Investor holds both
   delivery/legal ownership of the issued SeriesSeed SAFE LET, token 0, with
   correct 18-decimal investment/valuation/units, officer details, endorsement,
   real SAFE V3 series and certificate extension payloads. Metadata is valid JSON;
   embedded SVG parses and contains the issuer name. The runner checks rendered
   SAFE type/series, $7,500 investment and scoped extension details.
6. Unauthorized round creation/allocation and wrong-key investor signatures
   revert without issuance/payment side effects. Early recall refuses; after a
   local time warp past offer expiry, investor recall voids and fully refunds it.

Robinhood fixture company: `0x3F74c0afAf210D31f38f8B7B4c6C6948451CA949`;
SAFE LET: `0x0044331a23963bF976fE39fDBe6684a48A51aE77`.
Base control company: `0x09866BbF57655eA3685176b978549294d4886E13`;
SAFE LET: `0x86b2F0ff0c756782D783ea2E382c93E0943Bc611`.

## Reproduction and scope

From the repository root, using existing ignored Robinhood RPC configuration:

```powershell
$env:RPC_URL_BASE='https://base-rpc.publicnode.com'
$env:ROBINHOOD_COMPARE_BLOCK='101773759'
$env:BASE_COMPARE_BLOCK='53289424'
python script/check-robinhood-post-upgrade.py
python script/test-robinhood-post-upgrade.py
python script/test-robinhood-post-upgrade.py base
```

The comparison is read-only. The test runner uses Foundry/Solc 0.8.28, Cancun,
via-IR, optimizer 15, one thread and explicit OpenZeppelin remappings; no broadcast
or real key. Sanitized logs, decoded certificate JSON and SVG are local ignored
files under `out/robinhood-post-v5/`. Content hashes and result counts are in
[lifecycle evidence](robinhood-post-v5-lifecycle-20261030.json).
The checked contract source is base `b59269b`; tests/scripts/report are new local
working-tree additions. `src/` and deployment sources were not changed. The
existing `deps()` helper lacks Robinhood support, so the test asserts USDG against
its explicit observed address instead of calling that USDC helper for chain 4663.

**Next action:** register the intended production SAFE template(s) on Robinhood,
then rerun the end-to-end acceptance against that actual configured state.
No production template registration payload was executed or authorized here.
The test chooses template 32 as a standard SAFE control; it does not establish
legal suitability or app selection of that specific template.

No LeXcheX issuance, actual passport proof, explicit investor compliance conditions,
frontend flow, live signer/quorum control or real test-environment transaction
submission was covered. Independent external-model review and those integration
gates remain separate. No live transaction was signed/submitted, no Safe executed
by this task, no code upgrade or role change made, and nothing merged or pushed.
Operator dirty files were preserved. This handoff is local-only until committed
and deliberately shared.
