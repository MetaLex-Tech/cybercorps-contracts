# DealManager

Manages the lifecycle of deals — secondary transfers and other transactions —
for a cyberCORP. A deal is created from an agreement template and is
identified by a `bytes32 agreementId`.

* **Source:** [`src/DealManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/DealManager.sol)
  / interface [`IDealManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/IDealManager.sol)
* **Pattern:** UUPS proxy

## Lifecycle

```solidity
function proposeDeal(address[] _certPrinterAddress, address _paymentToken,
    uint256 _paymentAmount, bytes32 _templateId, uint256 _salt,
    string[] _globalValues, address[] _parties, CertificateDetails[] _certDetails,
    string[][] _partyValues, address[] conditions, bytes32 secretHash,
    uint256 expiry) external returns (bytes32 agreementId);

function proposeAndSignDeal(/* ...as above, plus */ address proposer,
    bytes signature /* ... */) external returns (bytes32 agreementId, uint256[] certIds);

function signDealAndPay(address signer, bytes32 agreementId, bytes signature,
    string[] partyValues, bool _fillUnallocated, string name, string secret) external;
function signAndFinalizeDeal(address signer, bytes32 _agreementId,
    string[] _partyValues, bytes signature, bool _fillUnallocated,
    string buyerName, string secret) external;
function finalizeDeal(bytes32 agreementId) external;

function voidExpiredDeal(bytes32 _agreementId, address signer, bytes signature) external;
function revokeDeal(bytes32 _agreementId, address signer, bytes signature) external;
function signToVoid(bytes32 _agreementId, address signer, bytes signature) external;

function initialize(address _auth, address _corp, address _dealRegistry,
    address _issuanceManager, address _upgradeFactory) external;
```

## How it works

* A deal references an agreement **template** (`_templateId`) and is recorded
  through the [CyberAgreementRegistry](CyberAgreementRegistry.md) —
  `_dealRegistry` in `initialize`.
* `_parties` countersign with EIP-712 signatures; `signDealAndPay` combines a
  party's signature with their payment.
* `conditions` are `ICondition` addresses that gate the deal.
* `expiry` and `secretHash` support timed and secret-gated deals;
  `voidExpiredDeal` cleans up expired deals.
* On `finalizeDeal` the deal's certificate effects (mint/assign/endorse) are
  applied via the IssuanceManager.

> The escrow of payment and assets is part of this deal flow. There is no
> separate `LeXscroWLite` contract in this repository — see
> [LeXscroWLite](LeXscroWLite.md).
