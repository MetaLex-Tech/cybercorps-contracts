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
  libraries; their events and errors are surfaced through the
  `IDealManagerStorage`, `ISecondaryTradeStorage`, and `ILexScrowStorage`
  interfaces so they appear in DealManager's ABI.
* **`DEPLOY_VERSION`:** `"4.0.1"`

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
defaultLegend}`.

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
  applied via the IssuanceManager, and escrowed payment (less the platform
  fee — see `computeFee` / `getPlatformPayable`) is released.
* Escrow state lives in the shared `LexScrowStorage` library — see
  [LeXscroWLite](LeXscroWLite.md). `getEscrowDetails(agreementId)` and
  `conditionCheck(agreementId)` expose it.

### Voiding a primary deal

Every void ultimately runs through the registry's `voidContractFor`, which
voids the agreement once every **allocated** party has requested it, as soon
as the proposer (party index 0) requests while still the only signer, or —
for a nonzero expiry only — once that expiry has passed. What differs between
the entry points is how much DealManager-side teardown follows.

* `signToVoid` forwards the request and, once the registry reports the
  agreement voided, voids the escrowed corp certificates and settles the
  escrow: a `PAID` escrow is refunded, a `PENDING` one is marked `VOIDED`.
* `revokeDeal` does the same for a still-pending deal (it reverts
  `DealNotPending` otherwise): it forwards the request, and if that request
  is the one that voids the agreement — the sole-signer proposer, say — the
  certificates are voided and the escrow marked `VOIDED` in the same call.
* Requests may also go straight to the registry, bypassing the DealManager
  entirely. The escrow then lags the agreement until anyone calls
  `refundVoidedDeal`, which voids the corp certificates and settles either
  state — a `PAID` escrow is refunded, a `PENDING` one just marked `VOIDED`.
  It reverts `DealNotVoided` while the agreement is still live, and
  `DealVoided` once the escrow is already synced.

The DealManager entry points tear the escrow down in the same call; a direct
registry void does not touch the DealManager, so the certificates stay live
and the escrow stays `PENDING` or `PAID` until someone calls
`refundVoidedDeal`. What holds on every route is that the teardown is always
reachable: no voided agreement can leave its escrow permanently stranded.

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
  consideration, and creates a settlement agreement.
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
  registered as legal owner.

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
`computeFee(size)` (factory-set fee ratio, in basis points) and
`getPlatformPayable()` for the platform fee recipient.

## Events

Owned directly: `MinTradeThresholdSet`, `SettlementWindowSet`. From the
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
