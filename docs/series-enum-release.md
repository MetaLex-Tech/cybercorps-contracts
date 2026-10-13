# Series enum expansion: direct issuance release

This PR implements the 84-entry catalog. It does not deploy or upgrade contracts.
The owner approved implementation on 2026-10-13. The first release targets
MetaLeX's cap table; its Series Seed 2 cyberRaise follows separately.

## Allocation and compatibility

Values 0–9 retain their identities. Append Pre-Seed 2–10 (10–18), Seed 2–10
(19–27), A-2–A-10 (28–36), B-2–B-10 (37–45), C-2–C-10 (46–54),
D-2–D-10 (55–63), E-2–E-10 (64–72), F-2–F-10 (73–81), Common A (82)
and Common B (83). The complete fixture is `test/res/series-catalog.json`.

MetaLeX's required pair is `PreferredStock` (8) / `SeriesSeed2` (19).
Common without a series stays `CommonStock` / `NA` (8). Common A/B are
series within Common Stock; they do not add classes or determine voting rights.
The app must validate Common A/B against the selected instrument type.

The ABI representation remains uint8, with the same selectors, tuple layout,
storage width and signature schemas. Old binaries still reject values above 9.
There is no added storage, mutable-series setter, rights field or authorization
change. Existing JSON identifiers and SVG wording for values 0–9 stay unchanged.
New numbered labels precede the type, including “Series Seed 2 Preferred Stock.”

## Upgrade scope

Before deployment, identify the source/build for the affected deployed code.
This PR targets develop at a57b99b; that is not proof every develop change is
already deployed. Review any unrelated differences before selecting a release
build. A version string of 5 is not evidence of expanded-enum support.

1. Compile and link IssuanceManager, IssuanceManagerStorage, LedgerEntryToken
   and LedgerEntryTokenStorage from the approved release source. Inspect their
   linked dependencies for enum decoding. Deploy the required implementations
   and libraries; no new class-registry behavior is needed.
2. Compile and link CertificateUriBuilder, CertificateImageBuilderContract,
   CertificateImageBuilder and CertificateImageContentBuilder coherently. The
   new SecuritySeriesNames helper is internal and requires no library deployment.
   Upgrade the URI proxy and its image-builder pointer together through the
   existing owner/Safe path. A shared URI proxy changes every referencing company.
   Alternatively, separately approve a dedicated compatible renderer and use
   the existing IssuanceManager.setUriBuilder method for the target company.
3. Publish the approved issuance/LET implementation references through the
   existing IssuanceManagerFactory setters. Record all chain, proxy, beacon,
   implementation and linked-library addresses and hashes, callers and call order.
   Follow the existing coordinated production-chain/factory/frontend policy.
4. MetaLeX's authorized owner accepts the IssuanceManager UUPS upgrade and calls
   upgradeCertPrinterBeaconImplementation for the LET beacon. A factory reference
   update alone does neither. The LET beacon covers the company's common and
   preferred printers; its scrip beacon is separate.
5. Read back the actual implementations, renderer pointer and supported outputs.
   Enable the app's direct new-code path only after its verified deployment
   manifest matches. Refuse partial or unknown combinations.

Do not run the broad core-stack upgrade for this change. The existing issuance
manager/beacons script also includes scrip; that deployment is not required by
this PR. No Release 1 upgrade is proposed for DealManager, RoundManager,
CyberCorp, corporate formation factories, registry, escrow or converters.
Those components need separate review when their workflows adopt new codes.
Compiling them against the expanded enum does not authorize deploying them.

## Existing holdings and later workflows

Create a new Seed 2 printer. Do not relabel all records in the existing Seed
printer: inspected MetaLeX terms include both Seed and Seed 2, and one LET is
already void. Confirm the exact replacement list, holders, units, terms and
outstanding dependencies. Use existing authorized void/issuance operations;
retain history and reconcile current holdings once. MetaLeX's common printer
has scrip exposure and is outside the preferred replacement list.

Deal/round, formation, secondary, scrip/conversion and general-import enablement
remain separate app and deployment work. Address-based selection of a new-code
printer must not bypass their workflow restrictions. No new-code write path is
made live by merging either repository's PR. Use ordinary code tests, compatibility checks and actual-result verification.

Once records use codes above 9, restoring old decoder binaries can make them
unreadable. Stop new writes and fix forward instead. Merge, deployment, company
upgrade, authorized replacement issuance and actual cap table verification are
separate milestones.
