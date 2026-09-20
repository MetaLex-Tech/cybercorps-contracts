---
description: Deployed addresses and versions per chain
---

# Deployments

Canonical contract addresses, by chain.

> **Source of truth:** the
> [
`script/libs/DeploymentConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/libs/DeploymentConstants.sol)
> library (and the raw deploy logs in `script/res/deployment-addresses.md`)
> in the contracts repository, plus MetaLeX release notes on
> [Substack](https://metalex.substack.com/). The tables below mirror those
> sources and will be kept in sync with releases.

## Production chains (Ethereum mainnet, Base)

The core suite is deployed at the same addresses on the production chains
(`DeploymentConstants.coreV2`):

| Contract                                 | Address                                                         |
|------------------------------------------|-----------------------------------------------------------------|
| MetaLeX Safe (multisig)                  | `0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C`                    |
| `BorgAuth` (MetaLeX platform auth)       | `0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01`                    |
| `CyberCorpFactory`                       | `0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2`                    |
| `CyberCorpSingleFactory`                 | `0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4`                    |
| `IssuanceManagerFactory`                 | `0xD353972D7955F421d94d0eA8c42c88c417F7155A`                    |
| `DealManagerFactory`                     | `0x3982b078f2ac306219c9540Ebc908360a960C251`                    |
| `RoundManagerFactory`                    | `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9`                    |
| `CyberAgreementRegistry`                 | `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`                    |
| `CertificateUriBuilder`                  | `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3`                    |
| LeXcheX `BorgAuth`                       | `0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2`                    |
| `LeXcheX`                                | `0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62`                    |
| `LeXcheXMinter`                          | `0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960`                    |
| `LexChexCondition`                       | `0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42`                    |
| `NonUSNationalityCondition` (zkPassport) | `0xe71fE689bFAA4939A760EDF7e07f44372a43932A`                    |
| `ParentCoFactory`                        | `0x5c6D411600774c8fE1Aa805d78F03202d7FCD47F` (Ethereum mainnet) |
| `PumpCorpFactory`                        | _see latest deployment script_                                  |
| `MetaDAOFactory`                         | _see latest deployment script_                                  |

`LeXcheXBadge` is deployed on Base Sepolia only. ACE production deployment
runs on Base (see [ace.metalex.tech](https://ace.metalex.tech)). Some
operational scripts also carry Arbitrum configuration (e.g. Arbitrum USDC),
but `DeploymentConstants` does not enumerate Arbitrum core addresses.

## Test environments

Base Sepolia and Ethereum Sepolia are the canonical test environments (some
tests fork them: `forge test --via-ir --fork-url <rpc>`). The testnet
suites share the production addresses **except**:

| Contract                    | Ethereum Sepolia                             | Base Sepolia                                 |
|-----------------------------|----------------------------------------------|----------------------------------------------|
| `IssuanceManagerFactory`    | _as production_                              | `0xbbD386D237f3b407E6511A52488850b1Da0cCad2` |
| `RoundManagerFactory`       | _as production_                              | `0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34` |
| `NonUSNationalityCondition` | `0xd91a24Ac7D2981c6d660EDEe05Aec22eA5B95E95` | _not deployed (no zkPassport verifier)_      |
| `ParentCoFactory`           | `0x0c6Fc81BEd7f91f7a3b3594CCc66484893634Bf9` | `0xC1304898FAfF45cA2B07C0f4E10B77843eD5a47B` |

### Certificate extensions (Base Sepolia)

The seven V3 extensions render the whole certificate. They have proxies on Base
Sepolia only. A v5 corp points its new printers at them; existing printers stay
on their V1 or V2 proxy. The addresses come from CREATE2, so the production run
gives the same ones.

| Contract                  | Address                                      |
|---------------------------|----------------------------------------------|
| `ACESAFEExtensionV3`      | `0x9a8ef946F18C4296e50f8DF0C97b5Cf5d1b5eCD2` |
| `SAFEExtensionV3`         | `0x740003076c9F16c4a364AE07f3770FB77899299b` |
| `SAFTExtensionV3`         | `0x2Bf1b2f8f6009c5524886243CE4F2EF34e3d4957` |
| `SAFTEExtensionV3`        | `0xE79C2b4a35b2509b27686D025FB8Fbab2Ca49406` |
| `TokenWarrantExtensionV3` | `0x3Bdb711517eEbd6A88D9Aa30B141adC43BAB033e` |
| `ShareExtensionV3`        | `0xa21C434379CC44bfeD6e3c1342e49951804ec30f` |
| `FundInterestExtensionV3` | `0x2322D1dcC199d7A9Ee60F331cA9D76d244F09a15` |

### Secondary-trading conditions (Base Sepolia)

The 19 shared conditions have instances on Base Sepolia only, with the first
LeXcheXBadge. Each one is configured per SPV through that SPV's own BorgAuth
admin. The two kill-switch admin keys there are staging values.

| Contract                               | Address                                      |
|----------------------------------------|----------------------------------------------|
| `LeXcheXBadge`                         | `0x114664773Ba721a6AA43890d5FDE7939aF37618F` |
| `LeXcheXBadge` BorgAuth                | `0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d` |
| `EligibilityCondition`                 | `0x64f43CEfc89279aB6a529eb4C7432cF4b37f3E4B` |
| `USStateOfResidenceCondition`          | `0x1d4918a83E1F971317f0DD529f088B208Ec24d8C` |
| `LegionSoulboundCondition`             | `0x3b96b3a385009B4D0C523DfD6D5B4cf5365e2A04` |
| `HolderCapCondition`                   | `0xA8422D5fFE6b697152aEE19d13910302dE1E0576` |
| `CFIUSCondition`                       | `0x89Fa72549b5Fadf209377d5348C30bca4c7e0462` |
| `Section4a7DisclosureCondition`        | `0x42c9e2dadE9669c725D88b78cD0e545FD9e7F723` |
| `Rule144DisclosureCondition`           | `0x7e30Ef03A0C4C7094D464b714E2480EF30088629` |
| `HoldingPeriodCondition`               | `0xc5417d7DDE94310Ba334e31517deFED0aa0ED81F` |
| `LegalOpinionCondition`                | `0xD27317AED94BE6d310eA6B8c4e08360957ff24e3` |
| `RegSDistributionComplianceCondition`  | `0xe8A325Ba2dF0ba3E08A55B3E3F2bBBBc9354CebB` |
| `GPLPApprovalCondition`                | `0x4be9Eaff732F4BA3f1Fc6359a2F0858F70637c69` |
| `AccreditedInvestorCondition`          | `0xedac303CAfdedd92aB6fbECFafFC0a648d9157a1` |
| `QualifiedPurchaserCondition`          | `0xE4bcf1c4EA266bbD7F3c58A3aa02c43B5cdc9875` |
| `QualifiedInstitutionalBuyerCondition` | `0x8A617187aF27a98c89548dfFd886EEab0De0936F` |
| `NonUSPersonCondition`                 | `0xe2AAc5187058a5c97Da7e6D3D6F9D5811124dcBb` |
| `SpvWhitelistCondition`                | `0x0f2952dcf0279782e6048D2800ee3BeAd9f59f33` |
| `SyndicateCondition`                   | `0x089b4Dba2E3EB49f875c0D7F92A06276B204870f` |
| `KillSwitchCondition`                  | `0x4c3b9Ec3B6e416A64Fde4a17Ea856e1cf2fE0344` |
| `TimeSettlementPeriodCondition`        | `0x1E466EcbBC41f6777c4458F8880E62dBf1D08fAd` |

The last six named conditions are parameterizations of
`LexChexBadgeKindCondition`: one proxy per fact-key, all on one implementation.

## Deploy versions

Version-tracking constants (`DEPLOY_VERSION`) in the current source: `CyberCorp`,
`IssuanceManager`, `DealManager`, `RoundManager`, `CyberScrip` and
`LedgerEntryToken` at `"5"`. A production corp keeps its 4.x code until the corp
owner executes the v5 upgrade batch.

## Reference cyberCORPs

MetaLeX dogfoods the protocol with its own Delaware C-corp; MetaLeX's stock
ledger is maintained natively onchain via this contract suite.
