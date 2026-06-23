# IssuanceManager

The issuance authority for a cyberCORP. It creates CyberCertPrinters, issues
and manages cyberCERTs, deploys CyberScrip, and runs scripification.

* **Source:** [`src/IssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/IssuanceManager.sol)
  / interface [`IIssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IIssuanceManager.sol)
* **Pattern:** UUPS proxy; owns the `cyberCertPrinterBeacon` and
  `cyberScripBeacon` `UpgradeableBeacon`s.

One IssuanceManager exists per cyberCORP. It creates **one CyberCertPrinter
per security class** (`createCertPrinter`), and **one CyberScrip per printer**
(`deployCyberScrip`).

## Certificate lifecycle

```solidity
function createCertPrinter(string[] _ledger, string _name, string _ticker,
    string _certificateUri, SecurityClass _securityType,
    SecuritySeries _securitySeries, address _extension) external returns (address);

function createCert(address certAddress, address to, CertificateDetails _details)
    external returns (uint256);
function createCertAndAssign(address certAddress, address investor,
    CertificateDetails _details) external returns (uint256 tokenId);
function createCertAndAssignWithName(address certAddress, address investor,
    CertificateDetails _details, string investorName, bytes endorsementSignature,
    uint256 timestamp) external returns (uint256 tokenId);
function createCertSignAndAssign(address certAddress, address investor,
    CertificateDetails _details, bytes endorsementSignature, address registry,
    bytes32 agreementId, string investorName) external returns (uint256 tokenId);
function assignCert(address certAddress, address from, uint256 tokenId,
    address investor, CertificateDetails _details) external;

function signCertificate(address certAddress, uint256 tokenId, bytes signature) external;
function addOfficerSignature(address certAddress, uint256 tokenId, bytes signature) external;
function endorseCertificate(address certAddress, uint256 tokenId, address endorser,
    bytes signature, bytes32 agreementId) external;
function voidCertificate(address certAddress, uint256 tokenId) external;
function unvoidCertificate(address certAddress, uint256 tokenId) external;
```

> There is no single `issueCert` function. Issuance is `createCert*` — the
> variant depends on whether you assign a holder, a name, and a signature/
> endorsement at mint time.

## Scripification

```solidity
function deployCyberScrip(address certAddress,
    ITransferRestrictionHook[] typeRestrictionHooks,
    ICondition[] certToScripConditions, ICondition[] scripToCertConditions,
    uint256 scripToCertMinimum, uint256 scripRatioNumerator,
    uint256 scripRatioDenominator, uint256[] scripifyWhitelistIds,
    bool scripifyWhitelistEnabled, bool enableForceTransfer,
    bool enableForceBurn, bool enableFreeze) external returns (address);

function scripifyCert(address certAddress, uint256 id, uint256 amount, address recipient) external;
function convertScripToCert(address certAddress, uint256 amount) external;
function setScripRatio(address certAddress, uint256 numerator, uint256 denominator) external;
function setScripToCertMinimum(address certAddress, uint256 minimum) external;

function setRecertificationApproval(address certAddress, address investor,
    string investorName, CertificateDetails details, bytes officerSignature) external;
function clearRecertificationApproval(address certAddress, address investor) external;
```

Plus scripify-whitelist management (`setScripifyWhitelistEnabled`,
`addScripifyWhitelistIds`, `removeScripifyWhitelistIds`,
`isScripifyWhitelisted`) and views (`getScripRatio`, `getScripToCertMinimum`,
`getRecertificationApproval`, `getCertScripifiedStatus`,
`getScripPoolAmountById`, `getScripPoolSharesById`).

## Hooks, legends, transferability

`setRestrictionHook`, `setGlobalRestrictionHook`, `setGlobalTransferable`,
`setTokenTransferable`, `addDefaultLegend`, `removeDefaultLegendAt`,
`addCertLegend`, `removeCertLegendAt`.

## Beacons / config

`CORP()`, `uriBuilder()` / `setUriBuilder`, `companyName()`,
`companyJurisdiction()`, `AUTH()`, `DEPLOY_VERSION()`, `printers(index)`,
`cyberCertPrinterBeacon()`, `cyberScripBeacon()`, `getUpgradeFactory()`,
`upgradeCertPrinterBeaconImplementation`, `upgradeScripBeaconImplementation`.

## Events

`CertPrinterCreated`, `CertificateCreated`, `ScripifiedCert`,
`ScripRecertified`, `ScripAddedToExistingCert`, `ScripToCertMinimumSet`,
`CompanyDetailsUpdated`, `CertPrinterBeaconImplementationUpgraded`,
`ScripBeaconImplementationUpgraded`.

> Access control: state-changing functions are gated through BorgAuth (the
> cyberCORP's officers/authorised roles). Consult the source for the exact
> role required by each function.
