# v5 Upgrade Plan

## TODO

- [x] Bump `DEPLOY_VERSION` on each changed contract.
- [x] Check the tier 2 and tier 3 upgrades. Make sure that no legacy behavior breaks if a corp keeps the old version.
- [x] Evaluate the effect of the `RoundManagerStorage.CyberCertData` field change.
- [x] Review all public ABI changes that may impact front-ends and indexers

## Corp contracts

Each corp owns these. They carry a `DEPLOY_VERSION`. The corp owner upgrades them, all at once.
Every corp contract changed. There is no unchanged row.

Production baselines: `a7584108` for the core stack, `c05b6763` for IssuanceManager.
Each row is verified by a bytecode comparison against Base mainnet.

| Contract         | Version on chain | Version in tree | Size delta | New size | EIP-170 margin | Action  |
|------------------|------------------|-----------------|------------|----------|----------------|---------|
| IssuanceManager  | 4.1              | 5               | -4,960 B   | 17,278 B | 7,298 B        | Upgrade |
| DealManager      | 4                | 5               | -2,089 B   | 21,947 B | 2,629 B        | Upgrade |
| RoundManager     | 4                | 5               | -1,296 B   | 20,681 B | 3,895 B        | Upgrade |
| CyberCorp        | 4                | 5               | +3,158 B   | 16,237 B | 8,339 B        | Upgrade |
| CyberScrip       | 4                | 5               | +1,856 B   | 11,343 B | 13,233 B       | Upgrade |
| LedgerEntryToken | 4                | 5               | -84 B      | 24,414 B | 162 B          | Upgrade |

## MetaLeX singletons

MetaLeX owns these. They have no `DEPLOY_VERSION`, but they are all UUPS proxies.
MetaLeX upgrades them directly.

There are two parallel stacks. The Pump stack has its own IssuanceManagerFactory, RoundManagerFactory,
CertificateUriBuilder, LeXcheX, LeXcheXMinter and LeXcheX BorgAuth. It shares the CyberAgreementRegistry,
the CyberCorpSingleFactory and the DealManagerFactory with the core stack.

A proxy that holds the same implementation on Base and on Ethereum shows one row. Where the two chains
hold different implementations, each chain gets its own row.

11 of the 20 proxies need an upgrade.

| Contract                  | Stack | Chain     | Proxy         | Size delta | Action  |
|---------------------------|-------|-----------|---------------|------------|---------|
| CyberCorpFactory          | core  | Base, ETH | `0x5141…6cB2` | +190 B     | Upgrade |
| CyberCorpSingleFactory    | core  | Base, ETH | `0xBE0D…A5C4` | none       | None    |
| IssuanceManagerFactory    | core  | Base, ETH | `0xD353…155A` | none       | None    |
| IssuanceManagerFactory    | pump  | Base      | `0x5eAB…65C3` | none       | None    |
| DealManagerFactory        | both  | Base, ETH | `0x3982…C251` | +654 B     | Upgrade |
| RoundManagerFactory       | core  | Base      | `0xc9d5…aeb9` | none       | None    |
| RoundManagerFactory       | core  | ETH       | `0xc9d5…aeb9` | +692 B     | Upgrade |
| RoundManagerFactory       | pump  | Base      | `0x0608…3432` | none       | None    |
| CyberAgreementRegistry    | both  | Base, ETH | `0xa9E8…c134` | +30 B      | Upgrade |
| LegalDocRegistry          | docs  | Base, ETH | `0x45e5…8738` | -263 B     | Upgrade |
| CertificateUriBuilder     | core  | Base, ETH | `0x5500…70A3` | +4,219 B   | Upgrade |
| CertificateUriBuilder     | pump  | Base      | `0x476C…05b8` | +4,219 B   | Upgrade |
| PumpCorpFactory           | pump  | Base      | `0xd426…487f` | +443 B     | Upgrade |
| ParentCoFactory           | umia  | Base      | `0x5051…1df1` | +578 B     | Upgrade |
| ParentCoFactory           | umia  | ETH       | `0x5c6D…D47F` | none       | None    |
| LeXcheX                   | core  | Base, ETH | `0xc8db…0b62` | none       | None    |
| LeXcheX                   | pump  | Base      | `0x19d8…b7fd` | none       | None    |
| LeXcheXMinter             | core  | Base, ETH | `0x0dD1…F960` | +710 B     | Upgrade |
| LeXcheXMinter             | pump  | Base      | `0x58a3…1630` | -3 B       | Upgrade |
| NonUSNationalityCondition | core  | Base, ETH | `0xe71f…932A` | none       | None    |

