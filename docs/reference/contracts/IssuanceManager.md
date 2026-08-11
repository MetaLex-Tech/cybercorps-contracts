---
description: "The issuance authority: printers, cyberCERTs, scrip, security classes, secondary transfers"
---

# IssuanceManager

The issuance authority for a cyberCORP. It creates LedgerEntryToken printers,
issues and manages cyberCERTs, registers security-class designations, deploys
CyberScrip, runs scripification, and effectuates secondary-trade ownership
changes.

* **Source:** [`src/IssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/IssuanceManager.sol)
  / interface [`IIssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IIssuanceManager.sol)
* **Pattern:** UUPS proxy; owns the `cyberCertPrinterBeacon` and
  `cyberScripBeacon` `UpgradeableBeacon`s. Most logic is delegated to the
  [`IssuanceManagerStorage`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/IssuanceManagerStorage.sol)
  library to stay under the EIP-170 size limit.
* **`DEPLOY_VERSION`:** `"4.1"`

One IssuanceManager exists per cyberCORP. It creates **one LedgerEntryToken
printer per security series** (`createCertPrinter`), and **one CyberScrip per
printer** (`deployCyberScrip`).

## Certificate lifecycle

```solidity
function createCertPrinter(string[] _ledger, string _name, string _ticker,
    string _certificateUri, SecurityClass _securityType,
    SecuritySeries _securitySeries, address _extension,
    bytes _seriesData) external returns (address);              // onlyOwner

function createCert(address certAddress, address to, CertificateDetails _details)
    external returns (uint256);                                  // onlyOwner
function createCertAndAssign(address certAddress, address investor,
    CertificateDetails _details) external returns (uint256 tokenId); // onlyOwnerOrSelf
function createCertAndAssignWithName(address certAddress, address investor,
    CertificateDetails _details, string investorName, bytes endorsementSignature,
    uint256 timestamp) external returns (uint256 tokenId);       // onlyOwnerOrSelf
function createCertSignAndAssign(address certAddress, address investor,
    CertificateDetails _details, bytes endorsementSignature, address registry,
    bytes32 agreementId, string investorName)
    external returns (uint256 tokenId);                          // onlyOwnerOrSelf
function assignCert(address certAddress, address from, uint256 tokenId,
    address investor, CertificateDetails _details) external;     // onlyOwner
```

> There is no single `issueCert` function. Issuance is `createCert*` — the
> variant depends on whether you assign a holder, a name, and a signature/
> endorsement at mint time. The `createCert*AndAssign` variants also record
> an endorsement and attach the cyberCORP's escrowed officer signature (if
> one is stored) as an issuer signature.

Certificate signing, endorsement, voiding, legends, hooks, and
transferability are no longer routed through the IssuanceManager: those
functions live on the [LedgerEntryToken](LedgerEntryToken.md) itself, gated
`onlyIssuanceManagerOrAdmin` so BorgAuth admins call the printer directly.

## Security-class registry

Class-level LET designations (see `SecurityClassInfo` in
`CyberCorpConstants.sol`) are registered on the IssuanceManager; each printer
(the series scope) may be assigned to one class, and multiple printers can
share a class.

```solidity
function defineSecurityClass(SecurityClass _classType, string _documentURI,
    address _dataExtension, bytes _classData)
    external returns (uint256 classId);                          // onlyOwner
function updateSecurityClass(uint256 _classId, SecurityClass _classType,
    string _documentURI, address _dataExtension, bytes _classData) external; // onlyOwner
function setPrinterClass(address _printer, uint256 _classId) external;       // onlyOwner

function getSecurityClass(uint256 _classId) external view returns (SecurityClassInfo);
function getSecurityClassCount() external view returns (uint256);
function getPrinterClassId(address _printer) external view returns (uint256); // 0 = unclassified
```

Class IDs are sequential starting at 1 (`0` = unclassified).

## Secondary transfers

```solidity
function secondaryTransfer(bytes dealMetadata) external;         // onlyOwner
```

Effectuates the ownership change of a settled secondary trade. Gated on
`OWNER_ROLE`, which the SPV's [DealManager](DealManager.md) holds;
`dealMetadata` is the abi-encoded tuple produced by
`DealManager.finalizeSecondaryTradeAgreement`. The seller's Ledger Entry
Token never moves wallets — ownership transfers via registered-owner
metadata (mutate-and-mint).

