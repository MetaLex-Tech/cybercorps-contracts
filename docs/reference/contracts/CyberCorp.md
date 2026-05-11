# CyberCorp

The **CyberCorp** contract is the root of a cyberCORP. It is the onchain
representation of the legal entity. Every other contract in the suite is
reachable from it.

* **Source:** [`src/CyberCorp.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorp.sol)
* **Proxy pattern:** UUPS (v3) or beacon proxy (legacy)

## Responsibilities

* Store the entity's legal identity: `legalName`, `entityType`,
  `jurisdiction`.
* Hold references to subsidiary contracts: `issuanceManager`,
  `dealManager`, `roundManager`, `cyberShares`, `auth` (BorgAuth),
  `agreementRegistry`.
* Hold the entity's authorized signatures escrow, default dispute resolution
  URI, and entity-level metadata.
* Expose UUPS `upgradeToAndCall` gated on `UPGRADE_AUTHORITY`.

## Selected public interface

```solidity
function legalName() external view returns (string memory);
function entityType() external view returns (EntityType);
function jurisdiction() external view returns (string memory);
function issuanceManager() external view returns (address);
function dealManager() external view returns (address);
function roundManager() external view returns (address);
function cyberShares() external view returns (address);
function auth() external view returns (address);
function agreementRegistry() external view returns (address);

function setLegalName(string calldata) external;             // OFFICER_AUTHORITY
function setDefaultDisputeResolution(string calldata) external; // OFFICER_AUTHORITY

function upgradeToAndCall(address, bytes calldata) external; // UPGRADE_AUTHORITY
```

## Entity types

The `EntityType` enum is configuration. It does not change the contract's
behaviour; it informs front-ends and the certificate URI builder. Supported
values include Delaware C-corp, Delaware LLC, Cayman LLC, Cayman SPC, BVI
fund, English company, generic LP, and analogues.

## Events

* `LegalNameUpdated(string newName)`
* `DefaultDisputeResolutionUpdated(string newUri)`
* `Upgraded(address indexed implementation)`

## See also

* [Access control](../access-control.md)
* [Upgrade model](../upgrade-model.md)
