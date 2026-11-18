# Task: CyberAgreementRegistry diamond (static router and facets)

- **Status:** Ready for review
- **Updated:** 2026-10-30
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** none known
- **Objective:** Move the registry's public functions out of one contract, so EIP-170 no longer limits it. Keep the live proxy address and data with no migration.
- **Out of scope:** Deployment, an EIP-2535 `diamondCut`.
- **Canonical plan / sources:** `src/interfaces/ICyberAgreementRegistry.sol`, `src/CyberAgreementRegistry.sol`, `src/registry/`, `src/libs/CyberAgreementRegistryLib.sol`, `src/storage/CyberAgreementRegistryStorage.sol`, `script/libs/CyberAgreementRegistryDeployment.sol`
- **Repository / branch:** `chore/diamond-pattern-cyberagreementregistry`, base `7ce4e1c8`
- **Verified base / code head:** `b6e4ec08` (storage at slot 1) plus the uncommitted router and facet work
- **PR / artifact:** not yet created

## Acceptance and current state

- The proxy at `0xa9E8…c134` stays. Its new implementation `CyberAgreementRegistry` is a UUPS router. The router sends each selector to one of three facets, which run in the proxy's storage. Verified.
- Every selector of `7ce4e1c8` except the dead `closedAgreementValues` reaches the router or a facet. Verified.
- Live Base data reads the same after the real Safe upgrade, and all flows work. Verified on a pinned fork in CI.
- A second `upgrade-core` run deploys nothing. Verified by fork tests.

## Decisions and evidence

- 2026-10-29: storage struct at slot 1 (no migration). The `closedAgreementValues` getter was removed after a check that nothing used it. See commit `b6e4ec08`.
- 2026-10-29, user: the goal is to move public functions out of the registry contract. Storage alone does not reach that goal.
- 2026-10-29, user: a static router (facets as immutables, change by UUPS upgrade), not EIP-2535.
- 2026-10-29, user: facet addresses are router constructor arguments. Before this, the router created the facets in its constructor, so its code changed on each deploy and `deployIfDifferent` redeployed every run.
- The linked libraries `CyberAgreementBound` and `CyberAgreementJson` were folded into the facets.
- 2026-10-30, user: one interface, `ICyberAgreementRegistry`, is the single source of truth for clients. It holds every function, event and error. `ISignerConditions` and the ZKPassport errors moved into it. The router is renamed `CyberAgreementRegistry`, because it is the contract at the original address.
- Facets and libraries revert with `ICyberAgreementRegistry` errors. OpenZeppelin and BorgAuth errors are declared again in the interface. The routing test fails when the interface ABI and the router and facet ABIs differ.

| Contract | Runtime | EIP-170 margin |
| --- | --- | --- |
| Registry at `b6e4ec08` | 22,412 B | 2,164 B |
| CyberAgreementRegistry (router) | 3,945 B | 20,631 B |
| CyberAgreementFacet | 14,383 B | 10,193 B |
| CyberAgreementBoundFacet | 16,335 B | 8,241 B |
| CyberAgreementViewFacet | 8,783 B | 15,793 B |

Gas, measured against `b6e4ec08` with cold accounts: `setDelegation` +56, `revokeDelegation` +247, `isVoided` +2,532 (cold and warm), `createTemplate` −6,829 (no library delegatecall). The router checks selectors in order, so a later entry costs more.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --nmc '(ForkTest\|AdhocTest)'`, `b6e4ec08` + uncommitted | 1,530 passed (after the interface merge) |
| Fork tests | `... --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`, same tree | 224 passed, 1 skipped (after the interface merge) |
| Routing table and interface ABI | `--match-path test/CyberAgreementRegistryRoutingTest.t.sol --nmc ForkTest`, a unit test in CI. It reads the interface, router and facet ABIs from `out/` and holds the `7ce4e1c8` ABI as a fixed list | 6 passed. A removed route, an added `closedAgreementValues`, an error or event missing from the interface, and an error only in the interface each make it fail, as expected |
| Live-proxy upgrade | `--match-path test/CyberAgreementRegistryUpgradeForkTest.t.sol --threads 1 --cups 10`, a CI fork test. Base block 53,264,116, real `UpgradeCoreScript` Safe batch. Checks 21 live views byte for byte, an agreement half-signed on the old code, and new sign, void, delegate and bound flows | 7 passed. A wrong `version()` in the view facet makes the live-view check fail. A wrong storage slot makes the 5 flow tests fail; its live-view run timed out on RPC twice |
| Build and size | `forge build ... --sizes` | passes; only test-only `CyberCertPrinterEnhanced` and `HolderCountHarness` exceed EIP-170, as before |

## Review and blockers

No independent review. `foundry.toml` now gives tests read access to `./out` for the routing test (user approved).

## Next action and handoff

User review of the uncommitted diff, then commit.