LegalDocRegistry is a second CyberAgreementRegistry deployment. It is used for arbitrary legal
document signing.

BorgAuth instances are plain contracts, not proxies, and `src/libs/auth.sol` did not change.
The CertificateImageBuilder contracts did not change. Neither group is in the table.

### Production is not one version

Four contract families already run different code at different addresses:

- CyberAgreementRegistry: the core proxy holds 22,893 B. The LegalDocRegistry proxy holds 23,186 B.
- LeXcheXMinter: the core proxy holds 10,720 B. The Pump proxy holds 11,433 B.
- RoundManagerFactory: the Base proxy already matches HEAD. The Ethereum proxy is 692 B behind.
- ParentCoFactory: the Ethereum proxy already matches HEAD. The Base proxy is 578 B behind. It misses
  commit `c1692373`.

The two chains drift in opposite directions. Upgrade both for parity, even without v5.

## Version mismatch between MetaLeX singletons and corps

Each corp is expected to upgrade all of its own contracts and beacons together. The corp owner co-approves.
So there is no version mismatch inside a corp.
MetaLeX upgrades the singletons and the factories for all corps at the same time. Each corp owner
decides when, or if, to follow. The mismatch is therefore between new singletons and an old corp.

The evidence shows that the all-at-once rule for a corp is necessary, not only convenient:

- The new IssuanceManager removes 13 functions. The production DealManager calls `voidCertificate`.
- The new managers call 6 printer functions that a v4 printer does not have.

### What an old corp calls outward

| Singleton              | Used by                                  | Status                                    |
|------------------------|------------------------------------------|-------------------------------------------|
| CyberAgreementRegistry | DealManager (19 sites), RoundManager (8) | Same signatures. 3 behavior changes.      |
| DealManagerFactory     | DealManager fee and upgrade paths (3)    | Additive only. Safe.                      |
| RoundManagerFactory    | RoundManager fee and upgrade paths (3)   | Unchanged. Safe.                          |
| CertificateUriBuilder  | LedgerEntryToken `tokenURI`              | Adds overloads, keeps the old ones. Safe. |
| LeXcheX                | RoundManager (5)                         | Unchanged. Safe.                          |
| LeXcheXMinter          | RoundManager (1)                         | External surface unchanged. Safe.         |

Only CyberAgreementRegistry needs attention.

### CyberAgreementRegistry changes reach every corp at once

No call reverts. The signatures do not change. The registry makes no call into a corp contract, so
there is no callback risk. Three behavior changes apply:

- `contractId` now includes `secretHash` and `finalizer`. On-chain corps are safe. They use the value
  that `createContract` returns and never derive the id. Off-chain code that derives the id must change.
- `isParty` no longer accepts a delegate. A delegate can no longer sign, escrow-sign, or request a
  void. `setDelegation` still exists and still emits, so the feature looks available.
- A zero `expiry` no longer voids an agreement. Unanimity now counts only the allocated party slots.

## Effect of the CyberCertData field change

`RoundManagerStorage.CyberCertData` adds `bytes seriesData` before `defaultLegend`.

### Storage is not affected

The struct is always in memory. No contract keeps it in storage.

### The ABI breaks

The struct is a parameter of external functions, so the selectors change.

| Function                                 | Old selector | New selector |
|------------------------------------------|--------------|--------------|
| `RoundManager.createRound`               | `0x570e99a3` | `0x67293f77` |
| `DealManager.proposeAndSignNewCertsDeal` | `0x1fb03ef1` | `0x5d02c45d` |

The production bytecode holds the old selectors only. So a client that uses the new ABI fails against
a corp that keeps the old version. This is the largest off-chain task in the release.
`CyberCorpFactory.deployCyberCorpAndCreateOffer` and `CyberCorpFactory.deployCyberCorpAndCreateRound`
also change their selectors.

