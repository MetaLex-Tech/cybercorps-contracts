# CyberCorp

The root contract of a cyberCORP — the onchain representation of the legal
entity.

* **Source:** [`src/CyberCorp.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberCorp.sol)
* **Inherits:** `Initializable`, `BorgAuthACL`, `UUPSUpgradeable`
* **`DEPLOY_VERSION`:** `"4"`

## State

| Variable | Type | Meaning |
|---|---|---|
| `cyberCORPName` | `string` | Legal name, including designation ("Inc.", "LLC"). |
| `cyberCORPType` | `string` | Entity type, as free-form text (e.g. "corporation"). **Not an enum.** |
| `cyberCORPJurisdiction` | `string` | Jurisdiction of formation. |
| `cyberCORPContactDetails` | `string` | Contact information. |
| `defaultDisputeResolution` | `string` | Default dispute-resolution mechanism for agreements. |
| `companyPayable` | `address` | Address that receives payments on the company's behalf. |
| `issuanceManager` | `address` | The cyberCORP's IssuanceManager. |
| `dealManager` | `address` | The cyberCORP's DealManager. |
| `roundManager` | `address` | The cyberCORP's RoundManager. |
| `upgradeFactory` | `address` | Factory whose reference implementation gates upgrades. |
| `companyOfficers` | `CompanyOfficer[]` | Officers (`{eoa, name, contact, title}`). |
| `escrowedOfficerSignatures` | `bytes[]` | Reusable pre-authorised officer signatures. |
| `extension` | `address` | Optional corp-level extension contract that interprets `extensionData`. |
| `extensionType` | `bytes32` | Type selector for the active extension schema. |
| `extensionData` | `bytes` | Raw extension payload interpreted by the active extension contract. |

## Functions

```solidity
function initialize(address _auth, string _name, string _type, string _jurisdiction,
    string _contact, string _disputeResolution, address _issuanceManager,
    address _companyPayable, CompanyOfficer _officer, address _upgradeFactory,
    address _roundManager) external;

function setcyberCORPDetails(string _name, string _type, string _jurisdiction,
    string _contact, string _disputeResolution) external;        // onlyOwner
function setIssuanceManager(address) external;                    // onlyOwner
function setDealManager(address) external;                        // onlyOwner
function setRoundManager(address) external;                       // onlyOwner
function setCompanyPayable(address) external;                     // onlyOwner
function addOfficer(CompanyOfficer) external;                     // onlyOwner
function removeOfficer(address) external;                         // onlyOwner
function removeOfficerAt(uint256) external;                       // onlyOwner
function isCyberCORPOfficer(address) external view returns (bool);

function addEscrowedOfficerSignature(bytes signature) external;             // onlyRole(200)
function setEscrowedOfficerSignature(uint256 index, bytes signature) external; // onlyRole(200)
function getEscrowedOfficerSignature(uint256 index) external view returns (bytes);
function getEscrowedOfficerSignatureCount() external view returns (uint256);

function setExtension(address _extension, bytes32 _extensionType) external; // onlyOwner
function setExtensionData(bytes _extensionData) external;                   // onlyOwner
function clearExtension() external;                                         // onlyOwner
function getExtensionURI() external view returns (string);
```

`addOfficer` also grants the officer's `eoa` BorgAuth role `200`;
`removeOfficer` / `removeOfficerAt` set it back to `0`.
`isCyberCORPOfficer` reports whether an address holds a role at or above
`OWNER_ROLE` (99). See [Access control](../access-control.md).

## Corp-level extension

`setExtension` installs an `ICyberCorpExtension` contract plus a schema
selector; the contract must report `supportsExtensionType(_extensionType)` or
the call reverts `ExtensionTypeNotSupported`. Setting or replacing the
extension clears any stored `extensionData`; `setExtensionData` then stores
the payload (reverting `ExtensionNotConfigured` if no extension is set).
`getExtensionURI` returns the extension-rendered JSON fragment for the
current payload — the
[CertificateUriBuilder](CertificateUriBuilder.md) appends it to every
cyberCERT's metadata.

## Events

`CyberCORPDetailsUpdated`, `OfficerAdded`, `OfficerRemoved`,
`CompanyPayableUpdated`, `EscrowedOfficerSignatureAdded`,
`EscrowedOfficerSignatureUpdated`, `CyberCORPExtensionSet`,
`CyberCORPExtensionDataUpdated`.

## Errors

`NotRefImplementation`, `SignatureRequired`, `InvalidEscrowSignatureIndex`,
`InvalidExtension`, `ExtensionTypeNotSupported`, `ExtensionNotConfigured`.

## Upgrades

`_authorizeUpgrade` is `onlyOwner` **and** requires the new implementation to
equal `ICyberCorpSingleFactory(upgradeFactory).getRefImplementation()` —
otherwise it reverts `NotRefImplementation`. The constructor calls
`_disableInitializers()`, so the implementation contract itself can never be
initialised. See [Upgrade model](../upgrade-model.md).
