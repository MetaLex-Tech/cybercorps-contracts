# CyberAgreementRegistry

An onchain registry of legal-agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds record their agreements
in it.

* **Source:** [`src/CyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberAgreementRegistry.sol)
  / interface [`ICyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberAgreementRegistry.sol)
* **Pattern:** UUPS proxy (`Initializable`, `UUPSUpgradeable`,
  `BorgAuthACL`); EIP-712 domain `EIP712Domain(string name,string
  version,uint256 chainId,address verifyingContract)` with name
  `"CyberAgreementRegistry"`, version `"1"`, the chain id and the registry
  proxy address. `DOMAIN_SEPARATOR()` and `version()` are public getters.

## Data model

```solidity
struct Template {                              // declared in ICyberAgreementRegistry
    string legalContractUri;   // canonical legal text
    string title;
    string[] globalFields;     // field names common to the whole contract
    string[] partyFields;      // field names filled per signing party
}

struct AgreementData {
    bytes32 templateId;
    string[] globalValues;
    address[] parties;                        // address(0) = open slot
    mapping(address => string[]) partyValues;
    mapping(address => uint256) signedAt;
    uint256 numSignatures;
    address finalizer;
    bool finalized;
    bool voided;
    bytes32 secretHash;
    uint256 expiry;
    address[] voidRequestedBy;
}

// What each party signs (EIP-712)
struct SignatureData {
    bytes32 contractId;
    address signer;            // the party this signature consents for
    string legalContractUri;
    string[] globalFields;
    string[] partyFields;
    string[] globalValues;
    string[] partyValues;      // the signing party's own values
}

bytes32 public constant SIGNATUREDATA_TYPEHASH = keccak256(
    "SignatureData(bytes32 contractId,address signer,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues)"
); // = 0xe37d17c3ab7740aee31093101f9d27d139a5c3b35324b266efe5d085d6486f05

bytes32 public VOIDSIGNATUREDATA_TYPEHASH; // keccak256("VoidSignatureData(bytes32 contractId,address party)")
```

The `contractId` is `keccak256(abi.encode(templateId, salt, globalValues,
parties, secretHash, finalizer))`. `secretHash` and `finalizer` are bound
into the id so a front-runner cannot seize the same id with hostile terms.
`expiry` is left out so presigned offchain signatures stay verifiable.

The `signer` field binds a signature to one party. A delegate can hold
delegations from several parties, and without the field one delegate
signature over an agreement would verify for each of them. The string
fields are hashed as EIP-712 requires: `legalContractUri` as
`keccak256(bytes(uri))`, and each `string[]` as the `keccak256` of the
concatenated `keccak256` of its elements.

{% hint style="warning" %}
**Two registry implementations run in production.** The registry proxy
`0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` on Ethereum, Base and
Arbitrum runs this implementation: `SIGNATUREDATA_TYPEHASH()` returns
`0xe37d17c3…6f05`, and `createContract` derives the six-field id above.
The separate zkSync Era registry
(`0x07E0a0BeC742f90f7879830bC917E783dA6a6357`) returns
`0x49ba7af1fd9b42077b5e2bf090b7deb0f443e9ae99b46ce66b4859e28d670da4`, the
type without `signer`, and derives ids from four fields:
`keccak256(abi.encode(templateId, salt, globalValues, parties))`. Both
report `version()` `"1"`.

Read `SIGNATUREDATA_TYPEHASH()` on the registry you are about to sign
against before choosing the typed data or the id formula. Where the flow
allows, take the id from the `ContractCreated` event or an `eth_call` of
`createContract`. An agreement keeps the id it was created with, so read an
existing agreement's id instead of recomputing it.
{% endhint %}

## Functions

```solidity
function createTemplate(bytes32 templateId, string title, string legalContractUri,
    string[] globalFields, string[] partyFields) external;      // permissionless

function createContract(bytes32 templateId, uint256 salt, string[] globalValues,
    address[] parties, string[][] partyValues, bytes32 secretHash,
    address finalizer, uint256 expiry) external returns (bytes32 contractId);

function createStandaloneContractAndSign(string title, string legalContractUri,
    string[] globalFields, string[] partyFields, uint256 salt,
    string[] globalValues, address[] parties, string[][] partyValues,
    uint256 expiry, bytes signature) external returns (bytes32 contractId);
function createStandaloneContractAndSignFor(/* ...as above, plus */ address signer,
    bytes signature) external returns (bytes32 contractId);

function signContract(bytes32 contractId, string[] partyValues, bytes signature,
    bool fillUnallocated, string secret) external;
function signContractFor(address signer, bytes32 contractId, string[] partyValues,
    bytes signature, bool fillUnallocated, string secret) external;
function signContractWithEscrow(address escrowSigner, bytes32 contractId,
    string[] partyValues, bytes signature, bool fillUnallocated, string secret)
    external; // onlyDefinedFinalizer

function setDelegation(address delegate, uint256 expiry) external;
function revokeDelegation() external;

function voidContractFor(bytes32 contractId, address party, bytes signature) external;
function finalizeContract(bytes32 contractId) external; // onlyFinalizerIfSet
```