MetaLeX contracts are not affected. CyberCorpFactory calls `createRound` only on a RoundManager that
it deployed in the same transaction, so both sides are always v5.

### The EIP-712 type hash breaks

`PumpCorpFactory.CERT_DATA_TYPEHASH` includes `bytes seriesData`. Old signatures do not verify.
Update the off-chain signer at the same time.

### Deployment order

CyberCorpFactory calls `RoundManager.createRound` with the new selector.
Set the new RoundManager reference implementation on RoundManagerFactory before you upgrade
CyberCorpFactory. If you do not, new corp creation fails.

### Local CyberCertData copies are not consistent

Three factories declare their own `CyberCertData`. All three still have 7 fields.

- PumpCorpFactory (line 159) is live and wrong. `deployCyberCorpAndCreateOffer` uses it and passes
  `bytes("")` to `createCertPrinter`. The same function in CyberCorpFactory passes
  `_certData[i].seriesData`. A corp made through the Pump offer path gets no series data.
  An admin can call `setSeriesData` later to correct this.
  The Pump round path is correct. It uses the imported 8-field type and the matching EIP-712 type hash.
- ParentCoFactory (line 110) and MetaDAOFactory (line 104) declare the struct and never use it.
  Neither calls `createRound`, `createCertPrinter` or `proposeAndSignNewCertsDeal`. An unused struct
  does not reach the ABI or the bytecode. These two copies are cosmetic.

## Front-end and indexer changes

This list compares each contract at HEAD with the code that runs in production now.
For the MetaLeX singletons the comparison reads the live implementation bytecode on Base and on Ethereum.
For the corp contracts it uses the verified production baselines.

### No log topic is lost

Every event that production emits today is still emitted after the upgrade. Every log change is an addition.
An indexer keeps all of its current streams. No backfill is necessary for lost data.

### 1. Add the new events

| Contract            | New events                                                                                                                                                                                                                                                                            |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| DealManager         | `OfferPosted`, `OfferAccepted`, `OfferCancelled`, `SecondaryTradeAgreementFinalized`, `SecondaryTradeAgreementVoided`, `SecondaryFeeDistributed`, `ClosingConditionsSet`, `MinTradeThresholdSet`, `PathwayThresholdConditionsSet`, `SettlementWindowSet`, `SpvThresholdConditionsSet` |
| LedgerEntryToken    | `LegalOwnerChanged`, `UnitsReservedUpdated`, `CertificateUnvoided`, `SeriesDataSet`, `LookThroughBadgeSet`, `AcquisitionTimestampSet`, `IssueTimestampSet`, `GlobalLegalTransferableSet`, `TokenLegalTransferableSet`                                                                 |
| IssuanceManager     | `SecondaryTransferExecuted`, `SecurityClassDefined`, `SecurityClassUpdated`, `PrinterClassAssigned`                                                                                                                                                                                   |
| CyberCorp           | `CyberCORPExtensionSet`, `CyberCORPExtensionDataUpdated`, `OfficerUpdated`                                                                                                                                                                                                            |
| CyberCorpFactory    | `AgreementDeployed`                                                                                                                                                                                                                                                                   |
| DealManagerFactory  | `IntegratorSet`                                                                                                                                                                                                                                                                       |
| RoundManagerFactory | `InstanceFeeOverrideSet`. Ethereum only. Base has it already.                                                                                                                                                                                                                         |
| ParentCoFactory     | `RoundManagerDeployed`. Base only. Ethereum has it already.                                                                                                                                                                                                                           |

RoundManager, CyberScrip and CyberAgreementRegistry add no event.

### 2. Events are migrated to interface ABI

Event declarations moved out of the contract and into its interface file. The compiled contract ABI
does not list them. This is an ABI migration, not a removal. The contract still emits the event,
and the emitting address does not change.

Build the front-end and the indexer from both artifacts.

