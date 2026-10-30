# Task: CyberAgreementRegistry diamond storage

- **Status:** Ready for review
- **Updated:** 2026-10-29
- **Owner:** detoo with Claude Code
- **Collaborators / boundaries:** none known
- **Objective:** Move all registry state into `src/storage/CyberAgreementRegistryStorage.sol` with no data migration for the live proxy.
- **Out of scope:** Deployment, the inherited `BorgAuthACL.AUTH` slot.
- **Canonical plan / sources:** `src/CyberAgreementRegistry.sol`, `src/storage/CyberAgreementRegistryStorage.sol`
- **Repository / branch:** `chore/diamond-pattern-cyberagreementregistry`, base `7ce4e1c8`
- **Verified base / code head:** `7ce4e1c8` plus uncommitted: registry refactor, new storage library, `test/CyberAgreementRegistryDiamondAdhocTest.t.sol`
- **PR / artifact:** not yet created

## Acceptance and current state

- The storage struct starts at slot 1 in the legacy field order. Live data stays readable with no migration. Verified on a Base fork.
- Registry ABI is the same as at `7ce4e1c8`, less the `closedAgreementValues` getter. Verified.
- Registry runtime size is 22,412 B (2,164 B EIP-170 margin). Baseline was 22,942 B. Verified.
- The new `CyberAgreementBound` and `CyberAgreementJson` signatures need new library deployments with the next implementation.

## Decisions and evidence

- 2026-10-29, user: use the slot-1 struct (variant B), not a hashed slot. "We want to avoid migration whenever possible."
  - A hashed slot loses the live state. On a Base fork, `version()` returned "".
  - Copying the data was estimated at 34K slots and at least 828M gas on Base (1,862 agreements), plus Ethereum and Arbitrum.
- 2026-10-29, user: remove the `closedAgreementValues` getter only after a check that nothing uses it. The check found no use:
  - No commit ever indexes or writes the mapping (`git log --all -G'closedAgreementValues\s*\['` is empty).
  - Live storage: the length slot reads zero for every agreement and template id on Ethereum, Base, Arbitrum and Robinhood (2,221 keys). The positive control `templates[2]` on Base reads nonzero.
  - Off-chain: the only references are generated ABI files in `metalex-webapp` and `MetaVesT/zkout`. No code calls the getter. This is a local snapshot.
- The struct keeps three placeholder fields (two type hashes and `deprecatedClosedAgreementValues`), so the layout does not move.

## Validation

| Check | Evidence and exact revision | Result / remaining limitation |
| --- | --- | --- |
| Unit tests | `forge test --use solc:0.8.28 --via-ir --optimize --optimizer-runs 15 --nmc '(ForkTest\|AdhocTest)'`, dirty tree on `7ce4e1c8` | 1,524 passed |
| Fork tests | `forge test ... --mc ForkTest --nmc AdhocTest --threads 1 --cups 10`, same tree | 217 passed, 1 skipped |
| Live-proxy upgrade | `--mc CyberAgreementRegistryDiamondAdhocTest`, Base block 53264116 | passed |
| Size | `forge build ... --sizes` | 22,412 B |

## Review and blockers

No independent review yet.

## Next action and handoff

User review of the uncommitted diff, then commit.
