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
function deployCyberCorpAndCreateRound(/* ..., bytes escrowedSignature,
    bytes metadataSignature, ... */) external returns (/* corp suite + roundId */);
function computeDeploymentSalt(bytes32 salt, /* company fields */,
    address _companyPayable, CompanyOfficer _officer) public pure returns (bytes32);
```

`deployCyberCorp`:

1. Checks that every sub-factory namespaces CREATE2 salts by caller (see
   below; `IncompatibleComponentFactory` otherwise), then replaces `salt`
   with `computeDeploymentSalt(...)`, a hash of the salt, the company
   details, the payout address and the officer. The predicted addresses
   therefore commit to that configuration: anyone may submit the call (so it
   works inside a multicall), but only with the same officer and settings,
   and deploying directly through a sub-factory lands in the caller's own
   namespace, so nobody can squat a company's predicted addresses.
2. Deploys a `BorgAuth` ACL via `CREATE2` and grants the officer level `200`.
3. Deploys the `IssuanceManager`, `CyberCorp`, `DealManager`, and
   `RoundManager` through their respective sub-factories and initialises
   them.
4. Grants the `IssuanceManager`, `DealManager`, and `RoundManager` BorgAuth
   level `99`, and the `CyberCorp` level `200`.
5. Emits `CyberCorpDeployed`.

The new `BorgAuth` is constructed with the factory as its owner (level
`99`), and the factory does not renounce that level; see
[Access control](access-control.md#roles-the-protocol-assigns).

The `deployCyberCorpAndCreate*` variants additionally create cert printers
and open a deal or a round in the same transaction. Their `CyberCertData`
struct (defined once in `CyberCorpConstants.sol` and shared by the factory,
deal and round paths) carries, per printer, the name, symbol, URI, security
class/series, the certificate [extension](extensions.md) contract, an
extension-encoded `seriesData` payload, and the default legend.

`deployCyberCorpAndCreateRound` also requires `metadataSignature`: the
officer's EIP-712 signature (domain name `"CyberCorpFactory"`, version
`"1"`) over the deployment metadata that the escrowed round signature does
not cover: the corp salt, payout address, round flags, officer, company
details, extension data, round party values, legal details, cert data and
condition addresses. A missing or wrong signature reverts
`InvalidMetadataSignature`, so a caller cannot substitute those fields.

Setters (`onlyOwner`): `setStable`, `setIssuanceManagerFactory`,
`setCyberCorpSingleFactory`, `setCyberAgreementFactory`,
`setDealManagerFactory`, `setRoundManagerFactory`, `setLexchexAuth`.

The factory no longer exposes a public `deployAndInitializeRoundManager`.
To attach a RoundManager to an older cyberCORP that has none, the
repository's `RoundManagerUpgradeHelper.upgradeCorp(corp, salt)` deploys
and wires one; the caller must hold `OWNER_ROLE` on the corp's BorgAuth, the
helper itself needs that role for the call, and it renounces the role
(`zeroOwner`) when done.

## Sub-factories

`CyberCorpFactory` composes:

| Factory | Deploys |
|---|---|
| `CyberCorpSingleFactory` | the `CyberCorp` proxy; holds the reference implementation that gates `CyberCorp` upgrades. |
| `IssuanceManagerFactory` | the `IssuanceManager`; holds the `LedgerEntryToken` (cert printer) and `CyberScrip` reference implementations that the IssuanceManager's own beacons point at. |
| `DealManagerFactory` | the `DealManager`; also holds the platform fee settings. |
| `RoundManagerFactory` | the `RoundManager`; also holds the platform fee settings and the payment-token whitelist. |

Each sub-factory's `deploy*(salt)` is permissionless but namespaced: it
deploys at `deploymentSalt(salt, msg.sender)` = `keccak256(abi.encode(msg.sender,
salt))`, so each caller has its own address space. Predict an address with
the two-argument `compute*Address(salt, deployer)`; the one-argument form
uses the caller. Each sub-factory publishes the reference implementation
for new deployments and upgrades (`getRefImplementation`, plus
`getCyberCertPrinterRefImplementation` / `getCyberScripRefImplementation` on
the IssuanceManagerFactory); see [Upgrade model](upgrade-model.md).

The `CyberAgreementRegistry` is shared (passed in as `registryAddress`).

## Specialised factories

These build on the same primitives for specific structures:

| Factory | Source | Purpose |
|---|---|---|
| `PumpCorpFactory` | `src/PumpCorpFactory.sol` | Deploys cyberCORPs configured for **ACE** (token-to-equity) offerings. Uses the same salt binding and the same officer metadata signature, under the EIP-712 domain name `"PumpCorpFactory"`. |
| `MetaDAOFactory` | `src/MetaDAOFactory.sol` | Deploys MetaDAO futarchy-governed SPC structures. |
| `ParentCoFactory` | `src/ParentCoFactory.sol` | Deploys parent/subsidiary cyberCORP structures. |

> The specialised factories are documented here at a high level. Consult
> their source for exact constructors and deployment parameters.