| Contract         | Also load           | Events that only the second file declares                                                                                                                                        |
|------------------|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| LedgerEntryToken | `ILedgerEntryToken` | `CertificateAssigned`, `CertificateEndorsed`, `CyberCertPrinter_CertificateCreated`, `LegalOwnerChanged`, `UnitsReservedUpdated`, `AcquisitionTimestampSet`, `IssueTimestampSet` |
| IssuanceManager  | `IIssuanceManager`  | `SecondaryTransferExecuted`, `SecurityClassDefined`, `SecurityClassUpdated`, `PrinterClassAssigned`                                                                              |
| DealManager      | `LexScrowStorage`   | `DealPaidAt`, `DealFinalizedAt`, `DealVoidedAt`, `FeeDistributed`                                                                                                                |
| RoundManager     | `LexScrowStorage`   | `DealPaidAt`, `DealFinalizedAt`, `DealVoidedAt`, `FeeDistributed`                                                                                                                |

The first two rows point to an interface file. Both interface artifacts hold every event in the row.

The last two rows do not. `LexScrowStorage` is a linked library, not an interface, and no interface
declares its four events. `ILexScrowStorage.sol` exists but omits them. Read these four from the
library artifact until that is resolved. TODO: decide if the four events move to `ILexScrowStorage`.

Some rows also appear in the table above. Those events are new and interface-declared at the same time.
The four deal events are not new. An indexer built today can already miss them.

Custom errors moved the same way. A front-end that decodes a revert reason needs the second artifact too.

| Contract         | Also load           | Errors that only the second file declares                                                                                                                                                                            |
|------------------|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| LedgerEntryToken | `ILedgerEntryToken` | `ConversionNotImplemented`, `EndorsementNotSignedOrInvalid`, `TokenNotTransferable`, `TransferRestricted`, `URISetForNonexistentToken`                                                                               |
| DealManager      | `LexScrowStorage`   | `CounterPartyNotSet`, `DealAlreadyFinalized`, `DealExpired`, `DealNotFinalized`, `DealNotFullySigned`, `DealNotPaid`, `DealNotVoided`, `DealVoided`, `EscrowNotPaid`, `EscrowNotPending`, `SafeERC20FailedOperation` |
| RoundManager     | `LexScrowStorage`   | The same list, less `DealNotPaid` and `SafeERC20FailedOperation`.                                                                                                                                                    |

DealManager also drops `NotUpgradeFactory`. That one is a real removal, not a move.
DealManager cannot revert with it any more.

### 3. Change the function selectors

The `CyberCertData` struct gets a `bytes seriesData` field. Each function that takes the struct gets a new selector.
The other rows change for a different reason. The old selector is not in the new code. A call with the old ABI fails.

| Function                                           | Old          | New          |
|----------------------------------------------------|--------------|--------------|
| `RoundManager.createRound`                         | `0x570e99a3` | `0x67293f77` |
| `DealManager.proposeAndSignNewCertsDeal`           | `0x1fb03ef1` | `0x5d02c45d` |
| `CyberCorpFactory.deployCyberCorpAndCreateOffer`   | `0x67a2662e` | `0x7f3bd719` |
| `CyberCorpFactory.deployCyberCorpAndCreateRound`   | `0x000388fb` | `0x217d1150` |
| `PumpCorpFactory.deployCyberCorpAndCreateRoundFor` | `0x72609abb` | `0xdd12bf9c` |
| `IssuanceManager.createCertPrinter`                | `0x6cf6f4b0` | `0xfe197ea2` |
| `IssuanceManager.assignCert`                       | `0xcd395def` | `0xc6e22865` |
| `LedgerEntryToken.assignCert`                      | `0x927cfd2e` | `0x54e1f5da` |
| `LedgerEntryToken.initialize`                      | `0xecfdf70b` | `0x5d17007b` |

`createCertPrinter` gets the `seriesData` argument. The three `assignCert` and `initialize` rows get a name or a data
argument.

### 4. Move the printer calls off IssuanceManager

IssuanceManager loses 21 functions. 19 move to the printer or to the scrip contract. Two stay with a new signature.
Send these calls to the token address, not to the IssuanceManager address.

