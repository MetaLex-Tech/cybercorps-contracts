---
description: "The issuance authority: LET contracts, LETs, scrip, security classes and secondary transfers"
---

# IssuanceManager

The issuance authority for a cyberCORP. It creates LET contracts, issues
and manages Ledger Entry Tokens (LETs), registers security classes,
deploys CyberScrip, runs scripification, and settles the ownership change
of secondary trades.

* **Source:** [`src/IssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/IssuanceManager.sol)
  / interface [`IIssuanceManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IIssuanceManager.sol)
* **Pattern:** UUPS proxy that owns the `cyberCertPrinterBeacon` and
  `cyberScripBeacon` `UpgradeableBeacon`s. Most logic sits in the
  [`IssuanceManagerStorage`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/IssuanceManagerStorage.sol)
  library to stay under the EIP-170 size limit.
* **`DEPLOY_VERSION`:** `"5"`; a company that has not upgraded reports
  `"4.1"` or `"3"`.

Each cyberCORP has one IssuanceManager. It creates **one LET contract per
security series** (`createCertPrinter`) and **at most one CyberScrip per
LET contract** (`deployCyberScrip`).

## LET lifecycle

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

The IssuanceManager has no `issueCert` function. All four `createCert*`
functions mint a LET and register a holder of record; they differ in what
else they write:

| Function | Writes |
|---|---|
| `createCert` | The bare mint. `to` becomes the holder of record, with a blank name, no endorsement and no signature. The deal and round managers use it to mint into escrow with `to` set to themselves. |
| `createCertAndAssign` | Adds an issuance endorsement naming the investor, stamped with the current block time. No name on the register. |
| `createCertAndAssignWithName` | Adds the holder's legal name and lets the caller set the endorsement date, so a reissue keeps the original date. The endorsement points at no agreement. |
| `createCertSignAndAssign` | Binds the endorsement to a `registry` and `agreementId`. Always stamped with the current block time. |

The three `*AndAssign` variants add a non-empty `endorsementSignature` as
an issuer signature, and also attach the cyberCORP's first escrowed officer
signature when one is stored.

