# Factories

Factories deploy cyberCORPs and their contracts.

## CyberCorpFactory

The top-level entry point.

* **Source:** [`src/CyberCorpFactory.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorpFactory.sol)
* **Inherits:** `UUPSUpgradeable`, `BorgAuthACL`

```solidity
function deployCyberCorp(bytes32 salt, string companyName, string companyType,
    string companyJurisdiction, string companyContactDetails,
    string defaultDisputeResolution, address _companyPayable,
    CompanyOfficer _officer)
    external returns (address cyberCorp, address auth, address issuanceManager,
                      address dealManager, address roundManager);

function deployCyberCorpAndCreateOffer(/* ... */) external returns (/* corp suite + deal */);
function deployCyberCorpAndCreateRound(/* ... */) external returns (/* corp suite + roundId */);
function deployAndInitializeRoundManager(bytes32 salt, address cyberCorp) public returns (address);
```

`deployCyberCorp`:

1. Deploys a `BorgAuth` ACL via `CREATE2` and grants the officer level `200`.
2. Deploys the `IssuanceManager`, `CyberCorp`, `DealManager`, and
   `RoundManager` through their respective sub-factories and initialises
   them.
3. Grants the `IssuanceManager`, `DealManager`, and `RoundManager` BorgAuth
   level `99`, and the `CyberCorp` level `200`.
4. Emits `CyberCorpDeployed`.

The `deployCyberCorpAndCreate*` variants additionally create cert printers
and open a deal or a round in the same transaction. Their `CyberCertData`
struct carries, per printer, the security class/series, the certificate
[extension](extensions.md) contract, and an extension-encoded `seriesData`
payload (series-scope terms; see `ICertificateExtensionV3`).

`deployAndInitializeRoundManager(salt, cyberCorp)` is public so a
`RoundManager` can be retrofitted onto an existing cyberCORP that predates
rounds (the corp must authorise it itself; see also
`src/helpers/RoundManagerUpgradeHelper.sol`).

Setters (`onlyOwner`): `setStable`, `setIssuanceManagerFactory`,
`setCyberCorpSingleFactory`, `setCyberAgreementFactory`,
`setDealManagerFactory`, `setRoundManagerFactory`, `setLexchexAuth`.

## Sub-factories

`CyberCorpFactory` composes:

| Factory | Deploys |
|---|---|
| `CyberCorpSingleFactory` | the `CyberCorp` proxy; holds the reference implementation that gates `CyberCorp` upgrades. |
| `IssuanceManagerFactory` | the `IssuanceManager`; holds the `LedgerEntryToken` (cert printer) and `CyberScrip` reference implementations that the IssuanceManager's own beacons point at. |
| `DealManagerFactory` | the `DealManager`. |
| `RoundManagerFactory` | the `RoundManager`. |

The `CyberAgreementRegistry` is shared (passed in as `registryAddress`).

## Specialised factories

These build on the same primitives for specific structures:

| Factory | Source | Purpose |
|---|---|---|
| `PumpCorpFactory` | `src/PumpCorpFactory.sol` | Deploys cyberCORPs configured for **ACE** (token-to-equity) offerings. |
| `MetaDAOFactory` | `src/MetaDAOFactory.sol` | Deploys MetaDAO futarchy-governed SPC structures. |
| `ParentCoFactory` | `src/ParentCoFactory.sol` | Deploys parent/subsidiary cyberCORP structures. |

> The specialised factories are documented here at a high level. Consult
> their source for exact constructors and deployment parameters.
