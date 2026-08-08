# Deployments

Canonical contract addresses, by chain.

> **Source of truth:** the
> [`script/libs/DeploymentConstants.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/script/libs/DeploymentConstants.sol)
> library (and the raw deploy logs in `script/res/deployment-addresses.md`)
> in the contracts repository, plus MetaLeX release notes on
> [Substack](https://metalex.substack.com/). The tables below mirror those
> sources and will be kept in sync with releases.

## Production chains (Ethereum mainnet, Base)

The core suite is deployed at the same addresses on the production chains
(`DeploymentConstants.coreV2`):

| Contract | Address |
|---|---|
| MetaLeX Safe (multisig) | `0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C` |
| `BorgAuth` (MetaLeX platform auth) | `0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01` |
| `CyberCorpFactory` | `0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2` |
| `CyberCorpSingleFactory` | `0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4` |
| `IssuanceManagerFactory` | `0xD353972D7955F421d94d0eA8c42c88c417F7155A` |
| `DealManagerFactory` | `0x3982b078f2ac306219c9540Ebc908360a960C251` |
| `RoundManagerFactory` | `0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9` |
| `CyberAgreementRegistry` | `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` |
| `CertificateUriBuilder` | `0x5500c095ea7dE6F8a5E15949e24B80604cc670A3` |
| LeXcheX `BorgAuth` | `0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2` |
| `LeXcheX` | `0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62` |
| `LeXcheXMinter` | `0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960` |
| `LexChexCondition` | `0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42` |
| `NonUSNationalityCondition` (zkPassport) | `0xe71fE689bFAA4939A760EDF7e07f44372a43932A` |
| `ParentCoFactory` | `0x5c6D411600774c8fE1Aa805d78F03202d7FCD47F` (Ethereum mainnet) |
| `PumpCorpFactory` | _see latest deployment script_ |
| `MetaDAOFactory` | _see latest deployment script_ |

`LeXcheXBadge` is not yet deployed on any chain. ACE production deployment
runs on Base (see [ace.metalex.tech](https://ace.metalex.tech)). Some
operational scripts also carry Arbitrum configuration (e.g. Arbitrum USDC),
but `DeploymentConstants` does not enumerate Arbitrum core addresses.

## Test environments

Base Sepolia and Ethereum Sepolia are the canonical test environments (some
tests fork them: `forge test --via-ir --fork-url <rpc>`). The testnet
suites share the production addresses **except**:

| Contract | Ethereum Sepolia | Base Sepolia |
|---|---|---|
| `IssuanceManagerFactory` | _as production_ | `0xbbD386D237f3b407E6511A52488850b1Da0cCad2` |
| `RoundManagerFactory` | _as production_ | `0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34` |
| `NonUSNationalityCondition` | `0xd91a24Ac7D2981c6d660EDEe05Aec22eA5B95E95` | _not deployed (no zkPassport verifier)_ |
| `ParentCoFactory` | `0x0c6Fc81BEd7f91f7a3b3594CCc66484893634Bf9` | `0xC1304898FAfF45cA2B07C0f4E10B77843eD5a47B` |

## Deploy versions

Version-tracking constants (`DEPLOY_VERSION`) in the current source:
`CyberCorp`, `RoundManager`, `CyberScrip`, and `LedgerEntryToken` at `"4"`;
`IssuanceManager` at `"4.1"`; `DealManager` at `"4.0.1"`.

## Reference cyberCORPs

MetaLeX dogfoods the protocol with its own Delaware C-corp; MetaLeX's stock
ledger is maintained natively onchain via this contract suite.