`assignCert` mints nothing. It re-registers an existing LET to a new holder
of record: `from` must be the current holder of record (not the wallet in
possession), `investorName` is written to the register, and the call writes
no endorsement and moves no payment. Use it to correct the register; trades
settle through the DealManager. It passes through the LET contract's
register gate (see
[LedgerEntryToken](LedgerEntryToken.md#delivery-and-registration-gates)).

`createCertPrinter` also files the new LET contract under its
`SecurityClass` (see [Security-class registry](#security-class-registry)).

Signing, endorsement, voiding, legends, hooks and transferability live on
the [LedgerEntryToken](LedgerEntryToken.md) contract itself, gated
`onlyIssuanceManagerOrAdmin`, so BorgAuth admins call the LET contract
directly.

```solidity
function voidEmptyCerts(address certAddress, uint256[] tokenIds) external; // onlyAdmin
```

`voidEmptyCerts` voids LETs that hold no units and no scrip-vault claim, so
the LET contract's holder tally stops counting them. It skips LETs that are
already void and reverts `CertNotEmpty` on a LET that still holds units or
a claim. It is admin-only because another party can drive a LET's vault
claim to zero while its holder still holds redeemable scrip.

## Security-class registry

Class-level designations (`SecurityClassInfo` in `CyberCorpConstants.sol`)
are registered on the IssuanceManager. Each LET contract (the series scope)
belongs to at most one class, and several LET contracts can share a class.

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

Class ids are sequential from 1 (`0` = unclassified). Each `SecurityClass`
value has one class: defining a second class of the same type reverts
`SecurityClassAlreadyDefined`. `createCertPrinter` assigns the new LET
contract to its type's class, creating an empty one (no document URI, no
data) when none exists, and `updateSecurityClass` fills it in later.
`setPrinterClass(printer, 0)` clears an assignment, and `setPrinterClass`
also gives a class to a LET contract that has none, such as one carried
over from an IssuanceManager without the registry.

The class's `classData` is the class scope of a LET:
[`ShareExtensionV3`](../extensions.md#shareextension--shareextensionv3)
reads it as the least specific layer of every LET in a share class.

## Secondary transfers

```solidity
function secondaryTransfer(bytes dealMetadata) external;         // onlyOwner
```

Settles the ownership change of a secondary trade. Gated on `OWNER_ROLE`,
which the SPV's [DealManager](DealManager.md) holds; `dealMetadata` is the
ABI-encoded tuple that `DealManager.finalizeSecondaryTradeAgreement`
produces. The seller's LET never moves wallets. The trade mutates the
seller's LET and mints a new one for the buyer:

1. The seller's endorsement (signed in blank by the seller, now naming the
   buyer) is written onto the seller's LET.
2. The sold units are deducted from the seller's LET.
3. The buyer gets a new LET through
   `LedgerEntryToken.safeMintFromAndAssign`, which names the seller's LET
   as the source. The LET contract treats that as a change of holder from
   the seller, so its stop-transfer flag, its registration hooks and its
   void check all apply. Under administered hosting the token goes to the
   admin multisig while the buyer is registered as holder of record.
4. The seller's LET is voided only if it holds no units **and** no
   scrip-vault claim. Otherwise it stays live, and `voidEmptyCerts` can
   sweep it later.
5. The same endorsement is copied onto the buyer's LET, and
   `SecondaryTransferExecuted` is emitted.

A new LET contract's register is closed by default. An admin must open it
(`LedgerEntryToken.setGlobalLegalTransferable(true)` or the per-LET switch)
before secondary trades on that LET contract can settle.

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

The LET's holder of record calls `scripifyCert`, which converts only units
not reserved for a pending deal. When the scrip's freeze power is enabled,
a frozen account can neither scripify nor convert scrip back
(`AccountFrozen`). Conversion burns scrip outside CyberScrip's own freeze
check, so the IssuanceManager makes that check itself.

`convertScripToCert` runs the LET contract's scrip-to-LET conditions. A
converter who is not the holder of record of a live LET in that LET
contract also needs a recertification approval from an admin
(`setRecertificationApproval`, carrying an officer signature); without one
the call reverts `RecertificationApprovalRequired`.

Scripified units sit in a vault per LET contract. Converting scrip back
first draws on the backing attributed to the converter's own non-void LETs
(in the order they are registered to the converter); any excess, and every
force burn, reduces all remaining LETs' claims in proportion. Moving scrip
between wallets does not move that attribution.

Scripify-whitelist management: `setScripifyWhitelistEnabled`,
`addScripifyWhitelistIds`, `removeScripifyWhitelistIds`,
`isScripifyWhitelisted`, `getScripifyWhitelistEnabled`. Views:
`getScripRatio`, `getScripToCertMinimum`, `getRecertificationApproval`,
`getCertScripifiedStatus`, `getScripPoolTotals`, `getCertScripUnitVault`,
`getScripPoolAmountById`, `getScripPoolSharesById`. `getScripPoolTotals`
returns the scrip `totalSupply` and the vault price per nominal share in
ray, which is `1e27` for any initialized, non-empty pool. Per-LET claims
are floored, so their sum can fall short of the pool total by rounding
dust.

## Scrip compliance administration

A BorgAuth admin calls most CyberScrip compliance controls on the scrip
itself (see [CyberScrip](CyberScrip.md)). Force burn goes through the
IssuanceManager, because it also withdraws the matching backing from the
vault:

```solidity
function forceScripBurn(address certAddress, address account, uint256 amount) external; // onlyAdmin
```

## Beacons and configuration

`CORP()`, `uriBuilder()` / `setUriBuilder`, `companyName()`,
`companyJurisdiction()`, `AUTH()`, `DEPLOY_VERSION()`, `printers(index)`,
`isPrinter(address)`, `cyberCertPrinterBeacon()`, `cyberScripBeacon()`,
`getCertPrinterBeaconImplementation()`, `getScripBeaconImplementation()`,
`getUpgradeFactory()`, `upgradeCertPrinterBeaconImplementation`,
`upgradeScripBeaconImplementation`. Beacon upgrades are `onlyOwner` and
accept only the factory's current reference implementation
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

`CertificateCreated(uint256 indexed tokenId, address indexed certificate,
uint256 amount, uint256 cap, CertificateDetails details)` does not carry
the token URI; indexers read `tokenURI(tokenId)` from the LET contract.

## Access

State-changing functions are gated through BorgAuth:

* `onlyOwner` (role 99 and above): issuance and configuration.
* `onlyAdmin` (role 98 and above): `forceScripBurn`, `voidEmptyCerts` and
  recertification approvals.
* `onlyOwnerOrSelf` (the contract itself or owner-role callers): the
  `createCert*AndAssign` variants.

The deal and round managers hold owner-level roles, which is how their
flows mint LETs. The source has the exact role each function requires.
