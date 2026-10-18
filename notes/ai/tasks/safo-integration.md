# Native SAFO integration: Reg D and Reg S

Updated 2026-10-18. Owner: Codex, current cyberForms task.

The owner explicitly approved the narrow native-SAFO contract rollout, both Reg D/Reg S activation after checks, and waived independent Claude review. Settled v22 economics and approved v1.1 notices PDFs remain fixed. The rollout covers a Base Sepolia pilot then coordinated Ethereum/Base/Arbitrum: separate SAFO extension; compatible IM/LET and libraries; shared URI/image builders; DM; RM/library; combined company factory and existing reference setters. It excludes unrelated implementations, ownership changes and blanket upgrades of existing companies. Runtime/fork/regression/CI checks and normal app release order remain required. No new external audit or private-code upload is authorized.

Implementation PRs #180 and app #1769 are merged; their monitors remain retired. Rollout branch `codex/safo-rollout-20261018` starts at develop `0661a0563572a4bb6560b64497f211224faefe14`. App activation branch is `codex/safo-activation-20261018`. No rollout transaction has been sent. Next: prepare narrow deterministic deployment and admin batches, verify authority, and rehearse storage/legacy/native routes against current testnet runtime. Do not run broad upgrade scripts which change unrelated contracts or drop ownership.

The cross-repository task record in `metalex-webapp/notes/ai/tasks/safo-integration.md` owns current release status; historical implementation evidence below remains dated.

## October 18 rollout checkpoint

The app operator tools at `scripts/safo-rollout/` prepare narrow unsigned CreateX deployments, owner calls and v1.1 registrations. All four chain packages are prepared. Base Sepolia deployment rehearsal passed: 21 calls, exact deployed code hashes, six unauthorized-upgrade refusals, 581 sampled storage words with seven intended changes, native label 14 and exact Reg D/S registry readbacks. Only the local fork changed.

`SAFORolloutForkTest` reuses the 11 existing SAFO signature/payment/allocation cases against actual forked factories, registry, extension and payment token. All 11 passed after the proposed rollout on Base Sepolia. The five source suites still pass all 113 tests. Source under test is develop `0661a056` plus this working tree's fixture and three virtual test hooks. The fork fixture skips explicitly when its generated plan is absent; no hosted RPC secret is required by default. Separate operator acceptance signs, simulates and submits local RPC transactions, verifies existing-company upgrade refusal/preservation and tests both native variants after owner upgrades. No live company is upgraded by these tests.

Full `forge build --sizes` compiled but exits nonzero for pre-existing test artifacts CyberCertPrinterEnhanced and HolderCountHarness. All 13 release artifacts satisfy EIP-170/EIP-3860 and deploy in the rehearsal. Production fork checks and repository review remain pending. No live pilot, production upgrade, registration or activation has occurred. Base Sepolia deployer access is pending; production Safe quorum is three on Ethereum and two on Base/Arbitrum. Preserve these signing boundaries.

## Source and implementation

Branch: `codex/safo-integration`. Code: `e74e22abca685ea705a22cda4937a4f8a1394841`. This retains SAFO extension `e294600d` and merges current develop `f2a4243` through `e4fcf23`. The matching app branch is `codex/safo-integration`, application code `1bf65ae2f2`, retaining develop merge `72b77fe15f`.

The extension follows the approved per-LET schema 1, with explicit presence flags and raw integer terms. Native `SecurityClass.SAFO` is appended as 14; values 0–13 remain unchanged. URI/image builders identify SAFO and display one instrument with total consideration. Existing core storage declarations, agreement IDs and signature formats are unchanged. Both new template specifications use 19 global and 5 party fields. Publication URIs remain pending.

The cross-repository discovery, complete app/legal status and release ownership live in `metalex-webapp/notes/ai/tasks/safo-integration.md`. This record owns contract evidence; it is not a second release plan. See [extension schema](../../../docs/reference/safo-extension.md), [Reg D](../../../templates/mlx_safo_reg_d_v1_0.md) and [Reg S](../../../templates/mlx_safo_reg_s_v1_0.md).

