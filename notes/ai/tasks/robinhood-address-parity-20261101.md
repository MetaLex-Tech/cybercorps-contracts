# Robinhood / Base / Ethereum / Arbitrum address comparison

- Owner: current Codex chat, November 1, 2026.
- User request: confirm Robinhood deployment addresses match Base, Ethereum and
  Arbitrum, using the supplied contract deployment checklist.
- Checkout: `codex/robinhood-intermediate-20261028`,
  `f90978dbf333abb19a20696fd879cb8aad55bdc4`; current remote ref refreshed.
- Existing cent-SAFE and LET verification edits remain owned by this chat and
  must be preserved. Read-only RPC/source comparison; no key use or transactions.
- Canonical current addresses: `script/libs/DeploymentConstants.sol`, live
  factory/contract references. Checklist includes historical/testnet/Base-only
  and client-specific records, so it cannot be treated as a current manifest.

## Acceptance criteria before checking

1. Pin each mainnet's own block/hash and validate IDs 4663/8453/1/42161.
2. Check code at shared auth/proxy addresses and their active factory/registry/
   URI/LeXcheX wiring. Distinguish same address, code presence and same bytecode.
3. Read active proxy implementation slots and factory reference implementations;
   report differences without requiring implementation address equality.
4. Check shared extensions and secondary conditions from the checklist/constants,
   distinguish old kill switch and original component factories from current ones,
   and identify any missing mainnet deployment. Keep testnet/client-specific
   deployments out of the shared-core verdict.
5. Record full public address evidence, block hashes and limits. No credentials,
   wallet information or private client details copied from the attachment.

## Confirmed result

Read-only mainnet snapshots: Robinhood **103799016**, Base **53394927**,
Ethereum **26323497**, Arbitrum **520420951**. Full block hashes and address/code/
reference results are in [public JSON evidence](robinhood-address-parity-20261101.json).
All **13 critical auth/proxy addresses match on all four chains**, with nonempty
code and identical auth/proxy runtime fingerprints. All **68/68 sampled shared
auth/factory wiring checks** pass (17 per chain). These include the four current
component factory references, registry/URI/LeXcheX references and auth getters.

All **16 shared certificate extension addresses** and **19 current secondary
condition addresses** have code at the same addresses on all four mainnets.
The 16 extension runtimes match exactly. 18 of 19 secondary condition runtimes
match; the shared kill switch has different runtime code, so no logic/admin/state
equivalence is implied for that singleton.

Current component factory addresses, superseding the checklist's original ones:

- CyberCorpSingleFactory: `0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4`.
- IssuanceManagerFactory: `0xD353972D7955F421d94d0eA8c42c88c417F7155A`.
- DealManagerFactory: `0x3982b078f2ac306219c9540Ebc908360a960C251`.
- RoundManagerFactory: `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9`.

### Checklist corrections / scope exceptions

- Active shared kill switch: `0x456EDAfB7283dB8FDa2A5b3ecE576d9292512435`.
  Checklist/testnet `0x4c3b9Ec3B6e416A64Fde4a17Ea856e1cf2fE0344` has no code
  on these four mainnets. Do not use it as the mainnet shared instance.
- Legacy ACE SAFE v1 `0x6aDaef2B79FD1cbA130c5807B31DE435FEa58EAC` exists only
  on Base; shared ACE SAFE V3 exists on all four.
- The listed MetaDAO factory/auth, production Pump factory, Pump condition and
  OR addresses have code only on Base in this snapshot; the listed Pump ZK auth
  also exists on Ethereum. These are outside shared CyberCorps core parity.
- Deprecated shared NonUSNationalityCondition is present only on Base/Ethereum;
  the listed verifier has no code on Arbitrum. No missing core proxy is inferred
  from these legacy/product-specific differences.
- The original component factories/LET implementation remain deployed at their
  historical addresses, but are not the current shared factory references.
- Client-specific Umia/Yearn, staging and testnet entries were excluded.

### Implementation and payment differences

The active implementation addresses are chain-specific. Current LET references:

- Robinhood: `0x487Ed0d21e489d66e647fB4A55cE20Daadaf7920`.
- Base: `0xa7fe0a48c4dc365e1a3b4b46dd37069abd4dd1af`.
- Ethereum: `0x4254de7dfb906e068d685b5e806f392438ae91ad`.
- Arbitrum: `0x678c30da359e85a970f5a9813ebd1d3ade38c219`.

All queried implementation targets have code. Six component reference
implementations per chain return version "5"; this does not prove matching
implementation bytecode. Robinhood uses USDG; other mainnets use their USDC
addresses. Primary round/deal fees are 50 bps on Robinhood and 30 bps elsewhere;
secondary deal fees are 500 bps on all four. No settings were changed.

## Deliverable and validation

Reusable read-only checker: `script/check-robinhood-address-parity.py`, reading
only allowlisted RPC settings. Configured and official Arbitrum endpoints
returned HTTP 429; retry through PublicNode with five-call batches completed
the Arbitrum snapshot while retaining completed snapshots for other chains.
[`--resume` preserves successful snapshots; no automatic claim that incomplete
chain reads mean undeployed contracts.]

Interactive canvas (local Codex/Cursor artifact):
`C:/Users/Michael/.cursor/projects/c-Users-Michael-git-cybercorps-contracts/canvases/robinhood-address-parity.canvas.tsx`.
It includes 63 named entries, searchable groups, current implementation links,
configuration differences and block evidence. Canvas skill used for this durable
four-chain comparison. TypeScript 5.0.4 strict checking against the installed canvas
SDK passed; Python compilation and whitespace checks passed. Canvas layout uses
real inline data, theme tokens and built-in tables/controls; no external fetches.

Source revision is `f90978dbf333abb19a20696fd879cb8aad55bdc4` plus the uncommitted
checker/evidence/records and pre-existing local changes. Source and checker SHA256
are in the report. No protocol source changes, wallet keys or chain transactions.
This confirms address/reference parity, not full logic/state equivalence, an
independent audit, every individual corporation's configuration or release approval.