| Old call on IssuanceManager                         | New call                                                     |
|-----------------------------------------------------|--------------------------------------------------------------|
| `addCertLegend(printer,id,legend)`                  | `LedgerEntryToken.addCertLegend(id,legend)`                  |
| `addDefaultLegend(printer,legend)`                  | `LedgerEntryToken.addDefaultLegend(legend)`                  |
| `addOfficerSignature(printer,id,sig)`               | `LedgerEntryToken.addIssuerSignature(id,sig)`                |
| `signCertificate(printer,id,sig)`                   | `LedgerEntryToken.addIssuerSignature(id,sig)`                |
| `endorseCertificate(printer,id,to,sig,agreementId)` | `LedgerEntryToken.endorseCertificate(id,to,sig,agreementId)` |
| `removeCertLegendAt(printer,id,i)`                  | `LedgerEntryToken.removeCertLegendAt(id,i)`                  |
| `removeDefaultLegendAt(printer,i)`                  | `LedgerEntryToken.removeDefaultLegendAt(i)`                  |
| `setGlobalRestrictionHook(printer,hook)`            | `LedgerEntryToken.setGlobalRestrictionHook(hook)`            |
| `setRestrictionHook(printer,id,hook)`               | `LedgerEntryToken.setRestrictionHook(id,hook)`               |
| `setGlobalTransferable(printer,flag)`               | `LedgerEntryToken.setGlobalTransferable(flag)`               |
| `setTokenTransferable(printer,id,flag)`             | `LedgerEntryToken.setTokenTransferable(id,flag)`             |
| `voidCertificate(printer,id)`                       | `LedgerEntryToken.voidCert(id)`                              |
| `unvoidCertificate(printer,id)`                     | `LedgerEntryToken.unvoidCert(id)`                            |
| `setScripFrozen(scrip,account,flag)`                | `CyberScrip.setFrozen(account,flag)`                         |
| `forceScripTransfer(scrip,from,to,amount)`          | `CyberScrip.forceTransfer(from,to,amount)`                   |
| `setScripRestrictionHooks(scrip,hooks)`             | `CyberScrip.setRestrictionHook(hooks)`                       |
| `disableScripFreeze(scrip)`                         | `CyberScrip.disableFreeze()`                                 |
| `disableScripForceBurn(scrip)`                      | `CyberScrip.disableForceBurn()`                              |
| `disableScripForceTransfer(scrip)`                  | `CyberScrip.disableForceTransfer()`                          |

`signCertificate` and `addOfficerSignature` were two names for one action. Both become `addIssuerSignature`.
The caller must be an admin. The printer accepts an admin directly now.

### 5. Change two off-chain computations

- Agreement id. `contractId` now includes `secretHash` and `finalizer`. Off-chain code that derives the id must add
  the two fields. See the registry section above.
- Signature payload. `PumpCorpFactory.CERT_DATA_TYPEHASH` includes `bytes seriesData`. Update the signer.
  Signatures made with the old type hash do not verify.

### 6. Rename the printer artifact

`CyberCertPrinter` is now `LedgerEntryToken`. Its interface `ICyberCertPrinter` is now `ILedgerEntryToken`.
Section 2 needs that interface artifact. The address, the storage and the beacon do not change.
Only the artifact name and the ABI file name change.

### What does not change

- Every function that keeps its selector keeps its return type. `onERC721Received` and `onERC1155Received`
  become `pure`, which does not change the encoding.
- CyberAgreementRegistry keeps its whole ABI and all of its log topics, on both proxies and both chains.
  Only its behavior changes.
- CyberScrip, CyberCorpSingleFactory, IssuanceManagerFactory, LeXcheX, LeXcheXMinter and
  NonUSNationalityCondition have no ABI change.
- CertificateUriBuilder adds overloads and keeps the old ones.

### How to tell which ABI a corp uses

The front-end must handle both versions at once. A corp that keeps v4 answers the old selectors.
A corp that upgrades answers the new ones.

Call `DEPLOY_VERSION()` on the corp contract to choose the ABI. The proxy delegates the call, so the
answer describes the implementation that runs now. Each v4 reference implementation on Base answers it:

| Contract                                                           | v4 answer | v5 answer |
|--------------------------------------------------------------------|-----------|-----------|
| IssuanceManager                                                    | `"4.1"`   | `"5"`     |
| CyberCorp, DealManager, RoundManager, LedgerEntryToken, CyberScrip | `"4"`     | `"5"`     |
