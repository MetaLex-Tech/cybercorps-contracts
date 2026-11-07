# Task: zkPassport condition presets (deploy script)

- **Status:** Ready for review. Not deployed.
- **Updated:** 2026-11-07
- **Owner:** Claude Code (desktop session), for the owner
- **Collaborators / boundaries:** Deployment script only. No contract source change, no upgrade. The webapp side (preset picker, allowlist, empty-list support) is a later metalex-webapp PR after metalex-webapp #2340.
- **Objective:** Two new `NonUSNationalityCondition` proxies on each chain, as additional options next to the default condition, which does not change:
  - **Embargo screen:** excludes `CUB`, `IRN`, `PRK` (the country-wide embargoes that OFAC FAQ 10 names); U.S. investors allowed; sanctions-list check.
  - **Sanctions screen:** excludes no nationality; sanctions-list check only.
- **Out of scope:** Changes to the default condition (owner, 2026-11-07: do not fix anything, only add options); Arbitrum, Base Sepolia and Robinhood Chain (no default condition).
- **Canonical sources:** metalex-webapp `notes/ai/tasks/zkpassport-granular-conditions-discovery.md` (deployed conditions, audit findings); `script/deploy-zkpassport-condition-presets.s.sol`.
- **Repository / branch:** cybercorps-contracts; base `develop` 8789081, branch `claude/zkpassport-condition-presets`
- **Verified base / code head:** script commit f03e485
- **PR / artifact:** not yet created

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Each proxy uses the default condition's implementation, BorgAuth, domain, verifier and maximum validity, read from the chain | Verified: simulation on Ethereum, Base and Sepolia, with the script's post-deploy checks |
| Each proxy stores its own sorted list and scope, and the list ends after the last entry | Verified: same simulations |
| The deployer gets no role | By construction: the proxies use the existing BorgAuth (MetaLeX Safe, role 99, on Ethereum and Base) |
| An empty list accepts a real sanctions-only proof | Not verified. The zkPassport SDK keeps `out: []` in the query and requires a nationality-exclusion proof when `out` is set, and the helper accepts an empty committed list that equals an empty stored list. Needs one mock-passport proof on Sepolia |
| Deployment on Sepolia, Ethereum and Base | Not done; the owner broadcasts with their own signer |

Simulated addresses (CREATE2 through the default deployer): Ethereum and Base, embargo screen `0x524224874f2A22e720edbb223CDF487E8a782872`, sanctions screen `0xE277147aAc479e1730e5d6d0766F85078DEaF75f`. Sepolia: `0xd5dB86E9F699E5818D09d6eA2c2028d4b0a1A8cf`, `0x533e12655dC34fC7F96cD2882aFBcEb11FBA76f1`.

## Decisions and evidence

- **Embargo list source:** OFAC FAQ 10 lists Cuba, Iran, North Korea, Crimea and the so-called Donetsk and Luhansk regions as broad-sanctions jurisdictions. The regions cannot be expressed as a nationality. OFAC's program list (checked 2026-11-07) has no Syria program; Syria now has the targeted PAARSS program.
- **Person-level sanctions:** zkPassport screens against US OFAC SDN, UK, EU and Swiss lists. `NonUSNationalityCondition` requires the non-strict match.
- **Related past audit findings:** Hexens MTLX1-33 (Medium, Acknowledged): caller-selected dev mode lets one passport qualify several wallets; it applies to the presets, so they are not per-person caps. Hexens MTLX1-29 (Low, Acknowledged): a list change does not invalidate cached proofs; treat preset lists as fixed. Sources searched: `audits/` (Hexens Jul–Aug 2026), metalex-webapp V12 records.

## Next action and handoff

Owner review of the script. Then the owner deploys on Sepolia, a mock-passport sanctions-only proof confirms the empty list, and the owner deploys on Ethereum and Base. Then the metalex-webapp preset PR.
