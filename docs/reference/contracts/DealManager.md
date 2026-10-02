---
description: Deal lifecycle and the secondary-trading venue with settlement escrow
---

# DealManager

Manages the lifecycle of deals for a cyberCORP — primary issuance deals
built on the agreement registry, and a secondary-trading venue with its own
offer/settlement machinery. A deal is created from an agreement template and
is identified by a `bytes32 agreementId`.

* **Source:** [`src/DealManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/DealManager.sol)
  / interface [`IDealManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IDealManager.sol)
* **Pattern:** UUPS proxy. Heavy logic is delegated to the
  `DealManagerStorage`, `SecondaryTradeStorage`, and `LexScrowStorage`
  libraries. The deal and secondary-trade events and errors are declared
  in the `IDealManagerStorage` and `ISecondaryTradeStorage` interfaces so
  they appear in DealManager's ABI; `ILexScrowStorage` contributes the
  shared `AgreementConditionsNotMet` error and the escrow views, while the
  escrow events (`DealPaidAt` etc.) are declared in the `LexScrowStorage`
  library itself. All of them are emitted from the DealManager's address.
* **`DEPLOY_VERSION`:** `"5"` in the current source. DealManagers of
  companies that have not upgraded report `"4.0.1"` or earlier; read
  `DEPLOY_VERSION()` on the instance before choosing an ABI (see
  [Integrate from a frontend](../../how-to/integrate-from-frontend.md#abis-and-versions)).

## Primary deal lifecycle

```solidity
function proposeDeal(address[] _certPrinterAddress, address _paymentToken,
    uint256 _paymentAmount, bytes32 _templateId, uint256 _salt,
    string[] _globalValues, address[] _parties, CertificateDetails[] _certDetails,
    string[][] _partyValues, address[] conditions, bytes32 secretHash,
    uint256 expiry) external
    returns (bytes32 agreementId, uint256[] certIds);            // onlyOwner

function proposeAndSignDeal(/* ...as above, plus */ address proposer,
    bytes signature /* ... */) external
    returns (bytes32 agreementId, uint256[] certIds);            // onlyOwner

function proposeAndSignNewCertsDeal(uint256 salt, CyberCertData[] _certData,
    bytes32 _templateId, string[] _globalValues, address[] _parties,
    uint256 _paymentAmount, string[][] _partyValues, bytes signature,
    CertificateDetails[] _details, address[] conditions, bytes32 secretHash,
    uint256 expiry, address stableAddress) external
    returns (address[] certPrinterAddress, bytes32 id, uint256[] certIds); // onlyOwner

function signDealAndPay(address signer, bytes32 agreementId, bytes signature,
    string[] partyValues, bool _fillUnallocated, string name, string secret) external;
function signAndFinalizeDeal(address signer, bytes32 agreementId,
    string[] partyValues, bytes signature, bool _fillUnallocated,
    string name, string secret) external;
function finalizeDeal(bytes32 agreementId) external;

function voidExpiredDeal(bytes32 _agreementId, address signer, bytes signature) external;
function revokeDeal(bytes32 _agreementId, address signer, bytes signature) external;
function signToVoid(bytes32 _agreementId, address signer, bytes signature) external;
function refundVoidedDeal(bytes32 agreementId) external; // for deals voided directly in the registry

function addCondition(bytes32 agreementId, address condition) external;      // onlyOwner, pending deals only
function removeConditionAt(bytes32 agreementId, uint256 index) external;     // onlyOwner, pending deals only

function initialize(address _auth, address _corp, address _dealRegistry,
    address _issuanceManager, address _upgradeFactory) external;
```

`proposeAndSignNewCertsDeal` deploys new LedgerEntryToken printers (via
`IssuanceManager.createCertPrinter`, prefixing the company name) and
proposes + signs the deal in one transaction. `CyberCertData` carries
`{name, symbol, uri, securityClass, securitySeries, extension, seriesData,
defaultLegend}`; it is declared once in `src/CyberCorpConstants.sol` and
shared by the deal path, the round path and the corporate factories.
v4 DealManagers take the struct without `seriesData`, so the function
selector differs between the two versions.

`proposeDeal` creates the registry agreement with the DealManager as its
`finalizer`, so only the DealManager can finalize it and the registry
accepts a relayed signature only when the DealManager submits it. Parties
sign the registry's `SignatureData` with `signer` set to their own address
(see [CyberAgreementRegistry](CyberAgreementRegistry.md#data-model)).

## How primary deals work

* A deal references an agreement **template** (`_templateId`) and is recorded
  through the [CyberAgreementRegistry](CyberAgreementRegistry.md) —
  `_dealRegistry` in `initialize`.
* `_parties` countersign with EIP-712 signatures; `signDealAndPay` combines a
  party's signature with their payment.
* `conditions` are `ICondition` addresses that gate the deal; the owner can
  `addCondition` / `removeConditionAt` while the deal is still pending.
* `expiry` and `secretHash` support timed and secret-gated deals;
  `voidExpiredDeal` cleans up expired deals. `expiry == 0` means **no
  deadline**: such a deal can pay and finalize at any time and is never
  void-expirable (`voidExpiredDeal` reverts `DealNotExpired`), so it unwinds
  only by void request — see [Voiding a primary deal](#voiding-a-primary-deal).
* On `finalizeDeal` the deal's certificate effects (mint/assign/endorse) are
  applied via the IssuanceManager, and escrowed payment (less the primary
  platform fee — see `computeFee` / `getPlatformPayable`) is released.
* Escrow state lives in the shared `LexScrowStorage` library — see
  [LeXscroWLite](LeXscroWLite.md). `getEscrowDetails(agreementId)` and
  `conditionCheck(agreementId)` expose it.

### Voiding a primary deal

Every void ultimately runs through the registry's `voidContractFor`, which
voids the agreement once every **allocated** party has requested it, as soon
as the proposer (party index 0) requests while still the only signer, or —
for a nonzero expiry only — once that expiry has passed. The registry knows
nothing of the escrow, so the DealManager entry points add the teardown:
voiding the corp certificates minted into escrow at proposal and refunding
or closing the escrow.

* `signToVoid` forwards the request and, once the registry reports the
  agreement voided, voids the escrowed corp certificates and settles the
  escrow: a `PAID` escrow is refunded, a `PENDING` one is marked `VOIDED`.
  Until then it only records the request.
* `revokeDeal` is the same route for a deal that has not been paid. It
  reverts `DealNotPending` unless the escrow is `PENDING`, forwards the
  request, and, when that request voids the agreement (the sole-signer
  proposer, say), voids the escrowed corp certificates and marks the escrow
  `VOIDED`.
* Both require the caller to be the `signer` they name
  (`CounterPartyValueMismatch` otherwise).
* `voidExpiredDeal` applies only to a deal with a nonzero expiry that has
  passed. It forwards the request, voids the certificates, and refunds or
  closes the escrow.
* Requests may also go straight to the registry, bypassing the DealManager
  entirely. The escrow then lags the agreement until `refundVoidedDeal` syncs
  it, which voids the corp certificates and refunds — but only for a `PAID`
  escrow (`voidAndRefund` reverts `EscrowNotPaid` on a `PENDING` one, so an
  unpaid deal voided this way still needs `signToVoid` from a party that has
  not yet requested the void).

## Secondary trading

DealManager doubles as the SPV-side secondary-trading venue for Ledger Entry
Tokens: sell and buy offers, partial acceptances, settlement escrows, and a
layered compliance-condition scheme.

```solidity
function postOffer(PostOfferParams params) external returns (bytes32 offerId);
function acceptOffer(AcceptOfferParams params) external returns (bytes32 settlementAgreementId);
function cancelOffer(bytes32 offerId) external;
function finalizeSecondaryTradeAgreement(bytes32 agreementId) external;
function voidSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes signature) external;
function voidSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes signature, uint256 nonce, bytes authSig) external;
function voidExpiredSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes signature) external;
function syncVoidedSecondaryTradeAgreement(bytes32 agreementId) external;
```

`postOffer`, `acceptOffer`, and `cancelOffer` each have a relayer overload
taking `(…, address forAddr, uint256 nonce, bytes sig)` where `sig` is the
user's EIP-712 authorization — so a relayer can submit on a user's behalf.
`voidSecondaryTradeAgreement`'s relayed overload has a different shape (see
above): `(agreementId, signer, voidSignature, nonce, authSig)` — the
registry void signature and the relayer-authorization signature are
separate, with `signer` as the authorized party.

* **Offers.** `PostOfferParams` covers both sides (`OfferSide.SELL` /
  `BUY`): the printer and token id, units, payment token and consideration,
  validity window, an agreement template + party values + the offeror's
  signature, an open endorsement signature (sell side), and the buyer's
  hosting mode. Offer status runs `LIVE → PARTIALLY_ACCEPTED /
  FULLY_ACCEPTED → FINALIZED`, or `CANCELLED`.
* **Acceptance and settlement.** `acceptOffer` fills an offer (fully or
  partially), reserving the seller's cert units and escrowing the buyer's
  consideration, and creates a settlement agreement. Each fill is priced
  from the offer's running total: the lot pays
  `consideration × (unitsAccepted + units) / units − paymentAccepted`, so
  rounding error does not grow with the number of fills and the lot that
  exhausts the offer pays the remainder. A priced fill that rounds to zero
  reverts `ZeroConsiderationFill`.
  `finalizeSecondaryTradeAgreement` settles it — the ownership change is
  effectuated through
  `IssuanceManager.secondaryTransfer` (the LET never moves wallets; legal
  ownership transfers via metadata). Voiding an ACCEPTED settlement takes
  both parties' void requests (or expiry).
* **Exemption pathways.** Every trade travels under an
  `ExemptionPathway` (`NONE`, `RULE_144`, `SECTION_4A7`, `SECTION_4A1HALF`,
  `RULE_144A`, `REGULATION_S`). A sell offer may pin one pathway or leave
  `NONE` so each buyer elects at acceptance; buy offers must specify one.
  Only pathways the SPV has enabled can be pinned or elected.
* **Hosting modes.** `HostingMode.DIRECT` delivers the LET to the buyer;
  `ADMINISTERED` delivers it to an admin multisig while the buyer is
  registered as legal owner. `ADMINISTERED` with a zero `adminMultisig`
  reverts `MissingAdminMultisig` at `postOffer` (buy offers) and at
  `acceptOffer`.
* **Void certificates.** A void seller certificate keeps its owner and its
  units, so the ownership and unit checks alone would pass it. Posting a
  sell offer against it, accepting an offer that settles from it, and
  finalizing all revert (`CertificateVoided` at post and accept, the
  printer's `VoidCertificate` at finalize).

### Secondary-trade configuration (owner/admin)

```solidity
function setMinTradeThreshold(uint256 units, uint256 consideration) external; // onlyAdmin
function setSettlementWindow(uint256 window) external;                        // onlyAdmin
function setDefaultIntegrator(address integrator) external;                   // onlyAdmin, factory-whitelisted
function setSpvThresholdConditions(address[] conditions) external;            // onlyAdmin
function setPathwayThresholdConditions(ExemptionPathway pathway,
    address[] conditions, bool enabled) external;                             // onlyAdmin
function setClosingConditions(address[] conditions) external;                 // onlyAdmin
```

Conditions are layered: exemption-specific *pathway* conditions and
fund-specific *SPV threshold* conditions are read live at post/accept and
re-checked at finalization; *closing* conditions are evaluated at
finalization. Each layer is set as a whole list. Views: `getSpvThresholdConditions`, `getPathwayThresholdConditions`,
`isPathwayEnabled`, `getClosingConditions`, `getMinTradeThreshold`,
`getDefaultIntegrator`, `getSettlementWindow`, `getOffer(offerId)`,
`getSecondaryEscrow(agreementId)`.

## Config / fees

`setDealRegistry`, `setCorp`, `setIssuanceManager` (all `onlyOwner`);
`issuanceManager()`, `getCounterPartyValues(agreementId)`;
`computeFee(size)` and `getPlatformPayable()` for the platform fee
recipient.

Primary deals and secondary trades are priced separately, both from the
DealManagerFactory and both in basis points of the ticket
(`BASIS_POINTS = 10000`):

* **Primary** (`computeFee`, used by `finalizeDeal`): the factory's
  `getDefaultFeeRatio()`, which returns the per-DealManager override when
  one is enabled (`setInstanceFeeOverride`) and the platform default
  otherwise. The name is kept so older DealManagers keep working.
* **Secondary** (`finalizeSecondaryTradeAgreement`): the factory's
  `getSecondaryFeeRatio()`, with its own per-DealManager override
  (`setSecondaryInstanceFeeOverride`) and default
  (`setDefaultSecondaryFeeRatio`). The integrator's share is then carved
  out of that fee.

The factory owner (MetaLeX) sets the defaults and overrides; an override
with `enabled = true` and a zero ratio is a real 0% rate. Read the
platform defaults, ignoring overrides, with `getUnderlyingDefaultFeeRatio()` /
`getUnderlyingDefaultSecondaryFeeRatio()` and one instance's override with
`getInstanceFeeOverride(dm)` / `getSecondaryInstanceFeeOverride(dm)`.
A DealManager implementation from before the split reads
`getDefaultFeeRatio()` for secondary trades too, so it pays the primary
rate on them until it is upgraded.

## Events

Owned directly: `MinTradeThresholdSet`, `SettlementWindowSet`,
`DealRegistrySet`, `CorpSet`, `IssuanceManagerSet`, and
`DefaultIntegratorSet` (each setter event carries the new value, the old
value, and the caller). From the
libraries (via the interfaces): `DealProposed`, `DealFinalized`
(`IDealManagerStorage`); `DealPaidAt`, `DealVoidedAt`, `DealFinalizedAt`,
`FeeDistributed` (`LexScrowStorage`); `OfferPosted`, `OfferCancelled`,
`OfferAccepted`, `SecondaryTradeAgreementFinalized`,
`SecondaryTradeAgreementVoided`, `SecondaryFeeDistributed`,
`SpvThresholdConditionsSet`, `PathwayThresholdConditionsSet`,
`ClosingConditionsSet` (`ISecondaryTradeStorage`).

## Upgrades

`_authorizeUpgrade` is `onlyOwner` and only accepts the DealManagerFactory's
current reference implementation (`NotRefImplementation` otherwise).
