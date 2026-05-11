# IssuanceManager

The **IssuanceManager** is the issuance authority for a cyberCORP. It is the
only contract permitted to mutate the register of holders.

* **Source:** [`src/IssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/IssuanceManager.sol)
* **Proxy pattern:** UUPS (v3)
* **Owns:** `CyberCertPrinter` beacon, `CyberScrip` beacon

## Responsibilities

* Issue cyberCERTs (`issueCert`) of any registered extension type.
* Revoke / burn cyberCERTs (`revokeCert`).
* Endorse cyberCERTs (`endorseCert`).
* Scripify a cert (full or partial) into cyberSCRIP (`scripifyCert`).
* De-scripify cyberSCRIP back to a cert (`convertScripToCert`).
* Manage per-class conditions for scripify / de-scripify.
* Manage the scripify whitelist per cert.
* Manage registration approvals for new holders presenting scrip.
* Deploy `CyberScrip` instances per share class on demand.

## Selected public interface

```solidity
function issueCert(CertIssuance calldata) external returns (uint256);  // ISSUER_AUTHORITY
function revokeCert(uint256 tokenId) external;                          // ISSUER_AUTHORITY
function endorseCert(uint256 tokenId, Endorsement calldata) external;   // SECRETARY_AUTHORITY

function scripifyCert(uint256 tokenId, uint256 units, address to) external;
function convertScripToCert(address scrip, uint256 amount) external returns (uint256 newTokenId);
function requestRecertification(address scrip, uint256 amount) external;
function approveRegistration(address holder, RegistrationData calldata) external; // OFFICER_AUTHORITY

function setScripifyCondition(bytes32 shareClass, ICondition) external;
function setDescripifyCondition(bytes32 shareClass, ICondition) external;

function setAuthorizedShares(bytes32 shareClass, uint256 authorized) external; // DIRECTOR_AUTHORITY

function upgradeCertPrinterBeaconImplementation(address impl) external; // UPGRADE_AUTHORITY
function upgradeScripBeaconImplementation(address impl) external;       // UPGRADE_AUTHORITY
```

## Scripification model

* **Partial scripification** is supported. The source cert remains active with
  a reduced unit count.
* **Configurable scrip ratio** (`numerator / denominator`) governs cert units
  ↔ scrip ERC-20 unit conversion.
* **Scripified Share Pool** is an ERC-4626-style vault tracking each
  registered holder's scripified units. De-scripification withdraws
  proportionally.
* **Two recertification paths:**
  * existing registered holders → direct merge onto their existing cert;
  * new holders → require `approveRegistration` first (the
    `IssuerApprovalRecertificationCondition` enforces this).

## Events

* `CertIssued(uint256 indexed tokenId, address indexed to, uint256 units, bytes32 shareClass)`
* `CertRevoked(uint256 indexed tokenId)`
* `CertScripified(uint256 indexed tokenId, uint256 units, address scrip, address to)`
* `ScripConvertedToCert(address indexed scrip, uint256 amount, uint256 indexed newTokenId, address indexed to)`
* `RegistrationApproved(address indexed holder, bytes32 dataHash)`

## See also

* [`CyberCertPrinter`](CyberCertPrinter.md), [`CyberScrip`](CyberScrip.md)
* [Conditions](../conditions.md)
