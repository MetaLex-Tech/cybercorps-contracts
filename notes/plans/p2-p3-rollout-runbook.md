# P2/P3 coordinated rollout runbook

**Status:** deployable tooling is implemented locally; no live upgrade or
migration has been performed from this worktree.

This runbook coordinates:

- **P2:** upgraded `ShareExtension` parsing, the externalized
  `ShareClassTermsController`, IssuanceManager 4.2 lifecycle enforcement,
  canonical class terms, and authorized-share caps. The LedgerEntryToken
  implementation is updated (void/unvoid accounting hook,
  `syncClassTermsOnVoidStatus`) with **no storage change**; the per-corp
  migration syncs each printer beacon to the factory's published reference in
  the same transaction, so the updated reference must be published first (see
  global step 4).
- **P3:** CyberAgreementRegistry 3.3 content-addressed public template creation
  plus the matching webapp ABI/call site.

Every `forge script` command must be simulated without `--broadcast` first.
Production broadcasts require the relevant MetaLeX/global owner or individual
corp owner; repository access is not upgrade authority.

## 1. Scope the rollout

Use the webapp launch-baseline shortlist, not all historical test corps. Start
with one named demo corp, then the first supported real pilot. For each record:

- chain, corp, IssuanceManager, share-printer, current extension, and renderer
  addresses;
- current implementation addresses and `DEPLOY_VERSION` values;
- the reviewed source certificate/token id for each existing share printer;
- charter/class-authority evidence supporting its `SeriesTerms`; and
- independently reconciled active certificate plus scrip units.

Stop if prior certificates on one printer disagree on class terms. Migration
chooses one canonical record and must not guess through a legal/data conflict.
Test-corp migration is not a release gate.

## 2. Verify the artifacts

Run:

```text
forge test --via-ir --match-contract CyberCertPrinterClassTermsTest
forge test --via-ir --match-contract CyberAgreementRegistryTest
forge build --via-ir --sizes --skip test --skip script
```

The audited local build has:

| Contract | Runtime bytes | EIP-170 margin |
| --- | ---: | ---: |
| CyberCertPrinter v4 | 24,539 | 37 |
| IssuanceManager 4.2 | 23,952 | 624 |
| IssuanceManagerWithMigration | 24,514 | 62 |
| ShareClassTermsController | 7,531 | 17,045 |
| ShareExtension renderer | 23,311 | 1,265 |

Stop on any size regression. The rejected in-printer P2 prototype was 28,979
bytes—4,403 bytes over EIP-170—which is why canonical state lives in the
external controller.

## 3. Global deployments and references

1. Upgrade each in-scope ShareExtension proxy with
   `script/upgrade-share-extension.s.sol` and `SHARE_EXTENSION_PROXY`. This adds
   the exact `SeriesTerms` extractor while preserving rendering.
2. Deploy one UUPS controller proxy with
   `script/deploy-share-class-terms-controller.s.sol` and
   `SHARE_EXTENSION_RENDERER`.
3. Deploy and set the IssuanceManager 4.2 reference with
   `script/upgrade-issuance-manager-ref.s.sol`.
4. Deploy and publish the updated LedgerEntryToken reference implementation on
   the IssuanceManager factory **before any per-corp migration**. The
   void/unvoid class-terms accounting (`syncClassTermsOnVoidStatus`) exists
   only in the updated token implementation, and the atomic migration syncs
   each corp's printer beacon **to whatever reference the factory publishes**.
   Migrating while the factory still points at the legacy implementation
   leaves direct voids, unvoids, and DealManager teardown skipping the
   controller, so `issuedUnits` goes stale on exactly the corps the migration
   was meant to protect. Storage layout is unchanged — the update adds the
   sync hook, no printer storage or reinitialization.
5. Upgrade CyberAgreementRegistry to 3.3 with
   `script/upgrade-cyber-agreement-registry.s.sol` and
   `CYBER_AGREEMENT_REGISTRY`.

Read back and archive:

- controller proxy, implementation, auth, renderer, and `SHARE` support;
- factory reference and `IssuanceManager(ref).DEPLOY_VERSION() == "4.2"`;
- the factory's LedgerEntryToken reference: confirm it is the updated
  implementation (carries `syncClassTermsOnVoidStatus`) before step 4 of the
  per-corp section runs anywhere;
- renderer proxy state and terms-extractor behavior; and
- registry implementation/version plus a known pre-existing template and
  agreement before and after upgrade.

