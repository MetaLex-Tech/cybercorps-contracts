---
description: Deployed addresses and versions per chain
---

# Deployments

Canonical contract addresses, by chain.

> **Source of truth:** the
> [`script/libs/DeploymentConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/libs/DeploymentConstants.sol)
> library (and the raw deploy logs in `script/res/deployment-addresses.md`)
> in the contracts repository, plus MetaLeX release notes on
> [Substack](https://metalex.substack.com/). Most entries are proxies whose
> implementations differ by chain, so read the EIP-1967 implementation slot
> instead of assuming one.

## Production chains (Ethereum, Base, Arbitrum)

The core suite is deployed at the same addresses on Ethereum mainnet, Base
and Arbitrum One (`DeploymentConstants.coreV2`):

| Contract                                 | Address                                      | Chains |
|------------------------------------------|----------------------------------------------|--------|
| MetaLeX Safe (multisig)                  | `0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C` | all three |
| `BorgAuth` (MetaLeX platform auth)       | `0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01` | all three |
| `CyberCorpFactory`                       | `0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2` | all three |
| `CyberCorpSingleFactory`                 | `0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4` | all three |
| `IssuanceManagerFactory`                 | `0xD353972D7955F421d94d0eA8c42c88c417F7155A` | all three |
| `DealManagerFactory`                     | `0x3982b078f2ac306219c9540Ebc908360a960C251` | all three |
| `RoundManagerFactory`                    | `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9` | all three |
| `CyberAgreementRegistry`                 | `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` | all three |
| `CertificateUriBuilder`                  | `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3` | all three |
| LeXcheX `BorgAuth`                       | `0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2` | all three |
| `LeXcheX`                                | `0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62` | all three |
| `LeXcheXMinter`                          | `0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960` | all three |
| `LexChexCondition`                       | `0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42` | all three |
| `LeXcheXBadge`                           | `0x114664773Ba721a6AA43890d5FDE7939aF37618F` | all three |
| `LeXcheXBadge` BorgAuth                  | `0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d` | all three |
| `NonUSNationalityCondition` (zkPassport) | `0xe71fE689bFAA4939A760EDF7e07f44372a43932A` | Ethereum, Base |
| `ParentCoFactory`                        | `0x5c6D411600774c8fE1Aa805d78F03202d7FCD47F` | Ethereum |
| `PumpCorpFactory`                        | `0xe73Ea052c2891cE1668742142a6634Df09c88512` | Base |
| `MetaDAOFactory`                         | _see latest deployment script_               | |

The certificate image builder is a separate contract on each chain; read
its address from `CertificateUriBuilder.imageBuilder()`. ACE runs in
production on Base (see [ace.metalex.tech](https://ace.metalex.tech)),
with its own pump stack beside the core suite.

zkSync Era is not in these tables: none of the shared addresses has code
there, and v5 is not deployed there. Its agreement registry,
`0x07E0a0BeC742f90f7879830bC917E783dA6a6357`, uses the signature type
without `signer` and the four-field agreement id (see
[CyberAgreementRegistry](contracts/CyberAgreementRegistry.md#data-model)).

## Test environments

Base Sepolia and Ethereum Sepolia are the test environments (some tests
fork them: `forge test --via-ir --fork-url <rpc>`). The testnet suites
share the production addresses **except**:

| Contract                    | Ethereum Sepolia                             | Base Sepolia                                 |
|-----------------------------|----------------------------------------------|----------------------------------------------|
| MetaLeX Safe                | _no code (testnets keep roles with the deployer)_ | _no code (testnets keep roles with the deployer)_ |
| `IssuanceManagerFactory`    | _as production_                              | `0xbbD386D237f3b407E6511A52488850b1Da0cCad2` |
| `RoundManagerFactory`       | _as production_                              | `0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34` |
| `NonUSNationalityCondition` | `0xd91a24Ac7D2981c6d660EDEe05Aec22eA5B95E95` | _not deployed (no zkPassport verifier)_      |
| `ParentCoFactory`           | `0x0c6Fc81BEd7f91f7a3b3594CCc66484893634Bf9` | `0xC1304898FAfF45cA2B07C0f4E10B77843eD5a47B` |

## Certificate extensions

The extension proxies have the same addresses on every chain above. A v5
company points its new LET contracts at the V3 extensions, which render
the whole certificate; an existing LET contract stays on the V1 or V2
proxy it was created with. See [Certificate extensions](extensions.md).

| Contract                    | Address                                      | Chains |
|-----------------------------|----------------------------------------------|--------|
| `SAFEExtension`             | `0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8` | all |
| `SAFEExtensionV3`           | `0x740003076c9F16c4a364AE07f3770FB77899299b` | all |
| `ACESAFEExtension`          | `0x6aDaef2B79FD1cbA130c5807B31DE435FEa58EAC` | Base |
| `ACESAFEExtensionV3`        | `0x9a8ef946F18C4296e50f8DF0C97b5Cf5d1b5eCD2` | all |
| `SAFTExtension`             | `0x109D2A13932bE393011835B308F81ce1992E365B` | all |
| `SAFTExtensionV2`           | `0x37c2A0e801e569e01f0972186aF4DB01409e92c1` | all |
| `SAFTExtensionV3`           | `0x2Bf1b2f8f6009c5524886243CE4F2EF34e3d4957` | all |
| `SAFTEExtension`            | `0xE070eDA75695bE3ED4B9ec3719b76Dd36794787C` | all |
| `SAFTEExtension` (older build, used by one SAFTE template) | `0xC23fFF0B06aE5EBea862611F489b1329108ce603` | all |
| `SAFTEExtensionV2`          | `0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A` | all |
| `SAFTEExtensionV3`          | `0xE79C2b4a35b2509b27686D025FB8Fbab2Ca49406` | all |
| `TokenWarrantExtension`     | `0xbad0b411C37cfF66e4C0B7764Db2d499eA757bb4` | all |
| `TokenWarrantExtensionV2`   | `0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F` | all |
| `TokenWarrantExtensionV3`   | `0x3Bdb711517eEbd6A88D9Aa30B141adC43BAB033e` | all |
| `ShareExtension`            | `0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81` | all |
| `ShareExtensionV3`          | `0xa21C434379CC44bfeD6e3c1342e49951804ec30f` | all |
| `FundInterestExtensionV3`   | `0x2322D1dcC199d7A9Ee60F331cA9D76d244F09a15` | all |

"All" means Ethereum, Base, Arbitrum, Base Sepolia and Ethereum Sepolia.

## Secondary-trading conditions

The 19 shared conditions have the same addresses on Ethereum, Base,
Arbitrum, Base Sepolia and Ethereum Sepolia. Each one is configured per SPV
through that SPV's own BorgAuth admin; see [Conditions](conditions.md).

| Contract                               | Address                                      |
|----------------------------------------|----------------------------------------------|
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
| `KillSwitchCondition`                  | `0x456EDAfB7283dB8FDa2A5b3ecE576d9292512435` |
| `TimeSettlementPeriodCondition`        | `0x1E466EcbBC41f6777c4458F8880E62dBf1D08fAd` |

The six conditions from `AccreditedInvestorCondition` to
`SyndicateCondition` are parameterizations of `LexChexBadgeKindCondition`:
one proxy per fact-key, all on one implementation. `KillSwitchCondition`
and `TimeSettlementPeriodCondition` are plain (non-upgradeable) contracts.

## Deploy versions

`CyberCorp`, `IssuanceManager`, `DealManager`, `RoundManager`,
`CyberScrip` and `LedgerEntryToken` report `DEPLOY_VERSION` `"5"` in the
source. On all five chains the factories publish v5 reference
implementations, so new companies are v5. An existing company keeps its
version (`"3"`, `"4"`, or `"4.1"` for the IssuanceManager) until its owner
runs the [upgrade](../how-to/upgrade-a-cybercorp.md).

The v5 reference implementations on the production chains (each factory's
`getRefImplementation()`, and the IssuanceManagerFactory's
`LedgerEntryToken` and `CyberScrip` references):

| Contract           | Ethereum                                     | Base                                         | Arbitrum                                     |
|--------------------|----------------------------------------------|----------------------------------------------|----------------------------------------------|
| `CyberCorp`        | `0x511C9A7c13076f37659F15202781D802EcaeEDBb` | `0x1d85C3932ee70c74B331c80cc4a6a0fd5fFeE4E2` | `0xE4c397CE002a53d7151dD53ddaC8eba98Fea559C` |
| `IssuanceManager`  | `0xE4c397CE002a53d7151dD53ddaC8eba98Fea559C` | `0x0BAF2f3cA8361C2AcdDc9c93018049dc2099634f` | `0x40B16aCE1f9A802207A9b4B0d2918A007edDf0f5` |
| `LedgerEntryToken` | `0xd96dB07756a4EFc9aF634Ed89aFf43A29B9E3533` | `0x2e2e7A233C842F5c454bb3db69380647421B98fA` | `0x571f1b093997f32Fef6b6B055Fe9202680074E20` |
| `CyberScrip`       | `0x40B16aCE1f9A802207A9b4B0d2918A007edDf0f5` | `0x3C0E4897A6ABfA013f40E5E6D27f852A5Cc60A80` | `0x37aa6934e735f3984D4885545A080233DBc9BB75` |
| `DealManager`      | `0x37aa6934e735f3984D4885545A080233DBc9BB75` | `0x820d6D00A90185d702B2d45840690DC96F9DAEb4` | `0xb87742F0743949EA1cBe0d2427CB8D41101EEBAD` |
| `RoundManager`     | `0xc4099c6212cc28EA28c9dAD8F3dAc613372f6e34` | `0xE463CFF49e2be5c4A4820939f8243daE480c6537` | `0x511C9A7c13076f37659F15202781D802EcaeEDBb` |

The same address can hold different contracts on different chains
(`0x511C…` is the CyberCorp reference on Ethereum and the RoundManager
reference on Arbitrum, for example), so always pair an address with its
chain.

## MetaLeX's own cyberCORP

MetaLeX runs its own Delaware C-corp on the protocol and keeps its stock
ledger natively onchain in this contract suite.
