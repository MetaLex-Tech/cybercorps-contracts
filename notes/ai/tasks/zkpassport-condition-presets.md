# Task: zkPassport condition presets (deploy script)

- **Status:** Ready for review. Not deployed.
- **Updated:** 2026-11-07
- **Owner:** Claude Code (desktop session), for the owner
- **Collaborators / boundaries:** Deployment script only. No contract source change, no upgrade. The webapp side (preset picker, allowlist, empty-list support) is a later metalex-webapp PR after metalex-webapp #2340.
- **Objective:** Three new `NonUSNationalityCondition` proxies on each chain, as additional options next to the default condition, which does not change:
  - **Embargo screen:** excludes `CUB`, `IRN`, `PRK` (the country-wide embargoes that OFAC FAQ 10 names); U.S. investors allowed; sanctions-list check.
  - **Sanctions screen:** excludes no nationality; sanctions-list check only.
  - **Non-U.S. + Cuba, Iran and North Korea exclusions:** excludes `CUB`, `IRN`, `PRK`, `USA`; sanctions-list check. Added at the owner's request on 2026-11-07; this is an additional choice, not a replacement default.
- **Out of scope:** Changes to the default condition (owner, 2026-11-07: do not fix anything, only add options); Arbitrum, Base Sepolia and Robinhood Chain (no default condition).
- **Canonical sources:** metalex-webapp `notes/ai/tasks/zkpassport-granular-conditions-discovery.md` (deployed conditions, audit findings); `script/deploy-zkpassport-condition-presets.s.sol`.
- **Repository / branch:** cybercorps-contracts; base `develop` 8789081, branch `claude/zkpassport-condition-presets`
- **Verified base / code head:** script commit f03e485
- **PR / artifact:** https://github.com/MetaLex-Tech/cybercorps-contracts/pull/196

## Acceptance and current state

| Criterion | State |
| --- | --- |
| Each proxy uses the default condition's implementation, BorgAuth, domain, verifier and maximum validity, read from the chain | Verified: simulation on Ethereum, Base and Sepolia, with the script's post-deploy checks |
| Each proxy stores its own sorted list and scope, and the list ends after the last entry | Verified: same simulations |
| The deployer gets no role | By construction: the proxies use the existing BorgAuth (MetaLeX Safe, role 99, on Ethereum and Base) |
| An empty list accepts a real sanctions-only proof | Not verified. The zkPassport SDK keeps `out: []` in the query and requires a nationality-exclusion proof when `out` is set, and the helper accepts an empty committed list that equals an empty stored list. Needs one mock-passport proof on Sepolia |
| Browser deploy page `script/browser/deploy-zkpassport-condition-presets.html` rebuilds the same transactions from the chain and refuses if an address differs from the simulation | Verified 2026-11-07 on a local Sepolia fork (Anvil) with a stand-in wallet: both deployments mined, all read-back checks passed, reload shows both deployed with the buttons disabled |
| Deployment on Sepolia, Ethereum and Base | Not done; the owner broadcasts with their own signer (forge script or the browser page) |

Simulated addresses (CREATE2 through the default deployer): Ethereum and Base, embargo screen `0x524224874f2A22e720edbb223CDF487E8a782872`, sanctions screen `0xE277147aAc479e1730e5d6d0766F85078DEaF75f`. Sepolia: `0xd5dB86E9F699E5818D09d6eA2c2028d4b0a1A8cf`, `0x533e12655dC34fC7F96cD2882aFBcEb11FBA76f1`.

## Decisions and evidence

- **Embargo list source:** OFAC FAQ 10 lists Cuba, Iran, North Korea, Crimea and the so-called Donetsk and Luhansk regions as broad-sanctions jurisdictions. The regions cannot be expressed as a nationality. OFAC's program list (checked 2026-11-07) has no Syria program; Syria now has the targeted PAARSS program.
- **Person-level sanctions:** zkPassport screens against US OFAC SDN, UK, EU and Swiss lists. `NonUSNationalityCondition` requires the non-strict match.
- **Related past audit findings:** Hexens MTLX1-33 (Medium, Acknowledged): caller-selected dev mode lets one passport qualify several wallets; it applies to the presets, so they are not per-person caps. Hexens MTLX1-29 (Low, Acknowledged): a list change does not invalidate cached proofs; treat preset lists as fixed. Sources searched: `audits/` (Hexens Jul–Aug 2026), metalex-webapp V12 records.

## Next action and handoff

Owner review of the script. Then the owner deploys on Sepolia, a mock-passport sanctions-only proof confirms the empty list, and the owner deploys on Ethereum and Base. Then the metalex-webapp preset PR.

## Third preset and labels (2026-11-07)

The owner authorized a second Non-U.S. option alongside the existing default.
The script and browser page add `NonUsEmbargoScreen` (`non-us-embargo-screen`),
with sorted codes CUB, IRN, PRK, USA. The existing two presets keep their salts,
scopes and addresses. The page spells out the excluded countries and whether
U.S. nationalities are allowed. These labels describe a passport nationality
check, not a determination of U.S.-person status or full sanctions compliance.

Simulation evidence: dirty tree on 15e9a1e, changing only the deployment script,
browser page and this record. Ethereum and Base completed the three-proxy
simulation and read-back assertions, estimated gas 1,435,873. Sepolia script
execution with read-back assertions passed; the first full simulation attempt
failed at the public RPC's block-hash lookup, and the full retry subsequently passed.
New predicted address: Ethereum/Base `0x4Cc1b51c9E317Dc915008F099dd2F1780b8bffD9`;
Sepolia `0xc58EA50bC312f610Ec22d1Bf9B3c7Df24d810aA8`. These are simulation results,
not deployment evidence. Empty-list proof acceptance remains unverified.

The owner also requested a screening-choice side wizard in the webapp. That work
is on `codex/zkpassport-screening-guide`; it must show undeployed presets as
unavailable and must not change the offering exemption or existing default.

## Wallet picker for Ambire (2026-11-07)

The owner asked for the browser page to connect to Ambire. The page now lists
every wallet that announces itself through EIP-6963 and sends all requests to
the wallet the owner picks; `window.ethereum` is only a fallback when no wallet
announces. A deployment counts as done only when contract code is at the CREATE2
address, because a smart-account wallet can return a hash before it mines.
Verified headless on a local Sepolia fork with stand-in wallets (15/15 checks):
an Ambire-like wallet that returns a non-transaction id deployed all three
presets with every read-back match, a decoy wallet holding `window.ethereum` got
no request, the fallback and no-wallet cases work. Not tested with the real
Ambire extension.