## Views

`getParties`, `hasSigned`, `getSignatureTimestamp`, `allPartiesSigned`,
`getContractDetails`, `getTemplateDetails`, `getSignerValues`, `isVoided`,
`isFinalized`, `getAgreementsForParty`, `getVoidRequestedBy`,
`getContractJson`, `getDelegation`, `isValidDelegation`, `isValidDelegate`.

## How signing works

* `createTemplate` registers a reusable template (id, title, legal URI,
  field schema). Anyone can register a template; a duplicate id reverts
  `TemplateAlreadyExists`.
* `createContract` instantiates an agreement from a template with its
  global values, parties and per-party values, bounded by `finalizer` and
  `expiry`. Parties left as `address(0)` are open slots that a later
  signer can claim with `fillUnallocated`, gated by `secretHash` if one is
  set.
* `createStandaloneContractAndSign(For)` derives the template (registering
  it on first use), creates the agreement and signs it in one transaction,
  so a single-party agreement takes one transaction. Standalone contracts
  always have `finalizer = address(0)`.
* Each party signs an EIP-712 `SignatureData` payload (contract id, the
  party's own address as `signer`, legal URI, field schema, global values,
  and their party values) and submits it through `signContract` (self),
  `signContractFor` (relayed) or `signContractWithEscrow`.
  `signContractWithEscrow` takes a pre-escrowed signature that only the
  agreement's defined finalizer can submit, such as a RoundManager holding
  an officer's escrowed signature. `signContract` and `signContractFor`
  verify the signature onchain, and when a finalizer is set, only the
  finalizer or the signer can submit. `signContractWithEscrow` does not
  re-verify: it requires a defined finalizer and relies on that vetted
  finalizer contract for access control.
* A party can give another address standing authority to sign for it
  (`setDelegation` / `revokeDelegation`, with optional expiry). Signature
  verification then accepts a valid, unexpired delegate's EIP-712
  signature in place of the party's own. Delegation affects signature
  recovery only, and the registry does not treat the delegate as the
  party. The delegate signs with `signer` set to the delegating party, so
  the signature counts for that party alone. `setDelegation` reverts
  `DelegateZeroAddress`, `DelegateIsSelf` or `ExpiryNotInFuture` (a
  nonzero expiry at or before the current block); `expiry == 0` means the
  delegation does not expire. The same delegate check applies to
  `VoidSignatureData` signatures.
* When all parties have signed, the registry emits `ContractFullySigned`.
  With no finalizer, the agreement finalizes automatically at that point;
  otherwise the finalizer calls `finalizeContract`.
* `voidContractFor` records a party's void request (event
  `VoidRequested`). The agreement is voided when every **allocated** party
  has requested, when its nonzero expiry has passed, or when the proposing
  party (index 0) voids while still the only signer. Unfilled `address(0)`
  slots in an open agreement cannot request and do not count toward
  unanimity, but a party who fills a slot must then also request. The
  finalizer can submit void requests without a signature; anyone else
  needs the party's EIP-712 `VoidSignatureData` signature. A finalized
  agreement cannot be voided.

{% hint style="info" %}
`expiry == 0` means **no deadline** in the void path, as in signing and
finalization. The expired branch never applies, so a zero-expiry
agreement voids only by unanimous request of its allocated parties, or by
the proposer while sole signer.
{% endhint %}

`getContractJson(contractId)` returns the agreement as a JSON string
(template id, title, legal URI, global fields, per-party values with
`signedAt`, signature count, `isComplete`, `voided`, `voidRequestedBy`,
`finalized`). Titles, URIs, field names and values are JSON-escaped, so a
quote or backslash typed into a field cannot break the document.

## Events

`TemplateCreated`, `ContractCreated`, `AgreementSigned` and
`ContractFullySigned` are declared in `ICyberAgreementRegistry`;
`ContractFinalized`, `VoidRequested`, `ContractVoided`, `DelegationSet`
and `DelegationRevoked` in the contract. The registry proxy emits all of
them.