## Verified locally

113 tests passed, zero failures or skips, across five matching suites (SAFO extension/integration, IssuanceManager, RoundManager, DealManager). Command:

```bash
forge test --match-contract '^(SAFOExtensionTest|SAFOIntegrationTest|IssuanceManagerTest|RoundManagerTest|DealManagerTest|CertificateUriBuilderTest|CertificateImageBuilderTest|CyberCorpFactoryTest)$' -vv
```

Eleven native integration cases cover both exemptions through signed ticket payment/finalization, FCFS EOI/allocation, founder-approved partial allocation/refund, combined new-company rounds and tickets, plus refusal when metadata changes after signature. They use actual registry/managers/LET contracts and a six-decimal test payment token. Ticket settlement preserves the original proposal Issue Date. Duplicate settlement/allocation refuses. Extension tests include native metadata/SVG, initialization/upgrade authority, optional false/zero, malformed data and 256 fuzz cases. Existing issuance/round/deal regressions pass.

No deployed upgrade/storage acceptance or target-company RPC sign → simulate → submit test has occurred. A local source test does not establish live capability. Required independent external-model review remains open; the local app reviewer is not that review. No external audit was started.

## Release constraints and next action

Review this PR and the matching app PR, then approve a concrete pilot/release plan separately. Required coordinated deployment includes the new extension proxy/AUTH, IM/LET and linked storage libraries, URI/image builders/content library, DM new-printer wrapper, RM/library, and combined company factory. Existing companies require their actual components and LET beacon checked and owner upgrades where necessary. Builder/beacon changes can affect existing instruments. No registry, CyberCorp, single-factory or escrow implementation change is proposed.

Before activation: approve the new Reg S offering adaptation; publish exact clean PDFs; register both templates per approved chain; verify actual runtime hashes, references, exact registered fields/legends and payment assets; complete external review and isolated target-runtime acceptance; populate the app release manifest; approve hosted indexer rollout; promote the app develop → staging → production. No step here is authorized merely by this record. Existing review/audit ownership remains unchanged.

## First GitHub review dispositions

Review #5561133969 identified accepted noncanonical payload bytes and stale documentation about native class 14. Two tests reproduced the decoding defect against `acc1d42`. Commit `e74e22a` compares decoded/re-encoded bytes and rejects trailing bytes or nonzero string padding with `NoncanonicalEncoding` on decoder, validator and renderer. Both tests pass; all 113 protocol tests pass. Native-class documentation is corrected. The paired app ABI matches the compiled extension exactly. This changes malformed-payload acceptance only; canonical schema-1 layout, storage and signatures remain unchanged.

## Owner approval and next release step (2026-10-17)

The owner approved the submitted Reg D/Reg S implementation and document package and asked for the next step. This clears the owner review of the new Reg S legal adaptation. The legal files are unchanged from the approved package; clean PDF hashes are:

- cyberSAFO - Reg D - clean.pdf: `eff41a0c6b75b05ba7f892b798698b1861b4a5c5bc6c86bf4b6a9a9709b4f3e5`.
- cyberSAFO - Reg S - clean.pdf: `c99c64d813f988861bd4c95f7da35d470badf587a807042f98e00c1fd48baf03`.
- mlx_safo_reg_d_v1_0.pdf: `ffdea368e833059496b31e672d0d10204ed97221943d394648b4573f4b36c810`.
- mlx_safo_reg_s_v1_0.pdf: `d629378f4da59db3fda6a49db23d823b288c46a2b4e45dec6a28c2447e2b056d`.

This approval does not waive CI, independent external-model review or isolated target-runtime acceptance. The owner asked for next steps; no new publication, live transactions, merge, upgrade or production activation was performed. Recommended sequence: close technical checks/review; publish the four clean PDFs with verified CIDs; perform an approved Base Sepolia pilot with both templates and compatible components; then coordinate mainnet upgrade/registration and app promotion through develop → staging → production.
