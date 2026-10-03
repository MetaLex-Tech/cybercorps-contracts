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
* **`DEPLOY_VERSION`:** `"5"` in the current source; companies that have not
  upgraded report `"4.1"` or `"3"`.

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
    address investor, CertificateDetails _details,
    string investorName) external;                               // onlyOwner
```

There is no single `issueCert` function. All four `createCert*` functions
mint a lot and register a holder of record; they differ in what else they
write:

| Function | Writes |
|---|---|
| `createCert` | The bare mint. `to` becomes the holder of record, with a blank name, no endorsement and no signature. The deal and round managers use it to mint into escrow with `to` set to themselves. |
| `createCertAndAssign` | Adds an issuance endorsement naming the investor, stamped now. No name on the register. |
| `createCertAndAssignWithName` | Adds the holder's legal name and lets the caller set the endorsement date, so a reissue keeps the original one. The endorsement points at no agreement. |
| `createCertSignAndAssign` | Binds the endorsement to a `registry` and `agreementId`. Always stamped now. |

The three `*AndAssign` variants add a non-empty `endorsementSignature` as an
issuer signature, and also attach the cyberCORP's first escrowed officer
signature when one is stored.

`assignCert` is not an issuance call: it mints nothing and re-registers an
existing lot to a new holder of record. `from` must be the current holder of
record (not the wallet in possession), `investorName` is written to the
register, and the call writes no endorsement and moves no payment. Use it to
correct the register, not to settle a trade; the DealManager settles trades.
It passes through the printer's register gate (see
[LedgerEntryToken](LedgerEntryToken.md#delivery-and-registration-gates)).

`createCertPrinter` also files the new printer under its `SecurityClass`
(see below).

Certificate signing, endorsement, voiding, legends, hooks, and
transferability are not routed through the IssuanceManager: those
functions live on the [LedgerEntryToken](LedgerEntryToken.md) itself, gated
`onlyIssuanceManagerOrAdmin` so BorgAuth admins call the printer directly.

```solidity
function voidEmptyCerts(address certAddress, uint256[] tokenIds) external; // onlyAdmin
```

`voidEmptyCerts` voids lots that hold no units and no scrip-vault claim, so
the printer's holder tally stops counting them. It skips lots that are
already void and reverts `CertNotEmpty` on a lot that still holds units or a
claim. It is admin-only because another party can drive a lot's vault claim
to zero while its holder still holds redeemable scrip.

## Security-class registry

Class-level LET designations (see `SecurityClassInfo` in
`CyberCorpConstants.sol`) are registered on the IssuanceManager. Each printer
(the series scope) belongs to at most one class, and several printers can
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

Class IDs are sequential starting at 1 (`0` = unclassified). There is one
class per `SecurityClass` value: defining a second class of the same type
reverts `SecurityClassAlreadyDefined`. `createCertPrinter` assigns the new
printer to its type's class, creating an empty one (no document URI, no
data) when none exists yet; `updateSecurityClass` fills it in later.
`setPrinterClass(printer, 0)` clears an assignment, and `setPrinterClass` is
also how printers created before the registry existed get a class.

The class's `classData` is the class scope of a certificate:
[`ShareExtensionV3`](../extensions.md#shareextension--shareextensionv3) reads
it as the least specific layer of every share certificate in the class.

## Secondary transfers

```solidity
function secondaryTransfer(bytes dealMetadata) external;         // onlyOwner
```

Effectuates the ownership change of a settled secondary trade. Gated on
`OWNER_ROLE`, which the SPV's [DealManager](DealManager.md) holds;
`dealMetadata` is the abi-encoded tuple produced by
`DealManager.finalizeSecondaryTradeAgreement`. The seller's Ledger Entry
Token never moves wallets; the trade works by mutate-and-mint:

1. The seller's endorsement (signed in blank, with the buyer now filled in)
   is written onto the seller's lot.
2. The sold units are deducted from the seller's lot.
3. The buyer gets a new lot through `LedgerEntryToken.safeMintFromAndAssign`,
   which names the seller's lot as the source. The printer treats that as a
   change of holder from the seller, so its stop-transfer flag, its
   registration hooks and its void check all apply. Under administered
   hosting the token goes to the admin multisig while the buyer is
   registered as holder of record.
4. The seller's lot is voided only if it holds no units **and** no
   scrip-vault claim; otherwise it stays live and can be swept later with
   `voidEmptyCerts`.
5. The same endorsement is copied onto the buyer's lot, and
   `SecondaryTransferExecuted` is emitted.

Because a new printer's register is closed by default, an admin must open it
(`LedgerEntryToken.setGlobalLegalTransferable(true)` or the per-lot switch)
before secondary trades on that printer can settle.

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

`scripifyCert` is called by the lot's holder of record and only converts
units not reserved for a pending deal. When the scrip has its freeze power
enabled, a frozen account can neither scripify nor convert scrip back
(`AccountFrozen`); conversion burns scrip outside CyberScrip's own freeze
check, so the IssuanceManager makes that check itself.

Scripified units sit in a per-printer vault. Converting scrip back first
draws on the backing attributed to the converter's own non-void lots (in
the order they are registered to the converter); any excess, and every force
burn, reduces all remaining lots' claims in proportion. Moving scrip between
wallets does not move that attribution.

Plus scripify-whitelist management (`setScripifyWhitelistEnabled`,
`addScripifyWhitelistIds`, `removeScripifyWhitelistIds`,
`isScripifyWhitelisted`, `getScripifyWhitelistEnabled`) and views
(`getScripRatio`, `getScripToCertMinimum`, `getRecertificationApproval`,
`getCertScripifiedStatus`, `getScripPoolTotals`, `getCertScripUnitVault`,
`getScripPoolAmountById`, `getScripPoolSharesById`). `getScripPoolTotals`
returns the scrip `totalSupply` and the vault price per nominal share in ray,
which is `1e27` for any initialized, non-empty pool. Per-lot claims are
floored, so their sum can fall short of the pool total by rounding dust.

## Scrip compliance administration

Most CyberScrip compliance controls are called on the scrip itself by a
BorgAuth admin (see [CyberScrip](CyberScrip.md)). Force burn is the
exception, because it also withdraws the matching backing from the vault:

```solidity
function forceScripBurn(address certAddress, address account, uint256 amount) external; // onlyAdmin
```

## Beacons / config

`CORP()`, `uriBuilder()` / `setUriBuilder`, `companyName()`,
`companyJurisdiction()`, `AUTH()`, `DEPLOY_VERSION()`, `printers(index)`,
`isPrinter(address)`, `cyberCertPrinterBeacon()`, `cyberScripBeacon()`,
`getCertPrinterBeaconImplementation()`, `getScripBeaconImplementation()`,
`getUpgradeFactory()`, `upgradeCertPrinterBeaconImplementation`,
`upgradeScripBeaconImplementation`. Beacon upgrades are `onlyOwner` and only
accept the factory's current reference implementation
(`NotRefImplementation` otherwise). `setUriBuilder` emits
`UriBuilderUpdated(new, old)`.

## Events

`CertPrinterCreated`, `CertificateCreated`, `CyberScripDeployed`,
`SecurityClassDefined`, `SecurityClassUpdated`, `PrinterClassAssigned`,
`SecondaryTransferExecuted`, `ScripifiedCert`, `ScripRecertified`,
`ScripAddedToExistingCert`, `ScripToCertMinimumSet`,
`ScripifyWhitelistEnabledSet`, `ScripifyWhitelistUpdated`,
`RecertificationApprovalSet`, `RecertificationApprovalCleared`,
`CertPrinterBeaconImplementationUpgraded`,
`ScripBeaconImplementationUpgraded`, `UriBuilderUpdated`.

> `CertificateCreated(uint256 indexed tokenId, address indexed certificate,
> uint256 amount, uint256 cap, CertificateDetails details)` does not carry
> the token URI; indexers read `tokenURI(tokenId)` from the printer instead.

> Access control: state-changing functions are gated through BorgAuth —
> `onlyOwner` (role 99+) for issuance/config, `onlyAdmin` (role 98+) for
> `forceScripBurn`, `voidEmptyCerts` and recertification approvals,
> `onlyOwnerOrSelf` (the contract itself or owner-role callers) for the
> `createCert*AndAssign` variants. Deal and round managers hold owner-level
> roles, which is how their flows mint certificates. Consult the source for
> the exact role required by each function.
