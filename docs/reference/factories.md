# Factories

Factories deploy and configure new cyberCORPs and their supporting
contracts. They are themselves UUPS-upgradeable and live in MetaLeX's
administrative domain (see [Upgrade model](upgrade-model.md)).

## CyberCorpFactory

The top-level entry point. Composes:

* `CyberCorpSingleFactory` (deploys the root `CyberCorp` proxy)
* `IssuanceManagerFactory` (deploys the issuance suite + beacons)
* `DealManagerFactory` (deploys the cyberCORP's `DealManager`)
* `RoundManagerFactory` (deploys the cyberCORP's `RoundManager`)

```solidity
function createCyberCorp(EntityConfig calldata, GovernanceConfig calldata)
    external returns (address cyberCorp);
```

## CyberCorpSingleFactory

Deploys a single `CyberCorp` UUPS proxy from the registered
`refImplementation`.

## IssuanceManagerFactory

Deploys an `IssuanceManager` UUPS proxy plus the `CyberCertPrinter` and
`CyberScrip` beacons owned by it. Holds the v3 reference implementations for
all three.

```solidity
function setRefImplementation(address) external;                       // METALEX_ADMIN
function setCyberCertPrinterRefImplementation(address) external;       // METALEX_ADMIN
function setCyberScripRefImplementation(address) external;             // METALEX_ADMIN
```

## DealManagerFactory / RoundManagerFactory

Symmetric factories for the deal and round managers.

## PumpCorpFactory

Powers **ACE**. Deploys a cyberCORP + `RoundManager` pre-configured for an
ACE-style Reg S offering, registers `ACESAFEExtension` on the
`CyberCertPrinter`, and seeds the agreement registry with the ACE SAFE
template.

Supports party-specific allocations and global price / cap configuration.

## MetaDAOFactory

Deploys a MetaDAO-style futarchy-governed Cayman SPC. Pre-registers the
`MetaDAO Futarchy Governance SPC` templates. Wires governance authority to a
futarchy oracle (per portfolio / SegCo).

## ParentCoFactory

Deploys parent + subsidiary cyberCORP structures for holding-company
configurations. Both parent and sub share the same agreement registry and
can cross-reference each other in their entity metadata.

## See also

* [How-to: Deploy a PumpCorp for ACE](../how-to/deploy-pumpcorp-ace.md)
* [How-to: Deploy a MetaDAO SPC](../how-to/deploy-metadao-spc.md)
* [Upgrade model](upgrade-model.md)
