# Deployments

Canonical contract addresses, by chain.

> **Source of truth:** the
> [`script/`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/script)
> directory of the contracts repository and MetaLeX release notes on
> [Substack](https://metalex.substack.com/). The tables below mirror those
> sources and will be kept in sync with releases.

## Ethereum mainnet

| Contract | Address |
|---|---|
| `CyberCorpFactory` | _see latest deployment script_ |
| `CyberCorpSingleFactory` | _see latest deployment script_ |
| `IssuanceManagerFactory` | _see latest deployment script_ |
| `DealManagerFactory` | _see latest deployment script_ |
| `RoundManagerFactory` | _see latest deployment script_ |
| `CyberAgreementRegistry` | _see latest deployment script_ |
| `CertificateUriBuilder` | _see latest deployment script_ |
| `LexChex` | _see latest deployment script_ |
| `LexChexMinter` | _see latest deployment script_ |
| `PumpCorpFactory` | _see latest deployment script_ |
| `MetaDAOFactory` | _see latest deployment script_ |
| `ParentCoFactory` | _see latest deployment script_ |

## Arbitrum

As above.

## Base

As above. ACE production deployment runs on Base (see
[ace.metalex.tech](https://ace.metalex.tech)).

## Test environments

* **Base Sepolia** — the canonical test environment. Some tests fork Base
  Sepolia (`forge test --via-ir --fork-url <rpc>`).

## Reference cyberCORPs

MetaLeX dogfoods the protocol with its own Delaware C-corp; MetaLeX's stock
ledger is maintained natively onchain via this contract suite.