## 4. Per-corp atomic upgrade and migration

An upgraded IssuanceManager fails closed when a share printer still points to a
legacy renderer: issuance, update, void, and restore cannot bypass cap
accounting. Use
`script/upgrade-and-migrate-share-class-terms.s.sol` with:

- `ISSUANCE_MANAGER`;
- `ISSUANCE_MANAGER_IMPLEMENTATION` (which must already be the factory reference);
- `SHARE_CLASS_TERMS_CONTROLLER`;
- comma-delimited `CERT_PRINTERS`;
- matching comma-delimited `SOURCE_TOKEN_IDS` — for a printer with no active
  certificate (never issued, or every lot voided), pass the sentinel
  `type(uint256).max` here; and
- `SOURCELESS_TERMS` (comma-delimited terms bytes, consumed in printer order)
  for each sentinel entry. Supplied terms carry the same reconciliation duty
  as a source certificate: charter/class-authority evidence per printer.

The script submits one owner transaction:

```text
upgradeToAndCall(
  referenceImplementation,
  abi.encodeCall(
    migrateClassTermsControllers,
    (printers, controller, sourceExtensionData)
  )
)
```

This upgrades the manager and migrates every supplied printer atomically. Any
bad source, class conflict, counter violation, length mismatch, or later-printer
failure rolls back the implementation upgrade and every earlier printer change.
The focused suite proves both the successful two-printer path and second-printer
rollback.

The older `accept-upgrade-issuance-manager.s.sol` plus
`configure-share-class-terms.s.sol` scripts remain useful for simulation and
diagnosis, but separate broadcasts create a temporary fail-closed pause. Do not
use them as the production cutover unless issuance is operationally disabled and
the non-atomic exception is explicitly approved.

Once a controller is installed, the migration function refuses to replace it.
Future implementation changes use the controller's governed UUPS upgrade; legal
term changes use `amendClassTerms`.

New printers must use `createCertPrinterWithClassTerms`, with the controller as
their share extension, so class creation and configuration are atomic.

## 5. Migration read-back

For every migrated printer, call
`ShareClassTermsController.getClassTerms(printer)` and archive:

- controller and printer addresses;
- terms bytes, hash, and decoded terms;
- authorized and issued units;
- the independently reconciled unit total;
- source certificate and authority evidence; and
- transaction hash, block, and operator.

Verify normal printer metadata, ownership, certificate details, legends, token
URIs, and scrip balances are unchanged. Stop on any counter disagreement.

## 6. Release the webapp as one protocol unit

Deploy the webapp build containing:

- P3 `createTemplatePublic`;
- the controller and IssuanceManager ABIs;
- the printer `getExtension(0)` resolver;
- `useCertPrinterClassTerms` and the strict `SeriesTerms` decoder; and
- locked canonical class fields in the issuance form.

Do not release the P2 UI for a corp before its manager and printers are migrated.
Legacy/unconfigured reads resolve to the labeled legacy form, but the upgraded
manager intentionally prevents lifecycle writes until migration succeeds.

## 7. Runtime acceptance

On the named demo corp, then the deliberately supported real pilot:

1. Open issue-existing-class and confirm terms come from
   `controller.getClassTerms(printer)` and are read-only.
2. Mint within remaining authorization and confirm `issuedUnits` increases.
3. Simulate/reject an over-cap mint and a mismatched-terms mint.
4. Scripify partially, then recertify; confirm the counter does not move.
5. Void/unvoid a test certificate and confirm the counter releases/restores.
6. Attempt to migrate the printer to a second controller and confirm it reverts.
7. Register identical award-template content twice; confirm the same id and no
   overwrite. Confirm curated caller-chosen creation remains owner-only.
8. Verify indexer/cap-table totals, holder portal visibility, and OCF export
   against the on-chain record.

## 8. Rollback and stop conditions

Pause issuance before any rollback. Once canonical state is configured,
downgrading the manager would make older code ignore its cap; pointing a printer
back to the renderer would strand controller accounting. Neither is a safe
operating state. Prefer fixing forward. If rollback is unavoidable, disable
issuance in the webapp and operationally block owner lifecycle transactions until
the controller-enforced implementation is restored.

Stop on any storage drift, class-term disagreement, counter mismatch, unexpected
typed revert, controller replacement, indexer divergence, or inability to
identify legal authority for the class record.
