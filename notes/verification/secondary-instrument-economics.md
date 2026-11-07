# Secondary instrument amount verification

Date: November 4, 2026, America/Bogota.
Code revision: `77a1b51906b03dd5eed6daf3e52df92bc5bc5930`.
Base revision: `caa83643b09806d5e0036e627e7cd14cd02a3b23`.
Branch: `codex/preserve-secondary-instrument-economics`.

## Results

| Check | Result |
| --- | --- |
| Allocation regressions against unchanged base source | Eight failed; one passed. The failures reproduce lost buyer amounts and incorrect seller amounts. |
| Full unit suite | 1,544 passed; zero failed; zero skipped. |
| Final allocation test | 10,000 randomized cases passed. |
| Contract build | Passed with Solc 0.8.28, via IR, optimizer runs 15. |
| IssuanceManager size | 18,692 runtime bytes. |
| Linked library size | 24,554 runtime bytes. The EIP-170 limit is 24,576 bytes. |
| Independent review | Claude Opus 5.5 found no introduced material defect after the approved guard. |
| Signed local sale | 37 successful transaction receipts. Direct state reads confirm the expected amounts and cash. |
| Signed local guard case | Simulation refused the conversion. A signed transaction also failed. The subsequent sale succeeded. |

Foundry version: 1.8.5. Dependencies match the base gitlink revisions.
The full suite excludes contracts that match `ForkTest` or `AdhocTest`.
Tests ran on the same source bytes as the code revision above.
Later documentation commits do not change the tested implementation.

## Commands

```bash
forge test --nmc '(ForkTest|AdhocTest)' -vv
forge test --match-contract IssuanceManagerSecondaryTransferTest \
  --match-test testFuzz_ConvertibleSale --fuzz-runs 10000 -vv
forge build --sizes --skip test script
```

Each command used an isolated output directory and cache directory.
An explicit artifact check also measured the linked library.
The new deployment-limit regression checks that library size inside the test environment.
The standard size table alone did not reject an oversized library during development.

## Local transaction acceptance

An owned Anvil process used an OS-assigned loopback port and chain ID 31337.
Only disposable test keys and synthetic data were used.
The rehearsal used the actual registry, DealManager, IM and LET implementations.
Company and URI dependencies used the existing test mocks.

The first case issued a $100,000 SAFE with a $10 million cap and 100 raw test units.
The seller posted a full sale for $60,000.
The purchaser signed the registry agreement.
Simulation passed before the script submitted its transactions.
All 37 receipts succeeded.

Direct RPC reads then confirmed these results:

- Buyer purchase amount: $100,000.
- Buyer valuation cap: $10 million.
- Seller resale cash: $60,000.
- Escrow cash: zero.

The second case reserved 50 units from that acquired lot and collected the purchaser's cash.
The source holder had 900 scrip units from another lot.
Simulation of conversion into the reserved source returned `CertificateReserved`.
A separately signed conversion transaction had receipt status zero.
The source still held 100 units and the $100,000 amount.

The subsequent finalization transaction succeeded.
The source and buyer lots each held 50 units and a $50,000 amount.
Escrow cash returned to zero.
The [local test evidence](secondary-instrument-economics.local-test.json) records the transaction hashes and final state.
Those hashes refer only to the disposable local chain.

## Independent review and owner decision

The first independent review found that external scrip could enter a reserved convertible lot.
The reproduced case reduced the purchaser's assigned amount from $50,000 to $5,000.
This was a new economic consequence of Hexens MTLX1-8, Medium, Acknowledged.
The owner explicitly approved the proposed reservation guard.

The final independent review confirmed that the guard closes that seller-controlled unit increase.
The guard and conversion code use the same legal-owner selection helper.
The guard does not freeze the shared vault or change the broader MTLX1-8 response.
Other holders can still reduce a vault claim before finalization.
Pre-offer scrip conversions can still change a lot's amount-to-unit ratio.

Existing tests confirm stock conversion behavior, other security classes, custody, unit accounting, conditions, voids, refunds and primary flows.
The POC printer mock now exposes its configured security class, as real LETs already do.
No production fallback was added to accommodate that mock.

## Limits and separate gates

Fork tests, deployed v4/v5 acceptance and a target-company upgrade rehearsal were not run.
No target company was supplied.
No contract was merged or deployed to a public chain.
The local test does not establish the legal effect of a particular signed instrument.

Deploy the updated IM and linked library as a pair when separately authorized.
A library-only change would omit the reserved-destination guard.
Verify the actual target company's implementation and component references before use.
The version number alone does not identify this change.

The webapp must show the current purchase amount, cap and source ratio before acceptance.
Gpxl retains ownership of that implementation.
Warrant groups, instrument leg history, bundles, legal amendments and historical zero corrections remain outside this PR.

## Size review of the PR

Review date: November 4, 2026, America/Bogota.
Reviewed head: `be40b585fca93ac7391fe38895ef3bbc1e74260d`.
Compared base: `caa83643b09806d5e0036e627e7cd14cd02a3b23`.

Fresh base and PR builds used the CI profile and pinned Foundry 1.8.5.
Both builds used Solc 0.8.28, via IR and 15 optimizer runs.
The compiler metadata reports the Prague EVM target.
The review counted artifact bytes, including metadata and library address slots.
It did not rely only on the `forge build --sizes` table, which omits this linked library.

[EIP-170](https://eips.ethereum.org/EIPS/eip-170) limits each deployed runtime to 24,576 bytes.
[EIP-3860](https://eips.ethereum.org/EIPS/eip-3860) limits initcode to 49,152 bytes on chains that enforce it.

| Component | Base runtime | PR runtime | Increase | Runtime space left | PR initcode | Initcode space left |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| IssuanceManager | 17,940 | 18,692 | 752 | 5,884 | 18,923 | 30,229 |
| IssuanceManagerStorage library | 24,376 | 24,554 | 178 | 22 | 24,586 | 24,566 |

All values are bytes. Neither changed component takes constructor arguments.
Their creation bytecode therefore gives the full initcode length.
Linking substitutes fixed-width addresses. It does not append the library runtime to IssuanceManager.
Each deployed component has its own runtime limit.
The factory creates a proxy and references the implementation separately.
It does not embed the updated implementation into its own runtime.

The review checked all 104 nonempty production runtimes from each fresh build, including libraries.
None exceeded the runtime limit or the creation-bytecode limit.
Only the two components above changed size.
LedgerEntryToken remained at 24,288 runtime bytes, with 288 bytes left.
IssuanceManagerFactory remained at 5,400 runtime bytes.
Constructor arguments for unrelated contracts were outside this review.

The existing library deployment-limit regression passed again.
Prior local-chain evidence also measures the deployed library at 24,554 bytes.
Hosted build-size, unit and fork checks passed on the reviewed head.
No contract source changed during this review.

The patch fits the checked limits with these exact build settings.
The library has almost no space left. Recheck its exact artifact after any code, dependency or build-setting change.
No target chain or company upgrade was verified by this size review.
Related audit responses and the approved MTLX1-8 guard remain as recorded above.