## Scripification

```solidity
function deployCyberScrip(address certAddress,
    ITransferRestrictionHook[] typeRestrictionHooks,
    ICondition[] certToScripConditions, ICondition[] scripToCertConditions,
    uint256 scripToCertMinimum, uint256 scripRatioNumerator,
    uint256 scripRatioDenominator, uint256[] scripifyWhitelistIds,
    bool scripifyWhitelistEnabled, bool enableForceTransfer,
    bool enableForceBurn, bool enableFreeze) external returns (address); // onlyOwner

function scripifyCert(address certAddress, uint256 id, uint256 amount, address target) external;
function convertScripToCert(address certAddress, uint256 amount) external;
function setScripRatio(address certAddress, uint256 numerator, uint256 denominator) external; // onlyOwner
function setScripToCertMinimum(address certAddress, uint256 minimum) external;                // onlyOwner

function setRecertificationApproval(address certAddress, address investor,
    string investorName, CertificateDetails details, bytes officerSignature) external; // onlyAdmin
function clearRecertificationApproval(address certAddress, address investor) external; // onlyAdmin
```

Plus scripify-whitelist management (`setScripifyWhitelistEnabled`,
`addScripifyWhitelistIds`, `removeScripifyWhitelistIds`,
`isScripifyWhitelisted`, `getScripifyWhitelistEnabled`) and views
(`getScripRatio`, `getScripToCertMinimum`, `getRecertificationApproval`,
`getCertScripifiedStatus`, `getScripPoolTotals`, `getCertScripUnitVault`,
`getScripPoolAmountById`, `getScripPoolSharesById`).

## Scrip compliance administration

The CyberScrip compliance powers are exercised through the IssuanceManager:

```solidity
function setScripRestrictionHooks(address certAddress, ITransferRestrictionHook[] hooks) external; // onlyAdmin
function setScripFrozen(address certAddress, address account, bool isFrozen) external;             // onlyAdmin
function forceScripTransfer(address certAddress, address from, address to, uint256 amount) external; // onlyAdmin
function forceScripBurn(address certAddress, address account, uint256 amount) external;            // onlyAdmin
function disableScripForceTransfer(address certAddress) external;  // onlyOwner, one-way
function disableScripForceBurn(address certAddress) external;      // onlyOwner, one-way
function disableScripFreeze(address certAddress) external;         // onlyOwner, one-way
```

## Beacons / config

`CORP()`, `uriBuilder()` / `setUriBuilder`, `companyName()`,
`companyJurisdiction()`, `AUTH()`, `DEPLOY_VERSION()`, `printers(index)`,
`isPrinter(address)`, `cyberCertPrinterBeacon()`, `cyberScripBeacon()`,
`getCertPrinterBeaconImplementation()`, `getScripBeaconImplementation()`,
`getUpgradeFactory()`, `upgradeCertPrinterBeaconImplementation`,
`upgradeScripBeaconImplementation`. Beacon upgrades are `onlyOwner` and only
accept the factory's current reference implementation
(`NotRefImplementation` otherwise).

## Events

`CertPrinterCreated`, `CertificateCreated`, `CyberScripDeployed`,
`SecurityClassDefined`, `SecurityClassUpdated`, `PrinterClassAssigned`,
`SecondaryTransferExecuted`, `ScripifiedCert`, `ScripRecertified`,
`ScripAddedToExistingCert`, `ScripToCertMinimumSet`,
`ScripifyWhitelistEnabledSet`, `ScripifyWhitelistUpdated`,
`RecertificationApprovalSet`, `RecertificationApprovalCleared`,
`CertPrinterBeaconImplementationUpgraded`,
`ScripBeaconImplementationUpgraded`.

> `CertificateCreated(uint256 indexed tokenId, address indexed certificate,
> uint256 amount, uint256 cap, CertificateDetails details)` no longer carries
> the token URI — indexers read `tokenURI(tokenId)` from the printer instead.

> Access control: state-changing functions are gated through BorgAuth —
> `onlyOwner` (role 99+) for issuance/config, `onlyAdmin` (role 98+) for
> scrip compliance and recertification approvals, `onlyOwnerOrSelf` (the
> contract itself or owner-role callers) for the `createCert*AndAssign`
> variants. Deal and round managers hold owner-level roles, which is how
> their flows mint certificates. Consult the source for the exact role
> required by each function.
